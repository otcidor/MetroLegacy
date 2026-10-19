#import "MLArtistViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLImageCache.h"
#import "MLComponents.h"
#import "MLNavigator.h"
#import "MLInnerTube.h"
#import "MLPlaybackManager.h"
#import "MLLocalization.h"
#import <QuartzCore/QuartzCore.h>

/*
 * Artist page: gradient header + circular shadowed avatar + Play/Shuffle buttons + sections.
 */
@interface MLArtistViewController ()
{
	NSString *_browseId;
	NSString *_name;
	NSDictionary *_header;

	UIView *_headerView;
	UIView *_topBounceView;
	CAGradientLayer *_headerGradient;
	UIColor *_accentColor;

	NSMutableArray *_rowSpecs;
	NSMutableArray *_allArtistSongs;
	UITableView *_table;
	BOOL _loading;
}
@end

@implementation MLArtistViewController

- (id)initWithBrowseId:(NSString *)browseId name:(NSString *)name
{
	self = [super init];
	if (self) {
		_browseId = [browseId copy];
		_name = [name copy];
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
	self.title = _name;
	_accentColor = [MLTheme surfaceContainerHigh];

	_rowSpecs = [NSMutableArray array];
	_allArtistSongs = [NSMutableArray array];

	_table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.backgroundColor = [UIColor clearColor];
	_table.dataSource = self;
	_table.delegate = self;
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	[self.view addSubview:_table];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(playbackChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];

	[self load];
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

- (void)updateGradientColors
{
	UIColor *accent = _accentColor ?: [MLTheme surfaceContainerHigh];
	CGFloat offsetY = _table ? _table.contentOffset.y : 0.0f;
	CGFloat headerH = _headerView ? _headerView.bounds.size.height : 240.0f;
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

- (void)setupHeaderView:(NSDictionary *)header
{
	if (!header)
		return;
	CGFloat W = self.view.bounds.size.width;
	CGFloat avatarSize = 132.0f;
	BOOL hasSongs = (_allArtistSongs.count > 0);
	CGFloat h = avatarSize + (hasSongs ? 114.0f : 62.0f);

	UIView *hv = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, h)];
	hv.backgroundColor = [UIColor clearColor];
	_headerView = hv;

	_topBounceView = [[UIView alloc] initWithFrame:CGRectMake(0, -320.0f, W, 320.0f)];
	[hv addSubview:_topBounceView];

	CAGradientLayer *grad = [CAGradientLayer layer];
	grad.frame = hv.bounds;
	_headerGradient = grad;
	[hv.layer insertSublayer:grad atIndex:0];

	[self updateGradientColors];

	UIView *avatarShadow = [[UIView alloc] initWithFrame:CGRectMake((W - avatarSize) / 2.0f, 16.0f, avatarSize, avatarSize)];
	avatarShadow.backgroundColor = [UIColor clearColor];
	avatarShadow.layer.shadowColor = [UIColor blackColor].CGColor;
	avatarShadow.layer.shadowOpacity = 0.45f;
	avatarShadow.layer.shadowOffset = CGSizeMake(0, 6.0f);
	avatarShadow.layer.shadowRadius = 12.0f;
	[hv addSubview:avatarShadow];

	UIImageView *avatar = [[UIImageView alloc] initWithFrame:avatarShadow.bounds];
	avatar.contentMode = UIViewContentModeScaleAspectFill;
	avatar.clipsToBounds = YES;
	avatar.layer.cornerRadius = avatarSize / 2.0f;
	avatar.layer.borderWidth = 1.5f;
	avatar.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.20f].CGColor;
	[avatarShadow addSubview:avatar];

	NSString *thumb = header[@"thumbnailUrl"];
	if (thumb) {
		__weak MLArtistViewController *wself = self;
		[MLImageCache loadImageAtURLString:thumb
		                          intoView:avatar
		                           fitSize:avatar.frame.size
		                      cornerRadius:avatarSize / 2.0f
		                       placeholder:[MLImageCache placeholderImageWithSize:avatar.frame.size]
		                        completion:^(UIImage *image) {
			MLArtistViewController *s = wself;
			if (s && image) {
				s->_accentColor = [MLTheme dominantColorForImage:image];
				[s updateGradientColors];
			}
		}];
	}

	CGFloat titleY = 16.0f + avatarSize + 12.0f;
	UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, titleY, W - 32.0f, 26.0f)];
	title.font = [MLTheme fontTitleLarge];
	title.textColor = [MLTheme onSurface];
	title.textAlignment = NSTextAlignmentCenter;
	title.backgroundColor = [UIColor clearColor];
	title.text = header[@"title"] ?: _name;
	[hv addSubview:title];

	if (hasSongs) {
		CGFloat btnY = titleY + 36.0f;
		CGFloat btnH = 40.0f;
		CGFloat btnW = (W - 48.0f - 12.0f) / 2.0f;

		UIButton *playBtn = [UIButton buttonWithType:UIButtonTypeCustom];
		playBtn.frame = CGRectMake(24.0f, btnY, btnW, btnH);
		playBtn.backgroundColor = [MLTheme primary];
		playBtn.layer.cornerRadius = btnH / 2.0f;
		playBtn.titleLabel.font = [MLTheme fontTitleSmall];
		[playBtn setImage:[MLIcon icon:@"play_arrow" size:18.0f color:[UIColor whiteColor]] forState:UIControlStateNormal];
		[playBtn setTitle:[NSString stringWithFormat:@"  %@", MLLocalizedString(@"play_all", nil)] forState:UIControlStateNormal];
		[playBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[playBtn addTarget:self action:@selector(playAllTap:) forControlEvents:UIControlEventTouchUpInside];
		[hv addSubview:playBtn];

		UIButton *shuffleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
		shuffleBtn.frame = CGRectMake(24.0f + btnW + 12.0f, btnY, btnW, btnH);
		shuffleBtn.backgroundColor = [MLTheme surfaceContainerHigh];
		shuffleBtn.layer.cornerRadius = btnH / 2.0f;
		shuffleBtn.layer.borderWidth = 1.0f;
		shuffleBtn.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.30f].CGColor;
		shuffleBtn.titleLabel.font = [MLTheme fontTitleSmall];
		[shuffleBtn setImage:[MLIcon icon:@"shuffle" size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
		[shuffleBtn setTitle:[NSString stringWithFormat:@"  %@", MLLocalizedString(@"shuffle_all", nil)] forState:UIControlStateNormal];
		[shuffleBtn setTitleColor:[MLTheme onSurface] forState:UIControlStateNormal];
		[shuffleBtn addTarget:self action:@selector(shuffleAllTap:) forControlEvents:UIControlEventTouchUpInside];
		[hv addSubview:shuffleBtn];
	}

	_table.tableHeaderView = hv;
}

- (void)playAllTap:(UIButton *)sender
{
	if (_allArtistSongs.count > 0) {
		[[MLPlaybackManager sharedManager] playQueue:_allArtistSongs startIndex:0];
	}
}

- (void)shuffleAllTap:(UIButton *)sender
{
	if (_allArtistSongs.count > 0) {
		[[MLPlaybackManager sharedManager] playShuffledQueue:_allArtistSongs];
	}
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self updateGradientColors];
	[_table reloadData];
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

- (void)load
{
	if (_loading)
		return;
	_loading = YES;
	NSString *bid = _browseId;
	[[MLInnerTube sharedClient] artistWithBrowseId:bid completion:^(NSDictionary *header, NSArray *sections, NSString *err) {
		_loading = NO;
		if (err) {
			self.title = err;
			return;
		}
		_header = header;
		[_rowSpecs removeAllObjects];
		[_allArtistSongs removeAllObjects];
		for (MLHomeSection *sec in sections ?: @[]) {
			BOOL allSongs = YES;
			for (MLYTItem *i in sec.items) {
				if (i.kind != MLYTKindSong && i.kind != MLYTKindVideo) {
					allSongs = NO;
					break;
				}
			}
			if (allSongs && sec.items.count) {
				if (sec.title)
					[_rowSpecs addObject:@{ @"type" : @"title", @"text" : sec.title }];
				for (MLYTItem *i in sec.items) {
					[_rowSpecs addObject:@{ @"type" : @"song", @"item" : i }];
					[_allArtistSongs addObject:i];
				}
			} else if (sec.items.count) {
				[_rowSpecs addObject:@{ @"type" : @"shelf", @"section" : sec }];
			}
		}
		[self setupHeaderView:header];
		[_table reloadData];
	}];
}

#pragma mark - Table

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSString *type = _rowSpecs[indexPath.row][@"type"];
	if ([type isEqualToString:@"title"])
		return 38.0f;
	if ([type isEqualToString:@"shelf"])
		return 240.0f;
	return MLLengthListItem;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _rowSpecs.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSDictionary *spec = _rowSpecs[indexPath.row];
	NSString *type = spec[@"type"];
	__weak MLArtistViewController *wself = self;

	if ([type isEqualToString:@"title"]) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"title"];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"title"];
			cell.backgroundColor = [UIColor clearColor];
			cell.textLabel.font = [UIFont boldSystemFontOfSize:19.0f];
			cell.textLabel.textColor = [MLTheme onSurface];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		cell.textLabel.text = spec[@"text"];
		return cell;
	}
	if ([type isEqualToString:@"shelf"]) {
		MLShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shelf"];
		if (!cell)
			cell = [[MLShelfCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"shelf"];
		[cell fillWithSection:spec[@"section"]];
		cell.cardTapped = ^(MLYTItem *item) {
			[MLNavigator openItem:item fromViewController:wself];
		};
		return cell;
	}

	MLSongCell *cell = [tableView dequeueReusableCellWithIdentifier:@"song"];
	if (!cell)
		cell = [[MLSongCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"song"];
	MLYTItem *it = spec[@"item"];
	BOOL isPlaying = [it.videoId isEqualToString:[MLPlaybackManager sharedManager].currentItem.videoId];
	[cell fillWithItem:it isPlaying:isPlaying];
	cell.moreTapped = ^(MLYTItem *tapped) {
		[MLNavigator presentSongMenuForItem:tapped fromViewController:wself];
	};
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	NSDictionary *spec = _rowSpecs[indexPath.row];
	if ([spec[@"type"] isEqualToString:@"song"]) {
		NSMutableArray *queue = [NSMutableArray array];
		BOOL found = NO;
		for (NSDictionary *s in _rowSpecs) {
			if (![s[@"type"] isEqualToString:@"song"])
				continue;
			MLYTItem *i = s[@"item"];
			if (s == spec)
				found = YES;
			if (found)
				[queue addObject:i];
		}
		[[MLPlaybackManager sharedManager] playQueue:queue startIndex:0];
	}
}

@end
