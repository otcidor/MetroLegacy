#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface MLLyricLine : NSObject
@property (nonatomic, assign) NSInteger timeMs;
@property (nonatomic, copy) NSString *text;
@end

@interface MLLyricsManager : NSObject

+ (instancetype)sharedManager;

- (void)fetchLyricsForTitle:(NSString *)title
                     artist:(NSString *)artist
                   duration:(CGFloat)duration
                    videoId:(NSString *)videoId
                 completion:(void (^)(NSArray *lines, BOOL synced, NSString *error))completion;

@end
