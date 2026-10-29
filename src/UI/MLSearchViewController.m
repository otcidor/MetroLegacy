#import "MLSearchViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLComponents.h"
#import "MLNavigator.h"
#import "MLInnerTube.h"
#import "MLPlaybackManager.h"
#import "MLLocalization.h"
#import "MLAccountSettingsViewController.h"

@interface MLSearchViewController ()
{
	UITextField *_field;
	UIButton *_clearButton;
	MLChipsRowView *_chipsRow;

	UITableView *_table;
	NSMutableArray *_results;
	NSMutableArray *_suggestions;
	NSMutableArray *_searchHistory;
	NSString *_nextContinuation;
	NSString *_query;
	NSString *_filterParams;
	BOOL _loading;
	BOOL _showingSuggestions;
	NSTimer *_debounce;
	NSString *_lastPlayingVideoId;
}
@end

@implementation MLSearchViewController

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];
}

- (void)dealloc
{
	[_debounce invalidate];
	_debounce = nil;
	_table.dataSource = nil;
	_table.delegate = nil;
	_field.delegate = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	[MLTheme setLeftNavigationTitle:MLLocalizedString(@"search_title", nil) forViewController:self];
	self.navigationItem.rightBarButtonItem = [MLAccountSettingsViewController barButtonItemForViewController:self];
	if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) {
		self.automaticallyAdjustsScrollViewInsets = NO;
	}

	_results = [NSMutableArray array];
	_suggestions = [NSMutableArray array];
	NSArray *savedHist = [[NSUserDefaults standardUserDefaults] arrayForKey:@"ml_search_history"];
	_searchHistory = savedHist ? [savedHist mutableCopy] : [NSMutableArray array];

	CGRect b = self.view.bounds;

	_field = [[UITextField alloc] initWithFrame:CGRectMake(12.0f, 8.0f, b.size.width - 24.0f, 40.0f)];
	_field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_field.backgroundColor = [MLTheme surfaceContainerHigh];
	_field.layer.cornerRadius = 20.0f;
	_field.layer.borderWidth = 1.0f;
	_field.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
	_field.textColor = [MLTheme onSurface];
	_field.font = [MLTheme fontBodyLarge];
	_field.returnKeyType = UIReturnKeySearch;
	_field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	[self updatePlaceholderText];

	UIView *leftWrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 38.0f, 40.0f)];
	UIImageView *searchIcon = [[UIImageView alloc] initWithFrame:CGRectMake(12.0f, 10.0f, 20.0f, 20.0f)];
	searchIcon.image = [MLIcon icon:@"search" size:20.0f color:[MLTheme onSurfaceVariant]];
	[leftWrap addSubview:searchIcon];
	_field.leftView = leftWrap;
	_field.leftViewMode = UITextFieldViewModeAlways;
	_field.delegate = self;

	UIButton *clearBtn = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 38.0f, 40.0f)];
	[clearBtn setImage:[MLIcon icon:@"close" size:18.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
	[clearBtn addTarget:self action:@selector(clearTap) forControlEvents:UIControlEventTouchUpInside];
	_field.rightView = clearBtn;
	_field.rightViewMode = UITextFieldViewModeWhileEditing;
	[self.view addSubview:_field];

	_chipsRow = [[MLChipsRowView alloc] initWithFrame:CGRectMake(0, 52.0f, b.size.width, 50.0f)];
	_chipsRow.hidden = YES;
	__weak MLSearchViewController *wself = self;
	_chipsRow.onChange = ^(MLChip *chip) {
		[wself filterTap:chip];
	};
	[self reloadChips];
	[self.view addSubview:_chipsRow];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(languageChanged:)
	                                             name:MLLanguageChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(playbackChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(themeChanged:)
	                                             name:MLThemeDidChangeNotification
	                                           object:nil];

	_table = [[UITableView alloc] initWithFrame:CGRectMake(0, 56.0f, b.size.width, b.size.height - 56.0f)];
	_table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_table.backgroundColor = [UIColor clearColor];
	_table.dataSource = self;
	_table.delegate = self;
	_table.separatorStyle = UITableViewCellSeparatorStyleNone;
	_table.rowHeight = MLLengthListItem;
	[self.view addSubview:_table];
	[self updateLayoutForResultsState];
}

- (void)updatePlaceholderText
{
	NSString *ph = MLLocalizedString(@"search_placeholder", nil) ?: @"";
	if ([_field respondsToSelector:@selector(setAttributedPlaceholder:)]) {
		_field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph
		                                                               attributes:@{
			NSForegroundColorAttributeName : [MLTheme onSurfaceVariant]
		}];
	} else {
		_field.placeholder = ph;
	}
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
	_field.backgroundColor = [MLTheme surfaceContainerHigh];
	_field.layer.borderColor = [[MLTheme outline] colorWithAlphaComponent:0.25f].CGColor;
	_field.textColor = [MLTheme onSurface];
	[_table reloadData];
}

