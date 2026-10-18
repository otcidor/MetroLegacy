#import <UIKit/UIKit.h>
#import "MLLyricsManager.h"

@interface MLLyricsView : UIView <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) void (^onSeekRequested)(CGFloat targetSeconds);
@property (nonatomic, readonly) BOOL hasLyrics;
@property (nonatomic, readonly) BOOL isSynced;

- (void)loadLyricsForTitle:(NSString *)title
                    artist:(NSString *)artist
                  duration:(CGFloat)duration
                   videoId:(NSString *)videoId;

- (void)updateCurrentPlaybackTime:(CGFloat)currentTime;
- (void)clear;

@end
