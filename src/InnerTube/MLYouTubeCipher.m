#import "MLYouTubeCipher.h"
#import "MLTLSTrustManager.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <stdlib.h>

#pragma mark - JavaScriptCore C API (runtime-loaded, private framework on iOS 6)

typedef struct OpaqueJSContext *JSGlobalContextRef;
typedef struct OpaqueJSString *JSStringRef;
typedef const struct OpaqueJSValue *JSValueRef;
typedef struct OpaqueJSValue *JSObjectRef;

typedef JSGlobalContextRef (*fn_JSGlobalContextCreate)(void *globalObjectClass);
typedef void (*fn_JSGlobalContextRelease)(JSGlobalContextRef ctx);
typedef JSValueRef (*fn_JSEvaluateScript)(JSGlobalContextRef ctx, JSStringRef script, JSObjectRef thisObject,
                                          JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception);
typedef JSStringRef (*fn_JSStringCreateWithUTF8CString)(const char *bytes);
typedef void (*fn_JSStringRelease)(JSStringRef string);
typedef unsigned long (*fn_JSStringGetMaximumUTF8CStringSize)(JSStringRef string);
typedef int (*fn_JSStringGetUTF8CString)(JSStringRef string, char *buffer, unsigned long bufferSize);
typedef JSStringRef (*fn_JSValueToStringCopy)(JSGlobalContextRef ctx, JSValueRef value, JSValueRef *exception);

static fn_JSGlobalContextCreate ml_JSGlobalContextCreate;
static fn_JSGlobalContextRelease ml_JSGlobalContextRelease;
static fn_JSEvaluateScript ml_JSEvaluateScript;
static fn_JSStringCreateWithUTF8CString ml_JSStringCreateWithUTF8CString;
static fn_JSStringRelease ml_JSStringRelease;
static fn_JSStringGetMaximumUTF8CStringSize ml_JSStringGetMaximumUTF8CStringSize;
static fn_JSStringGetUTF8CString ml_JSStringGetUTF8CString;
static fn_JSValueToStringCopy ml_JSValueToStringCopy;

static BOOL MLLoadJavaScriptCore(void)
{
	static BOOL loaded = NO;
	static BOOL attempted = NO;
	if (attempted)
		return loaded;
	attempted = YES;

	void *lib = dlopen("/System/Library/PrivateFrameworks/JavaScriptCore.framework/JavaScriptCore", RTLD_LAZY);
	if (!lib)
		lib = dlopen("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore", RTLD_LAZY);
	if (!lib)
		return NO;

	ml_JSGlobalContextCreate = (fn_JSGlobalContextCreate)dlsym(lib, "JSGlobalContextCreate");
	ml_JSGlobalContextRelease = (fn_JSGlobalContextRelease)dlsym(lib, "JSGlobalContextRelease");
	ml_JSEvaluateScript = (fn_JSEvaluateScript)dlsym(lib, "JSEvaluateScript");
	ml_JSStringCreateWithUTF8CString = (fn_JSStringCreateWithUTF8CString)dlsym(lib, "JSStringCreateWithUTF8CString");
	ml_JSStringRelease = (fn_JSStringRelease)dlsym(lib, "JSStringRelease");
	ml_JSStringGetMaximumUTF8CStringSize = (fn_JSStringGetMaximumUTF8CStringSize)dlsym(lib, "JSStringGetMaximumUTF8CStringSize");
	ml_JSStringGetUTF8CString = (fn_JSStringGetUTF8CString)dlsym(lib, "JSStringGetUTF8CString");
	ml_JSValueToStringCopy = (fn_JSValueToStringCopy)dlsym(lib, "JSValueToStringCopy");

	loaded = ml_JSGlobalContextCreate && ml_JSGlobalContextRelease && ml_JSEvaluateScript &&
	         ml_JSStringCreateWithUTF8CString && ml_JSStringRelease &&
	         ml_JSStringGetMaximumUTF8CStringSize && ml_JSStringGetUTF8CString && ml_JSValueToStringCopy;
	return loaded;
}

