#import "MLYouTubeStream.h"
#import "MLInnerTube.h"
#import "MLYouTubeCipher.h"
#import "MLPoTokenProvider.h"

/*
 * Full stream resolution flow (validated against Metrolist's app + innertubex):
 *   1. visitorData (bootstraps via sw.js_data if missing)
 *   2. signatureTimestamp from zemer-cipher config
 *   3. PoTokens: player-request token bound to visitorData,
 *      streaming token bound to videoId  (PoTokenGenerator.kt bindings)
 *   4. POST player {videoId, sts, serviceIntegrityDimensions.poToken}
 *   5. pick audio/mp4 (AAC); decipher signatureCipher via JS solver
 *   6. final URL: url + &sp=sig + &pot= + &cpn=
 * Formats carrying an `n=` challenge are rejected in v1 (audio/mp4 never has one).
 */

static NSString *MLRandomCPN(void)
{
	static const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
	char buf[17];
	for (int i = 0; i < 16; i++)
		buf[i] = alphabet[arc4random_uniform(64)];
	buf[16] = 0;
	return [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
}

@implementation MLYouTubeStream

+ (void)audioStreamURLForVideoId:(NSString *)videoId
                      completion:(void (^)(NSURL *url, NSString *error))completion
{
	[self resolveStreamForVideoId:videoId completion:^(NSURL *url, NSDictionary *videoDetails, NSString *error) {
		if (completion)
			completion(url, error);
	}];
}

+ (void)resolveStreamForVideoId:(NSString *)videoId
                     completion:(void (^)(NSURL *url, NSDictionary *videoDetails, NSString *error))completion
{
	NSString *vid = [videoId copy];
	if (!vid.length) {
		if (completion)
			completion(nil, nil, @"videoId vacío");
		return;
	}

	void (^fail)(NSString *) = ^(NSString *error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion)
				completion(nil, nil, error);
		});
	};

	void (^processPlayerResponse)(NSDictionary *, NSString *) = ^(NSDictionary *playerResponse, NSString *urlPot) {
		if (!playerResponse) {
			fail(@"Sin respuesta del player");
			return;
		}
		NSString *status = MLPath(playerResponse, @"playabilityStatus.status");
		if (![status isEqualToString:@"OK"]) {
			NSString *reason = MLPath(playerResponse, @"playabilityStatus.reason") ?: status;
			fail([NSString stringWithFormat:@"No reproducible: %@", reason]);
			return;
		}
		NSArray *formats = MLPath(playerResponse, @"streamingData.formats") ?: @[];
		NSArray *adaptive = MLPath(playerResponse, @"streamingData.adaptiveFormats") ?: @[];
		NSMutableArray *all = [NSMutableArray array];
		[all addObjectsFromArray:formats];
		[all addObjectsFromArray:adaptive];

		NSDictionary *best = nil;
		NSInteger bestRate = -1;
		BOOL bestIsDirect = NO;
		for (NSDictionary *f in all) {
			NSString *mimeType = [f objectForKey:@"mimeType"];
			if (![mimeType isKindOfClass:[NSString class]])
				continue;
			// audio-only (no width) and mp4/m4a/AAC (AVPlayer on iOS 6 can't do webm/opus)
			if (![mimeType hasPrefix:@"audio/mp4"] && ![mimeType hasPrefix:@"audio/m4a"])
				continue;
			NSString *sc = [f objectForKey:@"signatureCipher"] ?: [f objectForKey:@"cipher"];
			NSString *url = [f objectForKey:@"url"];
			BOOL direct = [url isKindOfClass:[NSString class]] && url.length > 0;
			BOOL cipher = [sc isKindOfClass:[NSString class]] && sc.length > 0;
			if (!direct && !cipher)
				continue;
			NSInteger bitrate = [[f objectForKey:@"bitrate"] integerValue];
			BOOL directPreferred = (best == nil) || (direct && !bestIsDirect) || (direct == bestIsDirect && bitrate > bestRate);
			if (directPreferred) {
				best = f;
				bestRate = bitrate;
				bestIsDirect = direct;
			}
		}

		if (!best) {
			fail(@"Sin stream de audio compatible (mp4)");
			return;
		}

		NSString *finalUrl = [self buildURLFromFormat:best];
		if (!finalUrl) {
			fail(@"No se pudo descifrar la firma del stream");
			return;
		}
		if (urlPot.length > 0) {
			NSString *sep = [finalUrl rangeOfString:@"?"].length > 0 ? @"&" : @"?";
			finalUrl = [finalUrl stringByAppendingFormat:@"%@pot=%@&cpn=%@", sep, urlPot, MLRandomCPN()];
		}
		NSDictionary *videoDetails = playerResponse[@"videoDetails"];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion)
				completion([NSURL URLWithString:finalUrl], videoDetails, nil);
		});
	};

	// 1. Direct player resolution via VisionOS (Troubadour primary client - direct stream, full song playback)
	[[MLInnerTube sharedClient] playerVisionOsForVideoId:vid completion:^(NSDictionary *vResp, NSString *vErr) {
		if (vResp && [MLPath(vResp, @"playabilityStatus.status") isEqualToString:@"OK"]) {
			processPlayerResponse(vResp, nil);
			return;
		}

		// 2. Direct player resolution (native iOS client with direct unencrypted stream)
		[[MLInnerTube sharedClient] playerForVideoId:vid signatureTimestamp:0 poToken:nil completion:^(NSDictionary *pResp, NSString *pErr) {
			if (pResp && [MLPath(pResp, @"playabilityStatus.status") isEqualToString:@"OK"]) {
				processPlayerResponse(pResp, nil);
				return;
			}

			// 3. Fallback to Oculus Quest 3 ANDROID_VR client
			[[MLInnerTube sharedClient] playerAndroidVrForVideoId:vid completion:^(NSDictionary *vrResp, NSString *vrErr) {
				if (vrResp && [MLPath(vrResp, @"playabilityStatus.status") isEqualToString:@"OK"]) {
					processPlayerResponse(vrResp, nil);
					return;
				}

				// 4. Fallback to PoToken / solver pipeline if direct clients failed
				[[MLYouTubeCipher sharedSolver] ensureConfigured:^(NSInteger sts, NSString *sigExpr, NSString *cfgError) {
					[[MLPoTokenProvider sharedProvider] tokenForIdentifier:vid completion:^(NSString *urlPot, NSString *err) {
						[[MLInnerTube sharedClient] playerForVideoId:vid signatureTimestamp:sts poToken:urlPot completion:^(NSDictionary *fbResp, NSString *fbErr) {
							processPlayerResponse(fbResp, urlPot);
						}];
					}];
				}];
			}];
		}];
	}];
}

