#import "MLPoTokenProvider.h"
#import "MLTLSTrustManager.h"
#import <UIKit/UIKit.h>

static NSString *const MLPotRequestKey = @"O43z0dpjhgX20SCx4KAo";
static NSString *const MLPotApiKey = @"AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw";
static NSString *const MLPotUserAgent = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                                        @"AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

typedef enum {
	MLPotStateIdle = 0,
	MLPotStatePageLoading,
	MLPotStateChallenge,
	MLPotStateSnapshot,
	MLPotStateGenerateIT,
	MLPotStateMinter,
	MLPotStateReady,
	MLPotStateFailed,
} MLPotState;

@interface MLPoTokenProvider () <UIWebViewDelegate>
{
	UIWebView *_web;
	MLPotState _state;
	NSString *_challengeProgram;
	NSString *_challengeGlobalName;
	NSString *_snapshotResponse;
	NSString *_integrityTokenB64;
	NSTimeInterval _integrityExpiry;
	NSString *_pendingInitError;

	// pending mint requests: dicts {identifier, completion}
	NSMutableArray *_mintQueue;
	// active mint: dict {identifier, completion, timer}
	NSMutableDictionary *_activeMint;

	NSTimer *_initWatchdog;
	NSTimeInterval _lastFailTime;
}

@end

@implementation MLPoTokenProvider

+ (instancetype)sharedProvider
{
	static MLPoTokenProvider *p = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ p = [[MLPoTokenProvider alloc] init]; });
	return p;
}

- (id)init
{
	self = [super init];
	if (self) {
		_state = MLPotStateIdle;
		_mintQueue = [NSMutableArray array];
	}
	return self;
}

- (BOOL)minterReady
{
	return _state == MLPotStateReady && _integrityExpiry > [[NSDate date] timeIntervalSince1970] && _web != nil;
}

#pragma mark - Public

- (void)tokenForIdentifier:(NSString *)identifier
               completion:(void (^)(NSString *, NSString *))completion
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.minterReady) {
			[self enqueueMint:identifier completion:completion];
			[self pumpMintQueue];
			return;
		}
		if (self->_state == MLPotStateFailed && ([[NSDate date] timeIntervalSince1970] - self->_lastFailTime < 60.0)) {
			if (completion)
				completion(nil, @"PoToken no disponible temporalmente");
			return;
		}
		if (self->_state == MLPotStateFailed || self->_state == MLPotStateIdle) {
			[self->_mintQueue removeAllObjects];
		}
		[self enqueueMint:identifier completion:completion];
		[self ensureInitializing];
	});
}

- (void)reset
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[self teardown];
		self->_state = MLPotStateIdle;
	});
}

#pragma mark - Queue

- (void)enqueueMint:(NSString *)identifier completion:(void (^)(NSString *, NSString *))completion
{
	if (!identifier)
		return;
	NSMutableDictionary *req = [NSMutableDictionary dictionary];
	req[@"identifier"] = identifier;
	if (completion)
		req[@"completion"] = [completion copy];
	if (_activeMint) {
		[_mintQueue addObject:req];
	} else {
		_activeMint = [req mutableCopy];
	}
}

- (void)pumpMintQueue
{
	if (!_activeMint || _state != MLPotStateReady)
		return;
	NSString *identifier = _activeMint[@"identifier"];
	NSString *call = [NSString stringWithFormat:@"__mlMint(%@)", MLEscapeJSLiteral(identifier)];
	NSString *sync = [_web stringByEvaluatingJavaScriptFromString:call];
	if ([sync hasPrefix:@"err"]) {
		[self failActiveMint:[NSString stringWithFormat:@"mint rejected: %@", sync]];
		return;
	}
	[self addActiveMintWatchdog];
}

- (void)addActiveMintWatchdog
{
	__weak MLPoTokenProvider *wself = self;
	_activeMint[@"timer"] = [NSTimer scheduledTimerWithTimeInterval:8.0 target:wself
	                                                     selector:@selector(mintWatchdogFire:)
	                                                     userInfo:nil repeats:NO];
}

- (void)mintWatchdogFire:(NSTimer *)t
{
	[self failActiveMint:@"timeout esperando el token"];
}

- (void)failActiveMint:(NSString *)error
{
	void (^completion)(NSString *, NSString *) = _activeMint[@"completion"];
	NSTimer *timer = _activeMint[@"timer"];
	[timer invalidate];
	_activeMint = nil;
	if (completion)
		completion(nil, error);
	[self pumpMintQueue];
}