- (void)reloadChips
{
	NSMutableArray *chips = [NSMutableArray array];
	NSArray *titles = @[
		MLLocalizedString(@"filter_all", nil),
		MLLocalizedString(@"filter_songs", nil),
		MLLocalizedString(@"filter_videos", nil),
		MLLocalizedString(@"filter_albums", nil),
		MLLocalizedString(@"filter_artists", nil),
		MLLocalizedString(@"filter_playlists", nil)
	];
	NSArray *params = @[@"", MLSearchFilterSongs, MLSearchFilterVideos, MLSearchFilterAlbums, MLSearchFilterArtists, MLSearchFilterPlaylists];
	for (NSUInteger i = 0; i < titles.count; i++) {
		MLChip *c = [[MLChip alloc] init];
		c.title = titles[i];
		if ([params[i] length] > 0)
			c.params = params[i];
		[chips addObject:c];
	}
	[_chipsRow setChips:chips];
}

- (void)languageChanged:(NSNotification *)note
{
	[MLTheme setLeftNavigationTitle:MLLocalizedString(@"search_title", nil) forViewController:self];
	[self updatePlaceholderText];
	[self reloadChips];
	if (_results.count > 0 && _query.length > 0) {
		[self runSearch];
	}
}

- (void)saveSearchToHistory:(NSString *)query
{
	NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length) return;
	for (NSInteger i = (NSInteger)_searchHistory.count - 1; i >= 0; i--) {
		if ([_searchHistory[(NSUInteger)i] caseInsensitiveCompare:trimmed] == NSOrderedSame) {
			[_searchHistory removeObjectAtIndex:(NSUInteger)i];
		}
	}
	[_searchHistory insertObject:trimmed atIndex:0];
	while (_searchHistory.count > 25) {
		[_searchHistory removeLastObject];
	}
	[[NSUserDefaults standardUserDefaults] setObject:_searchHistory forKey:@"ml_search_history"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)removeHistoryAtIndex:(NSUInteger)idx
{
	if (idx < _searchHistory.count) {
		[_searchHistory removeObjectAtIndex:idx];
		[[NSUserDefaults standardUserDefaults] setObject:_searchHistory forKey:@"ml_search_history"];
		[[NSUserDefaults standardUserDefaults] synchronize];
		[_table reloadData];
	}
}

- (void)clearHistory
{
	[_searchHistory removeAllObjects];
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ml_search_history"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[_table reloadData];
}

- (void)updateLayoutForResultsState
{
	CGRect b = self.view.bounds;
	BOOL hasResults = (_results.count > 0);
	_chipsRow.hidden = !hasResults;
	CGFloat tableY = hasResults ? 104.0f : 56.0f;
	_table.frame = CGRectMake(0, tableY, b.size.width, b.size.height - tableY);
}

- (void)deleteHistoryBtnTap:(UIButton *)sender
{
	[MLTheme triggerImpactHaptic];
	[self removeHistoryAtIndex:(NSUInteger)(sender.tag - 1000)];
}

- (void)insertHistoryBtnTap:(UIButton *)sender
{
	NSUInteger idx = (NSUInteger)(sender.tag - 2000);
	if (idx < _searchHistory.count) {
		[MLTheme triggerImpactHaptic];
		_field.text = _searchHistory[idx];
		[_field becomeFirstResponder];
	}
}

