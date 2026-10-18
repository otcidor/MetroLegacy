#import "MLLibraryManager.h"
#import "../InnerTube/MLInnerTube.h"
#import "../InnerTube/MLYouTubeStream.h"
#import "MLImageCache.h"
#import "MLTLSTrustManager.h"
#import "MLLocalization.h"

NSString *const MLLibraryDidUpdateNotification = @"MLLibraryDidUpdateNotification";

static const NSUInteger kMaxHistoryItems = 100;
static const unsigned long long kMaxAudioCacheBytes = 250ULL * 1024ULL * 1024ULL; // 250 MB
static const unsigned long long kDownloadChunkSize = 262144ULL; // 256 KB

@implementation MLLibraryManager {
	NSLock *_lock;
	NSMutableArray *_likedSongs;
	NSMutableSet *_likedIds;
	NSMutableSet *_syncedLikedIds;

	NSMutableArray *_syncedPlaylists;
	NSMutableArray *_syncedSongs;
	NSMutableArray *_syncedAlbums;
	NSMutableArray *_syncedArtists;
	NSMutableArray *_historySongs;

	NSMutableArray *_downloadedSongs;
	NSMutableSet *_downloadedIds;
	NSMutableSet *_downloadingIds;
	NSMutableSet *_cancelledDownloadIds;
	NSMutableArray *_batchDownloadQueue;
	BOOL _isBatchDownloading;
	BOOL _cancelAllBatchRequested;

	NSMutableArray *_cachedSongs;
	NSMutableSet *_cachedIds;
	NSMutableSet *_cachingIds;

	NSMutableDictionary *_playCounts;
	NSMutableDictionary *_playHistoryMap;

	NSString *_libraryPlistPath;
	NSString *_downloadsDir;
	NSString *_downloadsIndexPlistPath;
	NSString *_cacheDir;
	NSString *_cacheIndexPlistPath;
	NSString *_playlistCacheDir;

	BOOL _syncing;
	NSMutableArray *_syncCallbacks;
	NSDate *_lastSyncDate;
}

+ (instancetype)sharedManager
{
	static MLLibraryManager *inst;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		inst = [[MLLibraryManager alloc] init];
	});
	return inst;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_lock = [[NSLock alloc] init];
		_likedSongs = [NSMutableArray array];
		_likedIds = [NSMutableSet set];
		_syncedLikedIds = [NSMutableSet set];
		_syncedPlaylists = [NSMutableArray array];
		_syncedSongs = [NSMutableArray array];
		_syncedAlbums = [NSMutableArray array];
		_syncedArtists = [NSMutableArray array];
		_historySongs = [NSMutableArray array];
		_downloadedSongs = [NSMutableArray array];
		_downloadedIds = [NSMutableSet set];
		_downloadingIds = [NSMutableSet set];
		_cancelledDownloadIds = [NSMutableSet set];
		_batchDownloadQueue = [NSMutableArray array];
		_isBatchDownloading = NO;
		_cancelAllBatchRequested = NO;
		_cachedSongs = [NSMutableArray array];
		_cachedIds = [NSMutableSet set];
		_cachingIds = [NSMutableSet set];
		_playCounts = [NSMutableDictionary dictionary];
		_playHistoryMap = [NSMutableDictionary dictionary];
		_syncCallbacks = [NSMutableArray array];

		NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
		NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;

		_libraryPlistPath = [docs stringByAppendingPathComponent:@"MLLibraryState.plist"];
		_downloadsDir = [docs stringByAppendingPathComponent:@"Downloads"];
		_downloadsIndexPlistPath = [_downloadsDir stringByAppendingPathComponent:@"index.plist"];
		_cacheDir = [caches stringByAppendingPathComponent:@"AudioCache"];
		_cacheIndexPlistPath = [_cacheDir stringByAppendingPathComponent:@"index.plist"];
		_playlistCacheDir = [docs stringByAppendingPathComponent:@"PlaylistCache"];

		NSFileManager *fm = [NSFileManager defaultManager];
		[fm createDirectoryAtPath:_downloadsDir withIntermediateDirectories:YES attributes:nil error:nil];
		[fm createDirectoryAtPath:_cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
		[fm createDirectoryAtPath:_playlistCacheDir withIntermediateDirectories:YES attributes:nil error:nil];

		[self loadStateFromDisk];

		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(onSessionChanged)
		                                             name:MLSessionChangedNotification
		                                           object:nil];

		if ([[MLInnerTube sharedClient] loggedIn]) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self syncWithYouTubeMusicCompletion:nil];
			});
		}
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onSessionChanged
{
	if ([[MLInnerTube sharedClient] loggedIn]) {
		[self syncWithYouTubeMusicCompletion:nil];
	} else {
		[_lock lock];
		[_syncedLikedIds removeAllObjects];
		[_syncedPlaylists removeAllObjects];
		[_syncedSongs removeAllObjects];
		[_syncedAlbums removeAllObjects];
		[_syncedArtists removeAllObjects];
		[self saveLibraryStateLocked];
		[_lock unlock];
		[self notifyUpdate];
	}
}

- (void)notifyUpdate
{
	if ([NSThread isMainThread]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:MLLibraryDidUpdateNotification object:self];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:MLLibraryDidUpdateNotification object:self];
		});
	}
}

#pragma mark - Disk Persistence

- (NSArray *)deserializeItems:(NSArray *)rawArray
{
	NSMutableArray *out = [NSMutableArray array];
	if (![rawArray isKindOfClass:[NSArray class]]) return out;
	for (NSDictionary *d in rawArray) {
		MLYTItem *it = [MLYTItem itemFromDictionary:d];
		if (it) [out addObject:it];
	}
	return out;
}

- (NSArray *)serializeItems:(NSArray *)items
{
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
	for (MLYTItem *it in items) {
		NSDictionary *d = [it toDictionary];
		if (d) [out addObject:d];
	}
	return out;
}

