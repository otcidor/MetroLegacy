#import <UIKit/UIKit.h>

/*
 * Navbar circular profile avatar button (Metrolist style) +
 * Account & Storage modal controller (port of Metrolist AccountSettings.kt).
 */
@interface MLAccountBarButton : UIControl

- (id)initWithTargetViewController:(UIViewController *)targetVC;
- (void)reloadAvatar;

@end

@interface MLAccountSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>

+ (UIBarButtonItem *)barButtonItemForViewController:(UIViewController *)targetVC;
+ (void)presentFromViewController:(UIViewController *)presenter;

@end
