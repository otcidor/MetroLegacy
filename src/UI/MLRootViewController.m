#import "MLRootViewController.h"
#import "MLTheme.h"
#import "MLTabBarView.h"
#import "MLMiniPlayerView.h"
#import "MLHomeViewController.h"
#import "MLSearchViewController.h"
#import "MLLibraryViewController.h"
#import "MLPlayerViewController.h"
#import "MLPlaybackManager.h"
#import "MLLocalization.h"

@interface MLRootViewController () <MLTabBarViewDelegate, MLMiniPlayerViewDelegate, MLPlayerViewControllerDelegate>
@end

@implementation MLRootViewController
{
	UIView *_statusBarBg;
	UIView *_contentView;
	MLTabBarView *_tabBarView;
	MLMiniPlayerView *_miniPlayer;
	NSMutableArray *_navControllers;
	UIViewController *_currentChild;
	MLPlayerViewController *_playerVC;
	NSUInteger _selectedIndex;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
	if (self) {
		_navControllers = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
	return UIStatusBarStyleLightContent;
}

- (void)loadView
{
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.view.backgroundColor = [MLTheme background];

	CGRect bounds = self.view.bounds;

	_contentView = [[UIView alloc] initWithFrame:CGRectZero];
	_contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_contentView.clipsToBounds = YES;
	[self.view addSubview:_contentView];

	_statusBarBg = [[UIView alloc] initWithFrame:CGRectZero];
	_statusBarBg.backgroundColor = [MLTheme background];
	_statusBarBg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
	[self.view addSubview:_statusBarBg];

	_miniPlayer = [[MLMiniPlayerView alloc] initWithFrame:CGRectZero];
	_miniPlayer.delegate = self;
	_miniPlayer.hidden = YES;
	[self.view addSubview:_miniPlayer];

	_tabBarView = [[MLTabBarView alloc] initWithFrame:CGRectMake(0, bounds.size.height - MLLengthTabBar,
	                                                             bounds.size.width, MLLengthTabBar)];
	_tabBarView.delegate = self;
	[self reloadTabs];
	[self.view addSubview:_tabBarView];

	[self layoutChrome];
}

- (void)setStatusBarBackgroundColor:(UIColor *)color
{
	_statusBarBg.backgroundColor = color ?: [MLTheme background];
}

- (void)reloadTabs
{
	[_tabBarView setTabs:@[
		@{ @"icon": @"home", @"label": MLLocalizedString(@"tab_home", nil) },
		@{ @"icon": @"search", @"label": MLLocalizedString(@"tab_search", nil) },
		@{ @"icon": @"library_music", @"label": MLLocalizedString(@"tab_library", nil) },
	]];
	_tabBarView.selectedIndex = _selectedIndex;
}

- (void)viewDidLoad
{
	[super viewDidLoad];

	NSArray *roots = @[
		[[MLHomeViewController alloc] init],
		[[MLSearchViewController alloc] init],
		[[MLLibraryViewController alloc] init],
	];
	for (UIViewController *root in roots) {
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
		if ([nav.navigationBar respondsToSelector:@selector(setTranslucent:)]) {
			nav.navigationBar.translucent = NO;
		}
		if ([nav.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
			nav.navigationBar.barTintColor = [MLTheme background];
		}
		nav.navigationBar.backgroundColor = [MLTheme background];
		[_navControllers addObject:nav];
	}
	[self showChild:0];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(playbackStateChanged:)
	                                             name:MLPlaybackStateChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(playbackQueueStarted:)
	                                             name:MLPlaybackQueueStartedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(reloadTabs)
	                                             name:MLLanguageChangedNotification
	                                           object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(themeChanged:)
	                                             name:MLThemeDidChangeNotification
	                                           object:nil];

	if ([MLPlaybackManager sharedManager].currentItem != nil) {
		_miniPlayer.hidden = NO;
		[_miniPlayer reload];
	}
}

- (void)themeChanged:(NSNotification *)note
{
	self.view.backgroundColor = [MLTheme background];
	_contentView.backgroundColor = [MLTheme background];
	_statusBarBg.backgroundColor = [MLTheme background];
	for (UINavigationController *nav in _navControllers) {
		if ([nav.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
			nav.navigationBar.barTintColor = [MLTheme background];
		}
		nav.navigationBar.backgroundColor = [MLTheme background];
	}
}

- (void)viewSafeAreaInsetsDidChange
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
	if ([UIViewController instancesRespondToSelector:@selector(viewSafeAreaInsetsDidChange)]) {
		[super viewSafeAreaInsetsDidChange];
	}
#endif
	[self layoutChrome];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	[self layoutChrome];
}

- (void)layoutChrome
{
	CGRect bounds = self.view.bounds;
	CGFloat topInset = [MLTheme safeAreaTopInsetForView:self.view];
	CGFloat bottomInset = [MLTheme safeAreaBottomInsetForView:self.view];

	_statusBarBg.frame = CGRectMake(0, 0, bounds.size.width, topInset);
	_statusBarBg.hidden = (topInset <= 0.0f);

	CGFloat tabH = MLLengthTabBar + bottomInset;
	CGRect tabFrame = CGRectMake(0, bounds.size.height - tabH, bounds.size.width, tabH);
	_tabBarView.frame = tabFrame;

	BOOL miniVisible = !_miniPlayer.hidden;
	CGFloat miniH = MLLengthMiniPlayer;
	CGFloat miniMargin = 10.0f;
	CGFloat miniBottomGap = 8.0f;
	CGFloat miniY = bounds.size.height - tabH - miniH - miniBottomGap;
	_miniPlayer.frame = CGRectMake(miniMargin, miniY, bounds.size.width - miniMargin * 2, miniH);

	CGFloat contentH = bounds.size.height - topInset - tabH - (miniVisible ? (miniH + miniBottomGap) : 0);
	_contentView.frame = CGRectMake(0, topInset, bounds.size.width, contentH);
	if (_currentChild)
		_currentChild.view.frame = _contentView.bounds;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
	return (toInterfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - Remote controls (lock screen / headphones, iOS 6)

- (BOOL)canBecomeFirstResponder
{
	return YES;
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[self becomeFirstResponder];
	[[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event
{
	if (event.type != UIEventTypeRemoteControl)
		return;
	MLPlaybackManager *pm = [MLPlaybackManager sharedManager];
	switch (event.subtype) {
		case UIEventSubtypeRemoteControlPlay:
			if (!pm.playing)
				[pm togglePlayPause];
			break;
		case UIEventSubtypeRemoteControlPause:
			if (pm.playing)
				[pm togglePlayPause];
			break;
		case UIEventSubtypeRemoteControlTogglePlayPause:
			[pm togglePlayPause];
			break;
		case UIEventSubtypeRemoteControlNextTrack:
			[pm next];
			break;
		case UIEventSubtypeRemoteControlPreviousTrack:
			[pm previous];
			break;
		default:
			break;
	}
}

#pragma mark - Tabs

- (void)switchToTabIndex:(NSUInteger)index
{
	_tabBarView.selectedIndex = index;
	[self showChild:index];
}

- (UINavigationController *)navigationControllerForTab:(NSUInteger)index
{
	return index < _navControllers.count ? _navControllers[index] : nil;
}

- (void)showChild:(NSUInteger)index
{
	if (index >= _navControllers.count)
		return;
	if (_currentChild == _navControllers[index]) {
		UINavigationController *nav = (UINavigationController *)_currentChild;
		if (nav.viewControllers.count > 1) {
			[nav popToRootViewControllerAnimated:YES];
		}
		return;
	}
	if (_currentChild) {
		[_currentChild willMoveToParentViewController:nil];
		[_currentChild.view removeFromSuperview];
		[_currentChild removeFromParentViewController];
	}
	UINavigationController *nav = _navControllers[index];
	_currentChild = nav;
	_selectedIndex = index;
	[self addChildViewController:nav];
	nav.view.frame = _contentView.bounds;
	nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[_contentView addSubview:nav.view];
	[nav didMoveToParentViewController:self];
}

- (void)tabBarView:(MLTabBarView *)tabBar didSelectIndex:(NSUInteger)index
{
	[self showChild:index];
}

#pragma mark - Mini player

- (void)playbackQueueStarted:(NSNotification *)note
{
	_miniPlayer.hidden = NO;
	[_miniPlayer reload];
	[UIView animateWithDuration:0.25f animations:^{
		[self layoutChrome];
	}];
}

- (void)playbackStateChanged:(NSNotification *)note
{
	[_miniPlayer reload];
	if ([MLPlaybackManager sharedManager].currentItem == nil) {
		[MLTheme resetDynamicAccentColor];
		[UIView animateWithDuration:0.25f animations:^{
			self->_miniPlayer.alpha = 0.0f;
			[self layoutChrome];
		} completion:^(BOOL finished) {
			self->_miniPlayer.hidden = YES;
			self->_miniPlayer.alpha = 1.0f;
		}];
	} else if (_miniPlayer.hidden) {
		_miniPlayer.alpha = 0.0f;
		_miniPlayer.hidden = NO;
		[UIView animateWithDuration:0.25f animations:^{
			self->_miniPlayer.alpha = 1.0f;
			[self layoutChrome];
		}];
	}
}

- (void)miniPlayerTapped:(MLMiniPlayerView *)miniPlayer
{
	if (!_playerVC) {
		_playerVC = [[MLPlayerViewController alloc] init];
		_playerVC.delegate = self;
	}
	CGRect full = self.view.bounds;
	_playerVC.view.transform = CGAffineTransformIdentity;
	_playerVC.view.frame = full;
	_playerVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	if (_playerVC.parentViewController != self) {
		[self addChildViewController:_playerVC];
		[self.view addSubview:_playerVC.view];
		[_playerVC didMoveToParentViewController:self];
	} else if (_playerVC.view.superview != self.view) {
		[self.view addSubview:_playerVC.view];
	} else {
		[self.view bringSubviewToFront:_playerVC.view];
	}
	[_playerVC.view setNeedsLayout];
	[_playerVC.view layoutIfNeeded];
	[_playerVC reload];
	_playerVC.view.transform = CGAffineTransformMakeTranslation(0, full.size.height);
	[UIView animateWithDuration:0.28f delay:0.0f options:UIViewAnimationOptionCurveEaseOut animations:^{
		_playerVC.view.transform = CGAffineTransformIdentity;
	} completion:nil];
}

- (void)playerViewControllerDidClose:(MLPlayerViewController *)player
{
	CGRect full = self.view.bounds;
	[UIView animateWithDuration:0.24f delay:0.0f options:UIViewAnimationOptionCurveEaseIn animations:^{
		self->_playerVC.view.transform = CGAffineTransformMakeTranslation(0, full.size.height);
	} completion:^(BOOL finished) {
		[self->_playerVC willMoveToParentViewController:nil];
		[self->_playerVC.view removeFromSuperview];
		[self->_playerVC removeFromParentViewController];
		self->_playerVC = nil;
	}];
}

@end