- (void)loadStateFromDisk
{
	[_lock lock];
	NSDictionary *state = [NSDictionary dictionaryWithContentsOfFile:_libraryPlistPath];
	if ([state isKindOfClass:[NSDictionary class]]) {
		[_likedSongs setArray:[self deserializeItems:state[@"likedSongs"]]];
		[_likedIds removeAllObjects];
		for (MLYTItem *it in _likedSongs) {
			if (it.videoId.length) [_likedIds addObject:it.videoId];
		}
		[_syncedLikedIds removeAllObjects];
		if ([state[@"syncedLikedIds"] isKindOfClass:[NSArray class]]) {
			[_syncedLikedIds addObjectsFromArray:state[@"syncedLikedIds"]];
		}
		[_syncedPlaylists setArray:[self deserializeItems:state[@"syncedPlaylists"]]];
		[_syncedSongs setArray:[self deserializeItems:state[@"syncedSongs"]]];
		[_syncedAlbums setArray:[self deserializeItems:state[@"syncedAlbums"]]];
		[_syncedArtists setArray:[self deserializeItems:state[@"syncedArtists"]]];
		[_historySongs setArray:[self deserializeItems:state[@"historySongs"]]];
		if ([state[@"playCounts"] isKindOfClass:[NSDictionary class]]) {
			[_playCounts addEntriesFromDictionary:state[@"playCounts"]];
		}
		if ([state[@"playHistoryMap"] isKindOfClass:[NSDictionary class]]) {
			[_playHistoryMap addEntriesFromDictionary:state[@"playHistoryMap"]];
		}
		if ([state[@"lastSyncDate"] isKindOfClass:[NSDate class]]) {
			_lastSyncDate = state[@"lastSyncDate"];
		}
	}

	NSFileManager *fm = [NSFileManager defaultManager];

	NSArray *dlRaw = [NSArray arrayWithContentsOfFile:_downloadsIndexPlistPath];
	[_downloadedSongs removeAllObjects];
	[_downloadedIds removeAllObjects];
	for (MLYTItem *it in [self deserializeItems:dlRaw]) {
		if (!it.videoId.length) continue;
		NSString *path = [_downloadsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", it.videoId]];
		if ([self isValidLocalAudioFileAtPath:path]) {
			[_downloadedSongs addObject:it];
			[_downloadedIds addObject:it.videoId];
		} else {
			[fm removeItemAtPath:path error:nil];
		}
	}

	NSArray *cacheRaw = [NSArray arrayWithContentsOfFile:_cacheIndexPlistPath];
	[_cachedSongs removeAllObjects];
	[_cachedIds removeAllObjects];
	for (MLYTItem *it in [self deserializeItems:cacheRaw]) {
		if (!it.videoId.length) continue;
		NSString *path = [_cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", it.videoId]];
		if ([self isValidLocalAudioFileAtPath:path]) {
			[_cachedSongs addObject:it];
			[_cachedIds addObject:it.videoId];
		} else {
			[fm removeItemAtPath:path error:nil];
		}
	}
	[_lock unlock];
}

- (void)saveLibraryStateLocked
{
	NSMutableDictionary *state = [NSMutableDictionary dictionary];
	state[@"likedSongs"] = [self serializeItems:_likedSongs];
	state[@"syncedLikedIds"] = [_syncedLikedIds allObjects] ?: @[];
	state[@"syncedPlaylists"] = [self serializeItems:_syncedPlaylists];
	state[@"syncedSongs"] = [self serializeItems:_syncedSongs];
	state[@"syncedAlbums"] = [self serializeItems:_syncedAlbums];
	state[@"syncedArtists"] = [self serializeItems:_syncedArtists];
	state[@"historySongs"] = [self serializeItems:_historySongs];
	state[@"playCounts"] = _playCounts ?: @{};
	state[@"playHistoryMap"] = _playHistoryMap ?: @{};
	if (_lastSyncDate) state[@"lastSyncDate"] = _lastSyncDate;
	[state writeToFile:_libraryPlistPath atomically:YES];
}

- (void)saveDownloadsIndexLocked
{
	NSArray *serialized = [self serializeItems:_downloadedSongs];
	[serialized writeToFile:_downloadsIndexPlistPath atomically:YES];
}

- (void)saveCacheIndexLocked
{
	NSArray *serialized = [self serializeItems:_cachedSongs];
	[serialized writeToFile:_cacheIndexPlistPath atomically:YES];
}

#pragma mark - Accessors

- (NSArray *)likedSongs
{
	[_lock lock];
	NSArray *copy = [_likedSongs copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)syncedPlaylists
{
	[_lock lock];
	NSArray *copy = [_syncedPlaylists copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)syncedSongs
{
	[_lock lock];
	NSArray *copy = [_syncedSongs copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)syncedAlbums
{
	[_lock lock];
	NSArray *copy = [_syncedAlbums copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)syncedArtists
{
	[_lock lock];
	NSArray *copy = [_syncedArtists copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)historySongs
{
	[_lock lock];
	NSArray *copy = [_historySongs copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)downloadedSongs
{
	[_lock lock];
	NSArray *copy = [_downloadedSongs copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)cachedSongs
{
	[_lock lock];
	NSArray *copy = [_cachedSongs copy];
	[_lock unlock];
	return copy;
}

- (NSArray *)top50Songs
{
	[_lock lock];
	NSMutableArray *pairs = [NSMutableArray array];
	for (NSString *vid in [_playCounts allKeys]) {
		NSDictionary *dict = _playHistoryMap[vid];
		MLYTItem *item = dict ? [MLYTItem itemFromDictionary:dict] : nil;
		if (!item) {
			for (MLYTItem *h in _historySongs) {
				if ([h.videoId isEqualToString:vid]) { item = h; break; }
			}
			if (!item) {
				for (MLYTItem *l in _likedSongs) {
					if ([l.videoId isEqualToString:vid]) { item = l; break; }
				}
			}
		}
		if (item && item.videoId.length) {
			NSUInteger cnt = [_playCounts[vid] unsignedIntegerValue];
			[pairs addObject:@{ @"item" : item, @"count" : @(cnt) }];
		}
	}

	[pairs sortUsingComparator:^NSComparisonResult(NSDictionary *p1, NSDictionary *p2) {
		NSUInteger c1 = [p1[@"count"] unsignedIntegerValue];
		NSUInteger c2 = [p2[@"count"] unsignedIntegerValue];
		if (c1 > c2) return NSOrderedAscending;
		if (c1 < c2) return NSOrderedDescending;
		return NSOrderedSame;
	}];

	NSMutableArray *top = [NSMutableArray arrayWithCapacity:50];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSDictionary *p in pairs) {
		MLYTItem *it = p[@"item"];
		if (![seen containsObject:it.videoId]) {
			[seen addObject:it.videoId];
			[top addObject:it];
			if (top.count >= 50) break;
		}
	}

	if (top.count < 50) {
		for (MLYTItem *it in _historySongs) {
			if (it.videoId.length && ![seen containsObject:it.videoId]) {
				[seen addObject:it.videoId];
				[top addObject:it];
				if (top.count >= 50) break;
			}
		}
	}
	if (top.count < 50) {
		for (MLYTItem *it in _likedSongs) {
			if (it.videoId.length && ![seen containsObject:it.videoId]) {
				[seen addObject:it.videoId];
				[top addObject:it];
				if (top.count >= 50) break;
			}
		}
	}

	NSArray *result = [top copy];
	[_lock unlock];
	return result;
}

- (BOOL)isSyncing
{
	return _syncing;
}

- (NSDate *)lastSyncDate
{
	return _lastSyncDate;
}

#pragma mark - Likes

- (BOOL)isSongLiked:(NSString *)videoId
{
	if (!videoId.length) return NO;
	[_lock lock];
	BOOL liked = [_likedIds containsObject:videoId];
	[_lock unlock];
	return liked;
}

- (void)toggleLikeForSong:(MLYTItem *)song completion:(void (^)(BOOL isLiked, NSString *error))completion
{
	if (!song || !song.videoId.length) {
		if (completion) completion(NO, @"Canción inválida");
		return;
	}

	NSString *vid = song.videoId;
	[_lock lock];
	BOOL currentlyLiked = [_likedIds containsObject:vid];
	BOOL newState = !currentlyLiked;
	if (newState) {
		[_likedIds addObject:vid];
		NSIndexSet *existing = [_likedSongs indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
			return [obj.videoId isEqualToString:vid];
		}];
		if (existing.count > 0) [_likedSongs removeObjectsAtIndexes:existing];
		[_likedSongs insertObject:song atIndex:0];
	} else {
		[_likedIds removeObject:vid];
		NSIndexSet *existing = [_likedSongs indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
			return [obj.videoId isEqualToString:vid];
		}];
		if (existing.count > 0) [_likedSongs removeObjectsAtIndexes:existing];
	}
	[self saveLibraryStateLocked];
	[_lock unlock];

	[self notifyUpdate];

	if ([[MLInnerTube sharedClient] loggedIn]) {
		[[MLInnerTube sharedClient] likeVideoWithId:vid liked:newState completion:^(BOOL ok, NSString *err) {
			if (ok) {
				[self->_lock lock];
				if (newState) [self->_syncedLikedIds addObject:vid];
				else [self->_syncedLikedIds removeObject:vid];
				[self saveLibraryStateLocked];
				[self->_lock unlock];
			}
			if (completion) completion(newState, err);
		}];
	} else {
		if (completion) completion(newState, nil);
	}
}

#pragma mark - History

- (void)recordPlayedSong:(MLYTItem *)song
{
	if (!song || !song.videoId.length) return;
	[_lock lock];
	NSIndexSet *existing = [_historySongs indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
		return [obj.videoId isEqualToString:song.videoId];
	}];
	if (existing.count > 0) {
		[_historySongs removeObjectsAtIndexes:existing];
	}
	[_historySongs insertObject:song atIndex:0];
	while (_historySongs.count > kMaxHistoryItems) {
		[_historySongs removeLastObject];
	}

	NSUInteger cnt = [_playCounts[song.videoId] unsignedIntegerValue] + 1;
	_playCounts[song.videoId] = @(cnt);
	NSDictionary *ser = [song toDictionary];
	if (ser) {
		_playHistoryMap[song.videoId] = ser;
	}

	[self saveLibraryStateLocked];
	[_lock unlock];
	[self notifyUpdate];
}

#pragma mark - YouTube Music Synchronization

- (void)cacheNextContainerFromQueue:(NSMutableArray *)queue
{
	if (queue.count == 0) return;
	MLYTItem *item = queue.firstObject;
	[queue removeObjectAtIndex:0];

	if (item.kind == MLYTKindAlbum) {
		NSString *bid = item.browseId ?: item.playlistId;
		if (!bid.length || [self cachedPlaylistForKey:bid]) {
			[self cacheNextContainerFromQueue:queue];
			return;
		}
		[[MLInnerTube sharedClient] albumWithBrowseId:bid completion:^(NSDictionary *hdr, NSArray *trks, NSString *e) {
			if (trks.count > 0 || hdr.count > 0) {
				[self cachePlaylistHeader:hdr tracks:trks forKey:bid];
			}
			[self cacheNextContainerFromQueue:queue];
		}];
	} else {
		NSString *pid = item.playlistId ?: item.browseId;
		if (!pid.length || [self cachedPlaylistForKey:pid]) {
			[self cacheNextContainerFromQueue:queue];
			return;
		}
		[[MLInnerTube sharedClient] playlistWithId:pid continuation:nil completion:^(NSDictionary *hdr, NSArray *trks, NSString *nxt, NSString *e) {
			if (trks.count > 0 || hdr.count > 0) {
				[self cachePlaylistHeader:hdr tracks:trks forKey:pid];
				NSString *bestThumb = hdr[@"thumbnailUrl"] ?: ((MLYTItem *)trks.firstObject).thumbnailUrl;
				if (bestThumb.length && !item.thumbnailUrl.length) {
					[self->_lock lock];
					item.thumbnailUrl = bestThumb;
					[self saveLibraryStateLocked];
					[self->_lock unlock];
					[MLImageCache prefetchImageAtURLString:bestThumb];
					[self notifyUpdate];
				}
			}
			[self cacheNextContainerFromQueue:queue];
		}];
	}
}

- (void)syncWithYouTubeMusicCompletion:(void (^)(BOOL ok, NSString *error))completion
{
	if (![[MLInnerTube sharedClient] loggedIn]) {
		if (completion) completion(NO, @"No has iniciado sesión");
		return;
	}
	[_lock lock];
	if (completion) {
		[_syncCallbacks addObject:[completion copy]];
	}
	if (_syncing) {
		[_lock unlock];
		return;
	}
	_syncing = YES;
	[_lock unlock];
	[self notifyUpdate];

	__block NSArray *remoteLiked = nil;
	__block NSArray *remotePlaylists = nil;
	__block NSArray *remoteSongs = nil;
	__block NSArray *remoteAlbums = nil;
	__block NSArray *remoteArtists = nil;
	__block NSArray *remoteHistory = nil;
	__block NSString *firstError = nil;

	void (^finishSync)(void) = ^{
		NSMutableArray *unsyncedLocalLikesToPush = [NSMutableArray array];

		[self->_lock lock];

		if (remoteLiked != nil) {
			NSMutableSet *remoteIds = [NSMutableSet set];
			for (MLYTItem *it in remoteLiked) {
				if (it.videoId.length) [remoteIds addObject:it.videoId];
			}

			NSMutableArray *mergedLiked = [NSMutableArray array];
			NSMutableSet *seen = [NSMutableSet set];

			// Preserve offline local likes that were never synced to YouTube Music yet, and push them
			for (MLYTItem *localIt in self->_likedSongs) {
				NSString *vid = localIt.videoId;
				if (!vid.length || [seen containsObject:vid]) continue;
				if (![remoteIds containsObject:vid] && ![self->_syncedLikedIds containsObject:vid]) {
					[mergedLiked addObject:localIt];
					[seen addObject:vid];
					[unsyncedLocalLikesToPush addObject:vid];
				}
			}

			// Add all currently liked songs from YouTube Music (in remote order)
			for (MLYTItem *it in remoteLiked) {
				if (!it.videoId.length || [seen containsObject:it.videoId]) continue;
				[mergedLiked addObject:it];
				[seen addObject:it.videoId];
			}

			[self->_likedSongs setArray:mergedLiked];
			[self->_likedIds setSet:seen];
			[self->_syncedLikedIds setSet:seen];
		}

		if (remotePlaylists != nil) {
			NSMutableArray *filteredPlaylists = [NSMutableArray array];
			for (MLYTItem *existingPl in self->_syncedPlaylists) {
				NSString *epid = existingPl.playlistId ?: existingPl.browseId ?: @"";
				if ([epid hasPrefix:@"local_pl_"]) {
					[filteredPlaylists addObject:existingPl];
				}
			}
			for (MLYTItem *pl in remotePlaylists) {
				NSString *pid = pl.playlistId ?: pl.browseId ?: @"";
				if (!pid.length ||
				    [pid isEqualToString:@"VLLM"] || [pid isEqualToString:@"LM"] ||
				    [pid isEqualToString:@"VLSE"] || [pid isEqualToString:@"SE"] ||
				    [pid isEqualToString:@"VLRDPN"] || [pid isEqualToString:@"RDPN"]) {
					continue;
				}
				if (pl.kind != MLYTKindPlaylist && pl.kind != MLYTKindAlbum) {
					pl.kind = MLYTKindPlaylist;
				}
				[filteredPlaylists addObject:pl];
			}
			[self->_syncedPlaylists setArray:filteredPlaylists];
		}

		if (remoteSongs != nil) {
			NSMutableArray *validSongs = [NSMutableArray array];
			for (MLYTItem *s in remoteSongs) {
				if (s.videoId.length) {
					if (s.kind == MLYTKindUnknown) s.kind = MLYTKindSong;
					[validSongs addObject:s];
				}
			}
			[self->_syncedSongs setArray:validSongs];
		}

		if (remoteAlbums != nil) {
			NSMutableArray *validAlbums = [NSMutableArray array];
			for (MLYTItem *al in remoteAlbums) {
				if (!al.browseId.length && !al.playlistId.length) continue;
				al.kind = MLYTKindAlbum;
				[validAlbums addObject:al];
			}
			[self->_syncedAlbums setArray:validAlbums];
		}

		if (remoteArtists != nil) {
			NSMutableArray *validArtists = [NSMutableArray array];
			for (MLYTItem *ar in remoteArtists) {
				if (!ar.browseId.length) continue;
				if ([ar.browseId hasPrefix:@"MPLAUC"]) {
					ar.browseId = [ar.browseId substringFromIndex:4];
				}
				ar.kind = MLYTKindArtist;
				[validArtists addObject:ar];
			}
			[self->_syncedArtists setArray:validArtists];
		}

		if (remoteHistory.count > 0) {
			NSMutableSet *seenHist = [NSMutableSet set];
			NSMutableArray *mergedHist = [NSMutableArray array];
			for (MLYTItem *it in remoteHistory) {
				if (it.videoId.length && ![seenHist containsObject:it.videoId]) {
					if (it.kind == MLYTKindUnknown) it.kind = MLYTKindSong;
					[seenHist addObject:it.videoId];
					[mergedHist addObject:it];
				}
			}
			for (MLYTItem *it in self->_historySongs) {
				if (it.videoId.length && ![seenHist containsObject:it.videoId]) {
					[seenHist addObject:it.videoId];
					[mergedHist addObject:it];
				}
			}
			while (mergedHist.count > kMaxHistoryItems) {
				[mergedHist removeLastObject];
			}
			[self->_historySongs setArray:mergedHist];
		}

		self->_lastSyncDate = [NSDate date];
		[self saveLibraryStateLocked];
		self->_syncing = NO;

		NSArray *callbacks = [self->_syncCallbacks copy];
		[self->_syncCallbacks removeAllObjects];

		NSArray *plSnapshot = [self->_syncedPlaylists copy];
		NSArray *alSnapshot = [self->_syncedAlbums copy];
		NSArray *arSnapshot = [self->_syncedArtists copy];
		NSArray *lkSnapshot = [self->_likedSongs copy];
		[self->_lock unlock];

		// Push any offline local likes to YouTube Music
		for (NSString *vid in unsyncedLocalLikesToPush) {
			[[MLInnerTube sharedClient] likeVideoWithId:vid liked:YES completion:nil];
		}

		// Prefetch thumbnails for all synced items so covers are available offline
		for (NSArray *group in @[ plSnapshot ?: @[], alSnapshot ?: @[], arSnapshot ?: @[], lkSnapshot ?: @[] ]) {
			for (MLYTItem *it in group) {
				if (it.thumbnailUrl.length) {
					[MLImageCache prefetchImageAtURLString:it.thumbnailUrl];
				}
			}
		}

		// Sequentially background-cache playlist and album tracklists so iOS 6 TLS is not overloaded
		NSMutableArray *containerQueue = [NSMutableArray array];
		if (plSnapshot.count) [containerQueue addObjectsFromArray:plSnapshot];
		if (alSnapshot.count) [containerQueue addObjectsFromArray:alSnapshot];
		[self cacheNextContainerFromQueue:containerQueue];

		[self notifyUpdate];
		for (void (^cb)(BOOL, NSString *) in callbacks) {
			cb(firstError == nil || remoteLiked != nil || remotePlaylists != nil, firstError);
		}
	};

	// Execute sync endpoints sequentially (matching Metrolist SyncUtils.kt) to avoid saturating iOS 6 TLS sockets:
	// 1. Liked songs (VLLM) -> 2. Playlists -> 3. Library Songs -> 4. Albums -> 5. Artists -> 6. History
	[[MLInnerTube sharedClient] likedSongsWithCompletion:^(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) {
		if (tracks) remoteLiked = tracks;
		else if (err && !firstError) firstError = err;

		[[MLInnerTube sharedClient] libraryWithBrowseId:@"FEmusic_liked_playlists" completion:^(NSArray *plItems, NSString *plErr) {
			if (plItems) remotePlaylists = plItems;
			else if (plErr && !firstError) firstError = plErr;

			[[MLInnerTube sharedClient] libraryWithBrowseId:@"FEmusic_liked_videos" completion:^(NSArray *songItems, NSString *sErr) {
				if (songItems) remoteSongs = songItems;

				[[MLInnerTube sharedClient] libraryWithBrowseId:@"FEmusic_liked_albums" completion:^(NSArray *albumItems, NSString *alErr) {
					if (albumItems) remoteAlbums = albumItems;

					[[MLInnerTube sharedClient] libraryWithBrowseId:@"FEmusic_library_corpus_artists" completion:^(NSArray *artistItems, NSString *arErr) {
						if (artistItems) remoteArtists = artistItems;

						[[MLInnerTube sharedClient] libraryWithBrowseId:@"FEmusic_history" completion:^(NSArray *histItems, NSString *hErr) {
							if (histItems) remoteHistory = histItems;
							dispatch_async(dispatch_get_main_queue(), finishSync);
						}];
					}];
				}];
			}];
		}];
	}];
}

#pragma mark - Playlist & Album Metadata/Tracklist Cache

- (NSString *)playlistCacheFilePathForKey:(NSString *)key
{
	if (!key.length) return nil;
	NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
	NSString *safe = [[key componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
	if (!safe.length) return nil;
	return [_playlistCacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", safe]];
}

- (void)cachePlaylistHeader:(NSDictionary *)header tracks:(NSArray *)tracks forKey:(NSString *)key
{
	NSString *path = [self playlistCacheFilePathForKey:key];
	if (!path) return;
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	if (header) payload[@"header"] = header;
	if (tracks) payload[@"tracks"] = [self serializeItems:tracks];
	[payload writeToFile:path atomically:YES];

	NSString *hdrThumb = header[@"thumbnailUrl"];
	if (hdrThumb.length) [MLImageCache prefetchImageAtURLString:hdrThumb];
	for (MLYTItem *it in tracks) {
		if (it.thumbnailUrl.length) {
			[MLImageCache prefetchImageAtURLString:it.thumbnailUrl];
		}
	}
}

- (NSDictionary *)cachedPlaylistForKey:(NSString *)key
{
	NSString *path = [self playlistCacheFilePathForKey:key];
	if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
	NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:path];
	if (![raw isKindOfClass:[NSDictionary class]]) return nil;
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	if ([raw[@"header"] isKindOfClass:[NSDictionary class]]) {
		out[@"header"] = raw[@"header"];
	}
	if ([raw[@"tracks"] isKindOfClass:[NSArray class]]) {
		out[@"tracks"] = [self deserializeItems:raw[@"tracks"]];
	}
	return out;
}

#pragma mark - Offline Downloads & Audio Stream Cache

- (BOOL)isSongDownloaded:(NSString *)videoId
{
	if (!videoId.length) return NO;
	[_lock lock];
	BOOL ok = [_downloadedIds containsObject:videoId];
	[_lock unlock];
	return ok;
}

- (BOOL)isSongDownloading:(NSString *)videoId
{
	if (!videoId.length) return NO;
	[_lock lock];
	BOOL ok = [_downloadingIds containsObject:videoId];
	[_lock unlock];
	return ok;
}

- (BOOL)isSongCached:(NSString *)videoId
{
	if (!videoId.length) return NO;
	[_lock lock];
	BOOL ok = [_cachedIds containsObject:videoId];
	[_lock unlock];
	return ok;
}

- (BOOL)isBatchDownloading
{
	[_lock lock];
	BOOL bd = _isBatchDownloading || (_batchDownloadQueue.count > 0);
	[_lock unlock];
	return bd;
}

- (NSUInteger)activeDownloadsCount
{
	[_lock lock];
	NSUInteger count = _downloadingIds.count + _batchDownloadQueue.count;
	[_lock unlock];
	return count;
}

- (BOOL)isDownloadCancelledForVideoId:(NSString *)videoId
{
	if (!videoId.length) return NO;
	[_lock lock];
	BOOL c = _cancelAllBatchRequested || [_cancelledDownloadIds containsObject:videoId];
	[_lock unlock];
	return c;
}

- (void)cancelDownloadForVideoId:(NSString *)videoId
{
	if (!videoId.length) return;
	[_lock lock];
	[_cancelledDownloadIds addObject:videoId];
	[_downloadingIds removeObject:videoId];
	NSIndexSet *batchIdx = [_batchDownloadQueue indexesOfObjectsPassingTest:^BOOL(MLYTItem *it, NSUInteger idx, BOOL *stop) {
		return [it.videoId isEqualToString:videoId];
	}];
	if (batchIdx.count > 0) {
		[_batchDownloadQueue removeObjectsAtIndexes:batchIdx];
	}
	[_lock unlock];
	[self notifyUpdate];
}

- (void)cancelAllDownloads
{
	[_lock lock];
	_cancelAllBatchRequested = YES;
	[_batchDownloadQueue removeAllObjects];
	for (NSString *vid in [_downloadingIds allObjects]) {
		[_cancelledDownloadIds addObject:vid];
	}
	[_downloadingIds removeAllObjects];
	_isBatchDownloading = NO;
	[_lock unlock];
	[self notifyUpdate];
}

- (BOOL)isValidLocalAudioFileAtPath:(NSString *)filePath
{
	if (!filePath.length) return NO;
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:filePath]) return NO;
	NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
	unsigned long long fileSize = [attrs fileSize];
	if (fileSize <= 32768) return NO;

	NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:filePath];
	if (!fh) return NO;
	NSData *header = nil;
	@try {
		header = [fh readDataOfLength:65536];
	} @catch (id ex) {
		header = nil;
	}
	[fh closeFile];

	if (!header || header.length < 32) return NO;
	const uint8_t *bytes = (const uint8_t *)header.bytes;
	size_t len = header.length;
	if (bytes[4] != 'f' || bytes[5] != 't' || bytes[6] != 'y' || bytes[7] != 'p') {
		return NO;
	}

	// Verify sidx box completeness if present (DASH fragmented MP4)
	const uint8_t *sidxPtr = NULL;
	size_t sidxBoxStart = 0;
	for (size_t i = 4; i + 8 <= len; i++) {
		if (bytes[i] == 's' && bytes[i+1] == 'i' && bytes[i+2] == 'd' && bytes[i+3] == 'x') {
			sidxPtr = bytes + i;
			sidxBoxStart = i - 4;
			break;
		}
	}
	if (!sidxPtr || (size_t)(sidxPtr - bytes + 24) > len) {
		return NO;
	}

	uint32_t boxSize = ((uint32_t)bytes[sidxBoxStart] << 24) | ((uint32_t)bytes[sidxBoxStart+1] << 16) |
	                   ((uint32_t)bytes[sidxBoxStart+2] << 8) | (uint32_t)bytes[sidxBoxStart+3];
	if (boxSize < 32) return NO;

	uint8_t version = sidxPtr[4];
	const uint8_t *cur = sidxPtr + 16;
	uint64_t firstOffset = 0;
	if (version == 0) {
		cur += 4;
		firstOffset = ((uint32_t)cur[0] << 24) | ((uint32_t)cur[1] << 16) | ((uint32_t)cur[2] << 8) | (uint32_t)cur[3];
		cur += 4;
	} else {
		cur += 8;
		firstOffset = ((uint64_t)cur[0] << 56) | ((uint64_t)cur[1] << 48) | ((uint64_t)cur[2] << 40) | ((uint64_t)cur[3] << 32) |
		              ((uint64_t)cur[4] << 24) | ((uint64_t)cur[5] << 16) | ((uint64_t)cur[6] << 8)  | (uint64_t)cur[7];
		cur += 8;
	}
	cur += 2;
	if (cur + 2 > bytes + len) return NO;
	uint16_t refCount = ((uint16_t)cur[0] << 8) | (uint16_t)cur[1];
	cur += 2;
	if (refCount == 0) return NO;

	unsigned long long expectedEnd = (unsigned long long)(sidxBoxStart + boxSize + firstOffset);
	for (uint16_t i = 0; i < refCount; i++) {
		if (cur + 12 > bytes + len) return NO;
		uint32_t val1 = ((uint32_t)cur[0] << 24) | ((uint32_t)cur[1] << 16) | ((uint32_t)cur[2] << 8) | (uint32_t)cur[3];
		uint32_t refSz = val1 & 0x7FFFFFFF;
		expectedEnd += refSz;
		cur += 12;
	}

	return (fileSize >= expectedEnd);
}

- (NSURL *)localFileURLForVideoId:(NSString *)videoId
{
	if (!videoId.length) return nil;
	NSFileManager *fm = [NSFileManager defaultManager];

	NSString *dlPath = [_downloadsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", videoId]];
	if ([fm fileExistsAtPath:dlPath]) {
		if ([self isValidLocalAudioFileAtPath:dlPath]) {
			return [NSURL fileURLWithPath:dlPath];
		} else {
			[fm removeItemAtPath:dlPath error:nil];
		}
	}

	NSString *cachePath = [_cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", videoId]];
	if ([fm fileExistsAtPath:cachePath]) {
		if ([self isValidLocalAudioFileAtPath:cachePath]) {
			return [NSURL fileURLWithPath:cachePath];
		} else {
			[fm removeItemAtPath:cachePath error:nil];
		}
	}

	return nil;
}

- (BOOL)downloadStreamFromURL:(NSURL *)streamURL toDestinationPath:(NSString *)destPath error:(NSString **)errorOut
{
	return [self downloadStreamFromURL:streamURL toDestinationPath:destPath videoId:nil error:errorOut];
}

- (BOOL)downloadStreamFromURL:(NSURL *)streamURL toDestinationPath:(NSString *)destPath videoId:(NSString *)videoId error:(NSString **)errorOut
{
	if (!streamURL || [streamURL isFileURL] || [streamURL.host isEqualToString:@"127.0.0.1"]) {
		if (errorOut) *errorOut = @"URL de stream inválida";
		return NO;
	}

	NSString *partPath = [destPath stringByAppendingString:@".part"];
	NSFileManager *fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:partPath error:nil];
	[fm createFileAtPath:partPath contents:nil attributes:nil];

	NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:partPath];
	if (!fh) {
		if (errorOut) *errorOut = @"No se pudo crear archivo temporal";
		return NO;
	}

	NSString *absURL = [streamURL absoluteString] ?: @"";
	NSString *userAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
	if ([absURL rangeOfString:@"c=IOS"].location != NSNotFound) {
		userAgent = @"com.google.ios.youtube/20.10.4 (iPhone16,1; U; CPU iOS 18_0 like Mac OS X;)";
	} else if ([absURL rangeOfString:@"c=ANDROID_VR"].location != NSNotFound) {
		userAgent = @"com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip";
	}

	unsigned long long offset = 0;
	unsigned long long totalLength = 0;
	BOOL success = YES;

	while (totalLength == 0 || offset < totalLength) {
		if (videoId.length && [self isDownloadCancelledForVideoId:videoId]) {
			success = NO;
			if (errorOut) *errorOut = @"Descarga cancelada";
			break;
		}

		unsigned long long end = offset + kDownloadChunkSize - 1;
		if (totalLength > 0 && end >= totalLength) {
			end = totalLength - 1;
		}

		NSData *chunk = nil;
		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;

		for (int attempt = 0; attempt < 3; attempt++) {
			if (videoId.length && [self isDownloadCancelledForVideoId:videoId]) {
				break;
			}
			if (attempt > 0) {
				usleep(250000);
			}
			NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:streamURL
			                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
			                                               timeoutInterval:20.0];
			req.HTTPMethod = @"GET";
			req.HTTPShouldHandleCookies = NO;
			[req setValue:[NSString stringWithFormat:@"bytes=%llu-%llu", offset, end] forHTTPHeaderField:@"Range"];
			[req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
			[req setValue:@"*/*" forHTTPHeaderField:@"Accept"];
			[req setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];

			chunk = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];
			if (chunk.length > 0 && (resp.statusCode == 200 || resp.statusCode == 206)) {
				break;
			}
			chunk = nil;
		}

		if (videoId.length && [self isDownloadCancelledForVideoId:videoId]) {
			success = NO;
			if (errorOut) *errorOut = @"Descarga cancelada";
			break;
		}

		if (!chunk || chunk.length == 0) {
			success = NO;
			if (errorOut) *errorOut = err ? err.localizedDescription : @"Error descargando audio";
			break;
		}

		if (totalLength == 0) {
			NSString *cr = nil;
			for (NSString *k in resp.allHeaderFields) {
				if ([k caseInsensitiveCompare:@"Content-Range"] == NSOrderedSame) {
					cr = resp.allHeaderFields[k];
					break;
				}
			}
			if (cr.length > 0) {
				NSRange slash = [cr rangeOfString:@"/"];
				if (slash.location != NSNotFound && slash.location + 1 < cr.length) {
					NSString *totStr = [cr substringFromIndex:slash.location + 1];
					long long parsed = [totStr longLongValue];
					if (parsed > 0) totalLength = (unsigned long long)parsed;
				}
			}
			if (totalLength == 0 && resp.statusCode == 200 && resp.expectedContentLength > 0) {
				totalLength = (unsigned long long)resp.expectedContentLength;
			}
		}

		@try {
			[fh writeData:chunk];
		} @catch (id ex) {
			success = NO;
			break;
		}

		offset += chunk.length;
		if (totalLength == 0 || resp.statusCode == 200) {
			break;
		}
	}

	[fh closeFile];

	if (videoId.length && [self isDownloadCancelledForVideoId:videoId]) {
		[fm removeItemAtPath:partPath error:nil];
		return NO;
	}

	if (success && (totalLength == 0 || offset >= totalLength) && [self isValidLocalAudioFileAtPath:partPath]) {
		[fm removeItemAtPath:destPath error:nil];
		NSError *moveErr = nil;
		if ([fm moveItemAtPath:partPath toPath:destPath error:&moveErr]) {
			return YES;
		}
	}

	[fm removeItemAtPath:partPath error:nil];
	return NO;
}

- (void)downloadSong:(MLYTItem *)song completion:(void (^)(BOOL ok, NSString *error))completion
{
	if (!song || !song.videoId.length) {
		if (completion) completion(NO, @"Canción inválida");
		return;
	}
	if (song.thumbnailUrl.length) {
		[MLImageCache prefetchImageAtURLString:song.thumbnailUrl];
	}

	NSString *vid = song.videoId;
	[_lock lock];
	if ([_downloadedIds containsObject:vid]) {
		[_lock unlock];
		if (completion) completion(YES, nil);
		return;
	}
	if ([_downloadingIds containsObject:vid]) {
		[_lock unlock];
		if (completion) completion(NO, @"Descarga en progreso");
		return;
	}
	[_cancelledDownloadIds removeObject:vid];
	[_downloadingIds addObject:vid];
	[_lock unlock];
	[self notifyUpdate];

	NSString *destPath = [_downloadsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", vid]];
	NSString *cachePath = [_cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", vid]];
	NSFileManager *fm = [NSFileManager defaultManager];

	// Fast path: if already cached on disk, promote to Downloads immediately
	if ([self isValidLocalAudioFileAtPath:cachePath]) {
		[fm removeItemAtPath:destPath error:nil];
		if ([fm copyItemAtPath:cachePath toPath:destPath error:nil]) {
			[_lock lock];
			[_downloadingIds removeObject:vid];
			[_downloadedIds addObject:vid];
			[_downloadedSongs insertObject:song atIndex:0];
			[self saveDownloadsIndexLocked];
			[_lock unlock];
			[self notifyUpdate];
			if (completion) completion(YES, nil);
			return;
		}
	}

	[MLYouTubeStream resolveStreamForVideoId:vid completion:^(NSURL *url, NSDictionary *videoDetails, NSString *err) {
		if ([self isDownloadCancelledForVideoId:vid]) {
			[self->_lock lock];
			[self->_downloadingIds removeObject:vid];
			[self->_cancelledDownloadIds removeObject:vid];
			[self->_lock unlock];
			[self notifyUpdate];
			if (completion) completion(NO, @"Descarga cancelada");
			return;
		}

		if (!url) {
			[self->_lock lock];
			[self->_downloadingIds removeObject:vid];
			[self->_lock unlock];
			[self notifyUpdate];
			if (completion) completion(NO, err ?: @"No se pudo resolver el stream");
			return;
		}
		if (videoDetails) {
			NSInteger len = [videoDetails[@"lengthSeconds"] integerValue];
			if (len > 0 && song.duration == 0) song.duration = len;
		}

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			if ([self isDownloadCancelledForVideoId:vid]) {
				[self->_lock lock];
				[self->_downloadingIds removeObject:vid];
				[self->_cancelledDownloadIds removeObject:vid];
				[self->_lock unlock];
				[self notifyUpdate];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (completion) completion(NO, @"Descarga cancelada");
				});
				return;
			}

			NSString *dlErr = nil;
			BOOL ok = [self downloadStreamFromURL:url toDestinationPath:destPath videoId:vid error:&dlErr];
			[self->_lock lock];
			BOOL wasCancelled = [self->_cancelledDownloadIds containsObject:vid] || self->_cancelAllBatchRequested;
			[self->_downloadingIds removeObject:vid];
			[self->_cancelledDownloadIds removeObject:vid];
			if (ok && !wasCancelled) {
				[self->_downloadedIds addObject:vid];
				NSIndexSet *existing = [self->_downloadedSongs indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
					return [obj.videoId isEqualToString:vid];
				}];
				if (existing.count > 0) [self->_downloadedSongs removeObjectsAtIndexes:existing];
				[self->_downloadedSongs insertObject:song atIndex:0];
				[self saveDownloadsIndexLocked];
			}
			[self->_lock unlock];
			[self notifyUpdate];

			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(ok && !wasCancelled, wasCancelled ? @"Descarga cancelada" : dlErr);
			});
		});
	}];
}

