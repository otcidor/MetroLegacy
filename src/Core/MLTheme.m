#import "MLTheme.h"

static UIColor *MLRGB(int r, int g, int b, CGFloat a)
{
	return [UIColor colorWithRed:r / 255.0f green:g / 255.0f blue:b / 255.0f alpha:a];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 110000
@interface UIView (MLSafeAreaCompat)
- (UIEdgeInsets)safeAreaInsets;
@end
#endif

NSString *const MLThemeDidChangeNotification = @"MLThemeDidChangeNotification";

static UIColor *s_dynamicAccentColor = nil;

@implementation MLTheme

+ (BOOL)dynamicThemeEnabled
{
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	if ([ud objectForKey:@"ml_theme_dynamic"] == nil) {
		return YES; // Enabled by default like Metrolist
	}
	return [ud boolForKey:@"ml_theme_dynamic"];
}

+ (void)setDynamicThemeEnabled:(BOOL)enabled
{
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"ml_theme_dynamic"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	if (!enabled) {
		s_dynamicAccentColor = nil;
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:MLThemeDidChangeNotification object:nil];
}

+ (BOOL)pureBlackEnabled
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:@"ml_theme_pure_black"];
}

+ (void)setPureBlackEnabled:(BOOL)enabled
{
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"ml_theme_pure_black"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLThemeDidChangeNotification object:nil];
}

+ (NSArray *)availablePaletteColors
{
	return @[
		MLRGB(255, 84, 73, 1.0f),   // 0: Rojo YouTube Music M3 Pastel (#FF5449)
		MLRGB(237, 85, 100, 1.0f),  // 1: Carmesí Metrolist (#ED5564)
		MLRGB(30, 136, 229, 1.0f),  // 2: Azul Google (#1E88E5)
		MLRGB(67, 160, 71, 1.0f),   // 3: Verde M3 (#43A047)
		MLRGB(142, 36, 170, 1.0f),  // 4: Púrpura (#8E24AA)
		MLRGB(251, 140, 0, 1.0f),   // 5: Naranja M3 (#FB8C00)
	];
}

+ (NSArray *)availablePaletteNames
{
	return @[
		@"Rojo YouTube Music (M3)",
		@"Carmesí Metrolist",
		@"Azul Google",
		@"Verde M3",
		@"Púrpura",
		@"Naranja M3",
	];
}

+ (NSUInteger)selectedPaletteIndex
{
	return (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:@"ml_theme_palette_idx"];
}

