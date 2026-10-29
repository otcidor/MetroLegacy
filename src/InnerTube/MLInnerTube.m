#import "MLInnerTube.h"
#import "MLYouTubeStream.h"
#import "MLTLSTrustManager.h"
#import "../Core/MLLibraryManager.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *const MLAPIBase = @"https://music.youtube.com/youtubei/v1/";
static NSString *const MLClientName = @"WEB_REMIX";
static NSString *const MLClientVersion = @"1.20260707.12.00";
static NSString *const MLClientId = @"67";
static NSString *const MLUserAgent = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0";
static NSString *const MLOrigin = @"https://music.youtube.com";

NSString *const MLSessionChangedNotification = @"MLSessionChangedNotification";

NSString *const MLSearchFilterSongs = @"EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D";
NSString *const MLSearchFilterVideos = @"EgWKAQIQAWoKEAkQChAFEAMQBA%3D%3D";
NSString *const MLSearchFilterAlbums = @"EgWKAQIYAWoKEAkQChAFEAMQBA%3D%3D";
NSString *const MLSearchFilterArtists = @"EgWKAQIgAWoKEAkQChAFEAMQBA%3D%3D";
NSString *const MLSearchFilterPlaylists = @"EgeKAQQoADgBagwQDhAKEAMQBRAJEAQ%3D";

#pragma mark - JSON helpers

id MLPath(id root, NSString *keyPath)
{
	if (!root || !keyPath || root == [NSNull null])
		return nil;
	NSArray *parts = [keyPath componentsSeparatedByString:@"."];
	id cur = root;
	for (NSString *p in parts) {
		if ([cur isKindOfClass:[NSDictionary class]]) {
			cur = ((NSDictionary *)cur)[p];
		} else if ([cur isKindOfClass:[NSArray class]]) {
			NSScanner *scanner = [NSScanner scannerWithString:p];
			NSInteger idx = -1;
			if ([scanner scanInteger:&idx] && [scanner isAtEnd]) {
				if (idx >= 0 && idx < (NSInteger)[(NSArray *)cur count]) {
					cur = ((NSArray *)cur)[(NSUInteger)idx];
				} else {
					return nil;
				}
			} else {
				return nil;
			}
		} else {
			return nil;
		}
		if (!cur || cur == [NSNull null])
			return nil;
	}
	return cur;
}

@implementation MLHomeSection
@end
@implementation MLChip
@end

@implementation MLInnerTube
{
	NSURLCache *_noCache;
	NSString *_playerVisitorData;
	NSLock *_visitorLock;
}

+ (instancetype)sharedClient
{
	static MLInnerTube *client = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		client = [[MLInnerTube alloc] init];
		[client loadSavedSession];
	});
	return client;
}

- (id)init
{
	self = [super init];
	if (self) {
		_hl = @"es";
		_gl = @"US";
		_authUser = @"0";
		_visitorLock = [[NSLock alloc] init];
	}
	return self;
}

- (BOOL)loggedIn
{
	if (_accessToken.length > 0)
		return YES;
	return [self sapisidFromCookie:_cookie].length > 0;
}

- (NSString *)cleanDataSyncId:(NSString *)raw
{
	if (![raw isKindOfClass:[NSString class]])
		return nil;
	NSString *s = [[raw stringByReplacingOccurrencesOfString:@"\r" withString:@""]
	                    stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!s.length || [s isEqualToString:@"null"] || [s isEqualToString:@"undefined"])
		return nil;
	NSRange sep = [s rangeOfString:@"||"];
	if (sep.location != NSNotFound) {
		NSString *before = [[s substringToIndex:sep.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *after = [[s substringFromIndex:sep.location + 2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (after.length > 0 && ![after isEqualToString:@"null"] && ![after isEqualToString:@"undefined"]) {
			s = after;
		} else {
			s = before;
		}
	}
	if (!s.length || [s isEqualToString:@"null"] || [s isEqualToString:@"undefined"])
		return nil;
	return s;
}

- (void)setDataSyncId:(NSString *)dataSyncId
{
	_dataSyncId = [self cleanDataSyncId:dataSyncId];
}

- (void)setVisitorData:(NSString *)visitorData
{
	if (![visitorData isKindOfClass:[NSString class]]) {
		_visitorData = nil;
		return;
	}
	NSString *s = [[visitorData stringByReplacingOccurrencesOfString:@"\r" withString:@""]
	                            stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!s.length || [s isEqualToString:@"null"] || [s isEqualToString:@"undefined"]) {
		_visitorData = nil;
		return;
	}
	_visitorData = s;
}

- (void)setAuthUser:(NSString *)authUser
{
	if (![authUser isKindOfClass:[NSString class]]) {
		_authUser = @"0";
		return;
	}
	NSString *s = [authUser stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!s.length || [s isEqualToString:@"null"] || [s isEqualToString:@"undefined"]) {
		_authUser = @"0";
		return;
	}
	_authUser = s;
}

#pragma mark - Session persistence

- (void)saveSession
{
	NSDictionary *d = @{
		@"cookie" : _cookie ?: @"",
		@"visitorData" : _visitorData ?: @"",
		@"dataSyncId" : _dataSyncId ?: @"",
		@"authUser" : _authUser ?: @"0",
		@"accountName" : _accountName ?: @"",
		@"accountEmail" : _accountEmail ?: @"",
		@"accountChannelHandle" : _accountChannelHandle ?: @"",
		@"accountPhotoUrl" : _accountPhotoUrl ?: @"",
		@"hl" : _hl ?: @"es",
		@"gl" : _gl ?: @"US",
		@"accessToken" : _accessToken ?: @"",
		@"refreshToken" : _refreshToken ?: @"",
		@"tokenExpiry" : _tokenExpiry ? @([_tokenExpiry timeIntervalSince1970]) : @(0),
	};
	[[NSUserDefaults standardUserDefaults] setObject:d forKey:@"ml_session"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)loadSavedSession
{
	NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"ml_session"];
	if (!d)
		return;
	NSString *savedCookie = [d[@"cookie"] length] ? d[@"cookie"] : nil;
	if (savedCookie) {
		// If savedCookie was corrupted with headers or newlines from prior paste, auto-heal it
		if ([savedCookie rangeOfString:@"\n"].location != NSNotFound ||
		    [savedCookie rangeOfString:@"INNERTUBE COOKIE"].location != NSNotFound) {
			[self importSessionFromTokenString:savedCookie error:nil];
			return;
		}
		_cookie = [[savedCookie stringByReplacingOccurrencesOfString:@"\r" withString:@""]
		                        stringByReplacingOccurrencesOfString:@"\n" withString:@""];
	}
	self.visitorData = [d[@"visitorData"] length] ? d[@"visitorData"] : nil;
	self.dataSyncId = [d[@"dataSyncId"] length] ? d[@"dataSyncId"] : nil;
	self.authUser = d[@"authUser"] ?: @"0";
	_accountName = [d[@"accountName"] length] ? d[@"accountName"] : nil;
	_accountEmail = [d[@"accountEmail"] length] ? d[@"accountEmail"] : nil;
	_accountChannelHandle = [d[@"accountChannelHandle"] length] ? d[@"accountChannelHandle"] : nil;
	_accountPhotoUrl = [d[@"accountPhotoUrl"] length] ? d[@"accountPhotoUrl"] : nil;
	_hl = d[@"hl"] ?: @"es";
	_gl = d[@"gl"] ?: @"US";

	_accessToken = [d[@"accessToken"] length] ? d[@"accessToken"] : nil;
	_refreshToken = [d[@"refreshToken"] length] ? d[@"refreshToken"] : nil;
	double exp = [d[@"tokenExpiry"] doubleValue];
	_tokenExpiry = exp > 0 ? [NSDate dateWithTimeIntervalSince1970:exp] : nil;

	if (self.loggedIn && (!_accountPhotoUrl.length || !_accountName.length)) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self accountMenu:nil];
		});
	}
}

- (void)clearSession
{
	_cookie = nil;
	_accessToken = nil;
	_refreshToken = nil;
	_tokenExpiry = nil;
	_dataSyncId = nil;
	_accountName = nil;
	_accountEmail = nil;
	_accountChannelHandle = nil;
	_accountPhotoUrl = nil;
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ml_session"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLSessionChangedNotification object:self];
}

- (void)setOAuthAccessToken:(NSString *)access refreshToken:(NSString *)refresh expiresIn:(NSTimeInterval)expires
{
	_accessToken = [access copy];
	if (refresh.length) _refreshToken = [refresh copy];
	_tokenExpiry = [NSDate dateWithTimeIntervalSinceNow:(expires > 0 ? expires : 3600)];
	[self saveSession];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLSessionChangedNotification object:self];
}

