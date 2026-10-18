#import <UIKit/UIKit.h>
#import "MLIcon.h"

@class MLTabBarView;

@protocol MLTabBarViewDelegate <NSObject>
- (void)tabBarView:(MLTabBarView *)tabBar didSelectIndex:(NSUInteger)index;
@end

@interface MLTabBarView : UIView

@property (nonatomic, assign) NSUInteger selectedIndex;
@property (nonatomic, unsafe_unretained) id <MLTabBarViewDelegate> delegate;

- (void)setTabs:(NSArray *)tabs; // array of dicts: name, icon

@end
