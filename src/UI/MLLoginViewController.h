#import <UIKit/UIKit.h>

/*
 * YouTube Music login via UIWebView. Captures cookies (SAPISID) and
 * session values, then validates through account/account_menu.
 */
@interface MLLoginViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, assign) BOOL startInWebViewMode;

@end
