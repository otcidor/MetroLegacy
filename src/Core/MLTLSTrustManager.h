#import <Foundation/Foundation.h>
#import <Security/Security.h>

@interface MLTLSTrustManager : NSObject

@property (nonatomic, readonly) NSArray *anchors;

+ (instancetype)sharedManager;

- (void)loadAnchors;
- (BOOL)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host;
- (BOOL)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge forConnection:(NSURLConnection *)connection;

/*
 * Synchronous request runner that executes on a dedicated network thread
 * with an active runloop and validates server certificates against bundled
 * Google Trust Services (GTS) roots.
 */
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSHTTPURLResponse **)responseOut
                             error:(NSError **)errorOut;

@end