+ (void)setSelectedPaletteIndex:(NSUInteger)index
{
	if (index >= [self availablePaletteColors].count) index = 0;
	[[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"ml_theme_palette_idx"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:MLThemeDidChangeNotification object:nil];
}

+ (UIColor *)defaultAccentColor
{
	NSUInteger idx = [self selectedPaletteIndex];
	NSArray *colors = [self availablePaletteColors];
	if (idx < colors.count) {
		return colors[idx];
	}
	return MLRGB(255, 84, 73, 1.0f);
}

+ (void)setDynamicAccentColor:(UIColor *)color
{
	if (![self dynamicThemeEnabled] || !color) {
		return;
	}
	if (![s_dynamicAccentColor isEqual:color]) {
		s_dynamicAccentColor = color;
		[[NSNotificationCenter defaultCenter] postNotificationName:MLThemeDidChangeNotification object:nil];
	}
}

+ (void)resetDynamicAccentColor
{
	if (s_dynamicAccentColor != nil) {
		s_dynamicAccentColor = nil;
		[[NSNotificationCenter defaultCenter] postNotificationName:MLThemeDidChangeNotification object:nil];
	}
}

+ (UIColor *)primary
{
	if ([self dynamicThemeEnabled] && s_dynamicAccentColor != nil) {
		return s_dynamicAccentColor;
	}
	return [self defaultAccentColor];
}

+ (UIColor *)background
{
	if ([self pureBlackEnabled]) {
		return [UIColor blackColor];
	}
	return MLRGB(28, 27, 31, 1.0f);
}

+ (UIColor *)surface
{
	if ([self pureBlackEnabled]) {
		return [UIColor blackColor];
	}
	return MLRGB(40, 37, 43, 1.0f);
}

+ (UIColor *)surfaceContainer
{
	if ([self pureBlackEnabled]) {
		return MLRGB(18, 18, 20, 1.0f);
	}
	return MLRGB(52, 49, 56, 1.0f);
}

+ (UIColor *)surfaceContainerHigh
{
	if ([self pureBlackEnabled]) {
		return MLRGB(28, 28, 32, 1.0f);
	}
	return MLRGB(63, 59, 67, 1.0f);
}

+ (UIColor *)surfaceContainerHighest
{
	if ([self pureBlackEnabled]) {
		return MLRGB(42, 42, 48, 1.0f);
	}
	return MLRGB(78, 74, 82, 1.0f);
}

+ (UIColor *)onSurface { return MLRGB(233, 226, 234, 1.0f); }
+ (UIColor *)onSurfaceVariant { return MLRGB(201, 197, 206, 1.0f); }
+ (UIColor *)outline { return MLRGB(120, 114, 127, 1.0f); }
+ (UIColor *)onPrimary { return MLRGB(56, 14, 21, 1.0f); }
+ (UIColor *)primaryContainer { return [[self primary] colorWithAlphaComponent:0.35f]; }
+ (UIColor *)onPrimaryContainer { return [UIColor whiteColor]; }
+ (UIColor *)error { return MLRGB(242, 184, 181, 1.0f); }

+ (UIFont *)fontTitleLarge  { return [UIFont boldSystemFontOfSize:22]; }
+ (UIFont *)fontTitleMedium { return [UIFont boldSystemFontOfSize:17]; }
+ (UIFont *)fontTitleSmall  { return [UIFont boldSystemFontOfSize:14]; }
+ (UIFont *)fontBodyLarge   { return [UIFont systemFontOfSize:16]; }
+ (UIFont *)fontBodyMedium  { return [UIFont systemFontOfSize:14]; }
+ (UIFont *)fontBodySmall   { return [UIFont systemFontOfSize:12]; }
+ (UIFont *)fontLabelMedium { return [UIFont systemFontOfSize:11]; }

+ (UIImage *)solidImage:(UIColor *)color size:(CGSize)size
{
	UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, color.CGColor);
	CGContextFillRect(ctx, CGRectMake(0, 0, size.width, size.height));
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIImage *)circleThumbWithColor:(UIColor *)color diameter:(CGFloat)diameter
{
	CGSize size = CGSizeMake(diameter + 4.0f, diameter + 4.0f);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1.0f), 2.0f, [UIColor colorWithWhite:0.0f alpha:0.45f].CGColor);
	[color setFill];
	UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(2.0f, 2.0f, diameter, diameter)];
	[circle fill];
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIColor *)dominantColorForImage:(UIImage *)image
{
	if (!image || !image.CGImage)
		return [self surfaceContainerHigh];

	const int w = 12;
	const int h = 12;
	unsigned char pixels[w * h * 4];
	memset(pixels, 0, sizeof(pixels));

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(cs);
	if (!ctx)
		return [self surfaceContainerHigh];

	CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image.CGImage);
	CGContextRelease(ctx);

	CGFloat totalR = 0.0f, totalG = 0.0f, totalB = 0.0f, totalWeight = 0.0f;
	for (int i = 0; i < w * h; i++) {
		CGFloat r = pixels[i * 4 + 0] / 255.0f;
		CGFloat g = pixels[i * 4 + 1] / 255.0f;
		CGFloat b = pixels[i * 4 + 2] / 255.0f;
		CGFloat maxC = MAX(r, MAX(g, b));
		CGFloat minC = MIN(r, MIN(g, b));
		CGFloat sat = (maxC > 0.01f) ? ((maxC - minC) / maxC) : 0.0f;
		// Prefer saturated, non-black/non-white pixels like Metrolist's Palette extractor
		CGFloat weight = 0.25f + sat * 2.5f;
		if (maxC < 0.08f || minC > 0.92f) {
			weight *= 0.2f;
		}
		totalR += r * weight;
		totalG += g * weight;
		totalB += b * weight;
		totalWeight += weight;
	}

	if (totalWeight <= 0.001f)
		return [self defaultAccentColor];

	UIColor *avg = [UIColor colorWithRed:(totalR / totalWeight)
	                               green:(totalG / totalWeight)
	                                blue:(totalB / totalWeight)
	                               alpha:1.0f];
	CGFloat hue = 0.0f, sat = 0.0f, bri = 0.0f, alpha = 1.0f;
	if ([avg getHue:&hue saturation:&sat brightness:&bri alpha:&alpha]) {
		sat = MIN(0.78f, MAX(0.42f, sat * 1.15f));
		bri = MIN(0.96f, MAX(0.76f, bri * 1.25f));
		return [UIColor colorWithHue:hue saturation:sat brightness:bri alpha:1.0f];
	}
	return avg;
}