- (void)deliverActiveMint:(NSString *)token
{
	NSTimer *timer = _activeMint[@"timer"];
	[timer invalidate];
	void (^completion)(NSString *, NSString *) = _activeMint[@"completion"];
	_activeMint = nil;
	if (completion)
		completion(token, nil);
	[self pumpMintQueue];
}

#pragma mark - Initialization chain

- (void)ensureInitializing
{
	if (_state != MLPotStateIdle && _state != MLPotStateFailed)
		return;
	_state = MLPotStatePageLoading;
	[self startInitWatchdog];

	if (!_web) {
		_web = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 4, 4)];
		_web.delegate = self;
		_web.hidden = YES;
		UIWindow *win = [UIApplication sharedApplication].keyWindow;
		if (!win && [UIApplication sharedApplication].windows.count > 0)
			win = [UIApplication sharedApplication].windows[0];
		[win addSubview:_web];
	}
	NSString *path = [[NSBundle mainBundle] pathForResource:@"po_client" ofType:@"html"];
	NSString *html = [NSString stringWithContentsOfFile:path usedEncoding:nil error:nil];
	if (!html) {
		[self failInit:@"no se encontró po_client.html"];
		return;
	}
	[_web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://www.youtube.com/"]];
}

- (void)startInitWatchdog
{
	[_initWatchdog invalidate];
	__weak MLPoTokenProvider *wself = self;
	_initWatchdog = [NSTimer scheduledTimerWithTimeInterval:10.0 target:wself
	                                              selector:@selector(initWatchdogFire:)
	                                              userInfo:nil repeats:NO];
}

- (void)initWatchdogFire:(NSTimer *)t
{
	NSString *stageDesc = [NSString stringWithFormat:@"timeout en fase %d", _state];
	[self failInit:stageDesc];
}

- (void)failInit:(NSString *)error
{
	_lastFailTime = [[NSDate date] timeIntervalSince1970];
	[_initWatchdog invalidate];
	[self teardown];
	_state = MLPotStateFailed;
	// fail all queued mints
	NSArray *queue = [_mintQueue copy];
	NSDictionary *active = _activeMint;
	_mintQueue = [NSMutableArray array];
	_activeMint = nil;
	void (^cb)(NSString *, NSString *) = active[@"completion"];
	if (cb)
		cb(nil, [NSString stringWithFormat:@"PoToken: %@ (%@)", error, @"init"]);
	for (NSDictionary *req in queue) {
		void (^c)(NSString *, NSString *) = req[@"completion"];
		if (c)
			c(nil, [NSString stringWithFormat:@"PoToken: %@", error]);
	}
}

- (void)teardown
{
	if (_web) {
		[_web stopLoading];
		[_web loadHTMLString:@"" baseURL:nil];
		[_web removeFromSuperview];
		_web.delegate = nil;
		_web = nil;
	}
}

- (void)advanceState:(MLPotState)newState
{
	_state = newState;
}

#pragma mark - BotGuard service HTTP (native)

static NSData *MLPotPost(NSString *url, NSString *payload)
{
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
	                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
	                                               timeoutInterval:20.0];
	req.HTTPMethod = @"POST";
	req.HTTPBody = [payload dataUsingEncoding:NSUTF8StringEncoding];
	[req setValue:MLPotUserAgent forHTTPHeaderField:@"User-Agent"];
	[req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	[req setValue:@"application/json+protobuf" forHTTPHeaderField:@"Content-Type"];
	[req setValue:MLPotApiKey forHTTPHeaderField:@"x-goog-api-key"];
	[req setValue:@"grpc-web-javascript/0.1" forHTTPHeaderField:@"x-user-agent"];
	NSHTTPURLResponse *http = nil;
	NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&http error:nil];
	if (!data || ![http isKindOfClass:[NSHTTPURLResponse class]] || http.statusCode != 200)
		return nil;
	return data;
}

