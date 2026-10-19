#import "MLNavigator.h"
#import "MLListDetailViewController.h"
#import "MLArtistViewController.h"
#import "MLLibraryManager.h"
#import "MLInnerTube.h"
#import "MLLocalization.h"
#import "MLPlaybackManager.h"
#import "MLBottomSheet.h"
#import <objc/runtime.h>

static const char *const MLSongMenuActionTargetKey = "ml.songmenu.target";

@interface MLSongMenuHandler : NSObject <UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) MLYTItem *item;
@property (nonatomic, weak) UIViewController *viewController;
@property (nonatomic, strong) NSArray *actionKeys;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic, assign) BOOL pickingPlaylist;
@property (nonatomic, assign) BOOL pickingSleepTimer;
@property (nonatomic, strong) NSArray *sleepTimerOptions;
@end

@implementation MLSongMenuHandler

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];

	if (_pickingSleepTimer) {
		if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) {
			objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			return;
		}
		if (actionSheet.destructiveButtonIndex != -1 && buttonIndex == actionSheet.destructiveButtonIndex) {
			[pm cancelSleepTimer];
		} else if ((NSUInteger)buttonIndex < _sleepTimerOptions.count) {
			NSInteger mins = [_sleepTimerOptions[(NSUInteger)buttonIndex] integerValue];
			if (mins == -1) {
				[pm setSleepTimerStopAfterCurrentSong];
			} else {
				[pm setSleepTimerWithMinutes:(NSUInteger)mins];
			}
		}
		objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (_pickingPlaylist) {
		if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) {
			objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			return;
		}
		if ((NSUInteger)buttonIndex < _playlists.count) {
			MLYTItem *pl = _playlists[(NSUInteger)buttonIndex];
			NSString *pid = pl.playlistId ?: pl.browseId;
			if (pid.length && _item.videoId.length) {
				[[MLInnerTube sharedClient] addVideoId:_item.videoId toPlaylistId:pid completion:nil];
			}
			objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			return;
		}
		// "New playlist..." tapped
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"new_playlist", nil)
		                                                message:nil
		                                               delegate:self
		                                      cancelButtonTitle:MLLocalizedString(@"cancel", nil)
		                                      otherButtonTitles:MLLocalizedString(@"create", nil), nil];
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		UITextField *tf = [alert textFieldAtIndex:0];
		tf.placeholder = MLLocalizedString(@"playlist_name_placeholder", nil);
		objc_setAssociatedObject(alert, MLSongMenuActionTargetKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[alert show];
		objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (buttonIndex < 0 || (NSUInteger)buttonIndex >= _actionKeys.count) {
		objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}
	NSString *act = _actionKeys[(NSUInteger)buttonIndex];
	MLLibraryManager *lib = [MLLibraryManager sharedManager];

	if ([act isEqualToString:@"toggle_like"]) {
		[lib toggleLikeForSong:_item completion:nil];
	} else if ([act isEqualToString:@"download"]) {
		[lib downloadSong:_item completion:nil];
	} else if ([act isEqualToString:@"remove_download"]) {
		[lib removeDownloadedSong:_item.videoId];
	} else if ([act isEqualToString:@"add_to_playlist"]) {
		[self presentPlaylistPicker];
		objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	} else if ([act isEqualToString:@"cancel_download"]) {
		[lib cancelDownloadForVideoId:_item.videoId];
	} else if ([act isEqualToString:@"save_queue_as_playlist"]) {
		[self promptSaveQueue];
		objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	} else if ([act isEqualToString:@"play_next"]) {
		[pm playNextItem:_item];
	} else if ([act isEqualToString:@"add_to_queue"]) {
		[pm appendQueueItems:@[_item]];
	} else if ([act isEqualToString:@"start_radio"]) {
		[pm playRadioForItem:_item];
	} else if ([act isEqualToString:@"go_to_artist"]) {
		if (_item.artistBrowseId.length > 0 && _viewController.navigationController) {
			NSString *artistName = _item.artists.count ? _item.artists[0] : (_item.subtitle ?: @"");
			MLArtistViewController *artistVC = [[MLArtistViewController alloc] initWithBrowseId:_item.artistBrowseId name:artistName];
			[_viewController.navigationController pushViewController:artistVC animated:YES];
		}
	} else if ([act isEqualToString:@"go_to_album"]) {
		if (_item.albumBrowseId.length > 0 && _viewController.navigationController) {
			MLYTItem *albumItem = [[MLYTItem alloc] init];
			albumItem.kind = MLYTKindAlbum;
			albumItem.browseId = _item.albumBrowseId;
			albumItem.title = _item.title;
			albumItem.thumbnailUrl = _item.thumbnailUrl;
			MLListDetailViewController *detailVC = [[MLListDetailViewController alloc] initWithAlbumItem:albumItem];
			[_viewController.navigationController pushViewController:detailVC animated:YES];
		}
	} else if ([act isEqualToString:@"copy_link"]) {
		if (_item.videoId.length > 0) {
			[UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://music.youtube.com/watch?v=%@", _item.videoId];
		}
	} else if ([act isEqualToString:@"sleep_timer"]) {
		[self presentSleepTimerPicker];
		objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	objc_setAssociatedObject(actionSheet, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)presentSleepTimerPicker
{
	[MLNavigator presentSleepTimerPickerFromViewController:_viewController];
}

- (void)promptSaveQueue
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	if (pm.queue.count == 0) return;

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"save_queue_as_playlist", nil)
	                                                message:MLLocalizedString(@"enter_playlist_name", nil)
	                                               delegate:self
	                                      cancelButtonTitle:MLLocalizedString(@"cancel", nil)
	                                      otherButtonTitles:MLLocalizedString(@"save", nil), nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *tf = [alert textFieldAtIndex:0];
	tf.placeholder = MLLocalizedString(@"playlist_name_placeholder", nil);
	tf.text = [NSString stringWithFormat:@"%@ (%lu)", MLLocalizedString(@"queue_playlist_default", nil), (unsigned long)pm.queue.count];
	alert.tag = 4001;
	objc_setAssociatedObject(alert, MLSongMenuActionTargetKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[alert show];
}

- (void)presentPlaylistPicker
{
	if (!_viewController) return;
	NSArray *playlists = [MLLibraryManager sharedManager].syncedPlaylists ?: @[];
	NSMutableArray *items = [NSMutableArray array];

	for (MLYTItem *pl in playlists) {
		NSString *pid = pl.playlistId ?: pl.browseId;
		[items addObject:[MLBottomSheetItem itemWithTitle:pl.title ?: @"Playlist" iconName:@"playlist_play" handler:^{
			if (pid.length && self->_item.videoId.length) {
				[[MLInnerTube sharedClient] addVideoId:self->_item.videoId toPlaylistId:pid completion:nil];
			}
		}]];
	}

	__weak MLSongMenuHandler *whandler = self;
	[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"new_playlist", nil) iconName:@"add" handler:^{
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"new_playlist", nil)
		                                                message:nil
		                                               delegate:whandler
		                                      cancelButtonTitle:MLLocalizedString(@"cancel", nil)
		                                      otherButtonTitles:MLLocalizedString(@"create", nil), nil];
		alert.alertViewStyle = UIAlertViewStylePlainTextInput;
		UITextField *tf = [alert textFieldAtIndex:0];
		tf.placeholder = MLLocalizedString(@"playlist_name_placeholder", nil);
		objc_setAssociatedObject(alert, MLSongMenuActionTargetKey, whandler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[alert show];
	}]];

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"add_to_playlist", nil) items:items];
	[menu showInViewController:_viewController];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (alertView.tag == 4001) {
		if (buttonIndex != alertView.cancelButtonIndex) {
			UITextField *tf = [alertView textFieldAtIndex:0];
			NSString *name = tf.text;
			NSArray *queue = [[MLPlaybackManager sharedManager].queue copy];
			if (queue.count > 0) {
				[[MLLibraryManager sharedManager] saveQueue:queue asPlaylistWithTitle:name completion:^(NSString *playlistId, NSString *error) {
					NSString *cleanName = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					if (!cleanName.length) cleanName = MLLocalizedString(@"queue_playlist_default", nil);
					NSString *msg = [NSString stringWithFormat:MLLocalizedString(@"playlist_saved_prompt_download", nil), cleanName, (unsigned long)queue.count];
					UIAlertView *dlAlert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"playlist_saved_title", nil)
					                                                  message:msg
					                                                 delegate:self
					                                        cancelButtonTitle:MLLocalizedString(@"later", nil)
					                                        otherButtonTitles:MLLocalizedString(@"download_now", nil), nil];
					dlAlert.tag = 4002;
					objc_setAssociatedObject(dlAlert, "MLSavedQueueKey", queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
					objc_setAssociatedObject(dlAlert, MLSongMenuActionTargetKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
					[dlAlert show];
				}];
			}
		}
		objc_setAssociatedObject(alertView, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	} else if (alertView.tag == 4002) {
		if (buttonIndex != alertView.cancelButtonIndex) {
			NSArray *queue = objc_getAssociatedObject(alertView, "MLSavedQueueKey");
			if (queue.count > 0) {
				[[MLLibraryManager sharedManager] downloadAllSongs:queue];
			}
		}
		objc_setAssociatedObject(alertView, "MLSavedQueueKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(alertView, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return;
	}

	if (buttonIndex != alertView.cancelButtonIndex) {
		UITextField *tf = [alertView textFieldAtIndex:0];
		NSString *title = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSString *vid = _item.videoId;
		if (title.length > 0 && vid.length > 0) {
			[[MLInnerTube sharedClient] createPlaylistWithTitle:title completion:^(NSString *playlistId, NSString *error) {
				if (playlistId.length > 0) {
					[[MLInnerTube sharedClient] addVideoId:vid toPlaylistId:playlistId completion:^(BOOL ok, NSString *err) {
						[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:nil];
					}];
				}
			}];
		}
	}
	objc_setAssociatedObject(alertView, MLSongMenuActionTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation MLNavigator

+ (void)openItem:(MLYTItem *)item fromViewController:(UIViewController *)vc
{
	if (!item)
		return;
	MLYTKind kind = item.kind;
	if (kind == MLYTKindUnknown) {
		if ([item.browseId hasPrefix:@"VL"] || item.playlistId.length > 0) {
			kind = MLYTKindPlaylist;
		} else if ([item.browseId hasPrefix:@"MPRE"]) {
			kind = MLYTKindAlbum;
		} else if ([item.browseId hasPrefix:@"UC"] || [item.browseId hasPrefix:@"MPLA"]) {
			kind = MLYTKindArtist;
		} else if (item.videoId.length > 0) {
			kind = MLYTKindSong;
		}
	}

	if (item.videoId.length > 0 && kind != MLYTKindAlbum && kind != MLYTKindPlaylist && kind != MLYTKindArtist) {
		[self playSong:item fromViewController:vc];
		return;
	}

	switch (kind) {
		case MLYTKindSong:
		case MLYTKindVideo:
			[self playSong:item fromViewController:vc];
			break;
		case MLYTKindAlbum: {
			MLListDetailViewController *detail = [[MLListDetailViewController alloc] initWithAlbumItem:item];
			[vc.navigationController pushViewController:detail animated:YES];
			break;
		}
		case MLYTKindPlaylist: {
			NSString *pid = item.playlistId ?: item.browseId;
			if (!pid)
				return;
			MLListDetailViewController *detail = [[MLListDetailViewController alloc] initWithPlaylistId:pid title:item.title thumbnail:item.thumbnailUrl];
			[vc.navigationController pushViewController:detail animated:YES];
			break;
		}
		case MLYTKindArtist: {
			NSString *bid = item.browseId;
			if (!bid.length)
				return;
			if ([bid hasPrefix:@"MPLAUC"])
				bid = [bid substringFromIndex:4];
			MLArtistViewController *artist = [[MLArtistViewController alloc] initWithBrowseId:bid name:item.title];
			[vc.navigationController pushViewController:artist animated:YES];
			break;
		}
		default:
			break;
	}
}

+ (void)playSong:(MLYTItem *)item fromViewController:(UIViewController *)vc
{
	[[MLPlaybackManager sharedManager] playRadioForItem:item];
}

+ (void)presentSongMenuForItem:(MLYTItem *)item fromViewController:(UIViewController *)vc
{
	if (!item || !vc)
		return;
	if (item.kind == MLYTKindPlaylist || item.kind == MLYTKindAlbum || item.kind == MLYTKindArtist || item.videoId.length == 0) {
		[self openItem:item fromViewController:vc];
		return;
	}

	MLSongMenuHandler *handler = [[MLSongMenuHandler alloc] init];
	handler.item = item;
	handler.viewController = vc;

	MLLibraryManager *lib = [MLLibraryManager sharedManager];
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	NSMutableArray *items = [NSMutableArray array];

	// Like / Unlike
	BOOL isLiked = [lib isSongLiked:item.videoId];
	NSString *likeTitle = isLiked ? MLLocalizedString(@"unlike_song", nil) : MLLocalizedString(@"like_song", nil);
	NSString *likeIcon = isLiked ? @"favorite" : @"favorite_border";
	[items addObject:[MLBottomSheetItem itemWithTitle:likeTitle iconName:likeIcon handler:^{
		[lib toggleLikeForSong:item completion:nil];
	}]];

	// Download / Remove
	if ([lib isSongDownloaded:item.videoId]) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"remove_download", nil) subtitle:nil iconName:@"delete" isDestructive:YES handler:^{
			[lib removeDownloadedSong:item.videoId];
		}]];
	} else if ([lib isSongDownloading:item.videoId]) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"cancel_download", nil) subtitle:nil iconName:@"close" isDestructive:YES handler:^{
			[lib cancelDownloadForVideoId:item.videoId];
		}]];
	} else {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"download_song", nil) iconName:@"download" handler:^{
			[lib downloadSong:item completion:nil];
		}]];
	}

	// Add to playlist
	if ([[MLInnerTube sharedClient] loggedIn]) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"add_to_playlist", nil) iconName:@"playlist_add" handler:^{
			[handler presentPlaylistPicker];
		}]];
	}

	// Play next
	[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"play_next", nil) iconName:@"playlist_play" handler:^{
		[pm playNextItem:item];
	}]];

	// Add to queue
	[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"add_to_queue", nil) iconName:@"queue_music" handler:^{
		[pm appendQueueItems:@[item]];
	}]];

	// Start radio
	[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"start_radio", nil) iconName:@"radio" handler:^{
		[pm playRadioForItem:item];
	}]];

	// Go to artist
	if (item.artistBrowseId.length > 0 && vc.navigationController) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"go_to_artist", nil) iconName:@"person" handler:^{
			NSString *artistName = item.artists.count ? item.artists[0] : (item.subtitle ?: @"");
			MLArtistViewController *artistVC = [[MLArtistViewController alloc] initWithBrowseId:item.artistBrowseId name:artistName];
			[vc.navigationController pushViewController:artistVC animated:YES];
		}]];
	}

	// Go to album
	if (item.albumBrowseId.length > 0 && vc.navigationController) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"go_to_album", nil) iconName:@"album" handler:^{
			MLYTItem *albumItem = [[MLYTItem alloc] init];
			albumItem.kind = MLYTKindAlbum;
			albumItem.browseId = item.albumBrowseId;
			albumItem.title = item.title;
			albumItem.thumbnailUrl = item.thumbnailUrl;
			MLListDetailViewController *detailVC = [[MLListDetailViewController alloc] initWithAlbumItem:albumItem];
			[vc.navigationController pushViewController:detailVC animated:YES];
		}]];
	}

	// Copy link
	if (item.videoId.length > 0) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"copy_link", nil) iconName:@"content_copy" handler:^{
			[UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"https://music.youtube.com/watch?v=%@", item.videoId];
		}]];
	}

	// Sleep timer
	NSString *timerTitle = MLLocalizedString(@"sleep_timer", nil);
	if (pm.sleepTimerActive) {
		NSTimeInterval rem = pm.sleepTimerRemainingTime;
		NSInteger mins = (NSInteger)ceil(rem / 60.0);
		if (mins > 0) {
			timerTitle = [NSString stringWithFormat:MLLocalizedString(@"sleep_timer_active_min", nil), (long)mins];
		}
	}
	[items addObject:[MLBottomSheetItem itemWithTitle:timerTitle iconName:@"bedtime" handler:^{
		[handler presentSleepTimerPicker];
	}]];

	NSString *subtitle = item.artists.count ? [item.artists componentsJoinedByString:@", "] : (item.subtitle ?: @"");
	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:item.title subtitle:subtitle items:items];
	[menu showInViewController:vc];
}