+ (UIColor *)blendColor:(UIColor *)fg overBackground:(UIColor *)bg alpha:(CGFloat)alpha
{
	if (!fg) return bg ?: [self background];
	if (!bg) bg = [self background];
	alpha = MIN(1.0f, MAX(0.0f, alpha));
	CGFloat fr = 0, fgG = 0, fb = 0, fa = 1;
	CGFloat br = 0, bgG = 0, bb = 0, ba = 1;
	if (![fg getRed:&fr green:&fgG blue:&fb alpha:&fa]) {
		const CGFloat *c = CGColorGetComponents(fg.CGColor);
		if (c) { fr = c[0]; fgG = c[0]; fb = c[0]; }
	}
	if (![bg getRed:&br green:&bgG blue:&bb alpha:&ba]) {
		const CGFloat *c = CGColorGetComponents(bg.CGColor);
		if (c) { br = c[0]; bgG = c[0]; bb = c[0]; }
	}
	return [UIColor colorWithRed:(br * (1.0f - alpha) + fr * alpha)
	                       green:(bgG * (1.0f - alpha) + fgG * alpha)
	                        blue:(bb * (1.0f - alpha) + fb * alpha)
	                       alpha:1.0f];
}

+ (UIImage *)verticalGradientImageFromColor:(UIColor *)topColor toColor:(UIColor *)bottomColor size:(CGSize)size
{
	if (size.width < 1.0f) size.width = 4.0f;
	if (size.height < 1.0f) size.height = 44.0f;
	UIGraphicsBeginImageContextWithOptions(size, YES, 0.0f);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	NSArray *colors = @[ (id)(topColor ?: [self background]).CGColor, (id)(bottomColor ?: [self background]).CGColor ];
	CGFloat locs[2] = { 0.0f, 1.0f };
	CGGradientRef grad = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locs);
	if (grad) {
		CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
		CGGradientRelease(grad);
	}
	CGColorSpaceRelease(cs);
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}

+ (UIColor *)applyNavigationBarGradientWithAccent:(UIColor *)accentColor
                                     scrollOffset:(CGFloat)offsetY
                                     headerHeight:(CGFloat)headerH
                           toNavigationController:(UINavigationController *)nav
{
	UIColor *bg = [self background];
	UIColor *accent = accentColor ?: [self surfaceContainerHigh];
	UIColor *topBase = [self blendColor:accent overBackground:bg alpha:0.68f];
	UIColor *seamBase = [self blendColor:accent overBackground:bg alpha:0.50f];

	if (!nav) return seamBase;

	CGFloat fadeDist = MAX(100.0f, headerH * 0.72f);
	CGFloat progress = MIN(1.0f, MAX(0.0f, offsetY / fadeDist));
	CGFloat keep = 1.0f - progress;

	UIColor *barTop = [self blendColor:topBase overBackground:bg alpha:keep];
	UIColor *barBottom = [self blendColor:seamBase overBackground:bg alpha:keep];

	UIImage *gradImg = [self verticalGradientImageFromColor:barTop toColor:barBottom size:CGSizeMake(4.0f, 44.0f)];
	[nav.navigationBar setBackgroundImage:gradImg forBarMetrics:UIBarMetricsDefault];
	nav.navigationBar.backgroundColor = barBottom;
	if ([nav.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
		nav.navigationBar.barTintColor = barBottom;
	}

	id root = [UIApplication sharedApplication].keyWindow.rootViewController;
	if ([root respondsToSelector:@selector(setStatusBarBackgroundColor:)]) {
		[root performSelector:@selector(setStatusBarBackgroundColor:) withObject:barTop];
	}
	return seamBase;
}

+ (void)resetNavigationBarForNavigationController:(UINavigationController *)nav
{
	UIColor *bg = [self background];
	if (nav) {
		UIImage *barBg = [self solidImage:bg size:CGSizeMake(2.0f, 2.0f)];
		[nav.navigationBar setBackgroundImage:barBg forBarMetrics:UIBarMetricsDefault];
		nav.navigationBar.backgroundColor = bg;
		if ([nav.navigationBar respondsToSelector:@selector(setBarTintColor:)]) {
			nav.navigationBar.barTintColor = bg;
		}
	}
	id root = [UIApplication sharedApplication].keyWindow.rootViewController;
	if ([root respondsToSelector:@selector(setStatusBarBackgroundColor:)]) {
		[root performSelector:@selector(setStatusBarBackgroundColor:) withObject:bg];
	}
}

+ (void)setLeftNavigationTitle:(NSString *)title forViewController:(UIViewController *)vc
{
	if (!vc)
		return;
	NSString *safeTitle = title ?: @"";
	vc.title = safeTitle;
	if (!vc.navigationItem.titleView) {
		vc.navigationItem.titleView = [[UIView alloc] initWithFrame:CGRectZero];
	}
	UIView *container = vc.navigationItem.leftBarButtonItem.customView;
	UILabel *lbl = (UILabel *)[container viewWithTag:991];
	if (!container || !lbl) {
		container = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 180.0f, 32.0f)];
		container.backgroundColor = [UIColor clearColor];
		container.userInteractionEnabled = NO;

		lbl = [[UILabel alloc] initWithFrame:CGRectMake(9.0f, 0.0f, 171.0f, 32.0f)];
		lbl.tag = 991;
		lbl.font = [UIFont boldSystemFontOfSize:22.0f];
		lbl.textColor = [self onSurface];
		lbl.backgroundColor = [UIColor clearColor];
		lbl.textAlignment = NSTextAlignmentLeft;
		lbl.lineBreakMode = NSLineBreakByTruncatingTail;
		[container addSubview:lbl];

		vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:container];
	}
	lbl.text = safeTitle;
}

