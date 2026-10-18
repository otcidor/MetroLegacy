#import "MLQueueViewController.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLPlaybackManager.h"
#import "MLComponents.h"
#import "MLNavigator.h"
#import "MLLocalization.h"
#import "MLLibraryManager.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface MLQueueViewController ()
{
	UIView *_headerBar;
	UIView *_dragHandle;
	UIButton *_closeButton;
	UIButton *_saveButton;
	UILabel *_titleLabel;
	UILabel *_countLabel;
	UITableView *_tableView;
}
@end

@implementation MLQueueViewController

- (UIStatusBarStyle)preferredStatusBarStyle
{
	return UIStatusBarStyleLightContent;
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.view.backgroundColor = [MLTheme background];
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.view.backgroundColor = [MLTheme background];

	_headerBar = [[UIView alloc] initWithFrame:CGRectZero];
	_headerBar.backgroundColor = [MLTheme surfaceContainer];
	[self.view addSubview:_headerBar];

	_dragHandle = [[UIView alloc] initWithFrame:CGRectZero];
	_dragHandle.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
	_dragHandle.layer.cornerRadius = 2.0f;
	[_headerBar addSubview:_dragHandle];

	_closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[_closeButton setImage:[MLIcon icon:@"expand_more" size:28.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_closeButton addTarget:self action:@selector(closeTap:) forControlEvents:UIControlEventTouchUpInside];
	[_headerBar addSubview:_closeButton];

	_saveButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_saveButton.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
	_saveButton.layer.cornerRadius = 18.0f;
	_saveButton.layer.borderWidth = 0.5f;
	_saveButton.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
	[_saveButton setImage:[MLIcon icon:@"playlist_add" size:22.0f color:[MLTheme onSurface]] forState:UIControlStateNormal];
	[_saveButton addTarget:self action:@selector(saveQueueTap:) forControlEvents:UIControlEventTouchUpInside];
	[_headerBar addSubview:_saveButton];

	_titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_titleLabel.font = [MLTheme fontTitleMedium];
	_titleLabel.textColor = [MLTheme onSurface];
	_titleLabel.text = MLLocalizedString(@"up_next", nil);
	_titleLabel.backgroundColor = [UIColor clearColor];
	[_headerBar addSubview:_titleLabel];

	_countLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_countLabel.font = [MLTheme fontBodySmall];
	_countLabel.textColor = [MLTheme onSurfaceVariant];
	_countLabel.backgroundColor = [UIColor clearColor];
	[_headerBar addSubview:_countLabel];

	_tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	_tableView.backgroundColor = [UIColor clearColor];
	_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	_tableView.rowHeight = MLLengthListItem;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[self.view addSubview:_tableView];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(stateChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(languageChanged:)
	                                             name:MLLanguageChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(themeChanged:)
	                                             name:MLThemeDidChangeNotification
	                                           object:nil];
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_tableView.backgroundColor = [MLTheme background];
	[_tableView reloadData];
}

- (void)languageChanged:(NSNotification *)note
{
	_titleLabel.text = MLLocalizedString(@"up_next", nil);
	[self reload];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self reload];

	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	if (pm.queue.count > 0 && pm.currentIndex < pm.queue.count) {
		NSIndexPath *ip = [NSIndexPath indexPathForRow:pm.currentIndex inSection:0];
		[_tableView scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
	}
}

- (void)viewSafeAreaInsetsDidChange
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
	if ([UIViewController instancesRespondToSelector:@selector(viewSafeAreaInsetsDidChange)]) {
		[super viewSafeAreaInsetsDidChange];
	}
#endif
	[self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	CGRect b = self.view.bounds;
	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat bottomInset = [MLTheme safeAreaBottomInsetForView:self.view];
	CGFloat headerH = 60.0f + topInset;
	_headerBar.frame = CGRectMake(0, 0, b.size.width, headerH);
	_dragHandle.frame = CGRectMake((b.size.width - 36.0f) / 2.0f, topInset + 5.0f, 36.0f, 4.0f);
	_closeButton.frame = CGRectMake(8.0f, 12.0f + topInset, 40.0f, 40.0f);
	_saveButton.frame = CGRectMake(b.size.width - 48.0f, 12.0f + topInset, 36.0f, 36.0f);

	CGFloat titleX = 52.0f;
	CGFloat titleW = b.size.width - titleX - 56.0f;
	_titleLabel.frame = CGRectMake(titleX, 12.0f + topInset, titleW, 20.0f);
	_countLabel.frame = CGRectMake(titleX, 32.0f + topInset, titleW, 18.0f);

	_tableView.frame = CGRectMake(0, headerH, b.size.width, b.size.height - headerH);
	_tableView.contentInset = UIEdgeInsetsMake(0, 0, bottomInset + 10.0f, 0);
	if ([_tableView respondsToSelector:@selector(setScrollIndicatorInsets:)]) {
		_tableView.scrollIndicatorInsets = _tableView.contentInset;
	}
}

- (void)stateChanged:(NSNotification *)note
{
	[self reload];
}

- (void)reload
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	NSUInteger total = pm.queue.count;
	if (total == 1) {
		_countLabel.text = [NSString stringWithFormat:MLLocalizedString(@"songs_count_single", nil), (unsigned long)total];
	} else if (total > 1) {
		_countLabel.text = [NSString stringWithFormat:MLLocalizedString(@"songs_count_plural", nil), (unsigned long)total];
	} else {
		_countLabel.text = @"";
	}
	[_tableView reloadData];
}