static NSString *MLEvalToString(JSGlobalContextRef ctx, NSString *source)
{
	JSStringRef script = ml_JSStringCreateWithUTF8CString([source UTF8String]);
	JSValueRef result = ml_JSEvaluateScript(ctx, script, NULL, NULL, 1, NULL);
	ml_JSStringRelease(script);
	if (!result)
		return nil;
	NSString *out = nil;
	JSStringRef s = ml_JSValueToStringCopy(ctx, result, NULL);
	if (s) {
		unsigned long max = ml_JSStringGetMaximumUTF8CStringSize(s);
		char *buf = (char *)malloc(max);
		if (buf) {
			if (ml_JSStringGetUTF8CString(s, buf, max))
				out = [NSString stringWithUTF8String:buf];
			free(buf);
		}
		ml_JSStringRelease(s);
	}
	if (out && ([out isEqualToString:@"null"] || [out isEqualToString:@"undefined"] || out.length == 0))
		out = nil;
	return out;
}

#pragma mark -

static NSString *const MLHashDefaultsKey = @"ml_cipher_hash";
static NSString *const MLStsDefaultsKey = @"ml_cipher_sts";
static NSString *const MLSigExprDefaultsKey = @"ml_cipher_sigexpr";
static NSString *const MLFetchedAtDefaultsKey = @"ml_cipher_fetched_at";

static NSString *MLPlayerJSPath(NSString *hash)
{
	NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
	NSString *dir = [docs stringByAppendingPathComponent:@"playerjs"];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return [dir stringByAppendingPathComponent:[hash stringByAppendingString:@".js"]];
}

@implementation MLYouTubeCipher
{
	JSGlobalContextRef _ctx;
	NSString *_sigExpr;
	NSInteger _sts;
	NSString *_hash;
	NSString *_baseJsPath;
	BOOL _configured;
	dispatch_queue_t _jsQueue;
	BOOL _loading;
	NSMutableArray *_pendingEnsure;
}

+ (instancetype)sharedSolver
{
	static MLYouTubeCipher *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[MLYouTubeCipher alloc] init]; });
	return s;
}

- (id)init
{
	self = [super init];
	if (self) {
		_jsQueue = dispatch_queue_create("ml.cipher.js", DISPATCH_QUEUE_SERIAL);
		_pendingEnsure = [NSMutableArray array];
		_hash = [[NSUserDefaults standardUserDefaults] stringForKey:MLHashDefaultsKey];
		_sts = (NSInteger)[[NSUserDefaults standardUserDefaults] integerForKey:MLStsDefaultsKey];
		_sigExpr = [[NSUserDefaults standardUserDefaults] stringForKey:MLSigExprDefaultsKey];
		NSString *path = _hash ? MLPlayerJSPath(_hash) : nil;
		if (_hash && _sigExpr && path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
			_baseJsPath = path;
			_configured = YES;
		}
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                         selector:@selector(memoryWarn)
		                                             name:UIApplicationDidReceiveMemoryWarningNotification
		                                           object:nil];
	}
	return self;
}

- (void)memoryWarn
{
	dispatch_async(_jsQueue, ^{
		if (self->_ctx) {
			ml_JSGlobalContextRelease(self->_ctx);
			self->_ctx = NULL;
		}
	});
}

- (void)releaseJSContext
{
	[self memoryWarn];
}

#pragma mark - Setup

- (void)ensureConfigured:(void (^)(NSInteger, NSString *, NSString *))completion
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self->_configured) {
			if (completion)
				completion(self->_sts, self->_sigExpr, nil);
			return;
		}
		void (^done)(NSInteger, NSString *, NSString *) = [^(NSInteger sts, NSString *sig, NSString *err) {
			if (completion)
				completion(sts, sig, err);
		} copy];
		if (self->_loading) {
			[self->_pendingEnsure addObject:done];
			return;
		}
		self->_loading = YES;
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			[self fetchConfig:^(NSInteger sts, NSString *sigExpr, NSString *error) {
				dispatch_async(dispatch_get_main_queue(), ^{
					self->_loading = NO;
					NSArray *pending = self->_pendingEnsure;
					[self->_pendingEnsure removeAllObjects];
					done(sts, sigExpr, error);
					for (void (^p)(NSInteger, NSString *, NSString *) in pending)
						if (p) p(sts, sigExpr, error);
				});
			}];
		});
	});
}

static NSData *MLHTTPGet(NSString *urlString)
{
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url)
		return nil;
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
	                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
	                                               timeoutInterval:20.0];
	[req setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
	    forHTTPHeaderField:@"User-Agent"];
	NSError *err = nil;
	NSHTTPURLResponse *http = nil;
	NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&http error:&err];
	if (!data || ![http isKindOfClass:[NSHTTPURLResponse class]] || http.statusCode != 200)
		return nil;
	return data;
}