- (void)downloadAllSongs:(NSArray *)songs
{
	if (!songs.count) return;
	NSArray *copy = [songs copy];

	[_lock lock];
	_cancelAllBatchRequested = NO;
	NSMutableSet *enqueued = [NSMutableSet set];
	for (MLYTItem *it in _batchDownloadQueue) {
		if (it.videoId.length) [enqueued addObject:it.videoId];
	}
	for (MLYTItem *song in copy) {
		if (![song isKindOfClass:[MLYTItem class]] || !song.videoId.length) continue;
		if ([_downloadedIds containsObject:song.videoId]) continue;
		if ([_downloadingIds containsObject:song.videoId]) continue;
		if ([enqueued containsObject:song.videoId]) continue;
		[_batchDownloadQueue addObject:song];
		[enqueued addObject:song.videoId];
	}

	if (_isBatchDownloading) {
		[_lock unlock];
		[self notifyUpdate];
		return;
	}
	_isBatchDownloading = YES;
	[_lock unlock];
	[self notifyUpdate];

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		while (YES) {
			MLYTItem *nextSong = nil;
			[self->_lock lock];
			if (self->_cancelAllBatchRequested || self->_batchDownloadQueue.count == 0) {
				self->_isBatchDownloading = NO;
				[self->_batchDownloadQueue removeAllObjects];
				[self->_lock unlock];
				[self notifyUpdate];
				break;
			}
			nextSong = self->_batchDownloadQueue.firstObject;
			[self->_batchDownloadQueue removeObjectAtIndex:0];
			[self->_lock unlock];

			if (!nextSong || !nextSong.videoId.length) continue;
			if ([self isSongDownloaded:nextSong.videoId]) continue;

			dispatch_semaphore_t sem = dispatch_semaphore_create(0);
			[self downloadSong:nextSong completion:^(BOOL ok, NSString *error) {
				dispatch_semaphore_signal(sem);
			}];
			dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_SEC)));

			[self->_lock lock];
			BOOL shouldStop = self->_cancelAllBatchRequested;
			[self->_lock unlock];
			if (shouldStop) {
				[self->_lock lock];
				self->_isBatchDownloading = NO;
				[self->_batchDownloadQueue removeAllObjects];
				[self->_lock unlock];
				[self notifyUpdate];
				break;
			}
		}
	});
}

