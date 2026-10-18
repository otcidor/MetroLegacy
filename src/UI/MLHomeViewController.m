#import "MLHomeViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLComponents.h"
#import "MLNavigator.h"
#import "MLInnerTube.h"
#import "MLPlaybackManager.h"
#import "MLLocalization.h"
#import "MLAccountSettingsViewController.h"
#import "MLListDetailViewController.h"
#import "MLLibraryManager.h"

@interface MLHomeViewController ()
{
	NSMutableArray *_sections;
	NSMutableArray *_chips;
	NSUInteger _selectedChip;
	NSString *_selectedParams;
	BOOL _loading;

	UITableView *_table;
	MLChipsRowView *_chipsRow;
	UIRefreshControl *_refreshControl;
	UIActivityIndicatorView *_spinner;
	NSString *_lastPlayingVideoId;
}
@end

@implementation MLHomeViewController

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[MLTheme setLeftNavigationTitle:MLLocalizedString(@"home_title", nil) forViewController:self];
	[self setupNavButtons];

	_sections = [NSMutableArray array];
	_chips = [NSMutableArray array];

	CGRect b = self.view.bounds;

	_chipsRow = [[MLChipsRowView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 50.0f)];
	__weak MLHomeViewController *wself = self;
	_chipsRow.onChange = ^(MLChip *chip) {
		[wself selectChip:chip];
	};

	_table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, b.size.height) style:UITableViewStylePlain];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.backgroundColor = [UIColor clearColor];
	_table.dataSource = self;
	_table.delegate = self;
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	_table.tableHeaderView = _chipsRow;
	[self.view addSubview:_table];

	if ([UIRefreshControl class]) {
		_refreshControl = [[UIRefreshControl alloc] init];
		_refreshControl.tintColor = [MLTheme primary];
		[_refreshControl addTarget:self action:@selector(loadFeed) forControlEvents:UIControlEventValueChanged];
		[_table addSubview:_refreshControl];
	}

	_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	_spinner.color = [MLTheme primary];
	_spinner.center = CGPointMake(b.size.width / 2.0f, b.size.height / 2.0f);
	_spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
	_spinner.hidesWhenStopped = YES;
	[self.view addSubview:_spinner];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(loadFeed)
	                                             name:MLSessionChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(languageChanged:)
	                                             name:MLLanguageChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(playbackChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(libraryUpdated:)
	                                             name:MLLibraryDidUpdateNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(themeChanged:)
	                                             name:MLThemeDidChangeNotification
	                                           object:nil];

	[self populateDefaultMoodChips];
	[self loadFeed];
}

- (UIBarButtonItem *)circleBarButtonWithIcon:(NSString *)iconName action:(SEL)action
{
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
	btn.frame = CGRectMake(0, 0, 32.0f, 32.0f);
	btn.backgroundColor = [MLTheme surfaceContainer];
	btn.layer.cornerRadius = 16.0f;
	btn.layer.borderWidth = 0.5f;
	btn.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.28f].CGColor;
	[btn setImage:[MLIcon icon:iconName size:18.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return [[UIBarButtonItem alloc] initWithCustomView:btn];
}

- (void)setupNavButtons
{
	UIBarButtonItem *accountItem = [MLAccountSettingsViewController barButtonItemForViewController:self];
	UIBarButtonItem *statsItem = [self circleBarButtonWithIcon:@"trending_up" action:@selector(statsTapped:)];
	UIBarButtonItem *historyItem = [self circleBarButtonWithIcon:@"history" action:@selector(historyTapped:)];
	if ([self.navigationItem respondsToSelector:@selector(setRightBarButtonItems:)]) {
		self.navigationItem.rightBarButtonItems = @[ accountItem, statsItem, historyItem ];
	} else {
		self.navigationItem.rightBarButtonItem = accountItem;
	}
}

- (void)statsTapped:(id)sender
{
	[MLTheme triggerImpactHaptic];
	MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithTop50Songs];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)historyTapped:(id)sender
{
	[MLTheme triggerImpactHaptic];
	MLListDetailViewController *list = [[MLListDetailViewController alloc] initWithHistorySongs];
	[self.navigationController pushViewController:list animated:YES];
}

