#import "MLPlaybackManager.h"
#import "MLInnerTube.h"
#import "MLYouTubeStream.h"
#import "MLStreamRelay.h"
#import "MLLibraryManager.h"
#import "MLSponsorBlockManager.h"
#import "MLLocalization.h"
#import <MediaPlayer/MediaPlayer.h>

NSString *const MLPlaybackStateChangedNotification = @"MLPlaybackStateChangedNotification";
NSString *const MLPlaybackQueueStartedNotification = @"MLPlaybackQueueStartedNotification";

@interface MLPlaybackManager ()
@property (nonatomic, copy) NSArray *queue;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) BOOL buffering;
@property (nonatomic, copy) NSString *statusError;
@end

@implementation MLPlaybackManager
{
	id _timeObserver;
	BOOL _advancing;
	AVPlayerItem *_observedItem;
	NSString *_fetchingRadioForVideoId;
	NSURL *_currentPlaybackURL;
	NSURL *_currentRawStreamURL;
	CGFloat _lastKnownTime;
	NSInteger _retryCount;
	NSTimer *_sleepCountdownTimer;
	NSDate *_sleepTimerTargetDate;
	BOOL _sleepTimerActive;
	BOOL _sleepTimerStopAfterSong;
	NSArray *_currentSponsorSegments;
}

+ (instancetype)sharedManager
{
	static MLPlaybackManager *m = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ m = [[MLPlaybackManager alloc] init]; });
	return m;
}

- (id)init
{
	self = [super init];
	if (self) {
		_repeatMode = MLRepeatModeOff;
		_shuffle = NO;
		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		[nc addObserver:self
		       selector:@selector(itemEnded:)
		           name:AVPlayerItemDidPlayToEndTimeNotification
		         object:nil];
		[nc addObserver:self
		       selector:@selector(appWillEnterForeground:)
		           name:UIApplicationWillEnterForegroundNotification
		         object:nil];
		[nc addObserver:self
		       selector:@selector(appDidBecomeActive:)
		           name:UIApplicationDidBecomeActiveNotification
		         object:nil];
		[nc addObserver:self
		       selector:@selector(audioSessionInterrupted:)
		           name:AVAudioSessionInterruptionNotification
		         object:nil];
		[self ensureAudioSessionActive];
	}
	return self;
}

- (void)ensureAudioSessionActive
{
	NSError *err = nil;
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&err];
	[[AVAudioSession sharedInstance] setActive:YES error:&err];
}

