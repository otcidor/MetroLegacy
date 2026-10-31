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

/*
 * Returns a local loopback HTTP URL serving progressive ADTS AAC (e.g. http://127.0.0.1:<port>/<id>/stream.aac)
 * suitable for CoreAudio AudioFileStream and native PCM decoders.
 */
- (NSURL *)aacRelayURLForStreamURL:(NSURL *)remoteStreamURL;

/*
 * Returns exact parsed audio duration from sidx segments if available, or 0.
 */
- (NSTimeInterval)durationForStreamURL:(NSURL *)url;

/*
 * Returns whether all audio segments for this stream have finished sending to client.
 */
- (BOOL)isStreamFinishedForURL:(NSURL *)url;

@end
