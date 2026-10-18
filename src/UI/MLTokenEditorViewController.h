#import <UIKit/UIKit.h>

/*
 * Advanced session token editor, matching Metrolist Android's AccountSettings dialog.
 * Supports both full multi-line template (***INNERTUBE COOKIE***=...) and raw cookies.
 */
@interface MLTokenEditorViewController : UIViewController <UITextViewDelegate>

@property (nonatomic, copy) void (^completionHandler)(BOOL loggedIn);

@end