- (void)appWillEnterForeground:(NSNotification *)note
{
	[self ensureAudioSessionActive];
	[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
}

- (void)appDidBecomeActive:(NSNotification *)note
{
	[self ensureAudioSessionActive];
	[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];

	if (_player && _player.currentItem && _player.currentItem.status == AVPlayerItemStatusFailed) {
		NSLog(@"[MLPlaybackManager] Recovering failed player item on foreground at %.1fs", _lastKnownTime);
		_retryCount = 0;
		self.statusError = nil;
		[self recoverCurrentStreamWithResumeTime:_lastKnownTime];
	}
}

- (void)audioSessionInterrupted:(NSNotification *)note
{
	NSUInteger type = [note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
	if (type == AVAudioSessionInterruptionTypeEnded) {
		[self ensureAudioSessionActive];
		[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
		NSUInteger opts = [note.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
		if ((opts & AVAudioSessionInterruptionOptionShouldResume) && _playing && _player) {
			[_player play];
		}
	}
}

- (MLYTItem *)currentItem
{
	return _currentIndex < _queue.count ? _queue[_currentIndex] : nil;
}

- (CGFloat)currentTime
{
	if (!_player)
		return _lastKnownTime;
	CMTime t = [_player currentTime];
	return CMTIME_IS_NUMERIC(t) ? (CGFloat)CMTimeGetSeconds(t) : _lastKnownTime;
}

- (CGFloat)duration
{
	if (self.currentItem && self.currentItem.duration > 0) {
		return (CGFloat)self.currentItem.duration;
	}
	CGFloat secs = 0;
	if (_player && _player.currentItem) {
		AVPlayerItem *it = _player.currentItem;
		CMTime d = [it duration];
		if (CMTIME_IS_NUMERIC(d)) {
			secs = (CGFloat)CMTimeGetSeconds(d);
		} else {
			CMTime ad = [[it asset] duration];
			if (CMTIME_IS_NUMERIC(ad)) {
				secs = (CGFloat)CMTimeGetSeconds(ad);
			}
		}
	}
	return secs;
}

- (void)postState
{
	[[NSNotificationCenter defaultCenter] postNotificationName:MLPlaybackStateChangedNotification object:self];
}

- (void)updateNowPlaying
{
	MLYTItem *item = self.currentItem;
	MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
	if (!item) {
		center.nowPlayingInfo = nil;
		return;
	}
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	if (item.title)
		info[MPMediaItemPropertyTitle] = item.title;
	if (item.artists.count)
		info[MPMediaItemPropertyArtist] = [item.artists componentsJoinedByString:@", "];
	else if (item.subtitle)
		info[MPMediaItemPropertyArtist] = item.subtitle;
	CGFloat dur = self.duration;
	if (dur > 0)
		info[MPMediaItemPropertyPlaybackDuration] = @(dur);
	info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.currentTime);
	info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.playing ? 1.0 : 0.0);
	center.nowPlayingInfo = info;
}

- (void)playQueue:(NSArray *)items startIndex:(NSUInteger)index
{
	if (!items.count)
		return;
	MLYTItem *target = (index < items.count) ? items[index] : nil;
	NSMutableArray *valid = [NSMutableArray array];
	for (MLYTItem *it in items) {
		if (it.videoId.length > 0) {
			[valid addObject:it];
		}
	}
	if (!valid.count)
		return;
	NSUInteger newIndex = target ? [valid indexOfObject:target] : 0;
	if (newIndex == NSNotFound)
		newIndex = 0;
	self.queue = valid;
	_advancing = NO;
	_retryCount = 0;
	_lastKnownTime = 0;
	[self playIndex:newIndex fresh:YES resumeTime:0];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLPlaybackQueueStartedNotification object:self];
}

- (void)playRadioForItem:(MLYTItem *)item
{
	if (!item || !item.videoId.length)
		return;
	_fetchingRadioForVideoId = nil;
	[self playQueue:@[item] startIndex:0];
	[self loadRadioRecommendationsForCurrentItem];
}

- (void)playIndex:(NSUInteger)index fresh:(BOOL)fresh
{
	_retryCount = 0;
	_lastKnownTime = 0;
	[self playIndex:index fresh:fresh resumeTime:0];
}

- (void)playIndex:(NSUInteger)index fresh:(BOOL)fresh resumeTime:(CGFloat)resumeTime
{
	if (index >= _queue.count)
		return;
	_currentIndex = index;
	_currentPlaybackURL = nil;
	MLYTItem *item = self.currentItem;
	[self attachPlayer:nil];
	self.statusError = nil;
	self.buffering = YES;
	[self ensureAudioSessionActive];
	[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
	[self postState];

	NSString *videoId = item.videoId;
	if (!videoId) {
		self.statusError = MLLocalizedString(@"no_video_id", nil);
		self.buffering = NO;
		[self postState];
		return;
	}

	// Record played song in history
	[[MLLibraryManager sharedManager] recordPlayedSong:item];

	// Fetch SponsorBlock segments
	_currentSponsorSegments = nil;
	__weak typeof(self) wselfSB = self;
	[[MLSponsorBlockManager sharedManager] fetchSegmentsForVideoId:videoId completion:^(NSArray *segments) {
		MLPlaybackManager *strongSelf = wselfSB;
		if (strongSelf) {
			strongSelf->_currentSponsorSegments = segments;
		}
	}];

	// Auto-load Up Next / radio recommendations when near end of queue
	if (_queue.count <= _currentIndex + 3) {
		[self loadRadioRecommendationsForCurrentItem];
	}

	// Fast offline/cache path: play directly from downloaded or cached local file via MLStreamRelay
	NSURL *localFileURL = [[MLLibraryManager sharedManager] localFileURLForVideoId:videoId];
	if (localFileURL) {
		__weak MLPlaybackManager *wself = self;
		dispatch_async(dispatch_get_main_queue(), ^{
			MLPlaybackManager *s = wself;
			if (!s || s.currentIndex != index)
				return;
			s->_currentRawStreamURL = localFileURL;
			[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
			NSURL *playbackURL = [[MLStreamRelay sharedRelay] relayURLForStreamURL:localFileURL] ?: localFileURL;
			s->_currentPlaybackURL = playbackURL;
			AVPlayer *p = [AVPlayer playerWithURL:playbackURL];
			[s attachPlayer:p];
			if (resumeTime > 1.0) {
				[p seekToTime:CMTimeMakeWithSeconds(resumeTime, NSEC_PER_SEC)];
			}
			s.playing = YES;
			[p play];
			[s postState];
			[s updateNowPlaying];
		});
		return;
	}

	__weak MLPlaybackManager *wself = self;
	[MLYouTubeStream resolveStreamForVideoId:videoId completion:^(NSURL *url, NSDictionary *videoDetails, NSString *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			MLPlaybackManager *s = wself;
			if (!s)
				return;
			if (s.currentIndex != index)
				return; // stale
			if (!url) {
				s.statusError = error;
				s.buffering = NO;
				[s postState];
				return;
			}

			// Update duration and metadata from videoDetails
			if (videoDetails) {
				NSInteger len = [videoDetails[@"lengthSeconds"] integerValue];
				if (len > 0) {
					s.currentItem.duration = len;
				}
				if (!s.currentItem.title.length && videoDetails[@"title"]) {
					s.currentItem.title = videoDetails[@"title"];
				}
				if (!s.currentItem.subtitle.length && videoDetails[@"author"]) {
					s.currentItem.subtitle = videoDetails[@"author"];
				}
			}

			s->_currentRawStreamURL = url;
			[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
			NSURL *playbackURL = [[MLStreamRelay sharedRelay] relayURLForStreamURL:url] ?: url;
			s->_currentPlaybackURL = playbackURL;
			AVPlayer *p = [AVPlayer playerWithURL:playbackURL];
			[s attachPlayer:p];
			if (resumeTime > 1.0) {
				[p seekToTime:CMTimeMakeWithSeconds(resumeTime, NSEC_PER_SEC)];
			}
			s.playing = YES;
			[p play];
			[s postState];
			[s updateNowPlaying];

			// Cache the audio stream in the background after initial playback buffering
			MLYTItem *itemToCache = s.currentItem;
			if (itemToCache) {
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
					MLPlaybackManager *strongSelf = wself;
					if (strongSelf && strongSelf.currentItem == itemToCache) {
						[[MLLibraryManager sharedManager] cacheSong:itemToCache fromStreamURL:url];
					}
				});
			}
		});
	}];
}