- (void)ensureValidAccessToken:(void (^)(BOOL ok))completion
{
	if (!_refreshToken.length) {
		if (completion) completion(_accessToken.length > 0);
		return;
	}
	if (_accessToken.length && _tokenExpiry && [_tokenExpiry timeIntervalSinceNow] > 60) {
		if (completion) completion(YES);
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *urlStr = @"https://www.youtube.com/o/oauth2/token";
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:15.0];
		req.HTTPMethod = @"POST";
		[req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[req setValue:@"Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0)" forHTTPHeaderField:@"User-Agent"];

		NSString *bodyStr = [NSString stringWithFormat:@"client_id=%@&client_secret=%@&refresh_token=%@&grant_type=refresh_token",
		                     @"861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com",
		                     @"SboVhoG9s0rNafixCSGGKXAT",
		                     self->_refreshToken];
		req.HTTPBody = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];

		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];
		if (!err && resp.statusCode == 200 && data.length > 0) {
			NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([json isKindOfClass:[NSDictionary class]] && json[@"access_token"]) {
				self->_accessToken = [json[@"access_token"] copy];
				double exp = [json[@"expires_in"] doubleValue];
				self->_tokenExpiry = [NSDate dateWithTimeIntervalSinceNow:(exp > 0 ? exp : 3600)];
				[self saveSession];
				dispatch_async(dispatch_get_main_queue(), ^{
					if (completion) completion(YES);
				});
				return;
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(NO);
		});
	});
}

- (NSString *)exportSessionTokenString
{
	return [NSString stringWithFormat:
		@"*INNERTUBE COOKIE* =%@\n"
		@"*VISITOR DATA* =%@\n"
		@"*DATASYNC ID* =%@\n"
		@"*AUTH USER* =%@\n"
		@"*ACCOUNT NAME* =%@\n"
		@"*ACCOUNT EMAIL* =%@\n"
		@"*ACCOUNT CHANNEL HANDLE* =%@",
		_cookie ?: @"",
		_visitorData ?: @"",
		_dataSyncId ?: @"",
		_authUser ?: @"0",
		_accountName ?: @"",
		_accountEmail ?: @"",
		_accountChannelHandle ?: @""];
}