+ (void)presentSleepTimerPickerFromViewController:(UIViewController *)vc
{
	if (!vc) return;
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	NSMutableArray *items = [NSMutableArray array];

	NSArray *options = @[
		@{@"min": @15, @"title": MLLocalizedString(@"sleep_timer_15m", nil)},
		@{@"min": @30, @"title": MLLocalizedString(@"sleep_timer_30m", nil)},
		@{@"min": @45, @"title": MLLocalizedString(@"sleep_timer_45m", nil)},
		@{@"min": @60, @"title": MLLocalizedString(@"sleep_timer_60m", nil)},
		@{@"min": @(-1), @"title": MLLocalizedString(@"sleep_timer_end_of_song", nil)},
	];

	for (NSDictionary *opt in options) {
		NSInteger m = [opt[@"min"] integerValue];
		NSString *t = opt[@"title"];
		[items addObject:[MLBottomSheetItem itemWithTitle:t iconName:@"timer" handler:^{
			if (m == -1) {
				[pm setSleepTimerStopAfterCurrentSong];
			} else {
				[pm setSleepTimerWithMinutes:(NSUInteger)m];
			}
		}]];
	}

	if (pm.sleepTimerActive) {
		[items addObject:[MLBottomSheetItem itemWithTitle:MLLocalizedString(@"sleep_timer_off", nil)
		                                         subtitle:nil
		                                         iconName:@"close"
		                                    isDestructive:YES
		                                          handler:^{
			[pm cancelSleepTimer];
		}]];
	}

	MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"sleep_timer", nil) items:items];
	[menu showInViewController:vc];
}

@end