- (void)recoverCurrentStreamWithResumeTime:(CGFloat)resumeTime
{
	[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
	[self ensureAudioSessionActive];

	if (_currentPlaybackURL && _retryCount <= 1) {
		self.statusError = nil;
		self.buffering = YES;
		AVPlayer *p = [AVPlayer playerWithURL:_currentPlaybackURL];
		[self attachPlayer:p];
		if (resumeTime > 1.0) {
			[p seekToTime:CMTimeMakeWithSeconds(resumeTime, NSEC_PER_SEC)];
		}
		self.playing = YES;
		[p play];
		[self postState];
		[self updateNowPlaying];
	} else {
		[self playIndex:_currentIndex fresh:NO resumeTime:resumeTime];
	}
}

- (void)loadRadioRecommendationsForCurrentItem
{
	MLYTItem *item = self.currentItem;
	if (!item || !item.videoId.length)
		return;
	if ([_fetchingRadioForVideoId isEqualToString:item.videoId])
		return;
	_fetchingRadioForVideoId = [item.videoId copy];

	NSString *radioPlaylistId = item.playlistId;
	if (!radioPlaylistId.length || [radioPlaylistId hasPrefix:@"RDAMVM"]) {
		radioPlaylistId = [@"RDAMVM" stringByAppendingString:item.videoId];
	}

	__weak MLPlaybackManager *wself = self;
	[[MLInnerTube sharedClient] nextForVideoId:item.videoId playlistId:radioPlaylistId completion:^(NSArray *items, NSString *title, NSString *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			MLPlaybackManager *s = wself;
			if (!s)
				return;
			s->_fetchingRadioForVideoId = nil;
			if (items.count == 0)
				return;

			// Gather existing video IDs to avoid duplicates
			NSMutableSet *existingIds = [NSMutableSet set];
			for (MLYTItem *qItem in s.queue) {
				if (qItem.videoId.length)
					[existingIds addObject:qItem.videoId];
			}

			NSMutableArray *newItems = [NSMutableArray array];
			for (MLYTItem *it in items) {
				if (it.videoId.length && ![existingIds containsObject:it.videoId]) {
					[newItems addObject:it];
					[existingIds addObject:it.videoId];
				}
			}

			if (newItems.count > 0) {
				NSMutableArray *updated = [s.queue mutableCopy];
				[updated addObjectsFromArray:newItems];
				s.queue = updated;
				[s postState];
			}
		});
	}];
}