- (void)removeDownloadedSong:(NSString *)videoId
{
	if (!videoId.length) return;
	NSString *destPath = [_downloadsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", videoId]];
	[[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];

	[_lock lock];
	[_downloadedIds removeObject:videoId];
	NSIndexSet *existing = [_downloadedSongs indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
		return [obj.videoId isEqualToString:videoId];
	}];
	if (existing.count > 0) [_downloadedSongs removeObjectsAtIndexes:existing];
	[self saveDownloadsIndexLocked];
	[_lock unlock];
	[self notifyUpdate];
}

#pragma mark - Queue & Playlist Persistence

- (void)saveQueue:(NSArray *)queue
  asPlaylistWithTitle:(NSString *)title
           completion:(void (^)(NSString *playlistId, NSString *error))completion
{
	if (!queue.count) {
		if (completion) completion(nil, @"Cola vacía");
		return;
	}
	NSString *cleanTitle = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!cleanTitle.length) {
		cleanTitle = MLLocalizedString(@"queue_playlist_default", nil);
	}

	NSMutableArray *vids = [NSMutableArray array];
	for (MLYTItem *it in queue) {
		if ([it isKindOfClass:[MLYTItem class]] && it.videoId.length) {
			[vids addObject:it.videoId];
		}
	}

	void (^finishWithId)(NSString *pid) = ^(NSString *pid) {
		MLYTItem *plItem = [[MLYTItem alloc] init];
		plItem.kind = MLYTKindPlaylist;
		plItem.playlistId = pid;
		plItem.title = cleanTitle;
		NSString *fmt = (queue.count == 1) ? MLLocalizedString(@"songs_count_single", nil) : MLLocalizedString(@"songs_count_plural", nil);
		plItem.subtitle = [NSString stringWithFormat:fmt, (unsigned long)queue.count];
		MLYTItem *first = queue.firstObject;
		plItem.thumbnailUrl = first.thumbnailUrl;

		NSDictionary *hdr = @{
			@"title" : cleanTitle,
			@"subtitle" : plItem.subtitle,
			@"thumbnailUrl" : plItem.thumbnailUrl ?: @""
		};
		[self cachePlaylistHeader:hdr tracks:queue forKey:pid];

		[self->_lock lock];
		NSIndexSet *ex = [self->_syncedPlaylists indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
			return [obj.playlistId isEqualToString:pid];
		}];
		if (ex.count > 0) [self->_syncedPlaylists removeObjectsAtIndexes:ex];
		[self->_syncedPlaylists insertObject:plItem atIndex:0];
		[self saveLibraryStateLocked];
		[self->_lock unlock];
		[self notifyUpdate];

		if (completion) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(pid, nil);
			});
		}
	};

	if ([[MLInnerTube sharedClient] loggedIn]) {
		[[MLInnerTube sharedClient] createPlaylistWithTitle:cleanTitle videoIds:vids completion:^(NSString *remoteId, NSString *err) {
			if (remoteId.length) {
				finishWithId(remoteId);
			} else {
				NSString *localId = [NSString stringWithFormat:@"local_pl_%ld", (long)[[NSDate date] timeIntervalSince1970]];
				finishWithId(localId);
			}
		}];
	} else {
		NSString *localId = [NSString stringWithFormat:@"local_pl_%ld", (long)[[NSDate date] timeIntervalSince1970]];
		finishWithId(localId);
	}
}