- (void)populateDefaultMoodChips
{
	if (_chips.count > 0) return;
	NSArray *titles = @[
		MLLocalizedString(@"filter_all", nil),
		MLLocalizedString(@"mood_relax", nil),
		MLLocalizedString(@"mood_energize", nil),
		MLLocalizedString(@"mood_workout", nil),
		MLLocalizedString(@"mood_focus", nil),
		MLLocalizedString(@"mood_commute", nil),
	];
	for (NSUInteger i = 0; i < titles.count; i++) {
		MLChip *c = [[MLChip alloc] init];
		c.title = titles[i];
		c.selected = (i == _selectedChip);
		[_chips addObject:c];
	}
	[_chipsRow setChips:_chips];
	[_chipsRow setSelectedIndex:_selectedChip];
}

- (BOOL)isSpeedDialSection:(MLHomeSection *)section
{
	if (section.items.count == 0)
		return NO;
	NSString *title = section.title.lowercaseString ?: @"";
	return ([title isEqualToString:MLLocalizedString(@"speed_dial", nil).lowercaseString] ||
	        [title rangeOfString:@"speed dial"].location != NSNotFound ||
	        [title rangeOfString:@"marcado rápido"].location != NSNotFound ||
	        [title rangeOfString:@"быстрый набор"].location != NSNotFound);
}

