#import "MLImageCache.h"
#import "MLTheme.h"
#import "MLIcon.h"
#import "MLTLSTrustManager.h"
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

static const char *const MLImageCacheURLKey = "ml.url";

static NSString *MLCacheDirectory(void)
{
	static NSString *dir = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
		dir = [docs stringByAppendingPathComponent:@"mlimg"];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	});
	return dir;
}

static NSString *MLHashString(NSString *s)
{
	const char *c = [s UTF8String];
	unsigned char d[CC_MD5_DIGEST_LENGTH];
	CC_MD5(c, (CC_LONG)strlen(c), d);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
		[hex appendFormat:@"%02x", d[i]];
	return hex;
}

static NSUInteger MLBucketPixelSize(CGSize ptSize)
{
	CGFloat maxPt = MAX(ptSize.width, ptSize.height);
	if (maxPt <= 0.0f)
		return 240;
	if (maxPt <= 60.0f)
		return 120; // 42pt..56pt song rows & miniplayer -> 120x120 (~3 KB)
	if (maxPt <= 150.0f)
		return 240; // 134pt Home/Artist shelf cards -> 240x240 (~9 KB)
	return 480;     // Large headers & Now Playing -> 480x480 (~25 KB)
}

/*
 * Rewrites Google/YouTube thumbnail URLs to request the appropriate pixel tier
 * instead of downloading 544x544 or 1200x1200 images for small cards/rows.
 */
static NSString *MLOptimizedThumbnailURL(NSString *urlString, NSUInteger targetPx)
{
	if (!urlString.length)
		return urlString;
	if ([urlString hasPrefix:@"//"])
		urlString = [@"https:" stringByAppendingString:urlString];

	if ([urlString rangeOfString:@"googleusercontent.com"].location != NSNotFound ||
	    [urlString rangeOfString:@"ggpht.com"].location != NSNotFound) {
		NSRegularExpression *reWH = [NSRegularExpression regularExpressionWithPattern:@"=w\\d+-h\\d+"
		                                                                      options:0
		                                                                        error:nil];
		if ([reWH firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)]) {
			NSString *rep = [NSString stringWithFormat:@"=w%lu-h%lu", (unsigned long)targetPx, (unsigned long)targetPx];
			return [reWH stringByReplacingMatchesInString:urlString
			                                      options:0
			                                        range:NSMakeRange(0, urlString.length)
			                                 withTemplate:rep];
		}
		NSRegularExpression *reS = [NSRegularExpression regularExpressionWithPattern:@"=s\\d+"
		                                                                     options:0
		                                                                       error:nil];
		if ([reS firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)]) {
			NSString *rep = [NSString stringWithFormat:@"=s%lu", (unsigned long)targetPx];
			return [reS stringByReplacingMatchesInString:urlString
			                                     options:0
			                                       range:NSMakeRange(0, urlString.length)
			                                withTemplate:rep];
		}
	} else if (targetPx <= 240 && [urlString rangeOfString:@"i.ytimg.com/vi/"].location != NSNotFound) {
		urlString = [urlString stringByReplacingOccurrencesOfString:@"maxresdefault.jpg" withString:@"mqdefault.jpg"];
		urlString = [urlString stringByReplacingOccurrencesOfString:@"sddefault.jpg" withString:@"mqdefault.jpg"];
		urlString = [urlString stringByReplacingOccurrencesOfString:@"hqdefault.jpg" withString:@"mqdefault.jpg"];
	}
	return urlString;
}

static UIImage *MLDecodeAndRenderImage(NSString *path, CGSize fitSize, CGFloat radius, NSUInteger maxPx)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data)
		return nil;

	UIImage *decoded = nil;
	CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
	if (src) {
		NSDictionary *opts = @{
			(id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
			(id)kCGImageSourceCreateThumbnailWithTransform : @YES,
			(id)kCGImageSourceThumbnailMaxPixelSize : @(maxPx),
		};
		CGImageRef cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
		CFRelease(src);
		if (cgImg) {
			decoded = [UIImage imageWithCGImage:cgImg];
			CGImageRelease(cgImg);
		}
	}
	if (!decoded)
		decoded = [UIImage imageWithData:data];
	if (!decoded)
		return nil;

	CGSize outSize = fitSize;
	if (outSize.width < 8.0f || outSize.height < 8.0f) {
		outSize = decoded.size;
	}
	CGFloat scale = [UIScreen mainScreen].scale;
	if (scale < 1.0f)
		scale = 1.0f;
	if (scale > 2.0f)
		scale = 2.0f;

	// Pre-render exact target size + aspect-fill crop + rounded corners on the background thread
	UIGraphicsBeginImageContextWithOptions(outSize, (radius <= 0.01f), scale);
	if (radius > 0.01f) {
		UIBezierPath *clipPath = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, outSize.width, outSize.height)
		                                                    cornerRadius:radius];
		[clipPath addClip];
	}
	CGSize imgSize = decoded.size;
	if (imgSize.width > 0 && imgSize.height > 0) {
		CGFloat scaleW = outSize.width / imgSize.width;
		CGFloat scaleH = outSize.height / imgSize.height;
		CGFloat fillScale = MAX(scaleW, scaleH);
		CGFloat drawW = imgSize.width * fillScale;
		CGFloat drawH = imgSize.height * fillScale;
		CGRect drawRect = CGRectMake((outSize.width - drawW) * 0.5f, (outSize.height - drawH) * 0.5f, drawW, drawH);
		[decoded drawInRect:drawRect];
	} else {
		[decoded drawInRect:CGRectMake(0, 0, outSize.width, outSize.height)];
	}
	UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return rendered ?: decoded;
}