+ (void)triggerImpactHaptic
{
	Class hapticClass = NSClassFromString(@"UIImpactFeedbackGenerator");
	if (hapticClass) {
		id gen = [[hapticClass alloc] init];
		if ([gen respondsToSelector:@selector(prepare)]) [gen performSelector:@selector(prepare)];
		if ([gen respondsToSelector:@selector(impactOccurred)]) [gen performSelector:@selector(impactOccurred)];
	}
}

+ (void)triggerSuccessHaptic
{
	Class notifClass = NSClassFromString(@"UINotificationFeedbackGenerator");
	if (notifClass) {
		id gen = [[notifClass alloc] init];
		if ([gen respondsToSelector:@selector(prepare)]) [gen performSelector:@selector(prepare)];
		if ([gen respondsToSelector:@selector(notificationOccurred:)]) {
			typedef void (*NotifFn)(id, SEL, NSInteger);
			NotifFn fn = (NotifFn)[gen methodForSelector:@selector(notificationOccurred:)];
			if (fn) fn(gen, @selector(notificationOccurred:), 0); // UINotificationFeedbackTypeSuccess
		}
	}
}

+ (UIEdgeInsets)safeAreaInsetsForView:(UIView *)view
{
	UIEdgeInsets insets = UIEdgeInsetsZero;
	if (view && [view respondsToSelector:@selector(safeAreaInsets)]) {
		insets = [view safeAreaInsets];
	}
	if (insets.top <= 0.0f && insets.bottom <= 0.0f) {
		UIWindow *win = [UIApplication sharedApplication].keyWindow;
		if (!win && [UIApplication sharedApplication].windows.count > 0) {
			win = [UIApplication sharedApplication].windows[0];
		}
		if (win && [win respondsToSelector:@selector(safeAreaInsets)]) {
			insets = [win safeAreaInsets];
		}
	}

	CGFloat screenH = MAX([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
	BOOL isNotchDevice = (screenH >= 812.0f);

	if (insets.top <= 0.0f) {
		CGRect sbFrame = [UIApplication sharedApplication].statusBarFrame;
		CGFloat sbH = MIN(sbFrame.size.width, sbFrame.size.height);
		if (sbH > 0.0f) {
			insets.top = sbH;
		} else if (isNotchDevice) {
			insets.top = (screenH >= 852.0f) ? 54.0f : 47.0f;
		} else if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0f) {
			insets.top = 20.0f;
		}
	} else if (isNotchDevice && insets.top < 44.0f) {
		insets.top = (screenH >= 852.0f) ? 54.0f : 47.0f;
	}

	if (insets.bottom <= 0.0f && isNotchDevice) {
		insets.bottom = 34.0f;
	}

	return insets;
}

+ (CGFloat)safeAreaTopInsetForView:(UIView *)view
{
	return [self safeAreaInsetsForView:view].top;
}

+ (CGFloat)safeAreaBottomInsetForView:(UIView *)view
{
	return [self safeAreaInsetsForView:view].bottom;
}

@end

const CGFloat MLLengthTabBar = 62.0f;
const CGFloat MLLengthMiniPlayer = 60.0f;
const CGFloat MLLengthListItem = 64.0f;
const CGFloat MLLengthThumbnailList = 48.0f;
const CGFloat MLLengthThumbnailGrid = 128.0f;
const CGFloat MLRadiusThumbnail = 8.0f;
const CGFloat MLRadiusChip = 16.0f;
const CGFloat MLRadiusCard = 12.0f;
const CGFloat MLRadiusSheet = 28.0f;