- (BOOL)importSessionFromTokenString:(NSString *)tokenString error:(NSString **)errorOut
{
	if (!tokenString) {
		if (errorOut) *errorOut = @"El token no puede estar vacío.";
		return NO;
	}
	NSString *trimmed = [tokenString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (trimmed.length == 0) {
		if (errorOut) *errorOut = @"El token no puede estar vacío.";
		return NO;
	}

	NSString *cookie = nil;
	NSString *visitor = nil;
	NSString *dataSync = nil;
	NSString *auth = nil;
	NSString *accName = nil;
	NSString *accEmail = nil;
	NSString *accHandle = nil;

	NSArray *lines = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	BOOL structured = NO;

	for (NSString *rawLine in lines) {
		NSString *l = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (l.length == 0)
			continue;
		NSRange eq = [l rangeOfString:@"="];
		if (eq.location == NSNotFound)
			continue;

		NSString *rawKey = [l substringToIndex:eq.location];
		NSString *val = [[l substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

		// Normalize key: strip '*', '_', spaces, to uppercase
		NSString *cleanKey = [rawKey stringByReplacingOccurrencesOfString:@"*" withString:@""];
		cleanKey = [cleanKey stringByReplacingOccurrencesOfString:@"_" withString:@" "];
		cleanKey = [cleanKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].uppercaseString;

		if ([cleanKey isEqualToString:@"INNERTUBE COOKIE"] || [cleanKey isEqualToString:@"COOKIE"]) {
			cookie = val;
			structured = YES;
		} else if ([cleanKey isEqualToString:@"VISITOR DATA"] || [cleanKey isEqualToString:@"VISITOR"]) {
			visitor = val;
			structured = YES;
		} else if ([cleanKey isEqualToString:@"DATASYNC ID"] || [cleanKey isEqualToString:@"DATASYNC"]) {
			dataSync = val;
			structured = YES;
		} else if ([cleanKey isEqualToString:@"AUTH USER"] || [cleanKey isEqualToString:@"AUTH"]) {
			auth = val;
			structured = YES;
		} else if ([cleanKey isEqualToString:@"ACCOUNT NAME"]) {
			accName = val;
			structured = YES;
		} else if ([cleanKey isEqualToString:@"ACCOUNT EMAIL"]) {
			accEmail = val;
			structured = YES;
		} else if ([cleanKey isEqualToString:@"ACCOUNT CHANNEL HANDLE"] ||
		           [cleanKey isEqualToString:@"ACCOUNT HANDLE"] ||
		           [cleanKey isEqualToString:@"CHANNEL HANDLE"]) {
			accHandle = val;
			structured = YES;
		}
	}

	if (!structured && !cookie) {
		// Raw cookie pasted directly
		cookie = trimmed;
	}

	if (cookie.length > 0) {
		cookie = [cookie stringByReplacingOccurrencesOfString:@"\r" withString:@""];
		cookie = [cookie stringByReplacingOccurrencesOfString:@"\n" withString:@""];
		cookie = [cookie stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		// If the user pasted a line like '*INNERTUBE COOKIE* =...' as a single line, strip the key if present
		NSRange eqPos = [cookie rangeOfString:@"="];
		if (eqPos.location != NSNotFound) {
			NSString *prefix = [cookie substringToIndex:eqPos.location].uppercaseString;
			if ([prefix rangeOfString:@"COOKIE"].location != NSNotFound) {
				cookie = [[cookie substringFromIndex:eqPos.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			}
		}
	}

	if (cookie.length == 0) {
		if (errorOut) *errorOut = @"No se encontró la cookie de sesión.";
		return NO;
	}

	// Validate SAPISID
	if (![self sapisidFromCookie:cookie].length) {
		if (errorOut) *errorOut = @"La cookie debe contener SAPISID. Formato no reconocido.";
		return NO;
	}

	_cookie = cookie;
	if (visitor.length) {
		self.visitorData = visitor;
	}
	if (dataSync.length) {
		self.dataSyncId = dataSync;
	}
	self.authUser = auth.length ? auth : @"0";
	if (accName.length) _accountName = [accName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (accEmail.length) _accountEmail = [accEmail stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (accHandle.length) _accountChannelHandle = [accHandle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	[self saveSession];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLSessionChangedNotification object:self];
	[self accountMenu:nil];
	return YES;
}

#pragma mark - Request plumbing

- (NSString *)sapisidFromCookie:(NSString *)cookie
{
	if (!cookie)
		return nil;
	NSArray *parts = [cookie componentsSeparatedByString:@";"];
	// Prefer SAPISID first (matches Metrolist InnerTube.kt and Google's SAPISIDHASH verifier),
	// with fallback to __Secure-3PAPISID and __Secure-1PAPISID.
	NSString *sapisid = nil;
	NSString *sapisid3p = nil;
	NSString *sapisid1p = nil;
	for (NSString *rawP in parts) {
		NSString *p = [rawP stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSRange eq = [p rangeOfString:@"="];
		if (eq.location == NSNotFound)
			continue;
		NSString *name = [[p substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSString *value = [[p substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!value.length)
			continue;
		if ([name isEqualToString:@"SAPISID"]) {
			sapisid = value;
			break;
		} else if ([name isEqualToString:@"__Secure-3PAPISID"]) {
			if (!sapisid3p) sapisid3p = value;
		} else if ([name isEqualToString:@"__Secure-1PAPISID"]) {
			if (!sapisid1p) sapisid1p = value;
		}
	}
	return sapisid ?: (sapisid3p ?: sapisid1p);
}

- (NSString *)sapisidHash
{
	NSString *sapisid = [self sapisidFromCookie:_cookie];
	if (!sapisid)
		return nil;
	NSString *time = [NSString stringWithFormat:@"%lld", (long long)[[NSDate date] timeIntervalSince1970]];
	NSString *src = [NSString stringWithFormat:@"%@ %@ %@", time, sapisid, MLOrigin];
	const char *c = [src UTF8String];
	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(c, (CC_LONG)strlen(c), digest);
	NSMutableString *hex = [NSMutableString string];
	for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
		[hex appendFormat:@"%02x", digest[i]];
	return [NSString stringWithFormat:@"%@_%@", time, hex];
}

- (NSString *)prefCookie
{
	NSString *pref = [NSString stringWithFormat:@"PREF=hl=%@&gl=%@", _hl ?: @"es", _gl ?: @"US"];
	if (_cookie.length > 0) {
		NSString *clean = [[_cookie stringByReplacingOccurrencesOfString:@"\r" withString:@""]
		                        stringByReplacingOccurrencesOfString:@"\n" withString:@""];
		clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([clean rangeOfString:@"PREF="].location == NSNotFound)
			return [NSString stringWithFormat:@"%@; %@", clean, pref];
		return clean;
	}
	return pref;
}

- (NSDictionary *)contextDict
{
	NSMutableDictionary *client = [NSMutableDictionary dictionary];
	client[@"clientName"] = MLClientName;
	client[@"clientVersion"] = MLClientVersion;
	client[@"hl"] = _hl ?: @"es";
	client[@"gl"] = _gl ?: @"US";
	if (_visitorData.length > 0)
		client[@"visitorData"] = _visitorData;

	NSMutableDictionary *user = [NSMutableDictionary dictionary];
	user[@"lockedSafetyMode"] = @NO;
	if (self.loggedIn && _dataSyncId.length > 0)
		user[@"onBehalfOfUser"] = _dataSyncId;

	NSMutableDictionary *request = [NSMutableDictionary dictionary];
	request[@"useSsl"] = @YES;

	return @{
		@"client" : client,
		@"request" : request,
		@"user" : user,
	};
}

- (void)postEndpoint:(NSString *)endpoint
                body:(NSDictionary *)body
      urlParams:(NSDictionary *)urlParams
      completion:(void (^)(NSDictionary *response, NSString *error))completion
{
	[self ensureValidAccessToken:^(BOOL ok) {
		NSString *urlStr = [MLAPIBase stringByAppendingString:endpoint];
		if (urlParams.count) {
			NSMutableArray *qs = [NSMutableArray array];
			for (NSString *k in urlParams)
				[qs addObject:[NSString stringWithFormat:@"%@=%@", k, urlParams[k]]];
			urlStr = [urlStr stringByAppendingString:[@"?" stringByAppendingString:[qs componentsJoinedByString:@"&"]]];
		}

		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:30.0];
		req.HTTPMethod = @"POST";
		req.HTTPShouldHandleCookies = NO;
		[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
		[req setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
		[req setValue:MLClientId forHTTPHeaderField:@"X-YouTube-Client-Name"];
		[req setValue:MLClientVersion forHTTPHeaderField:@"X-YouTube-Client-Version"];
		[req setValue:@"1" forHTTPHeaderField:@"X-Goog-Api-Format-Version"];
		[req setValue:MLOrigin forHTTPHeaderField:@"Origin"];
		[req setValue:MLOrigin forHTTPHeaderField:@"X-Origin"];
		[req setValue:[MLOrigin stringByAppendingString:@"/"] forHTTPHeaderField:@"Referer"];
		[req setValue:MLUserAgent forHTTPHeaderField:@"User-Agent"];
		NSString *acceptLang = [NSString stringWithFormat:@"%@,en;q=0.8", self->_hl ?: @"es"];
		[req setValue:acceptLang forHTTPHeaderField:@"Accept-Language"];
		if (self->_visitorData.length > 0)
			[req setValue:self->_visitorData forHTTPHeaderField:@"X-Goog-Visitor-Id"];
		[req setValue:[self prefCookie] forHTTPHeaderField:@"Cookie"];
		if (self.loggedIn) {
			[req setValue:(self->_authUser.length ? self->_authUser : @"0") forHTTPHeaderField:@"X-Goog-AuthUser"];
			if (self->_accessToken.length > 0) {
				[req setValue:[NSString stringWithFormat:@"Bearer %@", self->_accessToken] forHTTPHeaderField:@"Authorization"];
			} else {
				NSString *hash = [self sapisidHash];
				if (hash)
					[req setValue:[@"SAPISIDHASH " stringByAppendingString:hash] forHTTPHeaderField:@"Authorization"];
			}
		}

		NSError *jsonErr = nil;
		NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonErr];
		if (!bodyData) {
			if (completion)
				completion(nil, [NSString stringWithFormat:@"JSON body error: %@", jsonErr.localizedDescription]);
			return;
		}
		req.HTTPBody = bodyData;

		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			NSError *err = nil;
			NSHTTPURLResponse *resp = nil;
			NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];
			NSString *error = nil;
			NSDictionary *json = nil;
			if (err) {
				error = [NSString stringWithFormat:@"Red: %@", err.localizedDescription];
			} else if (resp.statusCode != 200) {
				NSString *snippet = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
				if (snippet.length > 300)
					snippet = [snippet substringToIndex:300];
				error = [NSString stringWithFormat:@"HTTP %ld: %@", (long)resp.statusCode, snippet];
			} else {
				json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
				if (!json)
					error = [NSString stringWithFormat:@"JSON parse: %@", err.localizedDescription];
			}
			// capture visitorData from any response
			NSString *vd = MLPath(json, @"responseContext.visitorData");
			if ([vd isKindOfClass:[NSString class]] && vd.length > 0 && ![MLInnerTube sharedClient].visitorData) {
				[MLInnerTube sharedClient].visitorData = vd;
				[[MLInnerTube sharedClient] saveSession];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion)
					completion(json, error);
			});
		});
	}];
}

- (NSString *)sessionVisitorDataForVideoId:(NSString *)videoId forceRefresh:(BOOL)forceRefresh
{
	[_visitorLock lock];
	if (!forceRefresh && _playerVisitorData.length > 0) {
		NSString *cached = [_playerVisitorData copy];
		[_visitorLock unlock];
		return cached;
	}
	[_visitorLock unlock];

	NSString *probeVid = videoId.length ? videoId : @"dQw4w9WgXcQ";
	NSURL *url = [NSURL URLWithString:@"https://www.youtube.com/youtubei/v1/player?prettyPrint=false"];

	// 1. Fetch fresh anonymous IP-bound visitorData via IOS client (with .YT= rollout attestation)
	NSMutableURLRequest *iosReq = [NSMutableURLRequest requestWithURL:url
	                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
	                                                  timeoutInterval:15.0];
	iosReq.HTTPMethod = @"POST";
	iosReq.HTTPShouldHandleCookies = NO;
	[iosReq setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[iosReq setValue:@"com.google.ios.youtube/20.10.4 (iPhone16,1; U; CPU iOS 18_0 like Mac OS X;)" forHTTPHeaderField:@"User-Agent"];
	[iosReq setValue:@"5" forHTTPHeaderField:@"X-YouTube-Client-Name"];
	[iosReq setValue:@"20.10.4" forHTTPHeaderField:@"X-YouTube-Client-Version"];

	NSDictionary *iosBody = @{
		@"context" : @{
			@"client" : @{
				@"clientName" : @"IOS",
				@"clientVersion" : @"20.10.4",
				@"deviceModel" : @"iPhone16,1",
				@"hl" : self.hl ?: @"es",
				@"gl" : self.gl ?: @"US",
			}
		},
		@"videoId" : probeVid,
		@"contentCheckOk" : @YES,
		@"racyCheckOk" : @YES,
	};
	iosReq.HTTPBody = [NSJSONSerialization dataWithJSONObject:iosBody options:0 error:nil];

	NSHTTPURLResponse *resp = nil;
	NSData *data = [MLTLSTrustManager sendSynchronousRequest:iosReq returningResponse:&resp error:nil];
	NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	NSString *vd = MLPath(json, @"responseContext.visitorData");

	// 2. Fallback to anonymous WEB player request (Troubadour fetchFreshVisitorData: port)
	if (![vd isKindOfClass:[NSString class]] || vd.length == 0) {
		NSMutableURLRequest *webReq = [NSMutableURLRequest requestWithURL:url
		                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                                  timeoutInterval:15.0];
		webReq.HTTPMethod = @"POST";
		webReq.HTTPShouldHandleCookies = NO;
		[webReq setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[webReq setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
		[webReq setValue:@"1" forHTTPHeaderField:@"X-YouTube-Client-Name"];
		[webReq setValue:@"2.20260626.01.00" forHTTPHeaderField:@"X-YouTube-Client-Version"];
		[webReq setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];

		NSDictionary *webBody = @{
			@"context" : @{
				@"client" : @{
					@"clientName" : @"WEB",
					@"clientVersion" : @"2.20260626.01.00",
					@"hl" : self.hl ?: @"es",
					@"gl" : self.gl ?: @"US",
				}
			},
			@"videoId" : probeVid,
			@"contentCheckOk" : @YES,
			@"racyCheckOk" : @YES,
		};
		webReq.HTTPBody = [NSJSONSerialization dataWithJSONObject:webBody options:0 error:nil];
		NSData *webData = [MLTLSTrustManager sendSynchronousRequest:webReq returningResponse:&resp error:nil];
		NSDictionary *webJson = webData ? [NSJSONSerialization JSONObjectWithData:webData options:0 error:nil] : nil;
		vd = MLPath(webJson, @"responseContext.visitorData");
	}

	if ([vd isKindOfClass:[NSString class]] && vd.length > 0) {
		[_visitorLock lock];
		_playerVisitorData = [vd copy];
		[_visitorLock unlock];
		return vd;
	}
	return nil;
}

#pragma mark - Raw endpoints

- (void)browse:(NSString *)browseId params:(NSString *)params continuation:(NSString *)continuation
    completion:(void (^)(NSDictionary *, NSString *))completion
{
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	if (browseId.length && !continuation.length)
		body[@"browseId"] = browseId;
	if (params.length)
		body[@"params"] = params;
	if (continuation.length)
		body[@"continuation"] = continuation;
	[self postEndpoint:@"browse" body:body urlParams:nil completion:completion];
}

- (void)searchRaw:(NSString *)query params:(NSString *)params continuation:(NSString *)continuation
      completion:(void (^)(NSDictionary *, NSString *))completion
{
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	if (query)
		body[@"query"] = query;
	if (params)
		body[@"params"] = params;
	NSMutableDictionary *urlParams = nil;
	if (continuation)
		urlParams = [@{ @"ctoken" : continuation, @"continuation" : continuation } mutableCopy];
	[self postEndpoint:@"search" body:body urlParams:urlParams completion:completion];
}

- (void)playerForVideoId:(NSString *)videoId
	signatureTimestamp:(NSInteger)sts
	           poToken:(NSString *)poToken
	        completion:(void (^)(NSDictionary *, NSString *))completion
{
	if (!videoId.length) {
		if (completion)
			completion(nil, @"videoId vacío");
		return;
	}

	// 1. Primary: High-performance iOS native client player request (direct unencrypted streams, no PoToken needed)
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSURL *url = [NSURL URLWithString:@"https://www.youtube.com/youtubei/v1/player?prettyPrint=false"];
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:25.0];
		req.HTTPMethod = @"POST";
		req.HTTPShouldHandleCookies = NO;
		[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[req setValue:@"com.google.ios.youtube/20.10.4 (iPhone16,1; U; CPU iOS 18_0 like Mac OS X;)" forHTTPHeaderField:@"User-Agent"];
		[req setValue:@"5" forHTTPHeaderField:@"X-YouTube-Client-Name"];
		[req setValue:@"20.10.4" forHTTPHeaderField:@"X-YouTube-Client-Version"];

		NSDictionary *body = @{
			@"context" : @{
				@"client" : @{
					@"clientName" : @"IOS",
					@"clientVersion" : @"20.10.4",
					@"deviceModel" : @"iPhone16,1",
					@"hl" : self.hl ?: @"es",
					@"gl" : self.gl ?: @"US",
				}
			},
			@"videoId" : videoId,
			@"contentCheckOk" : @YES,
			@"racyCheckOk" : @YES,
		};

		NSError *err = nil;
		req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
		NSHTTPURLResponse *resp = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

		NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		NSString *freshVd = MLPath(json, @"responseContext.visitorData");
		if ([freshVd isKindOfClass:[NSString class]] && freshVd.length > 0) {
			[self->_visitorLock lock];
			self->_playerVisitorData = [freshVd copy];
			[self->_visitorLock unlock];
		}
		NSString *status = MLPath(json, @"playabilityStatus.status");
		NSArray *adaptive = MLPath(json, @"streamingData.adaptiveFormats");

		if ([status isEqualToString:@"OK"] && [adaptive isKindOfClass:[NSArray class]] && adaptive.count > 0) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion)
					completion(json, nil);
			});
			return;
		}

		// 2. Fallback to WEB_REMIX if iOS client endpoint failed
		dispatch_async(dispatch_get_main_queue(), ^{
			NSMutableDictionary *webBody = [NSMutableDictionary dictionary];
			NSMutableDictionary *ctx = [[self contextDict] mutableCopy];
			if (poToken.length > 0) {
				ctx[@"serviceIntegrityDimensions"] = @{ @"poToken" : poToken };
				webBody[@"serviceIntegrityDimensions"] = @{ @"poToken" : poToken };
			}
			webBody[@"context"] = ctx;
			webBody[@"videoId"] = videoId;
			webBody[@"contentCheckOk"] = @YES;
			webBody[@"racyCheckOk"] = @YES;
			NSMutableDictionary *cpm = [NSMutableDictionary dictionary];
			cpm[@"html5Preference"] = @"HTML5_PREF_WANTS";
			if (sts > 0)
				cpm[@"signatureTimestamp"] = @(sts);
			webBody[@"playbackContext"] = @{ @"contentPlaybackContext" : cpm };
			[self postEndpoint:@"player" body:webBody urlParams:nil completion:completion];
		});
	});
}

- (void)playerForVideoId:(NSString *)videoId signatureTimestamp:(NSInteger)sts
              completion:(void (^)(NSDictionary *, NSString *))completion
{
	[self playerForVideoId:videoId signatureTimestamp:sts poToken:nil completion:completion];
}

- (void)playerAndroidVrForVideoId:(NSString *)videoId
                       completion:(void (^)(NSDictionary *playerResponse, NSString *error))completion
{
	if (!videoId.length) {
		if (completion) completion(nil, @"videoId vacío");
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *vd = [self sessionVisitorDataForVideoId:videoId forceRefresh:NO];
		NSURL *url = [NSURL URLWithString:@"https://www.youtube.com/youtubei/v1/player?prettyPrint=false"];
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:25.0];
		req.HTTPMethod = @"POST";
		req.HTTPShouldHandleCookies = NO;
		[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		[req setValue:@"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip" forHTTPHeaderField:@"User-Agent"];
		[req setValue:@"28" forHTTPHeaderField:@"X-YouTube-Client-Name"];
		[req setValue:@"1.65.10" forHTTPHeaderField:@"X-YouTube-Client-Version"];
		[req setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
		if (vd.length > 0) {
			[req setValue:vd forHTTPHeaderField:@"X-Goog-Visitor-Id"];
		}

		NSMutableDictionary *client = [NSMutableDictionary dictionary];
		client[@"clientName"] = @"ANDROID_VR";
		client[@"clientVersion"] = @"1.65.10";
		client[@"deviceMake"] = @"Oculus";
		client[@"deviceModel"] = @"Quest 3";
		client[@"androidSdkVersion"] = @32;
		client[@"osName"] = @"Android";
		client[@"osVersion"] = @"12L";
		client[@"platform"] = @"MOBILE";
		client[@"hl"] = self.hl ?: @"es";
		client[@"gl"] = self.gl ?: @"US";
		if (vd.length > 0) {
			client[@"visitorData"] = vd;
		}

		NSDictionary *body = @{
			@"context" : @{ @"client" : client },
			@"videoId" : videoId,
			@"contentCheckOk" : @YES,
			@"racyCheckOk" : @YES,
		};

		NSError *err = nil;
		req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
		NSHTTPURLResponse *resp = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

		NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		NSString *status = MLPath(json, @"playabilityStatus.status");
		NSArray *adaptive = MLPath(json, @"streamingData.adaptiveFormats");

		if ([status isEqualToString:@"OK"] && [adaptive isKindOfClass:[NSArray class]] && adaptive.count > 0) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(json, nil);
			});
			return;
		}

		NSString *reason = MLPath(json, @"playabilityStatus.reason") ?: (err ? err.localizedDescription : @"Error ANDROID_VR");
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(nil, reason);
		});
	});
}