/* Minimal base64 decoder (iOS 6 NSData has no base64 API). */
static NSData *MLBase64Decode(NSString *b64)
{
	static signed char table[256];
	static BOOL tableReady = NO;
	if (!tableReady) {
		memset(table, -1, sizeof(table));
		const char *std = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 64; i++)
			table[(unsigned char)std[i]] = (signed char)i;
		tableReady = YES;
	}
	// strip padding
	NSMutableString *clean = [NSMutableString stringWithString:b64];
	while ([clean hasSuffix:@"="])
		[clean deleteCharactersInRange:NSMakeRange(clean.length - 1, 1)];

	NSMutableData *out = [NSMutableData dataWithCapacity:clean.length * 3 / 4 + 4];
	unsigned char buf[4];
	int n = 0;
	for (NSUInteger i = 0; i < clean.length; i++) {
		unichar c = [clean characterAtIndex:i];
		signed char v = (c < 256) ? table[c] : -1;
		if (v < 0)
			continue;
		buf[n++] = (unsigned char)v;
		if (n == 4) {
			unsigned char b0 = (buf[0] << 2) | (buf[1] >> 4);
			unsigned char b1 = ((buf[1] & 0x0F) << 4) | (buf[2] >> 2);
			unsigned char b2 = ((buf[2] & 0x03) << 6) | buf[3];
			[out appendBytes:&b0 length:1];
			[out appendBytes:&b1 length:1];
			[out appendBytes:&b2 length:1];
			n = 0;
		}
	}
	if (n == 2) {
		unsigned char b0 = (buf[0] << 2) | (buf[1] >> 4);
		[out appendBytes:&b0 length:1];
	} else if (n == 3) {
		unsigned char b0 = (buf[0] << 2) | (buf[1] >> 4);
		unsigned char b1 = ((buf[1] & 0x0F) << 4) | (buf[2] >> 2);
		[out appendBytes:&b0 length:1];
		[out appendBytes:&b1 length:1];
	}
	return out;
}

- (void)fetchChallenge
{
	_state = MLPotStateChallenge;
	NSString *payload = [NSString stringWithFormat:@"[\"%@\"]", MLPotRequestKey];
	__weak MLPoTokenProvider *wself = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *error = nil;
		NSString *interp = nil, *program = nil, *globalName = nil;
		NSData *data = MLPotPost(@"https://www.youtube.com/api/jnn/v1/Create", payload);
		id arr = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		if (![arr isKindOfClass:[NSArray class]]) {
			error = @"Create falló";
		} else {
			NSArray *challenge = arr;
			NSString *second = challenge.count > 1 && [challenge[1] isKindOfClass:[NSString class]] ? challenge[1] : nil;
			if (second) {
				// descramble: base64url decode, +97 per byte, UTF-8 string, JSON
				NSData *descBytes = MLBase64Decode(second);
				NSMutableData *shifted = [NSMutableData dataWithLength:descBytes.length];
				const unsigned char *src = descBytes.bytes;
				unsigned char *dst = (unsigned char *)shifted.mutableBytes;
				for (NSUInteger i = 0; i < descBytes.length; i++)
					dst[i] = (unsigned char)((src[i] + 97) & 0xFF);
				NSString *json = [[NSString alloc] initWithData:shifted encoding:NSUTF8StringEncoding];
				id inner = json ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
				                                                  options:0 error:nil] : nil;
				if ([inner isKindOfClass:[NSArray class]])
					challenge = inner;
			} else if (challenge.count > 0 && [challenge[0] isKindOfClass:[NSArray class]]) {
				challenge = challenge[0];
			}
			NSString *(^firstString)(id) = ^NSString *(id x) {
				if (![x isKindOfClass:[NSArray class]])
					return nil;
				for (id v in x) {
					if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 40)
						return v;
				}
				return nil;
			};
			interp = challenge.count > 1 ? firstString(challenge[1]) : nil;
			program = challenge.count > 4 && [challenge[4] isKindOfClass:[NSString class]] ? challenge[4] : nil;
			globalName = challenge.count > 5 && [challenge[5] isKindOfClass:[NSString class]] ? challenge[5] : nil;
			if (!interp || !program || !globalName)
				error = @"challenge incompleto";
		}
		NSString *interpC = interp, *programC = program, *globalC = globalName, *errC = error;
		dispatch_async(dispatch_get_main_queue(), ^{
			MLPoTokenProvider *s = wself;
			if (!s)
				return;
			if (s->_state != MLPotStateChallenge)
				return;
			if (errC) {
				[s failInit:errC];
				return;
			}
			NSString *eval = [NSString stringWithFormat:@"__mlEvalInterpreter(%@)", MLEscapeJSLiteral(interpC)];
			NSString *res = [s->_web stringByEvaluatingJavaScriptFromString:eval];
			if (![res isEqualToString:@"ok"]) {
				[s failInit:[NSString stringWithFormat:@"intérprete: %@", res]];
				return;
			}
			NSString *run = [NSString stringWithFormat:@"__mlRunBotGuard(%@, %@)",
			                MLEscapeJSLiteral(globalC), MLEscapeJSLiteral(programC)];
			NSString *started = [s->_web stringByEvaluatingJavaScriptFromString:run];
			if ([started hasPrefix:@"err"]) {
				[s failInit:[NSString stringWithFormat:@"runBotGuard: %@", started]];
				return;
			}
			s->_challengeProgram = programC;
			s->_challengeGlobalName = globalC;
			[s advanceState:MLPotStateSnapshot];
		});
	});
}

