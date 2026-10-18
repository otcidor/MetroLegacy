#import "MLLyricsManager.h"
#import "MLTLSTrustManager.h"

@implementation MLLyricLine
@end

@implementation MLLyricsManager
{
	NSCache *_cache;
}

+ (instancetype)sharedManager
{
	static MLLyricsManager *mgr = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		mgr = [[MLLyricsManager alloc] init];
	});
	return mgr;
}

- (id)init
{
	self = [super init];
	if (self) {
		_cache = [[NSCache alloc] init];
		_cache.countLimit = 50;
	}
	return self;
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

- (NSString *)cleanTitle:(NSString *)title
{
	if (!title.length) return @"";
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[\\(\\[\\{].*?(official|video|audio|mv|remaster|lyrics|clip).*?[\\)\\]\\}]"
	                                                                       options:NSRegularExpressionCaseInsensitive
	                                                                         error:nil];
	NSString *cleaned = [regex stringByReplacingMatchesInString:title
	                                                    options:0
	                                                      range:NSMakeRange(0, title.length)
	                                               withTemplate:@""];
	return [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSArray *)parseLRC:(NSString *)lrcText
{
	if (!lrcText.length) return @[];
	NSMutableArray *lines = [NSMutableArray array];
	NSArray *rawLines = [lrcText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@"\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\]"
	                                                                           options:0
	                                                                             error:nil];

	for (NSString *raw in rawLines) {
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (!trimmed.length) continue;

		NSArray *matches = [timeRegex matchesInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)];
		if (!matches.count) continue;

		NSUInteger lastMatchEnd = 0;
		NSMutableArray *timestamps = [NSMutableArray array];
		for (NSTextCheckingResult *m in matches) {
			if (m.numberOfRanges >= 4) {
				NSString *minStr = [trimmed substringWithRange:[m rangeAtIndex:1]];
				NSString *secStr = [trimmed substringWithRange:[m rangeAtIndex:2]];
				NSString *msStr = [trimmed substringWithRange:[m rangeAtIndex:3]];

				NSInteger mins = [minStr integerValue];
				NSInteger secs = [secStr integerValue];
				NSInteger ms = [msStr integerValue];
				if (msStr.length == 2) ms *= 10;

				NSInteger totalMs = (mins * 60 + secs) * 1000 + ms;
				[timestamps addObject:@(totalMs)];
			}
			lastMatchEnd = m.range.location + m.range.length;
		}

		NSString *lyricText = [[trimmed substringFromIndex:lastMatchEnd] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		for (NSNumber *ts in timestamps) {
			MLLyricLine *line = [[MLLyricLine alloc] init];
			line.timeMs = [ts integerValue];
			line.text = lyricText.length ? lyricText : @"♪";
			[lines addObject:line];
		}
	}

	[lines sortUsingComparator:^NSComparisonResult(MLLyricLine *a, MLLyricLine *b) {
		if (a.timeMs < b.timeMs) return NSOrderedAscending;
		if (a.timeMs > b.timeMs) return NSOrderedDescending;
		return NSOrderedSame;
	}];

	return lines;
}

- (NSArray *)parsePlain:(NSString *)plainText
{
	if (!plainText.length) return @[];
	NSMutableArray *lines = [NSMutableArray array];
	NSArray *rawLines = [plainText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	for (NSString *raw in rawLines) {
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (trimmed.length) {
			MLLyricLine *line = [[MLLyricLine alloc] init];
			line.timeMs = -1;
			line.text = trimmed;
			[lines addObject:line];
		}
	}
	return lines;
}

- (void)fetchLyricsForTitle:(NSString *)title
                     artist:(NSString *)artist
                   duration:(CGFloat)duration
                    videoId:(NSString *)videoId
                 completion:(void (^)(NSArray *lines, BOOL synced, NSString *error))completion
{
	NSString *cacheKey = videoId.length ? videoId : [NSString stringWithFormat:@"%@|%@", title, artist];
	NSDictionary *cached = [_cache objectForKey:cacheKey];
	if (cached) {
		if (completion) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(cached[@"lines"], [cached[@"synced"] boolValue], nil);
			});
		}
		return;
	}

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *cleanedTitle = [self cleanTitle:title];
		NSString *cleanedArtist = artist ?: @"";

		// 1. Try exact get
		NSString *getParams = [NSString stringWithFormat:@"track_name=%@&artist_name=%@",
		                       [self urlEncode:cleanedTitle],
		                       [self urlEncode:cleanedArtist]];
		if (duration > 0) {
			getParams = [getParams stringByAppendingFormat:@"&duration=%d", (int)round(duration)];
		}
		NSString *getUrl = [NSString stringWithFormat:@"https://lrclib.net/api/get?%@", getParams];
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:getUrl]
		                                                   cachePolicy:NSURLRequestUseProtocolCachePolicy
		                                               timeoutInterval:6.0];
		[req setValue:@"MetroLegacy/1.1 (iOS)" forHTTPHeaderField:@"User-Agent"];

		NSHTTPURLResponse *resp = nil;
		NSError *err = nil;
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:&resp error:&err];

		id json = (!err && resp.statusCode == 200 && data.length > 0) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;

		// 2. If exact get failed, try search
		if (![json isKindOfClass:[NSDictionary class]]) {
			NSString *query = [NSString stringWithFormat:@"%@ %@", cleanedTitle, cleanedArtist];
			NSString *searchUrl = [NSString stringWithFormat:@"https://lrclib.net/api/search?q=%@", [self urlEncode:query]];
			NSMutableURLRequest *sReq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:searchUrl]
			                                                    cachePolicy:NSURLRequestUseProtocolCachePolicy
			                                                timeoutInterval:6.0];
			[sReq setValue:@"MetroLegacy/1.1 (iOS)" forHTTPHeaderField:@"User-Agent"];
			NSData *sData = [MLTLSTrustManager sendSynchronousRequest:sReq returningResponse:&resp error:&err];
			if (!err && resp.statusCode == 200 && sData.length > 0) {
				id sJson = [NSJSONSerialization JSONObjectWithData:sData options:0 error:nil];
				if ([sJson isKindOfClass:[NSArray class]] && [(NSArray *)sJson count] > 0) {
					json = [(NSArray *)sJson firstObject];
				}
			}
		}

		NSArray *resultLines = nil;
		BOOL isSynced = NO;

		if ([json isKindOfClass:[NSDictionary class]]) {
			NSString *syncedText = json[@"syncedLyrics"];
			NSString *plainText = json[@"plainLyrics"];
			if ([syncedText isKindOfClass:[NSString class]] && syncedText.length > 0) {
				resultLines = [self parseLRC:syncedText];
				isSynced = YES;
			} else if ([plainText isKindOfClass:[NSString class]] && plainText.length > 0) {
				resultLines = [self parsePlain:plainText];
				isSynced = NO;
			}
		}

		if (resultLines.count > 0) {
			[self->_cache setObject:@{ @"lines": resultLines, @"synced": @(isSynced) } forKey:cacheKey];
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(resultLines, isSynced, nil);
			});
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (completion) completion(@[], NO, @"No lyrics found");
			});
		}
	});
}

@end