- (void)playerVisionOsForVideoId:(NSString *)videoId
                      completion:(void (^)(NSDictionary *playerResponse, NSString *error))completion
{
	if (!videoId.length) {
		if (completion) completion(nil, @"videoId vacío");
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *lastReason = nil;

		for (int attempt = 0; attempt < 2; attempt++) {
			NSString *vd = [self sessionVisitorDataForVideoId:videoId forceRefresh:(attempt > 0)];

			NSURL *url = [NSURL URLWithString:@"https://www.youtube.com/youtubei/v1/player?prettyPrint=false"];
			NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
			                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
			                                               timeoutInterval:25.0];
			req.HTTPMethod = @"POST";
			req.HTTPShouldHandleCookies = NO;
			[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
			[req setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15" forHTTPHeaderField:@"User-Agent"];
			[req setValue:@"101" forHTTPHeaderField:@"X-YouTube-Client-Name"];
			[req setValue:@"1.02" forHTTPHeaderField:@"X-YouTube-Client-Version"];
			[req setValue:@"https://www.youtube.com" forHTTPHeaderField:@"Origin"];
			if (vd.length > 0) {
				[req setValue:vd forHTTPHeaderField:@"X-Goog-Visitor-Id"];
			}

			NSMutableDictionary *client = [NSMutableDictionary dictionary];
			client[@"clientName"] = @"VISIONOS";
			client[@"clientVersion"] = @"1.02";
			client[@"deviceMake"] = @"Apple";
			client[@"deviceModel"] = @"RealityDevice14,1";
			client[@"osName"] = @"visionOS";
			client[@"osVersion"] = @"1.0.2.21O209";
			client[@"userAgent"] = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
			client[@"hl"] = self.hl ?: @"es";
			client[@"gl"] = self.gl ?: @"US";
			if (vd.length > 0) {
				client[@"visitorData"] = vd;
			}

			NSDictionary *body = @{
				@"context" : @{ @"client" : client },
				@"videoId" : videoId,
				@"contentCheckOk" : @YES,
				@"racyCheckOk" : @YES,
			};

			NSError *err = nil;
			req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
			NSHTTPURLResponse *resp = nil;
			NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

			NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
			NSString *status = MLPath(json, @"playabilityStatus.status");
			NSArray *adaptive = MLPath(json, @"streamingData.adaptiveFormats");

			if ([status isEqualToString:@"OK"] && [adaptive isKindOfClass:[NSArray class]] && adaptive.count > 0) {
				NSString *newVd = MLPath(json, @"responseContext.visitorData");
				if ([newVd isKindOfClass:[NSString class]] && newVd.length > 0) {
					[self->_visitorLock lock];
					self->_playerVisitorData = [newVd copy];
					[self->_visitorLock unlock];
				}
				dispatch_async(dispatch_get_main_queue(), ^{
					if (completion) completion(json, nil);
				});
				return;
			}

			lastReason = MLPath(json, @"playabilityStatus.reason") ?: (err ? err.localizedDescription : @"Error VISIONOS");
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(nil, lastReason ?: @"Error VISIONOS");
		});
	});
}