- (void)rebuildSynthesizedHomeSections
{
	if (_selectedParams.length > 0)
		return;

	MLLibraryManager *lib = [MLLibraryManager sharedManager];
	NSArray *history = lib.historySongs;
	NSArray *liked = lib.likedSongs;
	NSArray *top50 = lib.top50Songs;

	// Remove previously synthesized sections
	for (NSInteger i = (NSInteger)_sections.count - 1; i >= 0; i--) {
		MLHomeSection *s = _sections[(NSUInteger)i];
		NSString *t = s.title.lowercaseString ?: @"";
		if ([self isSpeedDialSection:s] ||
		    [s.title isEqualToString:MLLocalizedString(@"keep_listening", nil)] ||
		    [t rangeOfString:@"keep listening"].location != NSNotFound ||
		    [t rangeOfString:@"seguir escuchando"].location != NSNotFound ||
		    [t rangeOfString:@"volver a escuchar"].location != NSNotFound ||
		    [t rangeOfString:@"listen again"].location != NSNotFound) {
			[_sections removeObjectAtIndex:(NSUInteger)i];
		}
	}

	// 1. Synthesize Speed Dial (MetroList 3x3 paged grid)
	NSMutableArray *sdItems = [NSMutableArray array];
	NSMutableSet *sdIds = [NSMutableSet set];

	void (^addSDItem)(MLYTItem *) = ^(MLYTItem *it) {
		NSString *key = it.videoId.length ? it.videoId : it.browseId;
		if (key.length && ![sdIds containsObject:key]) {
			[sdIds addObject:key];
			[sdItems addObject:it];
		}
	};

	for (MLYTItem *it in top50) {
		addSDItem(it);
		if (sdItems.count >= 8) break;
	}
	if (sdItems.count < 8) {
		for (MLYTItem *it in history) {
			addSDItem(it);
			if (sdItems.count >= 8) break;
		}
	}
	if (sdItems.count < 8) {
		for (MLYTItem *it in liked) {
			addSDItem(it);
			if (sdItems.count >= 8) break;
		}
	}
	if (sdItems.count < 8) {
		for (MLYTItem *it in lib.syncedPlaylists) {
			addSDItem(it);
			if (sdItems.count >= 8) break;
		}
	}

	if (sdItems.count >= 3) {
		MLYTItem *lucky = [[MLYTItem alloc] init];
		lucky.videoId = @"speed_dial_lucky";
		lucky.title = MLLocalizedString(@"speed_dial_lucky", nil);
		[sdItems addObject:lucky];

		for (MLYTItem *it in history) {
			addSDItem(it);
			if (sdItems.count >= 18) break;
		}
		for (MLYTItem *it in liked) {
			addSDItem(it);
			if (sdItems.count >= 18) break;
		}

		MLHomeSection *sdSection = [[MLHomeSection alloc] init];
		sdSection.title = MLLocalizedString(@"speed_dial", nil);
		sdSection.items = sdItems;
		[_sections insertObject:sdSection atIndex:0];
	}

	// Check if server or feed already has Quick Picks
	BOOL hasQuickPicks = NO;
	NSMutableSet *quickPicksIds = [NSMutableSet set];
	for (MLHomeSection *s in _sections) {
		if ([self isSpeedDialSection:s]) continue;
		NSString *t = s.title.lowercaseString ?: @"";
		if ([t rangeOfString:@"quick picks"].location != NSNotFound ||
		    [t rangeOfString:@"selección rápida"].location != NSNotFound) {
			hasQuickPicks = YES;
			for (MLYTItem *it in s.items) {
				if (it.videoId.length) [quickPicksIds addObject:it.videoId];
			}
			break;
		}
	}

	// 2. If server did NOT provide Quick Picks, synthesize from Liked Songs
	if (!hasQuickPicks && liked.count >= 3) {
		NSMutableArray *qpItems = [NSMutableArray array];
		for (MLYTItem *it in liked) {
			if (it.videoId.length && ![quickPicksIds containsObject:it.videoId]) {
				[quickPicksIds addObject:it.videoId];
				[qpItems addObject:it];
				if (qpItems.count >= 12) break;
			}
		}
		if (qpItems.count >= 3) {
			MLHomeSection *qpSection = [[MLHomeSection alloc] init];
			qpSection.title = MLLocalizedString(@"quick_picks", nil);
			qpSection.items = qpItems;
			NSUInteger targetIdx = (_sections.count > 0 && [self isSpeedDialSection:_sections[0]]) ? 1 : 0;
			[_sections insertObject:qpSection atIndex:targetIdx];
			hasQuickPicks = YES;
		}
	}

	// 3. Keep Listening: playback history, filtering out songs already in Quick Picks
	if (history.count > 0) {
		NSMutableArray *recentSongs = [NSMutableArray array];
		for (MLYTItem *it in history) {
			if (it.videoId.length && ![quickPicksIds containsObject:it.videoId]) {
				[recentSongs addObject:it];
				if (recentSongs.count >= 20) break;
			}
		}
		if (recentSongs.count > 0) {
			MLHomeSection *klSection = [[MLHomeSection alloc] init];
			klSection.title = MLLocalizedString(@"keep_listening", nil);
			klSection.items = recentSongs;
			NSUInteger targetIdx = 0;
			for (NSUInteger i = 0; i < _sections.count; i++) {
				MLHomeSection *sec = _sections[i];
				if ([self isSpeedDialSection:sec]) {
					targetIdx = i + 1;
				} else {
					NSString *st = sec.title.lowercaseString ?: @"";
					if ([st rangeOfString:@"quick picks"].location != NSNotFound ||
					    [st rangeOfString:@"selección rápida"].location != NSNotFound) {
						targetIdx = i + 1;
					}
				}
			}
			[_sections insertObject:klSection atIndex:targetIdx];
		}
	}

	[_table reloadData];
}

- (void)libraryUpdated:(NSNotification *)note
{
	[self rebuildSynthesizedHomeSections];
}

