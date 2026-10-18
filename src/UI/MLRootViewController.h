#import <UIKit/UIKit.h>

@interface MLRootViewController : UIViewController

- (void)switchToTabIndex:(NSUInteger)index;
- (UINavigationController *)navigationControllerForTab:(NSUInteger)index;
- (void)setStatusBarBackgroundColor:(UIColor *)color;

@end