- (void)dealloc
{
	[self attachPlayer:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)attachPlayer:(AVPlayer *)player
{
	if (_observedItem) {
		[_observedItem removeObserver:self forKeyPath:@"status"];
		_observedItem = nil;
	}
	if (_player) {
		if (_timeObserver) {
			[_player removeTimeObserver:_timeObserver];
			_timeObserver = nil;
		}
		[_player pause];
		_player = nil;
	}
	_player = player;
	if (player) {
		_observedItem = player.currentItem;
		if (_observedItem) {
			[_observedItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
		}
		__weak MLPlaybackManager *wself = self;
		_timeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC)
		                                                   queue:dispatch_get_main_queue()
		                                              usingBlock:^(CMTime t) {
			MLPlaybackManager *s = wself;
			if (s) {
				CGFloat cur = CMTIME_IS_NUMERIC(t) ? (CGFloat)CMTimeGetSeconds(t) : 0;
				if (cur > 0.5) {
					s->_lastKnownTime = cur;
				}
				CGFloat skipTarget = [[MLSponsorBlockManager sharedManager] nextSkipTargetForTime:cur segments:s->_currentSponsorSegments];
				if (skipTarget > 0.0f && skipTarget > cur) {
					[s seekToTime:skipTarget];
					[[NSNotificationCenter defaultCenter] postNotificationName:MLSponsorBlockDidSkipNotification object:nil];
					return;
				}
				BOOL wasBuffering = s.buffering;
				if (wasBuffering && cur > 0.05) {
					s.buffering = NO;
				}
				CGFloat dur = [s duration];
				if (s.playing && dur > 5.0 && cur > 1.0 && cur >= dur - 0.5) {
					[s itemEnded:nil];
					return;
				}
				if (wasBuffering != s.buffering) {
					[s updateNowPlaying];
				}
				[s postState];
			}
		}];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"status"] && object == _observedItem) {
		AVPlayerItem *observed = _observedItem;
		AVPlayerItemStatus itemStatus = observed.status;
		NSError *itemError = observed.error;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (observed != self->_observedItem)
				return;
			if (itemStatus == AVPlayerItemStatusReadyToPlay) {
				self->_retryCount = 0;
				self.statusError = nil;
				self.buffering = NO;
				if (self.playing) {
					[self->_player play];
				}
				[self postState];
				[self updateNowPlaying];
			} else if (itemStatus == AVPlayerItemStatusFailed) {
				NSError *under = [itemError.userInfo objectForKey:NSUnderlyingErrorKey];
				NSInteger errCode = under ? under.code : itemError.code;
				NSLog(@"[MLPlaybackManager] AVPlayerItem failed (retry=%ld, code=%ld): %@, underlying: %@",
				      (long)self->_retryCount, (long)errCode, itemError, under);

				if (self->_currentRawStreamURL &&
				    ![self->_currentPlaybackURL isEqual:self->_currentRawStreamURL] &&
				    (errCode == -1022 || errCode == -1004 || errCode == -1001 || errCode == -1005)) {
					NSLog(@"[MLPlaybackManager] Relay failed with error %ld, falling back directly to raw stream: %@",
					      (long)errCode, self->_currentRawStreamURL);
					self->_currentPlaybackURL = self->_currentRawStreamURL;
					CGFloat resumeAt = self->_lastKnownTime;
					AVPlayer *directPlayer = [AVPlayer playerWithURL:self->_currentRawStreamURL];
					[self attachPlayer:directPlayer];
					if (resumeAt > 1.0) {
						[directPlayer seekToTime:CMTimeMakeWithSeconds(resumeAt, NSEC_PER_SEC)];
					}
					self.playing = YES;
					[directPlayer play];
					[self postState];
					[self updateNowPlaying];
					return;
				}

				if (self->_retryCount < 2) {
					self->_retryCount++;
					CGFloat resumeAt = self->_lastKnownTime;
					NSLog(@"[MLPlaybackManager] Auto-recovering stream (attempt %ld) at %.1fs",
					      (long)self->_retryCount, resumeAt);
					[self recoverCurrentStreamWithResumeTime:resumeAt];
					return;
				}

				NSString *errDesc = nil;
				if (under) {
					errDesc = [NSString stringWithFormat:@"%ld: %@", (long)under.code, under.localizedDescription ?: under.domain];
				} else if (itemError) {
					errDesc = [NSString stringWithFormat:@"%ld: %@", (long)itemError.code, itemError.localizedDescription ?: @"Error"];
				}
				self.statusError = errDesc ?: MLLocalizedString(@"playback_error", nil);
				self.buffering = NO;
				self.playing = NO;
				[self postState];
			}
		});
		return;
	}
	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)itemEnded:(NSNotification *)note
{
	if (_advancing)
		return;
	if (note.object && _player.currentItem && note.object != _player.currentItem)
		return;
	_advancing = YES;
	if (_sleepTimerStopAfterSong) {
		[self cancelSleepTimer];
		[_player pause];
		_playing = NO;
		[self postState];
		[self updateNowPlaying];
		_advancing = NO;
		return;
	}
	if (_repeatMode == MLRepeatModeOne) {
		[self seekToTime:0];
		[_player play];
		_playing = YES;
		[self postState];
		_advancing = NO;
		return;
	}
	[self next];
	_advancing = NO;
}