- (void)playbackChanged:(NSNotification *)note
{
	NSString *curId = [MLPlaybackManager sharedManager].currentItem.videoId ?: @"";
	if ([curId isEqualToString:_lastPlayingVideoId ?: @""])
		return;
	_lastPlayingVideoId = [curId copy];
	[_table reloadData];
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_table.backgroundColor = [MLTheme background];
	if (_refreshControl) {
		_refreshControl.tintColor = [MLTheme primary];
	}
	_spinner.color = [MLTheme primary];
	[self setupNavButtons];
	[_table reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[MLTheme resetNavigationBarForNavigationController:self.navigationController];
	[self rebuildSynthesizedHomeSections];
	NSString *curId = [MLPlaybackManager sharedManager].currentItem.videoId ?: @"";
	if (![curId isEqualToString:_lastPlayingVideoId ?: @""]) {
		_lastPlayingVideoId = [curId copy];
		[_table reloadData];
	}
}

- (void)languageChanged:(NSNotification *)note
{
	[MLTheme setLeftNavigationTitle:MLLocalizedString(@"home_title", nil) forViewController:self];
	[self setupNavButtons];
	[_chips removeAllObjects];
	_selectedChip = 0;
	_selectedParams = nil;
	[self loadFeed];
}

- (void)selectChip:(MLChip *)chip
{
	for (NSUInteger i = 0; i < _chips.count; i++) {
		MLChip *c = _chips[i];
		c.selected = (c == chip);
		if (c == chip)
			_selectedChip = i;
	}
	[_chipsRow setSelectedIndex:_selectedChip];
	_selectedParams = chip.params;
	[self loadFeed];
}

- (void)loadFeed
{
	if (_loading) {
		[_refreshControl endRefreshing];
		return;
	}
	_loading = YES;
	if (_sections.count == 0) {
		[_spinner startAnimating];
	}
	NSString *params = _selectedParams;
	if (_selectedParams == nil && _chips.count) {
		for (MLChip *c in _chips) {
			if (c.selected) {
				params = c.params;
				break;
			}
		}
	}
	[[MLInnerTube sharedClient] homeFeedWithParams:params completion:^(NSArray *sections, NSArray *chips, NSString *error) {
		_loading = NO;
		[_spinner stopAnimating];
		[_refreshControl endRefreshing];
		if (error) {
			[MLTheme setLeftNavigationTitle:MLLocalizedString(@"home_network_error", nil) forViewController:self];
			return;
		}
		[MLTheme setLeftNavigationTitle:MLLocalizedString(@"home_title", nil) forViewController:self];
		[_sections removeAllObjects];
		[_sections addObjectsFromArray:sections ?: @[]];
		[self rebuildSynthesizedHomeSections];
		if (chips.count > 0 && _selectedParams == nil) {
			[_chips removeAllObjects];
			[_chips addObjectsFromArray:chips];
			[_chipsRow setChips:_chips];
			[_chipsRow setSelectedIndex:_selectedChip];
		}
		[_table reloadData];
	}];
}

- (BOOL)isSongShelfSection:(MLHomeSection *)section
{
	if (section.items.count == 0 || [self isSpeedDialSection:section])
		return NO;
	NSString *title = section.title.lowercaseString ?: @"";
	if ([title isEqualToString:MLLocalizedString(@"quick_picks", nil).lowercaseString] ||
	    [title isEqualToString:MLLocalizedString(@"keep_listening", nil).lowercaseString] ||
	    [title rangeOfString:@"quick picks"].location != NSNotFound ||
	    [title rangeOfString:@"selección rápida"].location != NSNotFound ||
	    [title rangeOfString:@"keep listening"].location != NSNotFound ||
	    [title rangeOfString:@"seguir escuchando"].location != NSNotFound ||
	    [title rangeOfString:@"listen again"].location != NSNotFound) {
		return YES;
	}
	NSUInteger songCount = 0;
	for (MLYTItem *it in section.items) {
		if ((it.kind == MLYTKindSong || it.kind == MLYTKindVideo || it.videoId.length > 0) &&
		    it.kind != MLYTKindAlbum && it.kind != MLYTKindPlaylist && it.kind != MLYTKindArtist) {
			songCount++;
		}
	}
	return (songCount * 2 >= section.items.count);
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return _sections.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MLHomeSection *section = _sections[indexPath.row];
	if ([self isSpeedDialSection:section]) {
		return [MLSpeedDialCell heightForWidth:tableView.bounds.size.width];
	}
	if ([self isSongShelfSection:section]) {
		return 222.0f;
	}
	return 240.0f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MLHomeSection *section = _sections[indexPath.row];
	__weak MLHomeViewController *wself = self;

	if ([self isSpeedDialSection:section]) {
		MLSpeedDialCell *cell = [tableView dequeueReusableCellWithIdentifier:@"speed_dial"];
		if (!cell)
			cell = [[MLSpeedDialCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"speed_dial"];
		[cell fillWithItems:section.items title:section.title];
		cell.itemTapped = ^(MLYTItem *item, BOOL isLucky) {
			if (isLucky) {
				[MLTheme triggerImpactHaptic];
				NSMutableArray *pool = [NSMutableArray array];
				[pool addObjectsFromArray:[MLLibraryManager sharedManager].top50Songs];
				[pool addObjectsFromArray:[MLLibraryManager sharedManager].likedSongs];
				[pool addObjectsFromArray:[MLLibraryManager sharedManager].historySongs];
				if (pool.count > 0) {
					NSUInteger count = pool.count;
					for (NSUInteger i = 0; i < count; i++) {
						NSUInteger nElements = count - i;
						NSUInteger n = (arc4random() % nElements) + i;
						[pool exchangeObjectAtIndex:i withObjectAtIndex:n];
					}
					[[MLPlaybackManager sharedManager] playQueue:pool startIndex:0];
				}
				return;
			}
			BOOL isContainer = (item.kind == MLYTKindPlaylist ||
			                    item.kind == MLYTKindAlbum ||
			                    item.kind == MLYTKindArtist ||
			                    [item.browseId hasPrefix:@"VL"] ||
			                    [item.browseId hasPrefix:@"MPRE"] ||
			                    [item.browseId hasPrefix:@"UC"] ||
			                    item.videoId.length == 0);
			if (isContainer) {
				[MLNavigator openItem:item fromViewController:wself];
			} else {
				[[MLPlaybackManager sharedManager] playRadioForItem:item];
			}
		};
		return cell;
	}

	if ([self isSongShelfSection:section]) {
		MLQuickPicksShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"quick_picks"];
		if (!cell)
			cell = [[MLQuickPicksShelfCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"quick_picks"];
		NSString *playingId = [MLPlaybackManager sharedManager].currentItem.videoId;
		[cell fillWithSection:section playingVideoId:playingId];
		cell.songTapped = ^(MLYTItem *item, NSArray *sectionItems) {
			BOOL isContainer = (item.kind == MLYTKindPlaylist ||
			                    item.kind == MLYTKindAlbum ||
			                    item.kind == MLYTKindArtist ||
			                    [item.browseId hasPrefix:@"VL"] ||
			                    [item.browseId hasPrefix:@"MPRE"] ||
			                    [item.browseId hasPrefix:@"UC"] ||
			                    item.videoId.length == 0);
			if (isContainer) {
				[MLNavigator openItem:item fromViewController:wself];
				return;
			}
			[[MLPlaybackManager sharedManager] playRadioForItem:item];
		};
		cell.moreTapped = ^(MLYTItem *item) {
			[MLNavigator presentSongMenuForItem:item fromViewController:wself];
		};
		return cell;
	}

	MLShelfCell *cell = [tableView dequeueReusableCellWithIdentifier:@"shelf"];
	if (!cell)
		cell = [[MLShelfCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"shelf"];
	[cell fillWithSection:section];
	cell.cardTapped = ^(MLYTItem *item) {
		[MLNavigator openItem:item fromViewController:wself];
	};
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
}

@end