+ (NSDictionary *)decodeCipherURL:(NSString *)cipher
{
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *pair in [cipher componentsSeparatedByString:@"&"]) {
		NSRange eq = [pair rangeOfString:@"="];
		if (eq.location == NSNotFound)
			continue;
		NSString *key = [pair substringToIndex:eq.location];
		NSString *value = [self percentDecode:[pair substringFromIndex:eq.location + 1]];
		[out setValue:value forKey:key];
	}
	return out;
}

/*
 * Turns a format into a playable URL. Handles plain URLs and
 * signatureCipher (s/sp/url) via the JS decipher.
 */
+ (NSString *)buildURLFromFormat:(NSDictionary *)format
{
	NSString *url = [format objectForKey:@"url"];
	if ([url isKindOfClass:[NSString class]] && url.length > 0)
		return url;

	NSString *sc = [format objectForKey:@"signatureCipher"] ?: [format objectForKey:@"cipher"];
	if (![sc isKindOfClass:[NSString class]] || sc.length == 0)
		return nil;

	NSDictionary *params = [self decodeCipherURL:sc];
	NSString *s = params[@"s"];
	NSString *sp = params[@"sp"];
	NSString *base = params[@"url"];
	if (!s || !base)
		return nil;
	if (sp.length == 0)
		sp = @"signature";

	NSString *deciphered = [[MLYouTubeCipher sharedSolver] solveSignature:s error:nil];
	if (!deciphered)
		return nil;

	return [NSString stringWithFormat:@"%@&%@=%@", base, sp, deciphered];
}

+ (NSString *)percentDecode:(NSString *)s
{
	NSString *out = [s stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
	return [out stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

+ (void)pingAPI:(void (^)(BOOL, NSString *))completion
{
	[[MLInnerTube sharedClient] homeFeedWithParams:nil completion:^(NSArray *sections, NSArray *chips, NSString *error) {
		if (error) {
			if (completion)
				completion(NO, error);
		} else {
			if (completion)
				completion(YES, [NSString stringWithFormat:@"%lu secciones", (unsigned long)sections.count]);
		}
	}];
}

@end