- (void)togglePlayPause
{
	[[MLStreamRelay sharedRelay] reviveListenerKeepingPort];
	[self ensureAudioSessionActive];

	if (!_player || (_player.currentItem && _player.currentItem.status == AVPlayerItemStatusFailed) || self.statusError.length > 0) {
		if (self.currentItem) {
			_retryCount = 0;
			[self recoverCurrentStreamWithResumeTime:_lastKnownTime];
		}
		return;
	}
	if (_playing) {
		[_player pause];
		_playing = NO;
	} else {
		[_player play];
		_playing = YES;
	}
	[self postState];
	[self updateNowPlaying];
}

- (void)next
{
	if (_repeatMode == MLRepeatModeOne) {
		[self seekToTime:0];
		[_player play];
		_playing = YES;
		[self postState];
		return;
	}
	if (_shuffle && _queue.count > 1) {
		NSUInteger nextIdx = _currentIndex;
		if (_queue.count > 2) {
			while (nextIdx == _currentIndex) {
				nextIdx = arc4random_uniform((uint32_t)_queue.count);
			}
		} else {
			nextIdx = (_currentIndex == 0) ? 1 : 0;
		}
		[self playIndex:nextIdx fresh:NO];
		return;
	}
	if (_currentIndex + 1 < _queue.count) {
		[self playIndex:_currentIndex + 1 fresh:NO];
	} else if (_repeatMode == MLRepeatModeAll && _queue.count > 0) {
		[self playIndex:0 fresh:NO];
	} else {
		[self stop];
	}
}

- (void)previous
{
	if (self.currentTime > 3.0) {
		[self seekToTime:0];
		return;
	}
	if (_currentIndex > 0)
		[self playIndex:_currentIndex - 1 fresh:NO];
	else
		[self seekToTime:0];
}

- (void)seekToTime:(CGFloat)seconds
{
	if (!_player)
		return;
	[_player seekToTime:CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC)];
	[self postState];
}

- (void)stop
{
	[self attachPlayer:nil];
	_playing = NO;
	_buffering = NO;
	[self postState];
	[self updateNowPlaying];
}

- (void)toggleShuffle
{
	self.shuffle = !self.shuffle;
	[self postState];
}

- (void)toggleRepeat
{
	if (self.repeatMode == MLRepeatModeOff)
		self.repeatMode = MLRepeatModeAll;
	else if (self.repeatMode == MLRepeatModeAll)
		self.repeatMode = MLRepeatModeOne;
	else
		self.repeatMode = MLRepeatModeOff;
	[self postState];
}

