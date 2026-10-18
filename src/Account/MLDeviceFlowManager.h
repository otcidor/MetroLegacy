#import <Foundation/Foundation.h>

@interface MLDeviceFlowManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, copy, readonly) NSString *userCode;
@property (nonatomic, copy, readonly) NSString *verificationURL;
@property (nonatomic, readonly) BOOL isPolling;

- (void)startDeviceFlowWithProgress:(void (^)(NSString *userCode, NSString *url))progress
                         completion:(void (^)(BOOL success, NSString *error))completion;

- (void)cancel;

@end
