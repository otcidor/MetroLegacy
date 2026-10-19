#import "MLListDetailViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLComponents.h"
#import "MLNavigator.h"
#import "MLInnerTube.h"
#import "MLPlaybackManager.h"
#import "MLLibraryManager.h"
#import "MLLocalization.h"
#import "MLBottomSheet.h"
#import <QuartzCore/QuartzCore.h>

typedef enum {
	MLDetailModeAlbum,
	MLDetailModePlaylist,
	MLDetailModeLiked,
	MLDetailModeDownloaded,
	MLDetailModeCached,
	MLDetailModeHistory,
	MLDetailModeTop50,
} MLDetailMode;

@interface MLListDetailViewController ()
{
	MLDetailMode _mode;
	NSString *_browseId;
	NSString *_playlistId;
	NSString *_initialTitle;
	NSString *_initialThumb;

	UITableView *_table;
	UIView *_headerView;
	UIView *_topBounceView;
	CAGradientLayer *_headerGradient;
	UIColor *_accentColor;
	UIView *_artShadow;
	UIImageView *_artView;
	UILabel *_titleLabel;
	UILabel *_subtitleLabel;
	UIButton *_playButton;
	UIButton *_shuffleButton;

	UIActivityIndicatorView *_spinner;
	NSMutableArray *_tracks;
	NSString *_nextContinuation;
	BOOL _loading;
	UIButton *_downloadButton;
}
@end

@implementation MLListDetailViewController

- (id)initWithAlbumItem:(MLYTItem *)item
{
	self = [super init];
	if (self) {
		_mode = MLDetailModeAlbum;
		_browseId = [item.browseId copy];
		_playlistId = [item.playlistId copy];
		_initialTitle = [item.title copy];
		_initialThumb = [item.thumbnailUrl copy];
	}
	return self;
}

- (id)initWithPlaylistId:(NSString *)playlistId title:(NSString *)title thumbnail:(NSString *)thumbnail
{
	self = [super init];
	if (self) {
		_mode = MLDetailModePlaylist;
		_playlistId = [playlistId copy];
		_initialTitle = [title copy];
		_initialThumb = [thumbnail copy];
	}
	return self;
}

- (id)initWithLikedSongs
{
	self = [super init];
	if (self) {
		_mode = MLDetailModeLiked;
		_initialTitle = MLLocalizedString(@"liked_songs", nil);
	}
	return self;
}

- (id)initWithDownloadedSongs
{
	self = [super init];
	if (self) {
		_mode = MLDetailModeDownloaded;
		_initialTitle = MLLocalizedString(@"downloaded_songs", nil);
	}
	return self;
}

- (id)initWithCachedSongs
{
	self = [super init];
	if (self) {
		_mode = MLDetailModeCached;
		_initialTitle = MLLocalizedString(@"cached_songs", nil);
	}
	return self;
}

- (id)initWithHistorySongs
{
	self = [super init];
	if (self) {
		_mode = MLDetailModeHistory;
		_initialTitle = MLLocalizedString(@"history_songs", nil);
	}
	return self;
}

- (id)initWithTop50Songs
{
	self = [super init];
	if (self) {
		_mode = MLDetailModeTop50;
		_initialTitle = MLLocalizedString(@"my_top_50", nil);
	}
	return self;
}

