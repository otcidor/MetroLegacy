#import <Foundation/Foundation.h>

/*
 * PoToken minter: hidden UIWebView running the ES5 BotGuard client
 * (Resources/po_client.html). Native code performs the Create/GenerateIT
 * round-trips and drives the VM through mlbridge:// events.
 *
 * Port of Metrolist's PoTokenWebView.kt to iOS 6.
 */
@interface MLPoTokenProvider : NSObject

+ (instancetype)sharedProvider;

@property (nonatomic, readonly) BOOL minterReady;

/*
 * Mints a poToken bound to `identifier` (a videoId for GVS/streaming
 * tokens, or the session visitorData for player-request tokens).
 * Completion is invoked on the main thread; token is base64url.
 */
- (void)tokenForIdentifier:(NSString *)identifier
               completion:(void (^)(NSString *token, NSString *error))completion;

/* Tears the webview down; it is recreated on the next request. */
- (void)reset;

@end
