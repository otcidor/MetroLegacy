#import <Foundation/Foundation.h>

/*
 * YouTube signature decipher for iOS 6/7.
 *
 * Flow (ports Metrolist + zemer-cipher):
 *   1. Player hash from https://www.youtube.com/iframe_api
 *   2. sig expression + signatureTimestamp (sts) from the zemer-cipher
 *      remote config (github.com/ZemerTeam/zemer-cipher), cached.
 *   3. Player base.js cached on disk.
 *   4. base.js evaluated in JavaScriptCore (private framework on iOS 6,
 *      loaded via dlopen at runtime — works on jailbroken iOS 6/7).
 *      A hook is injected inside the player closure that exposes the
 *      obfuscated decipher function.
 *   5. solveSignature: calls the hook with each signature.
 */
@interface MLYouTubeCipher : NSObject

+ (instancetype)sharedSolver;

// Fetches/stores hash + sts + sig expression + base.js.
// Completion on main thread. sts == 0 means unknown.
- (void)ensureConfigured:(void (^)(NSInteger sts, NSString *sigExpr, NSString *error))completion;

// Deciphers a signature. Runs JS; call from any thread (serialized internally).
- (NSString *)solveSignature:(NSString *)signature error:(NSString **)errorOut;

- (void)releaseJSContext;

@end
