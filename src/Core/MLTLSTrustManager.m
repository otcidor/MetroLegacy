#import "MLTLSTrustManager.h"

@interface MLNetworkTask : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) NSHTTPURLResponse *response;
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) dispatch_semaphore_t sem;
@property (nonatomic, strong) NSURLConnection *connection;
@end

@implementation MLNetworkTask

+ (NSThread *)networkThread
{
	static NSThread *t = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		t = [[NSThread alloc] initWithTarget:self selector:@selector(networkThreadMain:) object:nil];
		t.name = @"win.otcidor.metrolegacy.network";
		[t start];
	});
	return t;
}

+ (void)networkThreadMain:(id)unused
{
	@autoreleasepool {
		NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
		[runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
		while (YES) {
			@autoreleasepool {
				[runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
			}
		}
	}
}

- (void)start
{
	if (!self.request || !self.request.URL) {
		self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
		if (self.sem) {
			dispatch_semaphore_signal(self.sem);
		}
		return;
	}
	self.data = [NSMutableData data];
	self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
	if (!self.connection) {
		self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
		if (self.sem) {
			dispatch_semaphore_signal(self.sem);
		}
		return;
	}
	[self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	[self.connection start];
}

- (void)cancelOnNetworkThread
{
	[self.connection cancel];
	self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
	if ([[challenge.protectionSpace authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
		BOOL handled = [[MLTLSTrustManager sharedManager] handleAuthenticationChallenge:challenge forConnection:connection];
		if (!handled) {
			[challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
		}
	} else {
		[challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
		self.response = (NSHTTPURLResponse *)response;
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	if (data.length > 0) {
		[self.data appendData:data];
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (self.sem) {
		dispatch_semaphore_signal(self.sem);
	}
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	self.error = error;
	if (self.sem) {
		dispatch_semaphore_signal(self.sem);
	}
}

@end

@interface MLTLSTrustManager ()
@property (nonatomic, strong) NSArray *anchors;
@end

@implementation MLTLSTrustManager

+ (instancetype)sharedManager
{
	static MLTLSTrustManager *m = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		m = [[MLTLSTrustManager alloc] init];
	});
	return m;
}

- (id)init
{
	self = [super init];
	if (self) {
		[self loadAnchors];
	}
	return self;
}

- (void)loadAnchors
{
	NSMutableArray *certs = [NSMutableArray array];
	NSBundle *bundle = [NSBundle mainBundle];
	NSString *bundlePath = [bundle bundlePath];

	NSArray *searchPaths = @[
		bundlePath ?: @"",
		[bundlePath stringByAppendingPathComponent:@"certs"],
		[bundlePath stringByAppendingPathComponent:@"Certs"],
	];

	NSFileManager *fm = [NSFileManager defaultManager];
	for (NSString *dir in searchPaths) {
		if (!dir.length)
			continue;
		BOOL isDir = NO;
		if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir)
			continue;

		NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
		for (NSString *file in files) {
			NSString *ext = [[file pathExtension] lowercaseString];
			if ([ext isEqualToString:@"der"] || [ext isEqualToString:@"cer"] || [ext isEqualToString:@"crt"]) {
				NSString *fullPath = [dir stringByAppendingPathComponent:file];
				NSData *certData = [NSData dataWithContentsOfFile:fullPath];
				if (certData.length > 0) {
					SecCertificateRef cert = SecCertificateCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)certData);
					if (cert) {
						[certs addObject:(__bridge_transfer id)cert];
					}
				}
			}
		}
	}

	self.anchors = [certs copy];
	NSLog(@"[MLTLSTrustManager] loaded %lu modern root anchors", (unsigned long)self.anchors.count);
}

- (BOOL)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host
{
	if (!trust)
		return NO;

	if (self.anchors.count > 0) {
		SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)self.anchors);
		SecTrustSetAnchorCertificatesOnly(trust, false);
	}

	if (host.length > 0) {
		SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)host);
		if (policy) {
			SecTrustSetPolicies(trust, policy);
			CFRelease(policy);
		}
	}

	SecTrustResultType result = kSecTrustResultInvalid;
	SecTrustEvaluate(trust, &result);
	return YES;
}

- (BOOL)handleAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge forConnection:(NSURLConnection *)connection
{
	if (![[challenge.protectionSpace authenticationMethod] isEqualToString:NSURLAuthenticationMethodServerTrust]) {
		return NO;
	}

	SecTrustRef trust = challenge.protectionSpace.serverTrust;
	NSString *host = challenge.protectionSpace.host;
	[self evaluateServerTrust:trust forHost:host];
	NSURLCredential *cred = [NSURLCredential credentialForTrust:trust];
	if (cred) {
		[challenge.sender useCredential:cred forAuthenticationChallenge:challenge];
		return YES;
	}

	return NO;
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSHTTPURLResponse **)responseOut
                             error:(NSError **)errorOut
{
	if (!request || !request.URL) {
		if (errorOut) {
			*errorOut = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
		}
		return nil;
	}

	MLNetworkTask *task = [[MLNetworkTask alloc] init];
	task.request = request;
	task.sem = dispatch_semaphore_create(0);

	[task performSelector:@selector(start) onThread:[MLNetworkTask networkThread] withObject:nil waitUntilDone:NO];

	NSTimeInterval timeout = request.timeoutInterval > 0 ? request.timeoutInterval : 30.0;
	dispatch_time_t dTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
	long timedOut = dispatch_semaphore_wait(task.sem, dTime);
	if (timedOut != 0) {
		[task performSelector:@selector(cancelOnNetworkThread) onThread:[MLNetworkTask networkThread] withObject:nil waitUntilDone:NO];
		if (errorOut) {
			*errorOut = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
		}
		return nil;
	}

	if (responseOut) {
		*responseOut = task.response;
	}
	if (errorOut) {
		*errorOut = task.error;
	}
	if (task.error) {
		return nil;
	}
	return task.data;
}

@end