- (void)removePlaylistWithId:(NSString *)playlistId
{
	if (!playlistId.length) return;
	[_lock lock];
	NSIndexSet *ex = [_syncedPlaylists indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
		return [obj.playlistId isEqualToString:playlistId] || [obj.browseId isEqualToString:playlistId];
	}];
	if (ex.count > 0) {
		[_syncedPlaylists removeObjectsAtIndexes:ex];
		[self saveLibraryStateLocked];
	}
	[_lock unlock];

	NSString *cachePath = [self playlistCacheFilePathForKey:playlistId];
	if (cachePath) {
		[[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
	}
	[self notifyUpdate];
}

- (void)cacheSong:(MLYTItem *)song fromStreamURL:(NSURL *)streamURL
{
	if (!song || !song.videoId.length || !streamURL) return;
	if ([streamURL isFileURL] || [streamURL.host isEqualToString:@"127.0.0.1"]) return;
	if (song.thumbnailUrl.length) {
		[MLImageCache prefetchImageAtURLString:song.thumbnailUrl];
	}

	NSString *vid = song.videoId;
	[_lock lock];
	if ([_downloadedIds containsObject:vid] || [_cachedIds containsObject:vid] ||
	    [_downloadingIds containsObject:vid] || [_cachingIds containsObject:vid]) {
		[_lock unlock];
		return;
	}
	[_cachingIds addObject:vid];
	[_lock unlock];

	NSString *cachePath = [_cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", vid]];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		BOOL ok = [self downloadStreamFromURL:streamURL toDestinationPath:cachePath error:nil];
		[self->_lock lock];
		[self->_cachingIds removeObject:vid];
		if (ok) {
			[self->_cachedIds addObject:vid];
			NSIndexSet *existing = [self->_cachedSongs indexesOfObjectsPassingTest:^BOOL(MLYTItem *obj, NSUInteger idx, BOOL *stop) {
				return [obj.videoId isEqualToString:vid];
			}];
			if (existing.count > 0) [self->_cachedSongs removeObjectsAtIndexes:existing];
			[self->_cachedSongs insertObject:song atIndex:0];
			[self trimAudioCacheLocked];
			[self saveCacheIndexLocked];
		}
		[self->_lock unlock];
		if (ok) [self notifyUpdate];
	});
}

