#import <UIKit/UIKit.h>

/*
 * Material Design 3 Bottom Sheet / Modal Menu Component.
 * Replaces native iOS UIActionSheet with integrated dark/AMOLED Material You UI.
 */

@interface MLBottomSheetItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, retain) UIColor *iconColor;
@property (nonatomic, retain) UIColor *swatchColor;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, assign) BOOL isRadio;
@property (nonatomic, assign) BOOL destructive;
@property (nonatomic, copy) void (^handler)(void);

+ (instancetype)itemWithTitle:(NSString *)title handler:(void (^)(void))handler;
+ (instancetype)itemWithTitle:(NSString *)title iconName:(NSString *)iconName handler:(void (^)(void))handler;
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconName:(NSString *)iconName handler:(void (^)(void))handler;
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle iconName:(NSString *)iconName isDestructive:(BOOL)destructive handler:(void (^)(void))handler;
+ (instancetype)itemWithTitle:(NSString *)title swatchColor:(UIColor *)swatch selected:(BOOL)selected handler:(void (^)(void))handler;
+ (instancetype)radioItemWithTitle:(NSString *)title subtitle:(NSString *)subtitle selected:(BOOL)selected handler:(void (^)(void))handler;

@end

@interface MLBottomSheetMenu : UIView <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, retain) NSArray *items; // MLBottomSheetItem
@property (nonatomic, assign) BOOL showCancelButton; // Defaults to YES

+ (instancetype)menuWithTitle:(NSString *)title items:(NSArray *)items;
+ (instancetype)menuWithTitle:(NSString *)title subtitle:(NSString *)subtitle items:(NSArray *)items;

- (void)showInViewController:(UIViewController *)vc;
- (void)showInView:(UIView *)parentView;
- (void)dismissAnimated:(BOOL)animated;
- (void)dismissAnimated:(BOOL)animated completion:(void (^)(void))completion;

@end
