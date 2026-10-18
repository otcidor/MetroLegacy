#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

extern NSString *const MLSponsorBlockDidSkipNotification;

@interface MLSponsorSegment : NSObject
@property (nonatomic, assign) CGFloat start;
@property (nonatomic, assign) CGFloat end;
@property (nonatomic, copy) NSString *category;
@end

@interface MLSponsorBlockManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) BOOL enabled;

- (void)fetchSegmentsForVideoId:(NSString *)videoId completion:(void (^)(NSArray *segments))completion;
- (CGFloat)nextSkipTargetForTime:(CGFloat)currentTime segments:(NSArray *)segments;

@end