- (void)suggestionsForInput:(NSString *)input completion:(void (^)(NSArray *, NSString *))completion
{
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	body[@"input"] = input;
	[self postEndpoint:@"music/get_search_suggestions" body:body urlParams:nil
	          completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (completion)
				completion(nil, err);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		NSArray *sections = [MLInnerTube allObjectsForKey:@"searchSuggestionsSectionRenderer" inObject:[resp objectForKey:@"contents"] maxDepth:6];
		for (NSDictionary *sec in sections) {
			for (NSDictionary *c in MLPath(sec, @"contents") ?: @[]) {
				NSDictionary *li = MLPath(c, @"musicResponsiveListItemRenderer");
				NSString *text = [MLInnerTube textFromRuns:MLPath(li, @"flexColumns.0.musicResponsiveListItemFlexColumnRenderer.text")];
				if (text.length)
					[out addObject:text];
			}
		}
		if (completion)
			completion(out, nil);
	}];
}

- (void)accountMenu:(void (^)(NSDictionary *, NSString *))completion
{
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	[self postEndpoint:@"account/account_menu" body:body urlParams:nil
	          completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (self->_accountName.length > 0) {
				NSMutableDictionary *fallback = [NSMutableDictionary dictionary];
				fallback[@"accountName"] = self->_accountName;
				if (self->_accountEmail) fallback[@"email"] = self->_accountEmail;
				if (self->_accountChannelHandle) fallback[@"channelHandle"] = self->_accountChannelHandle;
				if (self->_accountPhotoUrl) fallback[@"photo"] = self->_accountPhotoUrl;
				if (completion)
					completion(fallback, nil);
				return;
			}
			if (completion)
				completion(nil, err);
			return;
		}
		NSDictionary *hdr = [MLInnerTube allObjectsForKey:@"activeAccountHeaderRenderer" inObject:resp maxDepth:8].firstObject;
		if (!hdr) {
			hdr = [MLInnerTube allObjectsForKey:@"googleAccountHeaderRenderer" inObject:resp maxDepth:8].firstObject;
		}
		NSMutableDictionary *info = [NSMutableDictionary dictionary];
		NSString *name = [MLInnerTube textFromRuns:MLPath(hdr, @"accountName")] ?: [MLInnerTube textFromRuns:MLPath(hdr, @"name")];
		NSString *email = [MLInnerTube textFromRuns:MLPath(hdr, @"accountEmail")] ?: [MLInnerTube textFromRuns:MLPath(hdr, @"email")];
		NSString *photo = [MLInnerTube bestThumbnailUrl:MLPath(hdr, @"accountPhoto.thumbnails") ?: MLPath(hdr, @"accountPhoto")];
		NSString *handle = [MLInnerTube textFromRuns:MLPath(hdr, @"channelHandle")];

		if (name.length) info[@"accountName"] = name;
		if (email.length) info[@"email"] = email;
		if (photo.length) info[@"photo"] = photo;
		if (handle.length) info[@"channelHandle"] = handle;

		if (!info[@"accountName"] && self->_accountName.length > 0) {
			info[@"accountName"] = self->_accountName;
		}
		if (!info[@"channelHandle"] && self->_accountChannelHandle.length > 0) {
			info[@"channelHandle"] = self->_accountChannelHandle;
		}

		if (info[@"accountName"] || info[@"photo"]) {
			if (info[@"accountName"]) self->_accountName = info[@"accountName"];
			if (info[@"email"]) self->_accountEmail = info[@"email"];
			if (info[@"photo"]) self->_accountPhotoUrl = info[@"photo"];
			if (info[@"channelHandle"]) self->_accountChannelHandle = info[@"channelHandle"];
			[self saveSession];
			[[NSNotificationCenter defaultCenter] postNotificationName:MLSessionChangedNotification object:self];
		}

		if (completion)
			completion(info, info[@"accountName"] ? nil : @"No se pudo leer la cuenta");
	}];
}

#pragma mark - Parsed operations

- (void)homeFeedWithParams:(NSString *)params
               completion:(void (^)(NSArray *sections, NSArray *chips, NSString *error))completion
{
	[self browse:@"FEmusic_home" params:params continuation:nil
	      completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (completion)
				completion(nil, nil, err);
			return;
		}
		NSArray *sections = [MLInnerTube homeSectionsFromResponse:resp];
		NSArray *chips = [MLInnerTube chipsFromResponse:resp];
		if (completion)
			completion(sections, chips, nil);
	}];
}

- (void)searchQuery:(NSString *)query params:(NSString *)params continuation:(NSString *)continuation
        completion:(void (^)(NSArray *items, NSString *next, NSString *err))completion
{
	[self searchRaw:query params:params continuation:continuation
	      completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (completion)
				completion(nil, nil, err);
			return;
		}
		NSMutableArray *items = [NSMutableArray array];
		NSString *next = [MLInnerTube continuationFromResponseOrShelf:resp];

		// 1. Top result cards
		for (NSDictionary *card in [MLInnerTube allObjectsForKey:@"musicCardShelfRenderer" inObject:resp maxDepth:8]) {
			for (NSDictionary *c in MLPath(card, @"contents") ?: @[]) {
				MLYTItem *it = [MLInnerTube itemFromRenderer:c];
				if (it)
					[items addObject:it];
			}
		}

		// 2. Item sections (standard in modern YouTube Music search results)
		for (NSDictionary *sec in [MLInnerTube allObjectsForKey:@"itemSectionRenderer" inObject:resp maxDepth:8]) {
			for (NSDictionary *c in MLPath(sec, @"contents") ?: @[]) {
				MLYTItem *it = [MLInnerTube itemFromRenderer:c];
				if (it)
					[items addObject:it];
			}
		}

		// 3. Music shelves (filtered search tabs, e.g. songs, albums)
		for (NSDictionary *shelf in [MLInnerTube allObjectsForKey:@"musicShelfRenderer" inObject:resp maxDepth:8]) {
			for (NSDictionary *c in MLPath(shelf, @"contents") ?: @[]) {
				MLYTItem *it = [MLInnerTube itemFromRenderer:c];
				if (it)
					[items addObject:it];
			}
		}

		// 4. Fallback: direct responsive list items
		if (items.count == 0) {
			for (NSDictionary *r in [MLInnerTube allObjectsForKey:@"musicResponsiveListItemRenderer" inObject:resp maxDepth:12]) {
				MLYTItem *it = [MLInnerTube itemFromResponsiveListRenderer:r];
				if (it)
					[items addObject:it];
			}
		}

		if (completion)
			completion(items, next, nil);
	}];
}