- (void)fetchConfig:(void (^)(NSInteger, NSString *, NSString *))completion
{
	NSString *hash = nil;
	NSString *sigExpr = nil;
	NSString *error = nil;
	NSInteger sts = 0;

	NSData *apiData = MLHTTPGet(@"https://www.youtube.com/iframe_api");
	NSString *api = apiData ? [[NSString alloc] initWithData:apiData encoding:NSUTF8StringEncoding] : nil;
	NSString *cleanApi = [api stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
	NSRange r = [cleanApi rangeOfString:@"/s/player/" options:NSLiteralSearch];
	if (cleanApi && r.location != NSNotFound) {
		NSString *after = [cleanApi substringFromIndex:r.location + 10];
		NSString *h = after.length >= 8 ? [after substringToIndex:8] : nil;
		NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
		BOOL ok = h.length == 8;
		for (NSUInteger i = 0; i < h.length && ok; i++)
			if (![hex characterIsMember:[h characterAtIndex:i]])
				ok = NO;
		if (ok)
			hash = h;
	}
	if (!hash)
		error = @"No se pudo obtener el player hash";

	// zemer-cipher config
	NSData *cfgData = MLHTTPGet(@"https://raw.githubusercontent.com/ZemerTeam/zemer-cipher/master/library/src/main/assets/player_configs.json");
	NSDictionary *cfg = nil;
	if (cfgData) {
		NSError *jerr = nil;
		id obj = [NSJSONSerialization JSONObjectWithData:cfgData options:0 error:&jerr];
		if ([obj isKindOfClass:[NSDictionary class]])
			cfg = obj;
	}
	if (hash && cfg) {
		NSDictionary *players = [cfg objectForKey:@"players"];
		NSDictionary *entry = [players isKindOfClass:[NSDictionary class]] ? [players objectForKey:hash] : nil;
		if (![entry isKindOfClass:[NSDictionary class]]) {
			// hash may be an alias of another entry
			for (NSString *k in [players allKeys]) {
				NSDictionary *e = [players objectForKey:k];
				if (![e isKindOfClass:[NSDictionary class]])
					continue;
				NSArray *aliases = [e objectForKey:@"aliases"];
				if ([aliases isKindOfClass:[NSArray class]] && [aliases containsObject:hash]) {
					entry = e;
					break;
				}
			}
		}
		if ([entry isKindOfClass:[NSDictionary class]]) {
			NSString *sig = [entry objectForKey:@"sig"];
			if ([sig isKindOfClass:[NSString class]])
				sigExpr = sig;
			NSNumber *stsNum = [entry objectForKey:@"sts"];
			if ([stsNum isKindOfClass:[NSNumber class]])
				sts = [stsNum integerValue];
			if (!sigExpr && !error)
				error = @"Config sin expresión de firma";
		} else if (!error) {
			error = @"Player hash no está en el config de cipher (actualizará solo)";
		}
	} else if (!error) {
		error = @"No se pudo descargar el config de cipher";
	}

	NSString *baseJsPath = nil;
	if (hash) {
		NSString *path = MLPlayerJSPath(hash);
		if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
			NSString *jsUrl = [NSString stringWithFormat:@"https://www.youtube.com/s/player/%@/player_ias.vflset/en_GB/base.js", hash];
			NSData *js = MLHTTPGet(jsUrl);
			if (js && js.length > 100000) {
				[js writeToFile:path atomically:YES];
			} else if (!error) {
				error = @"No se pudo descargar base.js";
			}
		}
		if ([[NSFileManager defaultManager] fileExistsAtPath:path])
			baseJsPath = path;
	}

	dispatch_async(dispatch_get_main_queue(), ^{
		BOOL ok = hash && sigExpr && baseJsPath;
		self->_configured = ok;
		self->_hash = hash;
		self->_sts = sts;
		self->_sigExpr = sigExpr;
		self->_baseJsPath = baseJsPath;
		if (ok) {
			[[NSUserDefaults standardUserDefaults] setObject:hash forKey:MLHashDefaultsKey];
			[[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)sts forKey:MLStsDefaultsKey];
			[[NSUserDefaults standardUserDefaults] setObject:sigExpr forKey:MLSigExprDefaultsKey];
			[[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:MLFetchedAtDefaultsKey];
			[[NSUserDefaults standardUserDefaults] synchronize];
		}
		if (completion)
			completion(sts, sigExpr, ok ? nil : (error ?: @"Configuración de cipher incompleta"));
	});
}

#pragma mark - JS

- (BOOL)ensureContext:(NSString **)errorOut
{
	if (_ctx)
		return YES;
	if (!MLLoadJavaScriptCore()) {
		if (errorOut)
			*errorOut = @"JavaScriptCore no disponible";
		return NO;
	}

	NSString *js = [NSString stringWithContentsOfFile:_baseJsPath usedEncoding:nil error:nil];
	if (!js) {
		if (errorOut)
			*errorOut = @"No se pudo leer base.js";
		return NO;
	}

	NSRange tail = [js rangeOfString:@"})(_yt_player);" options:NSBackwardsSearch];
	if (tail.location == NSNotFound)
		tail = [js rangeOfString:@")(_yt_player);" options:NSBackwardsSearch];
	if (tail.location == NSNotFound) {
		if (errorOut)
			*errorOut = @"base.js con formato desconocido";
		return NO;
	}

	NSString *shims = @"var window=this;var self=this;"
	                  @"var document={createElement:function(){return {};}};"
	                  @"var navigator={userAgent:\"Mozilla/5.0\",cookieEnabled:true};"
	                  @"var location={href:\"https://www.youtube.com\",hostname:\"www.youtube.com\",protocol:\"https:\"};"
	                  @"var XMLHttpRequest=function(){};XMLHttpRequest.prototype={};";

	NSString *expr = [_sigExpr stringByReplacingOccurrencesOfString:@"INPUT" withString:@"x"];
	NSString *hook = [NSString stringWithFormat:
	    @";_yt_player.__mlSolve=function(x){try{return (%@);}catch(e){return null;}};",
	    expr];
	NSMutableString *script = [NSMutableString stringWithFormat:@"%@%@", shims, js];
	NSUInteger insertPos = shims.length + tail.location;
	[script insertString:hook atIndex:insertPos];

	__block BOOL ok = NO;
	__block NSString *err = nil;
	dispatch_sync(_jsQueue, ^{
		if (self->_ctx) {
			ok = YES;
			return;
		}
		JSGlobalContextRef ctx = ml_JSGlobalContextCreate(NULL);
		if (!ctx) {
			err = @"JSGlobalContextCreate falló";
			return;
		}
		NSString *probe = [script copy];
		JSStringRef s = ml_JSStringCreateWithUTF8CString([probe UTF8String]);
		JSValueRef ex = NULL;
		JSValueRef res = ml_JSEvaluateScript(ctx, s, NULL, NULL, 1, &ex);
		ml_JSStringRelease(s);
		if (!res) {
			if (ex) {
				JSStringRef exStr = ml_JSValueToStringCopy(ctx, ex, NULL);
				if (exStr) {
					char buf[256];
					ml_JSStringGetUTF8CString(exStr, buf, sizeof(buf));
					NSLog(@"[MLYouTubeCipher] JS error: %s", buf);
					ml_JSStringRelease(exStr);
				}
			}
			ml_JSGlobalContextRelease(ctx);
			err = @"Error evaluando base.js";
			return;
		}
		self->_ctx = ctx;
		ok = YES;
	});
	if (errorOut && err)
		*errorOut = err;
	return ok;
}

- (NSString *)solveSignature:(NSString *)signature error:(NSString **)errorOut
{
	NSString *err = nil;
	if (![self ensureContext:&err]) {
		if (errorOut)
			*errorOut = err;
		return nil;
	}
	__block NSString *out = nil;
	dispatch_sync(_jsQueue, ^{
		NSString *call = [NSString stringWithFormat:@"_yt_player.__mlSolve(%@)",
		                  MLEScapeJS(signature)];
		out = MLEvalToString(self->_ctx, call);
	});
	if (!out && errorOut)
		*errorOut = @"El descifrado devolvió vacío";
	return out;
}

static NSString *MLEScapeJS(NSString *s)
{
	// signatures are alnum+dash, but escape anyway
	NSMutableString *q = [NSMutableString stringWithString:@"\""];
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
		    c == '-' || c == '_' || c == '.' || c == '~' || c == '+') {
			[q appendFormat:@"%C", c];
		} else {
			[q appendFormat:@"\\u%04x", c];
		}
	}
	[q appendString:@"\""];
	return q;
}

@end