- (void)clearTap
{
	_field.text = @"";
	[_suggestions removeAllObjects];
	[_results removeAllObjects];
	_showingSuggestions = NO;
	_nextContinuation = nil;
	[self updateLayoutForResultsState];
	[_table reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[MLTheme resetNavigationBarForNavigationController:self.navigationController];
	[self updateLayoutForResultsState];
	[_table reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[_debounce invalidate];
	_debounce = nil;
}

- (void)filterTap:(MLChip *)chip
{
	[MLTheme triggerImpactHaptic];
	_filterParams = chip.params;
	if (_field.text.length > 0) {
		_query = _field.text;
		[_field resignFirstResponder];
	}
	[self runSearch];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
	[_field resignFirstResponder];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	[textField resignFirstResponder];
	_query = textField.text;
	[self runSearch];
	return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	[_debounce invalidate];
	_debounce = [NSTimer scheduledTimerWithTimeInterval:0.35 target:self selector:@selector(debounceFire:) userInfo:nil repeats:NO];
	return YES;
}

- (void)debounceFire:(NSTimer *)t
{
	NSString *text = _field.text;
	if (text.length < 2) {
		_showingSuggestions = NO;
		[_suggestions removeAllObjects];
		[self updateLayoutForResultsState];
		[_table reloadData];
		return;
	}
	[[MLInnerTube sharedClient] suggestionsForInput:text completion:^(NSArray *sugg, NSString *err) {
		if (![text isEqualToString:_field.text])
			return;
		[_suggestions removeAllObjects];
		[_suggestions addObjectsFromArray:sugg ?: @[]];
		_showingSuggestions = YES;
		[_table reloadData];
	}];
}

- (void)runSearch
{
	if (!_query.length)
		return;
	_loading = YES;
	NSString *q = _query;
	[self saveSearchToHistory:q];
	[MLTheme triggerImpactHaptic];

	NSString *fp = _filterParams;
	__weak typeof(self) wself = self;
	[[MLInnerTube sharedClient] searchQuery:q params:fp continuation:nil completion:^(NSArray *items, NSString *next, NSString *err) {
		MLSearchViewController *s = wself;
		if (!s) return;
		s->_loading = NO;
		s->_showingSuggestions = NO;
		[s->_suggestions removeAllObjects];
		[s->_results removeAllObjects];
		if (err) {
			[MLTheme setLeftNavigationTitle:err forViewController:s];
			return;
		}
		[MLTheme setLeftNavigationTitle:MLLocalizedString(@"search_title", nil) forViewController:s];
		[s->_results addObjectsFromArray:items ?: @[]];
		s->_nextContinuation = next;
		[s updateLayoutForResultsState];
		[s->_table reloadData];
	}];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if (_showingSuggestions)
		return _suggestions.count;
	if (_results.count > 0)
		return _results.count + (_nextContinuation ? 1 : 0);
	if (_field.text.length == 0) {
		if (_searchHistory.count > 0)
			return _searchHistory.count + 1; // history items + "Clear history" row
		return 1; // friendly empty state
	}
	return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (_results.count == 0 && !_showingSuggestions && _field.text.length == 0) {
		if (_searchHistory.count == 0) {
			return 140.0f;
		}
		if (indexPath.row == _searchHistory.count) {
			return 44.0f;
		}
		return 50.0f;
	}
	return MLLengthListItem;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (_showingSuggestions) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sugg"];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"sugg"];
			cell.backgroundColor = [UIColor clearColor];
			cell.textLabel.textColor = [MLTheme onSurface];
			cell.textLabel.font = [MLTheme fontBodyLarge];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.imageView.image = [MLIcon icon:@"search" size:20.0f color:[MLTheme onSurfaceVariant]];
		}
		cell.textLabel.text = _suggestions[indexPath.row];
		cell.accessoryView = nil;
		return cell;
	}

	if (_results.count > 0) {
		if (indexPath.row == _results.count) {
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
		MLYTItem *it = _results[indexPath.row];
		BOOL isPlaying = [it.videoId isEqualToString:[MLPlaybackManager sharedManager].currentItem.videoId];
		[cell fillWithItem:it isPlaying:isPlaying];
		__weak MLSearchViewController *wself = self;
		cell.moreTapped = ^(MLYTItem *tapped) {
			[MLNavigator presentSongMenuForItem:tapped fromViewController:wself];
		};
		return cell;
	}

	// Recent search history or empty state
	if (_field.text.length == 0 && _results.count == 0) {
		if (_searchHistory.count == 0) {
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"empty_hist"];
			if (!cell) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"empty_hist"];
				cell.backgroundColor = [UIColor clearColor];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.textLabel.textColor = [MLTheme onSurfaceVariant];
				cell.textLabel.font = [MLTheme fontTitleSmall];
				cell.textLabel.textAlignment = NSTextAlignmentCenter;
				cell.detailTextLabel.textColor = [[MLTheme onSurfaceVariant] colorWithAlphaComponent:0.7f];
				cell.detailTextLabel.font = [MLTheme fontBodyMedium];
				cell.detailTextLabel.textAlignment = NSTextAlignmentCenter;
			}
			cell.textLabel.text = MLLocalizedString(@"no_recent_searches", nil);
			cell.detailTextLabel.text = MLLocalizedString(@"search_placeholder", nil);
			cell.accessoryView = nil;
			return cell;
		}

		if (indexPath.row < _searchHistory.count) {
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"hist_cell"];
			if (!cell) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"hist_cell"];
				cell.backgroundColor = [UIColor clearColor];
				cell.textLabel.textColor = [MLTheme onSurface];
				cell.textLabel.font = [MLTheme fontBodyLarge];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.imageView.image = [MLIcon icon:@"history" size:20.0f color:[MLTheme onSurfaceVariant]];

				UIView *accWrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 76.0f, 36.0f)];
				accWrap.backgroundColor = [UIColor clearColor];

				UIButton *delBtn = [UIButton buttonWithType:UIButtonTypeCustom];
				delBtn.frame = CGRectMake(0, 0, 36.0f, 36.0f);
				[delBtn setImage:[MLIcon icon:@"close" size:16.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
				delBtn.tag = 101;
				[accWrap addSubview:delBtn];

				UIButton *insertBtn = [UIButton buttonWithType:UIButtonTypeCustom];
				insertBtn.frame = CGRectMake(38.0f, 0, 36.0f, 36.0f);
				[insertBtn setImage:[MLIcon icon:@"north_west" size:16.0f color:[MLTheme onSurfaceVariant]] forState:UIControlStateNormal];
				insertBtn.tag = 102;
				[accWrap addSubview:insertBtn];

				cell.accessoryView = accWrap;
			}
			cell.textLabel.text = _searchHistory[indexPath.row];

			UIView *acc = cell.accessoryView;
			UIButton *delBtn = (UIButton *)[acc viewWithTag:101];
			UIButton *insertBtn = (UIButton *)[acc viewWithTag:102];

			delBtn.tag = 1000 + indexPath.row;
			[delBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
			[delBtn addTarget:self action:@selector(deleteHistoryBtnTap:) forControlEvents:UIControlEventTouchUpInside];

			insertBtn.tag = 2000 + indexPath.row;
			[insertBtn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
			[insertBtn addTarget:self action:@selector(insertHistoryBtnTap:) forControlEvents:UIControlEventTouchUpInside];

			return cell;
		} else {
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"clear_hist"];
			if (!cell) {
				cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"clear_hist"];
				cell.backgroundColor = [UIColor clearColor];
				cell.textLabel.textColor = [MLTheme error];
				cell.textLabel.font = [MLTheme fontTitleSmall];
				cell.textLabel.textAlignment = NSTextAlignmentCenter;
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
			}
			cell.textLabel.text = MLLocalizedString(@"clear_search_history", nil);
			cell.accessoryView = nil;
			return cell;
		}
	}

	return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[_field resignFirstResponder];
	if (_showingSuggestions) {
		[MLTheme triggerImpactHaptic];
		_query = _suggestions[indexPath.row];
		_field.text = _query;
		[self runSearch];
		return;
	}
	if (_results.count > 0) {
		if (indexPath.row == _results.count) {
			NSString *q = _query;
			NSString *cont = _nextContinuation;
			NSString *fp = _filterParams;
			[[MLInnerTube sharedClient] searchQuery:q params:fp continuation:cont completion:^(NSArray *items, NSString *next, NSString *err) {
				if (items.count) {
					[_results addObjectsFromArray:items];
					_nextContinuation = next;
					[_table reloadData];
				}
			}];
			return;
		}
		[MLTheme triggerImpactHaptic];
		[MLNavigator openItem:_results[indexPath.row] fromViewController:self];
		return;
	}
	if (_searchHistory.count > 0 && _field.text.length == 0 && _results.count == 0) {
		if (indexPath.row < _searchHistory.count) {
			[MLTheme triggerImpactHaptic];
			_query = _searchHistory[indexPath.row];
			_field.text = _query;
			[self runSearch];
		} else {
			[MLTheme triggerImpactHaptic];
			[self clearHistory];
		}
	}
}

@end
