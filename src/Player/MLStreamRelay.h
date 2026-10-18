#import <Foundation/Foundation.h>

@interface MLStreamRelay : NSObject

@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedRelay;

- (BOOL)start;
- (BOOL)reviveListenerKeepingPort;
- (void)stop;

/*
 * Returns a local loopback HTTP URL (e.g. http://127.0.0.1:<port>/<id>/stream.mp4)
 * that AVPlayer can stream without TLS validation failure.
 */
- (NSURL *)relayURLForStreamURL:(NSURL *)remoteStreamURL;

@end
