#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "MLYTItem.h"

extern NSString *const MLPlaybackStateChangedNotification;
extern NSString *const MLPlaybackQueueStartedNotification;

typedef NS_ENUM(NSInteger, MLRepeatMode) {
	MLRepeatModeOff = 0,
	MLRepeatModeAll,
	MLRepeatModeOne
};

/*
 * Queue playback engine: AVPlayer streaming audio/mp4.
 */
@interface MLPlaybackManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSArray *queue;
@property (nonatomic, readonly) NSUInteger currentIndex;
@property (nonatomic, readonly) MLYTItem *currentItem;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) BOOL buffering;
@property (nonatomic, readonly) AVPlayer *player;
@property (nonatomic, readonly) CGFloat currentTime;   // seconds
@property (nonatomic, readonly) CGFloat duration;      // seconds, 0 unknown
@property (nonatomic, readonly) NSString *statusError;
@property (nonatomic, assign) MLRepeatMode repeatMode;
@property (nonatomic, assign) BOOL shuffle;

@property (nonatomic, readonly) BOOL sleepTimerActive;
@property (nonatomic, readonly) NSTimeInterval sleepTimerRemainingTime; // in seconds
@property (nonatomic, readonly) BOOL sleepTimerStopAfterSong;

- (void)setSleepTimerWithMinutes:(NSUInteger)minutes;
- (void)setSleepTimerStopAfterCurrentSong;
- (void)cancelSleepTimer;

- (void)playQueue:(NSArray *)items startIndex:(NSUInteger)index;
- (void)playShuffledQueue:(NSArray *)items;
- (void)playRadioForItem:(MLYTItem *)item;
- (void)playIndex:(NSUInteger)index fresh:(BOOL)fresh;
- (void)playNextItem:(MLYTItem *)item;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)seekToTime:(CGFloat)seconds;
- (void)stop;
- (void)toggleShuffle;
- (void)toggleRepeat;

- (void)appendQueueItems:(NSArray *)items;
- (void)removeQueueItemAtIndex:(NSUInteger)index;
- (void)moveQueueItemFromIndex:(NSUInteger)from toIndex:(NSUInteger)to;

@end