- (void)albumWithBrowseId:(NSString *)browseId
              completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *err))completion
{
	if ([browseId hasPrefix:@"VL"]) {
		[self playlistWithId:browseId continuation:nil
		        completion:^(NSDictionary *h, NSArray *t, NSString *next, NSString *e) {
			if (completion)
				completion(h, t, e);
		}];
		return;
	}

	[self browse:browseId params:nil continuation:nil
	      completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (completion)
				completion(nil, nil, err);
			return;
		}

		NSDictionary *header = [MLInnerTube headerInfoFromResponse:resp];
		NSMutableArray *tracks = [NSMutableArray array];

		// Check if tracks are directly in this album browse response (under musicShelfRenderer, etc.)
		NSArray *shelfKeys = @[ @"musicShelfRenderer", @"musicPlaylistShelfRenderer" ];
		for (NSString *key in shelfKeys) {
			for (NSDictionary *shelf in [MLInnerTube allObjectsForKey:key inObject:resp maxDepth:14]) {
				for (NSDictionary *c in MLPath(shelf, @"contents") ?: @[]) {
					MLYTItem *it = [MLInnerTube itemFromRenderer:c];
					if (it)
						[tracks addObject:it];
				}
			}
		}

		// Fallback: direct responsive items in response
		if (tracks.count == 0) {
			for (NSDictionary *r in [MLInnerTube allObjectsForKey:@"musicResponsiveListItemRenderer" inObject:resp maxDepth:14]) {
				MLYTItem *it = [MLInnerTube itemFromResponsiveListRenderer:r];
				if (it)
					[tracks addObject:it];
			}
		}

		if (tracks.count > 0) {
			if (completion)
				completion(header, tracks, nil);
			return;
		}

		// Otherwise, find playlist id from microformat
		NSString *canonical = MLPath(resp, @"microformat.microformatDataRenderer.urlCanonical");
		NSString *playlistId = nil;
		if ([canonical isKindOfClass:[NSString class]]) {
			NSRange r = [canonical rangeOfString:@"list=" options:NSBackwardsSearch];
			if (r.location != NSNotFound)
				playlistId = [canonical substringFromIndex:r.location + 5];
		}
		if (!playlistId) {
			if (completion)
				completion(header, @[], nil);
			return;
		}
		NSString *vl = [@"VL" stringByAppendingString:playlistId];
		[self playlistWithId:vl continuation:nil
		        completion:^(NSDictionary *h, NSArray *vlTracks, NSString *next, NSString *e2) {
			NSMutableDictionary *hdr = header ? [header mutableCopy] : [NSMutableDictionary dictionary];
			if (h)
				[hdr addEntriesFromDictionary:h];
			if (completion)
				completion(hdr, vlTracks, e2);
		}];
	}];
}

- (void)playlistWithId:(NSString *)playlistId continuation:(NSString *)continuation
           completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err))completion
{
	if ([playlistId hasPrefix:@"MPRE"]) {
		[self albumWithBrowseId:playlistId completion:^(NSDictionary *h, NSArray *t, NSString *e) {
			if (completion)
				completion(h, t, nil, e);
		}];
		return;
	}

	NSString *browseId = ([playlistId hasPrefix:@"VL"] || [playlistId hasPrefix:@"FE"]) ? playlistId : [@"VL" stringByAppendingString:playlistId];
	NSString *rawPid = [playlistId hasPrefix:@"VL"] ? [playlistId substringFromIndex:2] : playlistId;

	[self browse:(continuation.length ? nil : browseId) params:nil continuation:continuation
	      completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (!continuation.length && rawPid.length > 0) {
				[self nextForVideoId:nil playlistId:rawPid completion:^(NSArray *items, NSString *title, NSString *nextErr) {
					if (items.count > 0) {
						NSDictionary *hdr = title.length ? @{ @"title" : title } : @{};
						if (completion)
							completion(hdr, items, nil, nil);
					} else if (completion) {
						completion(nil, nil, nil, err ?: nextErr);
					}
				}];
				return;
			}
			if (completion)
				completion(nil, nil, nil, err);
			return;
		}
		NSDictionary *header = [MLInnerTube headerInfoFromResponse:resp];
		NSMutableArray *tracks = [NSMutableArray array];
		NSString *next = [MLInnerTube continuationFromResponseOrShelf:resp];

		NSArray *shelfKeys = @[
			@"musicPlaylistShelfRenderer",
			@"musicShelfRenderer",
			@"musicPlaylistShelfContinuation",
			@"musicShelfContinuation"
		];
		for (NSString *shelfKey in shelfKeys) {
			NSArray *shelves = [MLInnerTube allObjectsForKey:shelfKey inObject:resp maxDepth:14];
			for (NSDictionary *shelf in shelves) {
				for (NSDictionary *c in MLPath(shelf, @"contents") ?: @[]) {
					MLYTItem *it = [MLInnerTube itemFromRenderer:c];
					if (it)
						[tracks addObject:it];
				}
				NSString *shelfNext = [MLInnerTube continuationFromResponseOrShelf:shelf];
				if (shelfNext)
					next = shelfNext;
			}
		}

		for (NSDictionary *act in [MLInnerTube allObjectsForKey:@"appendContinuationItemsAction" inObject:resp maxDepth:10]) {
			for (NSDictionary *c in MLPath(act, @"continuationItems") ?: @[]) {
				MLYTItem *it = [MLInnerTube itemFromRenderer:c];
				if (it)
					[tracks addObject:it];
			}
		}

		// Fallback: search for direct musicResponsiveListItemRenderer
		if (tracks.count == 0) {
			for (NSDictionary *r in [MLInnerTube allObjectsForKey:@"musicResponsiveListItemRenderer" inObject:resp maxDepth:14]) {
				MLYTItem *it = [MLInnerTube itemFromResponsiveListRenderer:r];
				if (it)
					[tracks addObject:it];
			}
		}

		if (tracks.count == 0 && !continuation.length && rawPid.length > 0) {
			[self nextForVideoId:nil playlistId:rawPid completion:^(NSArray *items, NSString *title, NSString *nextErr) {
				if (items.count > 0) {
					NSMutableDictionary *hdr = header ? [header mutableCopy] : [NSMutableDictionary dictionary];
					if (title.length && !hdr[@"title"])
						hdr[@"title"] = title;
					if (completion)
						completion(hdr, items, nil, nil);
				} else if (completion) {
					completion(header, tracks, next, nil);
				}
			}];
			return;
		}

		if (completion)
			completion(header, tracks, next, nil);
	}];
}

- (void)artistWithBrowseId:(NSString *)browseId
               completion:(void (^)(NSDictionary *header, NSArray *sections, NSString *err))completion
{
	if ([browseId hasPrefix:@"MPLAUC"]) {
		browseId = [browseId substringFromIndex:4];
	}
	[self browse:browseId params:nil continuation:nil
	      completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (completion)
				completion(nil, nil, err);
			return;
		}
		if (completion)
			completion([MLInnerTube headerInfoFromResponse:resp], [MLInnerTube homeSectionsFromResponse:resp], nil);
	}];
}

- (void)fetchPlaylistPagesWithId:(NSString *)playlistId
                    continuation:(NSString *)continuation
                     accumHeader:(NSDictionary *)accumHeader
                     accumTracks:(NSMutableArray *)accumTracks
                         seenIds:(NSMutableSet *)seenIds
                       remaining:(NSInteger)remaining
                      completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err))completion
{
	[self playlistWithId:playlistId continuation:continuation completion:^(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err) {
		if (err && accumTracks.count == 0) {
			if (completion) completion(nil, nil, nil, err);
			return;
		}
		NSDictionary *mergedHeader = accumHeader.count ? accumHeader : header;
		for (MLYTItem *it in tracks) {
			if (it.videoId.length) {
				if ([seenIds containsObject:it.videoId]) continue;
				[seenIds addObject:it.videoId];
			}
			[accumTracks addObject:it];
		}
		if (next.length > 0 && remaining > 1 && tracks.count > 0) {
			[self fetchPlaylistPagesWithId:playlistId
			                  continuation:next
			                   accumHeader:mergedHeader
			                   accumTracks:accumTracks
			                       seenIds:seenIds
			                     remaining:remaining - 1
			                    completion:completion];
		} else {
			if (completion) completion(mergedHeader, accumTracks, next, nil);
		}
	}];
}