static BOOL IsCurrentKey(UIImageView *iv, NSString *key)
{
	NSString *cur = objc_getAssociatedObject(iv, (void *)MLImageCacheURLKey);
	return [cur isEqualToString:key];
}

@implementation MLImageCache
{
	NSCache *_mem;
	NSOperationQueue *_diskQueue;
	NSOperationQueue *_netQueue;
	NSMutableDictionary *_inflight;
}

+ (MLImageCache *)sharedCache
{
	static MLImageCache *c = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ c = [[MLImageCache alloc] init]; });
	return c;
}

- (id)init
{
	self = [super init];
	if (self) {
		_mem = [[NSCache alloc] init];
		[_mem setCountLimit:260];

		NSUInteger cores = [[NSProcessInfo processInfo] activeProcessorCount];

		_diskQueue = [[NSOperationQueue alloc] init];
		_diskQueue.maxConcurrentOperationCount = (cores > 2) ? 2 : 1;

		_netQueue = [[NSOperationQueue alloc] init];
		_netQueue.maxConcurrentOperationCount = (cores > 2) ? 4 : 2;

		_inflight = [NSMutableDictionary dictionary];

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			[self trimDisk];
		});
	}
	return self;
}

- (void)trimDisk
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		NSString *dir = MLCacheDirectory();
		NSFileManager *fm = [NSFileManager defaultManager];
		NSError *err = nil;
		NSArray *files = [fm contentsOfDirectoryAtPath:dir error:&err];
		if (!files || files.count < 1400)
			return;
		NSMutableArray *withDates = [NSMutableArray array];
		for (NSString *f in files) {
			NSString *p = [dir stringByAppendingPathComponent:f];
			NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
			NSDate *d = [at objectForKey:NSFileModificationDate];
			if (d)
				[withDates addObject:@{ @"path" : p, @"date" : d }];
		}
		[withDates sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
			return [a[@"date"] compare:b[@"date"]];
		}];
		NSUInteger excess = withDates.count - 1100;
		for (NSUInteger i = 0; i < excess; i++)
			[fm removeItemAtPath:withDates[i][@"path"] error:nil];
	});
}

+ (void)loadImageAtURLString:(NSString *)urlString
                    intoView:(UIImageView *)imageView
                     fitSize:(CGSize)size
                cornerRadius:(CGFloat)radius
                 placeholder:(UIImage *)placeholder
{
	[self loadImageAtURLString:urlString
	                  intoView:imageView
	                   fitSize:size
	              cornerRadius:radius
	               placeholder:placeholder
	                completion:nil];
}

