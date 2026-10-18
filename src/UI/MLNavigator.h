#import "MLComponents.h"
#import "MLPlaybackManager.h"

/*
 * Router: opens the right screen for an item (song / album / playlist / artist)
 * and presents contextual action menus for songs.
 */
@interface MLNavigator : NSObject

+ (void)openItem:(MLYTItem *)item fromViewController:(UIViewController *)vc;
+ (void)playSong:(MLYTItem *)item fromViewController:(UIViewController *)vc;
+ (void)presentSongMenuForItem:(MLYTItem *)item fromViewController:(UIViewController *)vc;

@end
