#import <UIKit/UIKit.h>

@class MLMiniPlayerView;

@protocol MLMiniPlayerViewDelegate <NSObject>
- (void)miniPlayerTapped:(MLMiniPlayerView *)miniPlayer;
@end

/*
 * Metrolist legacy-style mini player: flat 64pt bar with
 * thumbnail, title/artist, play/pause and a thin progress line.
 */
@interface MLMiniPlayerView : UIView

@property (nonatomic, unsafe_unretained) id <MLMiniPlayerViewDelegate> delegate;

- (void)reload;

@end
