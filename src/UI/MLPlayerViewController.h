#import <UIKit/UIKit.h>

@class MLPlayerViewController;

@protocol MLPlayerViewControllerDelegate <NSObject>
- (void)playerViewControllerDidClose:(MLPlayerViewController *)player;
@end

/*
 * Full-screen player: big artwork, title/artist, seekbar, transport controls.
 */
@interface MLPlayerViewController : UIViewController

@property (nonatomic, unsafe_unretained) id <MLPlayerViewControllerDelegate> delegate;

- (void)reload;

@end