- (void)closeTap:(UIButton *)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveQueueTap:(UIButton *)sender
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	if (pm.queue.count == 0) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"queue_empty_title", nil)
		                                                message:MLLocalizedString(@"queue_empty_message", nil)
		                                               delegate:nil
		                                      cancelButtonTitle:MLLocalizedString(@"ok", nil)
		                                      otherButtonTitles:nil];
		[alert show];
		return;
	}

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"save_queue_as_playlist", nil)
	                                                message:MLLocalizedString(@"enter_playlist_name", nil)
	                                               delegate:self
	                                      cancelButtonTitle:MLLocalizedString(@"cancel", nil)
	                                      otherButtonTitles:MLLocalizedString(@"save", nil), nil];
	alert.alertViewStyle = UIAlertViewStylePlainTextInput;
	UITextField *tf = [alert textFieldAtIndex:0];
	tf.placeholder = MLLocalizedString(@"playlist_name_placeholder", nil);
	tf.text = [NSString stringWithFormat:@"%@ (%lu)", MLLocalizedString(@"queue_playlist_default", nil), (unsigned long)pm.queue.count];
	alert.tag = 3001;
	[alert show];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (alertView.tag == 3001) {
		if (buttonIndex == 1) {
			NSString *name = [alertView textFieldAtIndex:0].text;
			NSArray *queue = [[MLPlaybackManager sharedManager].queue copy];
			if (!queue.count) return;

			[[MLLibraryManager sharedManager] saveQueue:queue asPlaylistWithTitle:name completion:^(NSString *playlistId, NSString *error) {
				NSString *cleanName = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if (!cleanName.length) cleanName = MLLocalizedString(@"queue_playlist_default", nil);

				NSString *msg = [NSString stringWithFormat:MLLocalizedString(@"playlist_saved_prompt_download", nil), cleanName, (unsigned long)queue.count];
				UIAlertView *dlAlert = [[UIAlertView alloc] initWithTitle:MLLocalizedString(@"playlist_saved_title", nil)
				                                                  message:msg
				                                                 delegate:self
				                                        cancelButtonTitle:MLLocalizedString(@"later", nil)
				                                        otherButtonTitles:MLLocalizedString(@"download_now", nil), nil];
				dlAlert.tag = 3002;
				objc_setAssociatedObject(dlAlert, "MLSavedQueueKey", queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				[dlAlert show];
			}];
		}
	} else if (alertView.tag == 3002) {
		if (buttonIndex == 1) {
			NSArray *queue = objc_getAssociatedObject(alertView, "MLSavedQueueKey");
			if (queue.count > 0) {
				[[MLLibraryManager sharedManager] downloadAllSongs:queue];
			}
		}
		objc_setAssociatedObject(alertView, "MLSavedQueueKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return [MLPlaybackManager sharedManager].queue.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *CellId = @"MLQueueSongCell";
	MLSongCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
	if (!cell) {
		cell = [[MLSongCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellId];
	}

	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	NSArray *q = pm.queue;
	if (indexPath.row < q.count) {
		MLYTItem *item = q[indexPath.row];
		BOOL isPlaying = (indexPath.row == pm.currentIndex);
		[cell fillWithItem:item isPlaying:isPlaying];
		__weak MLQueueViewController *wself = self;
		cell.moreTapped = ^(MLYTItem *tapped) {
			[MLNavigator presentSongMenuForItem:tapped fromViewController:wself];
		};
	}

	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	if (indexPath.row < pm.queue.count) {
		[pm playIndex:indexPath.row fresh:NO];
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
		[pm removeQueueItemAtIndex:indexPath.row];
		[self reload];
	}
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath
{
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	[pm moveQueueItemFromIndex:sourceIndexPath.row toIndex:destinationIndexPath.row];
	[self reload];
}

@end
