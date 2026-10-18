#import "MLDeviceFlowManager.h"
#import "MLInnerTube.h"
#import "MLLibraryManager.h"
#import "MLTLSTrustManager.h"

static NSString *const TBGoogleDefaultClientID = @"861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com";
static NSString *const TBGoogleDefaultClientSecret = @"SboVhoG9s0rNafixCSGGKXAT";
static NSString *const TBGoogleScope = @"http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content";
static NSString *const TBGoogleDeviceCodeURL = @"https://www.youtube.com/o/oauth2/device/code";
static NSString *const TBGoogleTokenURL = @"https://www.youtube.com/o/oauth2/token";
static NSString *const TBTvUserAgent = @"Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0)";
static NSString *const TBTvDeviceModel = @"ytlr:samsung:smarttv";

@implementation MLDeviceFlowManager
{
	BOOL _cancelled;
	NSString *_deviceCode;
	NSString *_userCode;
	NSString *_verificationURL;
}

+ (instancetype)sharedManager
{
	static MLDeviceFlowManager *mgr = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		mgr = [[MLDeviceFlowManager alloc] init];
	});
	return mgr;
}

- (NSString *)userCode { return _userCode; }
- (NSString *)verificationURL { return _verificationURL; }

- (void)cancel
{
	_cancelled = YES;
	_isPolling = NO;
}

- (void)startDeviceFlowWithProgress:(void (^)(NSString *userCode, NSString *url))progress
                         completion:(void (^)(BOOL success, NSString *error))completion
{
	[self cancel];
	_cancelled = NO;
	_isPolling = YES;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
		NSString *deviceId = uuid ? [(__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) lowercaseString] : @"metrolegacy-ios";
		if (uuid) CFRelease(uuid);

		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:TBGoogleDeviceCodeURL]
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:15.0];
		req.HTTPMethod = @"POST";
		[req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[req setValue:TBTvUserAgent forHTTPHeaderField:@"User-Agent"];

		NSString *postStr = [NSString stringWithFormat:@"client_id=%@&scope=%@&device_id=%@&device_model=%@",
		                     TBGoogleDefaultClientID,
		                     [self urlEncode:TBGoogleScope],
		                     deviceId,
		                     TBTvDeviceModel];
		req.HTTPBody = [postStr dataUsingEncoding:NSUTF8StringEncoding];

		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

		if (err || resp.statusCode != 200 || !data.length) {
			self->_isPolling = NO;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(NO, err ? err.localizedDescription : @"Error solicitando código de dispositivo.");
			});
			return;
		}

		NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if (![json isKindOfClass:[NSDictionary class]]) {
			self->_isPolling = NO;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(NO, @"Respuesta no válida de Google.");
			});
			return;
		}

		NSString *devCode = json[@"device_code"];
		NSString *uCode = json[@"user_code"];
		NSString *vUrl = json[@"verification_url"] ?: @"https://www.google.com/device";
		NSTimeInterval interval = [json[@"interval"] doubleValue] > 0 ? [json[@"interval"] doubleValue] : 5.0;
		NSTimeInterval expires = [json[@"expires_in"] doubleValue] > 0 ? [json[@"expires_in"] doubleValue] : 1800.0;

		if (!devCode.length || !uCode.length) {
			self->_isPolling = NO;
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(NO, @"Google no proporcionó el código de usuario.");
			});
			return;
		}

		self->_deviceCode = devCode;
		self->_userCode = uCode;
		self->_verificationURL = vUrl;

		dispatch_async(dispatch_get_main_queue(), ^{
			if (progress) progress(uCode, vUrl);
		});

		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:expires];
		[self pollDeviceCode:devCode interval:interval deadline:deadline completion:completion];
	});
}

- (void)pollDeviceCode:(NSString *)deviceCode
              interval:(NSTimeInterval)interval
              deadline:(NSDate *)deadline
            completion:(void (^)(BOOL success, NSString *error))completion
{
	if (_cancelled) {
		_isPolling = NO;
		return;
	}

	if ([deadline timeIntervalSinceNow] <= 0) {
		_isPolling = NO;
		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(NO, @"El código ha expirado. Por favor, inténtalo de nuevo.");
		});
		return;
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		if (self->_cancelled) {
			self->_isPolling = NO;
			return;
		}

		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:TBGoogleTokenURL]
		                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
		                                               timeoutInterval:15.0];
		req.HTTPMethod = @"POST";
		[req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		[req setValue:TBTvUserAgent forHTTPHeaderField:@"User-Agent"];

		NSString *postStr = [NSString stringWithFormat:@"client_id=%@&client_secret=%@&code=%@&grant_type=%@",
		                     TBGoogleDefaultClientID,
		                     TBGoogleDefaultClientSecret,
		                     deviceCode,
		                     @"http://oauth.net/grant_type/device/1.0"];
		req.HTTPBody = [postStr dataUsingEncoding:NSUTF8StringEncoding];

		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

		if (self->_cancelled) {
			self->_isPolling = NO;
			return;
		}

		NSDictionary *json = (data.length > 0) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		if ([json isKindOfClass:[NSDictionary class]]) {
			NSString *accessToken = json[@"access_token"];
			if (accessToken.length > 0) {
				NSString *refreshToken = json[@"refresh_token"];
				NSTimeInterval exp = [json[@"expires_in"] doubleValue];
				[[MLInnerTube sharedClient] setOAuthAccessToken:accessToken refreshToken:refreshToken expiresIn:exp];
				[[MLInnerTube sharedClient] accountMenu:nil];
				[[MLLibraryManager sharedManager] syncWithYouTubeMusicCompletion:nil];
				self->_isPolling = NO;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (completion) completion(YES, nil);
				});
				return;
			}

			NSString *errCode = json[@"error"];
			if ([errCode isEqualToString:@"authorization_pending"] || !errCode.length) {
				[self pollDeviceCode:deviceCode interval:interval deadline:deadline completion:completion];
				return;
			} else if ([errCode isEqualToString:@"slow_down"]) {
				[self pollDeviceCode:deviceCode interval:(interval + 4.0) deadline:deadline completion:completion];
				return;
			} else if ([errCode isEqualToString:@"access_denied"]) {
				self->_isPolling = NO;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (completion) completion(NO, @"Inicio de sesión rechazado.");
				});
				return;
			} else if ([errCode isEqualToString:@"expired_token"]) {
				self->_isPolling = NO;
				dispatch_async(dispatch_get_main_queue(), ^{
					if (completion) completion(NO, @"El código ha expirado.");
				});
				return;
			}
		}

		// Network hiccup: retry after interval
		[self pollDeviceCode:deviceCode interval:interval deadline:deadline completion:completion];
	});
}

- (NSString *)urlEncode:(NSString *)str
{
	if (!str.length) return @"";
	CFStringRef esc = CFURLCreateStringByAddingPercentEscapes(
		kCFAllocatorDefault,
		(__bridge CFStringRef)str,
		NULL,
		CFSTR(":/?#[]@!$&'()*+,;="),
		kCFStringEncodingUTF8);
	return (__bridge_transfer NSString *)esc ?: str;
}

@end