+ (void)loadImageAtURLString:(NSString *)urlString
                    intoView:(UIImageView *)imageView
                     fitSize:(CGSize)size
                cornerRadius:(CGFloat)radius
                 placeholder:(UIImage *)placeholder
                  completion:(void (^)(UIImage *image))completion
{
	if (!urlString.length) {
		imageView.image = placeholder;
		if (completion)
			completion(nil);
		return;
	}
	if ([urlString hasPrefix:@"//"])
		urlString = [@"https:" stringByAppendingString:urlString];

	NSUInteger bucketPx = MLBucketPixelSize(size);
	NSString *fetchURL = MLOptimizedThumbnailURL(urlString, bucketPx);
	NSString *memKey = [NSString stringWithFormat:@"%@|%.0fx%.0f|r%.0f", fetchURL, size.width, size.height, radius];

	objc_setAssociatedObject(imageView, (void *)MLImageCacheURLKey, memKey, OBJC_ASSOCIATION_COPY_NONATOMIC);

	MLImageCache *cache = [self sharedCache];
	UIImage *hit = [cache->_mem objectForKey:memKey];
	if (hit) {
		imageView.image = hit;
		if (completion)
			completion(hit);
		return;
	}

	imageView.image = placeholder;

	NSString *sizedFile = [MLCacheDirectory() stringByAppendingPathComponent:MLHashString(fetchURL)];
	NSString *rawFile = [MLCacheDirectory() stringByAppendingPathComponent:MLHashString(urlString)];
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *existingFile = [fm fileExistsAtPath:sizedFile] ? sizedFile : ([fm fileExistsAtPath:rawFile] ? rawFile : nil);

	if (existingFile) {
		[cache->_diskQueue addOperationWithBlock:^{
			UIImage *rendered = MLDecodeAndRenderImage(existingFile, size, radius, bucketPx);
			if (rendered) {
				[cache->_mem setObject:rendered forKey:memKey];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				if (IsCurrentKey(imageView, memKey) && rendered) {
					imageView.image = rendered;
				}
				if (completion)
					completion(rendered);
			});
		}];
		return;
	}

	void (^cb)(UIImage *) = ^(UIImage *rendered) {
		if (IsCurrentKey(imageView, memKey)) {
			imageView.image = rendered ?: placeholder;
		}
		if (completion)
			completion(rendered);
	};

	@synchronized (cache->_inflight) {
		NSMutableArray *waiters = cache->_inflight[memKey];
		if (waiters) {
			[waiters addObject:[cb copy]];
			return;
		}
		cache->_inflight[memKey] = [NSMutableArray arrayWithObject:[cb copy]];
	}

	[cache->_netQueue addOperationWithBlock:^{
		UIImage *rendered = nil;
		if ([fm fileExistsAtPath:sizedFile]) {
			rendered = MLDecodeAndRenderImage(sizedFile, size, radius, bucketPx);
		} else {
			NSURL *url = [NSURL URLWithString:fetchURL];
			if (url) {
				NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
				                                                   cachePolicy:NSURLRequestUseProtocolCachePolicy
				                                               timeoutInterval:15.0];
				req.HTTPShouldHandleCookies = NO;
				[req setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0" forHTTPHeaderField:@"User-Agent"];
				NSError *err = nil;
				NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:nil error:&err];
				if (data && data.length > 200) {
					[data writeToFile:sizedFile atomically:YES];
					rendered = MLDecodeAndRenderImage(sizedFile, size, radius, bucketPx);
				}
			}
		}
		if (rendered) {
			[cache->_mem setObject:rendered forKey:memKey];
		}
		NSArray *callbacks = nil;
		@synchronized (cache->_inflight) {
			callbacks = [cache->_inflight[memKey] copy];
			[cache->_inflight removeObjectForKey:memKey];
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			for (void (^block)(UIImage *) in callbacks) {
				block(rendered);
			}
		});
	}];
}

+ (UIImage *)placeholderImageWithSize:(CGSize)size
{
	if (size.width < 8.0f || size.height < 8.0f) {
		size = CGSizeMake(48.0f, 48.0f);
	}
	NSString *key = [NSString stringWithFormat:@"ph-%.0f-%.0f", size.width, size.height];
	MLImageCache *cache = [self sharedCache];
	UIImage *hit = [cache->_mem objectForKey:key];
	if (hit)
		return hit;
	UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	[[MLTheme surfaceContainerHigh] setFill];
	UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:MLRadiusThumbnail];
	[p fill];
	CGFloat iconSz = MIN(size.width, size.height) * 0.45f;
	UIImage *note = [MLIcon icon:@"music_note" size:iconSz color:[MLTheme outline]];
	if (note) {
		[note drawInRect:CGRectMake((size.width - iconSz) / 2.0f, (size.height - iconSz) / 2.0f, iconSz, iconSz)];
	}
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (img)
		[cache->_mem setObject:img forKey:key];
	return img;
}

+ (void)prefetchImageAtURLString:(NSString *)urlString
{
	if (!urlString.length)
		return;
	if ([urlString hasPrefix:@"//"])
		urlString = [@"https:" stringByAppendingString:urlString];

	NSString *fetchURL = MLOptimizedThumbnailURL(urlString, 240);
	NSString *file = [MLCacheDirectory() stringByAppendingPathComponent:MLHashString(fetchURL)];
	if ([[NSFileManager defaultManager] fileExistsAtPath:file])
		return;

	MLImageCache *cache = [self sharedCache];
	[cache->_netQueue addOperationWithBlock:^{
		if ([[NSFileManager defaultManager] fileExistsAtPath:file])
			return;
		NSURL *url = [NSURL URLWithString:fetchURL];
		if (!url)
			return;
		NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
		                                                   cachePolicy:NSURLRequestUseProtocolCachePolicy
		                                               timeoutInterval:15.0];
		req.HTTPShouldHandleCookies = NO;
		[req setValue:@"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0" forHTTPHeaderField:@"User-Agent"];
		NSData *data = [MLTLSTrustManager sendSynchronousRequest:req returningResponse:nil error:nil];
		if (data && data.length > 200) {
			[data writeToFile:file atomically:YES];
		}
	}];
}

@end