- (void)likedSongsWithContinuation:(NSString *)continuation
                        completion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err))completion
{
	if (!self.loggedIn) {
		if (completion)
			completion(nil, nil, nil, @"Inicia sesión para ver tus canciones gustadas");
		return;
	}
	[self playlistWithId:@"VLLM" continuation:continuation completion:completion];
}

- (void)likedSongsWithCompletion:(void (^)(NSDictionary *header, NSArray *tracks, NSString *next, NSString *err))completion
{
	[self likedSongsWithContinuation:nil completion:completion];
}

- (void)fetchLibraryPagesWithBrowseId:(NSString *)browseId
                         continuation:(NSString *)continuation
                           accumItems:(NSMutableArray *)accumItems
                              seenIds:(NSMutableSet *)seenIds
                            remaining:(NSInteger)remaining
                           completion:(void (^)(NSArray *items, NSString *error))completion
{
	[self browse:(continuation.length ? nil : browseId) params:nil continuation:continuation completion:^(NSDictionary *resp, NSString *err) {
		if (!resp) {
			if (accumItems.count > 0) {
				if (completion) completion(accumItems, nil);
			} else {
				if (completion) completion(nil, err);
			}
			return;
		}
		NSMutableArray *pageItems = [NSMutableArray array];
		NSString *next = [MLInnerTube continuationFromResponseOrShelf:resp];

		// 1. Parse grids and grid continuations (FEmusic_liked_playlists, FEmusic_liked_albums)
		for (NSString *gridKey in @[ @"gridRenderer", @"gridContinuation" ]) {
			for (NSDictionary *grid in [MLInnerTube allObjectsForKey:gridKey inObject:resp maxDepth:14]) {
				for (NSDictionary *entry in MLPath(grid, @"items") ?: @[]) {
					MLYTItem *it = [MLInnerTube itemFromRenderer:entry];
					if (!it) continue;
					NSString *uid = it.videoId ?: (it.playlistId ?: it.browseId);
					if (uid.length && [seenIds containsObject:uid]) continue;
					if (uid.length) [seenIds addObject:uid];
					[pageItems addObject:it];
				}
				NSString *gridNext = [MLInnerTube continuationFromResponseOrShelf:grid];
				if (gridNext) next = gridNext;
			}
		}

		// 2. Parse music shelves / playlist shelves / continuations (FEmusic_liked_videos, FEmusic_library_corpus_artists, FEmusic_history)
		// Note: Exclude musicCarouselShelfRenderer so "Recent activity" carousels do not pollute library tabs.
		for (NSString *shelfKey in @[ @"musicShelfRenderer", @"musicPlaylistShelfRenderer", @"musicShelfContinuation", @"musicPlaylistShelfContinuation" ]) {
			for (NSDictionary *shelf in [MLInnerTube allObjectsForKey:shelfKey inObject:resp maxDepth:14]) {
				for (NSDictionary *entry in MLPath(shelf, @"contents") ?: @[]) {
					MLYTItem *it = [MLInnerTube itemFromRenderer:entry];
					if (!it) continue;
					NSString *uid = it.videoId ?: (it.playlistId ?: it.browseId);
					if (uid.length && [seenIds containsObject:uid]) continue;
					if (uid.length) [seenIds addObject:uid];
					[pageItems addObject:it];
				}
				NSString *shelfNext = [MLInnerTube continuationFromResponseOrShelf:shelf];
				if (shelfNext) next = shelfNext;
			}
		}

		for (NSDictionary *act in [MLInnerTube allObjectsForKey:@"appendContinuationItemsAction" inObject:resp maxDepth:10]) {
			for (NSDictionary *entry in MLPath(act, @"continuationItems") ?: @[]) {
				MLYTItem *it = [MLInnerTube itemFromRenderer:entry];
				if (!it) continue;
				NSString *uid = it.videoId ?: (it.playlistId ?: it.browseId);
				if (uid.length && [seenIds containsObject:uid]) continue;
				if (uid.length) [seenIds addObject:uid];
				[pageItems addObject:it];
			}
		}

		// 3. Fallback: direct two-row or responsive items
		if (pageItems.count == 0) {
			for (NSDictionary *r in [MLInnerTube allObjectsForKey:@"musicTwoRowItemRenderer" inObject:resp maxDepth:14]) {
				MLYTItem *it = [MLInnerTube itemFromTwoRowRenderer:r];
				if (!it) continue;
				NSString *uid = it.videoId ?: (it.playlistId ?: it.browseId);
				if (uid.length && [seenIds containsObject:uid]) continue;
				if (uid.length) [seenIds addObject:uid];
				[pageItems addObject:it];
			}
			for (NSDictionary *r in [MLInnerTube allObjectsForKey:@"musicResponsiveListItemRenderer" inObject:resp maxDepth:14]) {
				MLYTItem *it = [MLInnerTube itemFromResponsiveListRenderer:r];
				if (!it) continue;
				NSString *uid = it.videoId ?: (it.playlistId ?: it.browseId);
				if (uid.length && [seenIds containsObject:uid]) continue;
				if (uid.length) [seenIds addObject:uid];
				[pageItems addObject:it];
			}
		}

		[accumItems addObjectsFromArray:pageItems];

		if (next.length > 0 && remaining > 1 && pageItems.count > 0) {
			[self fetchLibraryPagesWithBrowseId:browseId
			                       continuation:next
			                         accumItems:accumItems
			                            seenIds:seenIds
			                          remaining:remaining - 1
			                         completion:completion];
		} else {
			if (completion) completion(accumItems, nil);
		}
	}];
}

- (void)libraryWithBrowseId:(NSString *)browseId
                 completion:(void (^)(NSArray *items, NSString *error))completion
{
	if (!browseId.length) {
		if (completion) completion(@[], nil);
		return;
	}
	NSInteger maxPages = [browseId isEqualToString:@"FEmusic_history"] ? 2 : 5;
	[self fetchLibraryPagesWithBrowseId:browseId
	                       continuation:nil
	                         accumItems:[NSMutableArray array]
	                            seenIds:[NSMutableSet set]
	                          remaining:maxPages
	                         completion:completion];
}

