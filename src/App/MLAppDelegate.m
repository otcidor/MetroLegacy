#import "MLAppDelegate.h"
#import "MLTheme.h"
#import "MLRootViewController.h"
#import "MLInnerTube.h"
#import "MLYouTubeCipher.h"
#import "MLLibraryManager.h"

@implementation MLAppDelegate

@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	[MLLibraryManager sharedManager];

	// flat dark M3 bars matching app background
	UIImage *barBg = [MLTheme solidImage:[MLTheme background] size:CGSizeMake(2, 2)];
	UIImage *navShadow = [MLTheme solidImage:[UIColor clearColor] size:CGSizeMake(2, 1)];
	[[UINavigationBar appearance] setBackgroundImage:barBg forBarMetrics:UIBarMetricsDefault];
	[[UINavigationBar appearance] setShadowImage:navShadow];
	[[UINavigationBar appearance] setTintColor:[MLTheme primary]];
	NSDictionary *titleAttrs = @{
		UITextAttributeTextColor : [MLTheme onSurface],
		UITextAttributeFont : [UIFont boldSystemFontOfSize:17],
		UITextAttributeTextShadowColor : [UIColor clearColor],
	};
	[[UINavigationBar appearance] setTitleTextAttributes:titleAttrs];
	if ([UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)]) {
		[[UINavigationBar appearance] setBarTintColor:[MLTheme background]];
	}

	// Clean translucent pill appearance for UIBarButtonItem & Back button on iOS 6
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(28.0f, 28.0f), NO, 0.0f);
	[[UIColor colorWithWhite:1.0f alpha:0.12f] setFill];
	[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 2.0f, 28.0f, 24.0f) cornerRadius:12.0f] fill];
	UIImage *btnPill = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(12.0f, 12.0f, 12.0f, 12.0f)];
	UIGraphicsEndImageContext();
	[[UIBarButtonItem appearance] setBackgroundImage:btnPill forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	[[UIBarButtonItem appearance] setBackButtonBackgroundImage:btnPill forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	[[UIBarButtonItem appearance] setTitleTextAttributes:@{
		UITextAttributeTextColor : [MLTheme onSurface],
		UITextAttributeFont : [MLTheme fontTitleSmall],
		UITextAttributeTextShadowColor : [UIColor clearColor],
	} forState:UIControlStateNormal];

	if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0f) {
		[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent animated:NO];
	} else {
		[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];
	}

	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.backgroundColor = [MLTheme background];
	[self.window makeKeyAndVisible];
	self.window.rootViewController = [[MLRootViewController alloc] init];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
		[[MLInnerTube sharedClient] bootstrapVisitorData:^(BOOL ok) {}];
		[[MLYouTubeCipher sharedSolver] ensureConfigured:^(NSInteger sts, NSString *sig, NSString *err) {}];
	});

	return YES;
}

@end