- (void)handleSnapshot:(NSString *)response
{
	_snapshotResponse = [response copy];
	_state = MLPotStateGenerateIT;
	NSString *payload = [NSString stringWithFormat:@"[\"%@\",\"%@\"]", MLPotRequestKey, response];
	__weak MLPoTokenProvider *wself = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *error = nil;
		NSString *token = nil;
		NSTimeInterval expiry = 0;
		NSData *data = MLPotPost(@"https://www.youtube.com/api/jnn/v1/GenerateIT", payload);
		id arr = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		if (![arr isKindOfClass:[NSArray class]]) {
			error = @"GenerateIT falló";
		} else {
			NSArray *resp = (NSArray *)arr;
			for (id v in resp) {
				if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 20) {
					token = v;
					break;
				}
			}
			NSNumber *exp = (resp.count > 1 && [resp[1] isKindOfClass:[NSNumber class]]) ? resp[1] : nil;
			expiry = exp ? [exp doubleValue] : 43200.0;
			if (!token)
				error = @"GenerateIT sin token";
		}
		NSString *tokenC = token, *errC = error;
		NSTimeInterval expiryC = expiry;
		dispatch_async(dispatch_get_main_queue(), ^{
			MLPoTokenProvider *s = wself;
			if (!s)
				return;
			if (s->_state != MLPotStateGenerateIT)
				return;
			if (errC) {
				[s failInit:errC];
				return;
			}
			s->_integrityTokenB64 = tokenC;
			s->_integrityExpiry = [[NSDate date] timeIntervalSince1970] + expiryC - 600.0;
			NSString *call = [NSString stringWithFormat:@"__mlCreateMinter(%@)", MLEscapeJSLiteral(tokenC)];
			NSString *res = [s->_web stringByEvaluatingJavaScriptFromString:call];
			if ([res hasPrefix:@"err"]) {
				[s failInit:[NSString stringWithFormat:@"minter: %@", res]];
				return;
			}
			[s advanceState:MLPotStateMinter];
		});
	});
}

- (void)handleMinterReady
{
	[_initWatchdog invalidate];
	_state = MLPotStateReady;
	[self pumpMintQueue];
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
	NSString *abs = request.URL.absoluteString;
	if ([abs hasPrefix:@"mlbridge://"]) {
		NSString *encoded = [abs substringFromIndex:[@"mlbridge://" length]];
		NSString *decoded = [encoded stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		id obj = decoded ? [NSJSONSerialization JSONObjectWithData:[decoded dataUsingEncoding:NSUTF8StringEncoding]
		                                                  options:0 error:nil] : nil;
		if ([obj isKindOfClass:[NSDictionary class]])
			[self handleBridgeEvent:obj];
		return NO;
	}
	return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	// po_client.html fires pageReady through the bridge; nothing else needed here.
}

- (void)handleBridgeEvent:(NSDictionary *)event
{
	NSString *type = event[@"event"];
	if ([type isEqualToString:@"pageReady"]) {
		if (_state == MLPotStatePageLoading)
			[self fetchChallenge];
	} else if ([type isEqualToString:@"snapshot"]) {
		if (_state == MLPotStateSnapshot)
			[self handleSnapshot:event[@"response"]];
	} else if ([type isEqualToString:@"minterReady"]) {
		if (_state == MLPotStateMinter)
			[self handleMinterReady];
	} else if ([type isEqualToString:@"token"]) {
		NSString *tok = event[@"token"];
		if (tok && _activeMint)
			[self deliverActiveMint:tok];
	} else if ([type isEqualToString:@"error"]) {
		NSString *msg = [NSString stringWithFormat:@"%@: %@", event[@"stage"], event[@"message"]];
		if (_state == MLPotStateReady && _activeMint) {
			[self failActiveMint:msg];
		} else {
			[self failInit:msg];
		}
	}
}

#pragma mark - JS escaping

static NSString *MLEscapeJSLiteral(NSString *s)
{
	NSMutableString *out = [NSMutableString stringWithString:@"\""];
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		switch (c) {
			case '"': [out appendString:@"\\\""]; break;
			case '\\': [out appendString:@"\\\\"]; break;
			case '\n': [out appendString:@"\\n"]; break;
			case '\r': [out appendString:@"\\r"]; break;
			case '\t': [out appendString:@"\\t"]; break;
			default:
				if (c < 0x20 || c == 0x2028 || c == 0x2029) {
					[out appendFormat:@"\\u%04x", c];
				} else {
					[out appendFormat:@"%C", c];
				}
				break;
		}
	}
	[out appendString:@"\""];
	return out;
}

@end