- (void)playShuffledQueue:(NSArray *)items
{
	if (!items.count)
		return;
	NSMutableArray *shuffled = [items mutableCopy];
	for (NSUInteger i = shuffled.count; i > 1; i--) {
		NSUInteger j = arc4random_uniform((uint32_t)i);
		[shuffled exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
	}
	self.shuffle = YES;
	[self playQueue:shuffled startIndex:0];
}

- (void)playNextItem:(MLYTItem *)item
{
	if (!item)
		return;
	if (!_queue.count || !self.currentItem) {
		[self playQueue:@[item] startIndex:0];
		return;
	}
	NSMutableArray *q = [_queue mutableCopy];
	NSUInteger insertIdx = MIN(_currentIndex + 1, q.count);
	[q insertObject:item atIndex:insertIdx];
	self.queue = q;
	[self postState];
}

- (void)appendQueueItems:(NSArray *)items
{
	if (!items.count)
		return;
	if (!_queue.count || !self.currentItem) {
		[self playQueue:items startIndex:0];
		return;
	}
	NSMutableArray *q = [_queue mutableCopy] ?: [NSMutableArray array];
	[q addObjectsFromArray:items];
	self.queue = q;
	[self postState];
}

- (void)removeQueueItemAtIndex:(NSUInteger)index
{
	if (index >= _queue.count)
		return;
	NSMutableArray *q = [_queue mutableCopy];
	[q removeObjectAtIndex:index];
	if (index < _currentIndex) {
		_currentIndex--;
	} else if (index == _currentIndex) {
		if (index < q.count) {
			self.queue = q;
			[self playIndex:index fresh:NO];
			return;
		} else if (q.count > 0) {
			self.queue = q;
			[self playIndex:q.count - 1 fresh:NO];
			return;
		} else {
			self.queue = @[];
			[self stop];
			return;
		}
	}
	self.queue = q;
	[self postState];
}

- (void)moveQueueItemFromIndex:(NSUInteger)from toIndex:(NSUInteger)to
{
	if (from >= _queue.count || to >= _queue.count || from == to)
		return;
	NSMutableArray *q = [_queue mutableCopy];
	MLYTItem *it = q[from];
	[q removeObjectAtIndex:from];
	[q insertObject:it atIndex:to];
	if (_currentIndex == from) {
		_currentIndex = to;
	} else if (from < _currentIndex && to >= _currentIndex) {
		_currentIndex--;
	} else if (from > _currentIndex && to <= _currentIndex) {
		_currentIndex++;
	}
	self.queue = q;
	[self postState];
}

#pragma mark - Sleep Timer

- (BOOL)sleepTimerActive { return _sleepTimerActive; }
- (BOOL)sleepTimerStopAfterSong { return _sleepTimerStopAfterSong; }

- (NSTimeInterval)sleepTimerRemainingTime
{
	if (!_sleepTimerActive || !_sleepTimerTargetDate)
		return 0;
	NSTimeInterval rem = [_sleepTimerTargetDate timeIntervalSinceNow];
	return rem > 0 ? rem : 0;
}

- (void)setSleepTimerWithMinutes:(NSUInteger)minutes
{
	[self cancelSleepTimer];
	if (minutes == 0)
		return;
	_sleepTimerActive = YES;
	_sleepTimerStopAfterSong = NO;
	_sleepTimerTargetDate = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)(minutes * 60)];
	_sleepCountdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
	                                                        target:self
	                                                      selector:@selector(sleepTimerTick:)
	                                                      userInfo:nil
	                                                       repeats:YES];
	[self postState];
}

- (void)setSleepTimerStopAfterCurrentSong
{
	[self cancelSleepTimer];
	_sleepTimerActive = YES;
	_sleepTimerStopAfterSong = YES;
	_sleepTimerTargetDate = nil;
	[self postState];
}

- (void)cancelSleepTimer
{
	if (_sleepCountdownTimer) {
		[_sleepCountdownTimer invalidate];
		_sleepCountdownTimer = nil;
	}
	_sleepTimerActive = NO;
	_sleepTimerStopAfterSong = NO;
	_sleepTimerTargetDate = nil;
	[self postState];
}

- (void)sleepTimerTick:(NSTimer *)t
{
	if (!_sleepTimerActive || !_sleepTimerTargetDate) {
		[self cancelSleepTimer];
		return;
	}
	if ([_sleepTimerTargetDate timeIntervalSinceNow] <= 0) {
		[self fireSleepTimer];
	}
}

- (void)fireSleepTimer
{
	[self cancelSleepTimer];
	if (_player && _playing) {
		float origVol = _player.volume;
		__weak typeof(self) weakSelf = self;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			for (int i = 10; i >= 0; i--) {
				float v = origVol * (i / 10.0f);
				dispatch_async(dispatch_get_main_queue(), ^{
					weakSelf.player.volume = v;
				});
				[NSThread sleepForTimeInterval:0.12];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				[weakSelf.player pause];
				weakSelf.player.volume = origVol;
				weakSelf.playing = NO;
				[weakSelf postState];
				[weakSelf updateNowPlaying];
			});
		});
	}
}

@end