- (void)trimAudioCacheLocked
{
	NSFileManager *fm = [NSFileManager defaultManager];
	unsigned long long total = 0;
	for (MLYTItem *it in _cachedSongs) {
		NSString *p = [_cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", it.videoId]];
		total += [[fm attributesOfItemAtPath:p error:nil] fileSize];
	}
	while (total > kMaxAudioCacheBytes && _cachedSongs.count > 1) {
		MLYTItem *oldest = [_cachedSongs lastObject];
		NSString *p = [_cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", oldest.videoId]];
		unsigned long long sz = [[fm attributesOfItemAtPath:p error:nil] fileSize];
		[fm removeItemAtPath:p error:nil];
		[_cachedIds removeObject:oldest.videoId];
		[_cachedSongs removeLastObject];
		if (total >= sz) total -= sz;
		else total = 0;
	}
}

- (void)clearAudioCache
{
	NSFileManager *fm = [NSFileManager defaultManager];
	[_lock lock];
	[_cachedSongs removeAllObjects];
	[_cachedIds removeAllObjects];
	[fm removeItemAtPath:_cacheDir error:nil];
	[fm createDirectoryAtPath:_cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
	[self saveCacheIndexLocked];
	[_lock unlock];
	[self notifyUpdate];
}

#pragma mark - Storage Metrics

- (unsigned long long)directoryBytesAtPath:(NSString *)dirPath
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *files = [fm contentsOfDirectoryAtPath:dirPath error:nil];
	unsigned long long total = 0;
	for (NSString *file in files) {
		if (![file hasSuffix:@".m4a"]) continue;
		NSString *full = [dirPath stringByAppendingPathComponent:file];
		total += [[fm attributesOfItemAtPath:full error:nil] fileSize];
	}
	return total;
}

- (unsigned long long)downloadedTotalBytes
{
	return [self directoryBytesAtPath:_downloadsDir];
}

- (unsigned long long)audioCacheTotalBytes
{
	return [self directoryBytesAtPath:_cacheDir];
}

- (NSString *)formattedSizeForBytes:(unsigned long long)bytes
{
	double mb = (double)bytes / (1024.0 * 1024.0);
	if (mb < 0.1) return @"0 MB";
	return [NSString stringWithFormat:@"%.1f MB", mb];
}

@end