- (void)likeVideoWithId:(NSString *)videoId
                  liked:(BOOL)liked
             completion:(void (^)(BOOL ok, NSString *error))completion
{
	if (!videoId.length) {
		if (completion) completion(NO, @"videoId vacío");
		return;
	}
	if (!self.loggedIn) {
		if (completion) completion(NO, nil);
		return;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	body[@"target"] = @{ @"videoId" : videoId };
	NSString *endpoint = liked ? @"like/like" : @"like/removelike";
	[self postEndpoint:endpoint body:body urlParams:nil completion:^(NSDictionary *resp, NSString *err) {
		if (completion)
			completion(resp != nil && !err, err);
	}];
}

- (void)createPlaylistWithTitle:(NSString *)title
                     completion:(void (^)(NSString *playlistId, NSString *error))completion
{
	[self createPlaylistWithTitle:title videoIds:nil completion:completion];
}

- (void)createPlaylistWithTitle:(NSString *)title
                       videoIds:(NSArray *)videoIds
                     completion:(void (^)(NSString *playlistId, NSString *error))completion
{
	if (!title.length) {
		if (completion) completion(nil, @"Título vacío");
		return;
	}
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	body[@"title"] = title;
	body[@"privacyStatus"] = @"PRIVATE";
	if (videoIds.count > 0) {
		body[@"videoIds"] = videoIds;
	}
	[self postEndpoint:@"playlist/create" body:body urlParams:nil completion:^(NSDictionary *resp, NSString *err) {
		NSString *pid = [resp objectForKey:@"playlistId"];
		if (completion)
			completion(pid, err);
	}];
}

- (void)addVideoId:(NSString *)videoId
      toPlaylistId:(NSString *)playlistId
        completion:(void (^)(BOOL ok, NSString *error))completion
{
	if (!videoId.length) {
		if (completion) completion(NO, @"Parámetros inválidos");
		return;
	}
	[self addVideoIds:@[videoId] toPlaylistId:playlistId completion:completion];
}

- (void)addVideoIds:(NSArray *)videoIds
       toPlaylistId:(NSString *)playlistId
         completion:(void (^)(BOOL ok, NSString *error))completion
{
	if (!videoIds.count || !playlistId.length) {
		if (completion) completion(NO, @"Parámetros inválidos");
		return;
	}
	NSString *cleanPid = [playlistId hasPrefix:@"VL"] ? [playlistId substringFromIndex:2] : playlistId;
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	body[@"playlistId"] = cleanPid;
	NSMutableArray *actions = [NSMutableArray array];
	for (NSString *vid in videoIds) {
		if ([vid isKindOfClass:[NSString class]] && vid.length > 0) {
			[actions addObject:@{
				@"action" : @"ACTION_ADD_VIDEO",
				@"addedVideoId" : vid
			}];
		}
	}
	body[@"actions"] = actions;
	[self postEndpoint:@"browse/edit_playlist" body:body urlParams:nil completion:^(NSDictionary *resp, NSString *err) {
		NSString *status = [resp objectForKey:@"status"];
		BOOL ok = (resp != nil && !err) || [status isEqualToString:@"STATUS_SUCCEEDED"];
		if (completion)
			completion(ok, err);
	}];
}

- (void)nextForVideoId:(NSString *)videoId
            playlistId:(NSString *)playlistId
            completion:(void (^)(NSArray *items, NSString *title, NSString *error))completion
{
	[self fetchNextItemsForVideoId:videoId
	                    playlistId:playlistId
	                  continuation:nil
	                        params:nil
	                    accumItems:[NSMutableArray array]
	                       seenIds:[NSMutableSet set]
	                    accumTitle:nil
	                     remaining:5
	                    completion:completion];
}

- (void)fetchNextItemsForVideoId:(NSString *)videoId
                      playlistId:(NSString *)playlistId
                    continuation:(NSString *)continuation
                          params:(NSString *)params
                      accumItems:(NSMutableArray *)accumItems
                         seenIds:(NSMutableSet *)seenIds
                      accumTitle:(NSString *)accumTitle
                       remaining:(NSInteger)remaining
                      completion:(void (^)(NSArray *items, NSString *title, NSString *error))completion
{
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"context"] = [self contextDict];
	if (continuation.length > 0) {
		body[@"continuation"] = continuation;
	} else {
		if (videoId.length > 0) {
			body[@"videoId"] = videoId;
		}
		if (playlistId.length > 0) {
			body[@"playlistId"] = playlistId;
		} else if (videoId.length > 0) {
			// Radio mix queue seeded from this video (Metrolist behavior)
			body[@"playlistId"] = [@"RDAMVM" stringByAppendingString:videoId];
		}
		if (params.length > 0) {
			body[@"params"] = params;
		}
	}
	body[@"isAudioOnly"] = @YES;

	[self postEndpoint:@"next" body:body urlParams:nil completion:^(NSDictionary *resp, NSString *err) {
		if (err || !resp) {
			if (accumItems.count > 0) {
				if (completion) completion(accumItems, accumTitle, nil);
			} else {
				if (completion) completion(nil, nil, err ?: @"Error al obtener recomendaciones");
			}
			return;
		}

		// Detect real-time likeStatus from response for current video or queued items
		for (NSDictionary *lb in [MLInnerTube allObjectsForKey:@"likeButtonRenderer" inObject:resp maxDepth:15]) {
			NSString *targetVid = MLPath(lb, @"target.videoId") ?: MLPath(lb, @"target.likeTarget.videoId");
			if (!targetVid.length && videoId.length) targetVid = videoId;
			NSString *status = lb[@"likeStatus"];
			if (targetVid.length > 0 && [status isKindOfClass:[NSString class]]) {
				if ([status isEqualToString:@"LIKE"]) {
					[[MLLibraryManager sharedManager] markSongId:targetVid asLiked:YES];
				}
			}
		}

		NSString *queueTitle = accumTitle;
		if (!queueTitle) {
			@try {
				NSDictionary *qh = MLPath(resp, @"contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs.0.tabRenderer.content.musicQueueRenderer.header.musicQueueHeaderRenderer");
				if (qh) {
					queueTitle = [MLInnerTube textFromRuns:qh[@"subtitle"]] ?: [MLInnerTube textFromRuns:qh[@"title"]];
				}
			} @catch (id ex) {}
		}

		NSArray *renderers = [MLInnerTube allObjectsForKey:@"playlistPanelVideoRenderer" inObject:resp maxDepth:15];
		for (NSDictionary *r in renderers) {
			MLYTItem *it = [MLInnerTube itemFromRenderer:@{ @"playlistPanelVideoRenderer" : r }];
			if (it && it.videoId.length > 0) {
				if (![seenIds containsObject:it.videoId]) {
					[seenIds addObject:it.videoId];
					[accumItems addObject:it];
				}
			}
		}

		// Check if we should load the next page to reach ~50 songs
		if (accumItems.count < 50 && remaining > 1) {
			// 1. Look for automix preview playlist endpoint
			NSDictionary *automix = [MLInnerTube allObjectsForKey:@"automixPlaylistVideoRenderer" inObject:resp maxDepth:15].firstObject;
			NSDictionary *watchPlEp = MLPath(automix, @"navigationEndpoint.watchPlaylistEndpoint");
			NSString *automixPid = watchPlEp[@"playlistId"];
			NSString *automixParams = watchPlEp[@"params"];
			NSString *automixVid = watchPlEp[@"videoId"];

			// 2. Look for continuation token in response or playlistPanelContinuation
			NSString *nextCont = nil;
			for (NSDictionary *pc in [MLInnerTube allObjectsForKey:@"playlistPanelContinuation" inObject:resp maxDepth:15]) {
				for (NSDictionary *c in MLPath(pc, @"continuations") ?: @[]) {
					NSString *t = MLPath(c, @"nextContinuationData.continuation");
					if (t.length) { nextCont = t; break; }
				}
				if (nextCont) break;
			}
			if (!nextCont) {
				nextCont = [MLInnerTube continuationFromResponseOrShelf:resp];
			}

			if (automixPid.length > 0) {
				[self fetchNextItemsForVideoId:automixVid
				                    playlistId:automixPid
				                  continuation:nil
				                        params:automixParams
				                    accumItems:accumItems
				                       seenIds:seenIds
				                    accumTitle:queueTitle
				                     remaining:remaining - 1
				                    completion:completion];
				return;
			} else if (nextCont.length > 0) {
				[self fetchNextItemsForVideoId:nil
				                    playlistId:nil
				                  continuation:nextCont
				                        params:nil
				                    accumItems:accumItems
				                       seenIds:seenIds
				                    accumTitle:queueTitle
				                     remaining:remaining - 1
				                    completion:completion];
				return;
			}
		}

		if (completion)
			completion(accumItems, queueTitle, nil);
	}];
}


#pragma mark - Visitor data bootstrap (sw.js_data)

- (void)bootstrapVisitorData:(void (^)(BOOL ok))completion
{
	if (_visitorData.length > 0) {
		if (completion)
			completion(YES);
		return;
	}
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.youtube.com/sw.js_data"]
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:15.0];
		[req setValue:MLUserAgent forHTTPHeaderField:@"User-Agent"];
		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];
		NSString *vd = nil;
		if (data) {
			NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
			// format: first line is junk, then JSON array: [0][2][0][0][13] = visitorData
			NSString *jsonPart = nil;
			NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
			for (NSString *line in lines) {
				NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
					jsonPart = trimmed;
					break;
				}
			}
			id obj = jsonPart ? [NSJSONSerialization JSONObjectWithData:[jsonPart dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
			if ([obj isKindOfClass:[NSArray class]]) {
				NSArray *root = obj;
				if (root.count > 2 && [root[2] isKindOfClass:[NSArray class]]) {
					NSArray *lvl2 = root[2];
					if (lvl2.count > 0 && [lvl2[0] isKindOfClass:[NSArray class]]) {
						NSArray *lvl3 = lvl2[0];
						if (lvl3.count > 0 && [lvl3[0] isKindOfClass:[NSArray class]]) {
							NSArray *lvl4 = lvl3[0];
							if (lvl4.count > 13)
								vd = [NSString stringWithFormat:@"%@", lvl4[13]];
						}
					}
				}
			}
		}
		if ([vd isKindOfClass:[NSString class]] && vd.length > 10) {
			self.visitorData = vd;
			[self saveSession];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion)
				completion(vd.length > 10);
		});
	});
}

@end
