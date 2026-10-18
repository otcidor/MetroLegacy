#import "MLSponsorBlockManager.h"
#import "MLTLSTrustManager.h"

NSString *const MLSponsorBlockDidSkipNotification = @"MLSponsorBlockDidSkipNotification";
static NSString *const MLSponsorBlockEnabledKey = @"MLSponsorBlockEnabled";

@implementation MLSponsorSegment
@end

@implementation MLSponsorBlockManager
{
	NSCache *_cache;
}

+ (instancetype)sharedManager
{
	static MLSponsorBlockManager *mgr = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		mgr = [[MLSponsorBlockManager alloc] init];
	});
	return mgr;
}

- (id)init
{
	self = [super init];
	if (self) {
		_cache = [[NSCache alloc] init];
		_cache.countLimit = 60;
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		if ([ud objectForKey:MLSponsorBlockEnabledKey] == nil) {
			_enabled = YES;
		} else {
			_enabled = [ud boolForKey:MLSponsorBlockEnabledKey];
		}
	}
	return self;
}

- (void)setEnabled:(BOOL)enabled
{
	_enabled = enabled;
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:MLSponsorBlockEnabledKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)fetchSegmentsForVideoId:(NSString *)videoId completion:(void (^)(NSArray *segments))completion
{
	if (!videoId.length || !_enabled) {
		if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(@[]); });
		return;
	}

	NSArray *cached = [_cache objectForKey:videoId];
	if (cached) {
		if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *cats = @"%5B%22music_offtopic%22%2C%22intro%22%2C%22outro%22%2C%22sponsor%22%5D";
		NSString *urlStr = [NSString stringWithFormat:@"https://sponsor.ajay.app/api/skipSegments?videoID=%@&categories=%@", videoId, cats];
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]
		                                                   cachePolicy:NSURLRequestUseProtocolCachePolicy
		                                               timeoutInterval:8.0];
		[req setValue:@"MetroLegacy/1.1 (iOS)" forHTTPHeaderField:@"User-Agent"];

		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

		NSMutableArray *result = [NSMutableArray array];
		if (!err && resp.statusCode == 200 && data.length > 0) {
			id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([json isKindOfClass:[NSArray class]]) {
				for (id item in json) {
					if (![item isKindOfClass:[NSDictionary class]]) continue;
					NSDictionary *d = (NSDictionary *)item;
					NSArray *seg = d[@"segment"];
					if ([seg isKindOfClass:[NSArray class]] && seg.count >= 2) {
						CGFloat s = [seg[0] floatValue];
						CGFloat e = [seg[1] floatValue];
						if (e > s + 0.5f) {
							MLSponsorSegment *segment = [[MLSponsorSegment alloc] init];
							segment.start = s;
							segment.end = e;
							segment.category = [d[@"category"] description] ?: @"music_offtopic";
							[result addObject:segment];
						}
					}
				}
				[result sortUsingComparator:^NSComparisonResult(MLSponsorSegment *a, MLSponsorSegment *b) {
					if (a.start < b.start) return NSOrderedAscending;
					if (a.start > b.start) return NSOrderedDescending;
					return NSOrderedSame;
				}];
			}
		}

		if (result.count > 0) {
			[_cache setObject:result forKey:videoId];
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			if (completion) completion(result);
		});
	});
}

- (CGFloat)nextSkipTargetForTime:(CGFloat)currentTime segments:(NSArray *)segments
{
	if (!_enabled || !segments.count) return 0.0f;
	for (MLSponsorSegment *s in segments) {
		if (currentTime >= s.start && currentTime < (s.end - 0.4f)) {
			return s.end + 0.05f;
		}
	}
	return 0.0f;
}

@end