- (void)dealloc
{
	_table.dataSource = nil;
	_table.delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	_tracks = [NSMutableArray array];

	_table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.backgroundColor = [UIColor clearColor];
	_table.dataSource = self;
	_table.delegate = self;
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	_table.rowHeight = MLLengthListItem;
	[self.view addSubview:_table];

	self.title = _initialTitle;

	if (_mode != MLDetailModeDownloaded) {
		UIButton *dlBtn = [UIButton buttonWithType:UIButtonTypeCustom];
		dlBtn.frame = CGRectMake(0, 0, 32.0f, 32.0f);
		dlBtn.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
		dlBtn.layer.cornerRadius = 16.0f;
		dlBtn.layer.borderWidth = 0.5f;
		dlBtn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
		[dlBtn setImage:[MLIcon icon:@"download" size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
		[dlBtn addTarget:self action:@selector(downloadAllTap) forControlEvents:UIControlEventTouchUpInside];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:dlBtn];
		_downloadButton = dlBtn;
	}

	[self buildHeader];
	_table.tableHeaderView = _headerView;

	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	_spinner.color = [MLTheme primary];
	_spinner.center = CGPointMake(self.view.bounds.size.width / 2.0f, _headerView.frame.size.height + 36.0f);
	_spinner.hidesWhenStopped = YES;
	[_table addSubview:_spinner];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(playbackChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(libraryUpdated:)
	                                             name:MLLibraryDidUpdateNotification
	                                           object:nil];

	[self load];
	[self updateDownloadButtonState];
}

- (void)updateDownloadButtonState
{
	if (!_downloadButton || _mode == MLDetailModeDownloaded) return;
	MLLibraryManager *lib = [MLLibraryManager sharedManager];

	if (_tracks.count == 0) {
		[_downloadButton setImage:[MLIcon icon:@"download" size:18.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
		return;
	}

	BOOL anyDownloading = NO;
	NSUInteger downloadedCount = 0;
	for (MLYTItem *it in _tracks) {
		if (![it isKindOfClass:[MLYTItem class]] || !it.videoId.length) continue;
		if ([lib isSongDownloading:it.videoId]) {
			anyDownloading = YES;
		}
		if ([lib isSongDownloaded:it.videoId]) {
			downloadedCount++;
		}
	}

	if (anyDownloading || [lib isBatchDownloading]) {
		[_downloadButton setImage:[MLIcon icon:@"close" size:18.0f color:[MLTheme primary]] forState:UIControlStateNormal];
	} else if (downloadedCount == _tracks.count) {
		[_downloadButton setImage:[MLIcon icon:@"download_done" size:18.0f color:[UIColor colorWithRed:0.18f green:0.65f blue:0.45f alpha:1.0f]] forState:UIControlStateNormal];
	} else {
		[_downloadButton setImage:[MLIcon icon:@"download" size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	}
}

- (void)downloadAllTap
{
	if (_tracks.count == 0)
		return;

	MLLibraryManager *lib = [MLLibraryManager sharedManager];

	BOOL anyDownloading = NO;
	NSUInteger dlCount = 0;
	for (MLYTItem *it in _tracks) {
		if (![it isKindOfClass:[MLYTItem class]] || !it.videoId.length) continue;
		if ([lib isSongDownloading:it.videoId]) {
			anyDownloading = YES;
		}
		if ([lib isSongDownloaded:it.videoId]) {
			dlCount++;
		}
	}

	if (anyDownloading || [lib isBatchDownloading]) {
		__weak MLListDetailViewController *wself = self;
		MLBottomSheetItem *itCancel = [MLBottomSheetItem itemWithTitle:MLLocalizedString(@"cancel_downloads", nil)
		                                                      subtitle:nil
		                                                      iconName:@"close"
		                                                 isDestructive:YES
		                                                       handler:^{
			[[MLLibraryManager sharedManager] cancelAllDownloads];
			[wself updateDownloadButtonState];
		}];
		MLBottomSheetMenu *menu = [MLBottomSheetMenu menuWithTitle:MLLocalizedString(@"downloads_in_progress", nil)
		                                                     items:@[itCancel]];
		[menu showInView:self.view];
		return;
	}

	if (dlCount == _tracks.count) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"download_completed_title", nil)
		                                                message:MLLocalizedString(@"all_songs_downloaded", nil)
		                                               delegate:nil
		                                      cancelButtonTitle:MLLocalizedString(@"ok", nil)
		                                      otherButtonTitles:nil];
		[alert show];
		return;
	}

	[lib downloadAllSongs:_tracks];
	[self updateDownloadButtonState];
}

- (void)playbackChanged:(NSNotification *)note
{
	static NSString *lastVideoId = nil;
	NSString *curId = [MLPlaybackManager sharedManager].currentItem.videoId ?: @"";
	if ([curId isEqualToString:lastVideoId ?: @""])
		return;
	lastVideoId = [curId copy];
	[_table reloadData];
}

- (void)libraryUpdated:(NSNotification *)note
{
	if (_mode == MLDetailModeLiked) {
		[_tracks setArray:[MLLibraryManager sharedManager].likedSongs];
		[self applyHeaderInfo:@{}];
	} else if (_mode == MLDetailModeDownloaded) {
		[_tracks setArray:[MLLibraryManager sharedManager].downloadedSongs];
		[self applyHeaderInfo:@{}];
	} else if (_mode == MLDetailModeCached) {
		[_tracks setArray:[MLLibraryManager sharedManager].cachedSongs];
		[self applyHeaderInfo:@{}];
	} else if (_mode == MLDetailModeHistory) {
		[_tracks setArray:[MLLibraryManager sharedManager].historySongs];
		[self applyHeaderInfo:@{}];
	} else if (_mode == MLDetailModeTop50) {
		[_tracks setArray:[MLLibraryManager sharedManager].top50Songs];
		[self applyHeaderInfo:@{}];
	}
	[_table reloadData];
	[self updateDownloadButtonState];
}

- (void)updateGradientColors
{
	UIColor *accent = _accentColor ?: [MLTheme surfaceContainerHigh];
	CGFloat offsetY = _table ? _table.contentOffset.y : 0.0f;
	CGFloat headerH = _headerView ? _headerView.bounds.size.height : 260.0f;
	UIColor *seamColor = [MLTheme applyNavigationBarGradientWithAccent:accent
	                                                      scrollOffset:offsetY
	                                                      headerHeight:headerH
	                                            toNavigationController:self.navigationController];
	if (_headerGradient) {
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		_headerGradient.colors = @[
			(id)seamColor.CGColor,
			(id)[MLTheme background].CGColor
		];
		[CATransaction commit];
	}
	if (_topBounceView) {
		_topBounceView.backgroundColor = seamColor;
	}
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self updateGradientColors];
	[_table reloadData];
	[self updateDownloadButtonState];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	if ([self isMovingFromParentViewController]) {
		[MLTheme resetNavigationBarForNavigationController:self.navigationController];
	}
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	[self updateGradientColors];
}

- (void)buildHeader
{
	CGRect screen = self.view.bounds;
	CGFloat w = screen.size.width;
	CGFloat artSide = MIN(176.0f, w - 104.0f);
	CGFloat y = 18.0f;

	CGFloat titleY = y + artSide + 14.0f;
	CGFloat subY = titleY + 26.0f;
	CGFloat btnY = subY + 24.0f;
	CGFloat btnH = 44.0f;
	CGFloat headerH = btnY + btnH + 18.0f;

	_headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerH)];
	_headerView.backgroundColor = [UIColor clearColor];

	_topBounceView = [[UIView alloc] initWithFrame:CGRectMake(0, -320.0f, w, 320.0f)];
	[_headerView addSubview:_topBounceView];

	_headerGradient = [CAGradientLayer layer];
	_headerGradient.frame = _headerView.bounds;
	_accentColor = [MLTheme surfaceContainerHigh];
	[_headerView.layer insertSublayer:_headerGradient atIndex:0];

	_artShadow = [[UIView alloc] initWithFrame:CGRectMake((w - artSide) / 2.0f, y, artSide, artSide)];
	_artShadow.backgroundColor = [UIColor clearColor];
	_artShadow.layer.shadowColor = [UIColor blackColor].CGColor;
	_artShadow.layer.shadowOpacity = 0.45f;
	_artShadow.layer.shadowOffset = CGSizeMake(0, 6.0f);
	_artShadow.layer.shadowRadius = 12.0f;
	[_headerView addSubview:_artShadow];

	_artView = [[UIImageView alloc] initWithFrame:_artShadow.bounds];
	_artView.contentMode = UIViewContentModeScaleAspectFill;
	_artView.clipsToBounds = YES;
	_artView.layer.cornerRadius = 14.0f;
	_artView.layer.borderWidth = 0.5f;
	_artView.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.15f].CGColor;
	[_artShadow addSubview:_artView];

	if (_mode == MLDetailModeLiked && !_initialThumb.length) {
		_accentColor = [MLTheme primary];
		_artView.backgroundColor = _accentColor;
		_artView.contentMode = UIViewContentModeCenter;
		_artView.image = [MLIcon icon:@"favorite" size:64.0f color:[UIColor whiteColor]];
	} else if (_mode == MLDetailModeDownloaded) {
		_accentColor = [UIColor colorWithRed:0.18f green:0.65f blue:0.45f alpha:1.0f];
		_artView.backgroundColor = _accentColor;
		_artView.contentMode = UIViewContentModeCenter;
		_artView.image = [MLIcon icon:@"download_done" size:64.0f color:[UIColor whiteColor]];
	} else if (_mode == MLDetailModeCached) {
		_accentColor = [UIColor colorWithRed:0.22f green:0.52f blue:0.85f alpha:1.0f];
		_artView.backgroundColor = _accentColor;
		_artView.contentMode = UIViewContentModeCenter;
		_artView.image = [MLIcon icon:@"cached" size:64.0f color:[UIColor whiteColor]];
	} else if (_mode == MLDetailModeHistory) {
		_accentColor = [UIColor colorWithRed:0.58f green:0.38f blue:0.82f alpha:1.0f];
		_artView.backgroundColor = _accentColor;
		_artView.contentMode = UIViewContentModeCenter;
		_artView.image = [MLIcon icon:@"history" size:64.0f color:[UIColor whiteColor]];
	} else if (_mode == MLDetailModeTop50) {
		_accentColor = [UIColor colorWithRed:0.95f green:0.60f blue:0.18f alpha:1.0f];
		_artView.backgroundColor = _accentColor;
		_artView.contentMode = UIViewContentModeCenter;
		_artView.image = [MLIcon icon:@"trending_up" size:64.0f color:[UIColor whiteColor]];
	} else if (_initialThumb.length) {
		[self loadHeaderThumb:_initialThumb];
	} else {
		_artView.image = [MLImageCache placeholderImageWithSize:_artView.frame.size];
	}

	[self updateGradientColors];

	_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0f, titleY, w - 40.0f, 24.0f)];
	_titleLabel.font = [UIFont boldSystemFontOfSize:19.0f];
	_titleLabel.textColor = [MLTheme onSurface];
	_titleLabel.textAlignment = NSTextAlignmentCenter;
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.text = _initialTitle;
	[_headerView addSubview:_titleLabel];

	_subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0f, subY, w - 40.0f, 18.0f)];
	_subtitleLabel.font = [MLTheme fontBodyMedium];
	_subtitleLabel.textColor = [MLTheme onSurfaceVariant];
	_subtitleLabel.textAlignment = NSTextAlignmentCenter;
	_subtitleLabel.backgroundColor = [UIColor clearColor];
	[_headerView addSubview:_subtitleLabel];

	CGFloat btnW = (w - 48.0f - 12.0f) / 2.0f;

	_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_playButton.frame = CGRectMake(24.0f, btnY, btnW, btnH);
	_playButton.backgroundColor = [MLTheme primary];
	_playButton.layer.cornerRadius = btnH / 2.0f;
	_playButton.titleLabel.font = [MLTheme fontTitleSmall];
	[_playButton setImage:[MLIcon icon:@"play_arrow" size:20.0f color:[UIColor whiteColor]] forState:UIControlStateNormal];
	[_playButton setTitle:[NSString stringWithFormat:@"  %@", MLLocalizedString(@"play_all", nil)] forState:UIControlStateNormal];
	[_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[_playButton addTarget:self action:@selector(playAll:) forControlEvents:UIControlEventTouchUpInside];
	[_headerView addSubview:_playButton];

	_shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_shuffleButton.frame = CGRectMake(24.0f + btnW + 12.0f, btnY, btnW, btnH);
	_shuffleButton.backgroundColor = [MLTheme surfaceContainerHigh];
	_shuffleButton.layer.cornerRadius = btnH / 2.0f;
	_shuffleButton.layer.borderWidth = 1.0f;
	_shuffleButton.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.30f].CGColor;
	_shuffleButton.titleLabel.font = [MLTheme fontTitleSmall];
	[_shuffleButton setImage:[MLIcon icon:@"shuffle" size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_shuffleButton setTitle:[NSString stringWithFormat:@"  %@", MLLocalizedString(@"shuffle_all", nil)] forState:UIControlStateNormal];
	[_shuffleButton setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
	[_shuffleButton addTarget:self action:@selector(shuffleAll:) forControlEvents:UIControlEventTouchUpInside];
	[_headerView addSubview:_shuffleButton];
}

- (void)loadHeaderThumb:(NSString *)thumbUrl
{
	_artView.contentMode = UIViewContentModeScaleAspectFill;
	__weak MLListDetailViewController *wself = self;
	[MLImageCache loadImageAtURLString:thumbUrl
	                          intoView:_artView
	                           fitSize:_artView.frame.size
	                      cornerRadius:14.0f
	                       placeholder:[MLImageCache placeholderImageWithSize:_artView.frame.size]
	                        completion:^(UIImage *image) {
		MLListDetailViewController *s = wself;
		if (!s || !image)
			return;
		s->_accentColor = [MLTheme dominantColorForImage:image];
		[s updateGradientColors];
	}];
}

- (void)applyHeaderInfo:(NSDictionary *)info
{
	NSString *title = info[@"title"];
	NSString *sub = info[@"subtitle"];
	NSString *thumb = info[@"thumbnailUrl"];
	if (title.length) {
		_titleLabel.text = title;
		self.title = title;
	}
	if (sub.length)
		_subtitleLabel.text = sub;
	else {
		NSString *fmt = (_tracks.count == 1) ? MLLocalizedString(@"songs_count_single", nil) : MLLocalizedString(@"songs_count_plural", nil);
		_subtitleLabel.text = [NSString stringWithFormat:fmt, (unsigned long)_tracks.count];
	}
	if (thumb.length)
		[self loadHeaderThumb:thumb];
}

- (NSString *)currentCacheKey
{
	if (_mode == MLDetailModeAlbum && _browseId.length)
		return _browseId;
	if (_playlistId.length)
		return _playlistId;
	return _browseId;
}

- (void)load
{
	if (_mode == MLDetailModeDownloaded) {
		[_tracks setArray:[MLLibraryManager sharedManager].downloadedSongs];
		[self applyHeaderInfo:@{}];
		[_table reloadData];
		return;
	}
	if (_mode == MLDetailModeCached) {
		[_tracks setArray:[MLLibraryManager sharedManager].cachedSongs];
		[self applyHeaderInfo:@{}];
		[_table reloadData];
		return;
	}
	if (_mode == MLDetailModeHistory) {
		[_tracks setArray:[MLLibraryManager sharedManager].historySongs];
		[self applyHeaderInfo:@{}];
		[_table reloadData];
		return;
	}
	if (_mode == MLDetailModeTop50) {
		[_tracks setArray:[MLLibraryManager sharedManager].top50Songs];
		[self applyHeaderInfo:@{}];
		[_table reloadData];
		return;
	}
	if (_mode == MLDetailModeLiked) {
		NSArray *localLiked = [MLLibraryManager sharedManager].likedSongs;
		if (localLiked.count > 0) {
			[_tracks setArray:localLiked];
			[self applyHeaderInfo:@{}];
			[_table reloadData];
		}
		if ([[MLInnerTube sharedClient] loggedIn]) {
			_loading = YES;
			if (_tracks.count == 0) [_spinner startAnimating];
			[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:^(BOOL ok, NSString *err) {
				_loading = NO;
				[_spinner stopAnimating];
				[_tracks setArray:[MLLibraryManager sharedManager].likedSongs];
				[self applyHeaderInfo:@{}];
				[_table reloadData];
			}];
		} else {
			[self applyHeaderInfo:@{}];
		}
		return;
	}

	NSString *cacheKey = [self currentCacheKey];
	if (cacheKey.length) {
		NSDictionary *cached = [[MLLibraryManager sharedManager] cachedPlaylistForKey:cacheKey];
		NSArray *cachedTracks = cached[@"tracks"];
		if (cachedTracks.count > 0) {
			[_tracks setArray:cachedTracks];
			[self applyHeaderInfo:cached[@"header"] ?: @{}];
			[_table reloadData];
		}
	}

	if (_loading)
		return;
	_loading = YES;
	if (_tracks.count == 0)
		[_spinner startAnimating];

	void (^done)(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) =
	    ^(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) {
		_loading = NO;
		[_spinner stopAnimating];
		if (err) {
			if (_tracks.count == 0)
				self.title = err;
			return;
		}
		if (tracks.count > 0) {
			[_tracks setArray:tracks];
			NSString *ck = [self currentCacheKey];
			if (ck.length) {
				NSMutableDictionary *hdr = [NSMutableDictionary dictionaryWithDictionary:header ?: @{}];
				if (![hdr[@"title"] length] && _initialTitle.length)
					hdr[@"title"] = _initialTitle;
				if (![hdr[@"thumbnailUrl"] length] && _initialThumb.length)
					hdr[@"thumbnailUrl"] = _initialThumb;
				[[MLLibraryManager sharedManager] cachePlaylistHeader:hdr tracks:_tracks forKey:ck];
			}
		}
		_nextContinuation = next;
		[self applyHeaderInfo:header ?: @{}];
		[_table reloadData];
		[self updateDownloadButtonState];
	};

	if (_mode == MLDetailModeAlbum && _browseId) {
		if ([_browseId hasPrefix:@"VL"]) {
			_mode = MLDetailModePlaylist;
			_playlistId = _browseId;
			[[MLInnerTube sharedClient] playlistWithId:_playlistId continuation:nil
			                                completion:^(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) {
				done(header, tracks, next, err);
			}];
			return;
		}
		[[MLInnerTube sharedClient] albumWithBrowseId:_browseId
		                                  completion:^(NSDictionary *header, NSArray *tracks, NSString *err) {
			if (tracks.count == 0 && self->_playlistId.length > 0) {
				[[MLInnerTube sharedClient] playlistWithId:self->_playlistId continuation:nil
				                                completion:^(NSDictionary *h, NSArray *t, NSString *n, NSString *e) {
					done(h ?: header, t, n, e);
				}];
				return;
			}
			done(header, tracks, nil, err);
		}];
	} else if (_mode == MLDetailModePlaylist && _playlistId) {
		if ([_playlistId hasPrefix:@"local_pl_"]) {
			_loading = NO;
			[_spinner stopAnimating];
			[self updateDownloadButtonState];
			return;
		}
		if ([_playlistId hasPrefix:@"MPRE"]) {
			_mode = MLDetailModeAlbum;
			_browseId = _playlistId;
			[[MLInnerTube sharedClient] albumWithBrowseId:_browseId
			                                  completion:^(NSDictionary *header, NSArray *tracks, NSString *err) {
				done(header, tracks, nil, err);
			}];
			return;
		}
		[[MLInnerTube sharedClient] playlistWithId:_playlistId continuation:nil
		                                completion:^(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) {
			done(header, tracks, next, err);
		}];
	} else {
		_loading = NO;
		[_spinner stopAnimating];
		[self updateDownloadButtonState];
		if (_tracks.count == 0)
			self.title = MLLocalizedString(@"not_available", nil);
	}
}

- (void)loadMore
{
	NSString *cont = _nextContinuation;
	if (!cont || _loading)
		return;
	_loading = YES;
	NSString *pid = _playlistId;
	[[MLInnerTube sharedClient] playlistWithId:pid continuation:cont
	                                completion:^(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) {
		_loading = NO;
		if (tracks.count) {
			[_tracks addObjectsFromArray:tracks];
			_nextContinuation = next;
			NSString *ck = [self currentCacheKey];
			if (ck.length) {
				NSDictionary *hdr = @{
					@"title" : _titleLabel.text ?: _initialTitle ?: @"",
					@"subtitle" : _subtitleLabel.text ?: @"",
					@"thumbnailUrl" : _initialThumb ?: @""
				};
				[[MLLibraryManager sharedManager] cachePlaylistHeader:hdr tracks:_tracks forKey:ck];
			}
			[_table reloadData];
		}
	}];
}

- (void)playAll:(UIButton *)sender
{
	if (_tracks.count)
		[[MLPlaybackManager sharedManager] playQueue:_tracks startIndex:0];
}

- (void)shuffleAll:(UIButton *)sender
{
	if (_tracks.count)
		[[MLPlaybackManager sharedManager] playShuffledQueue:_tracks];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	NSUInteger n = _tracks.count;
	if (_nextContinuation)
		n++;
	return n;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.row == _tracks.count) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"more"];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"more"];
			cell.textLabel.text = MLLocalizedString(@"load_more", nil);
			cell.textLabel.textColor = [MLTheme primary];
			cell.textLabel.font = [MLTheme fontTitleSmall];
			cell.textLabel.textAlignment = NSTextAlignmentCenter;
			cell.backgroundColor = [UIColor clearColor];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		return cell;
	}
	MLSongCell *cell = [tableView dequeueReusableCellWithIdentifier:@"song"];
	if (!cell)
		cell = [[MLSongCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"song"];
	MLYTItem *it = _tracks[indexPath.row];
	BOOL isPlaying = [it.videoId isEqualToString:[MLPlaybackManager sharedManager].currentItem.videoId];
	[cell fillWithItem:it isPlaying:isPlaying];
	__weak MLListDetailViewController *wself = self;
	cell.moreTapped = ^(MLYTItem *tapped) {
		[MLNavigator presentSongMenuForItem:tapped fromViewController:wself];
	};
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath.row == _tracks.count) {
		[self loadMore];
		return;
	}
	[[MLPlaybackManager sharedManager] playQueue:_tracks startIndex:indexPath.row];
}

@end
