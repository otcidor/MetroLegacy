#import <UIKit/UIKit.h>

extern NSString *const MLThemeDidChangeNotification;

/*
 * M3 dark theme with Metrolist-style dynamic color extraction and pure black AMOLED.
 */
@interface MLTheme : NSObject

// Dynamic Theme (Material You extracted from playing track)
+ (BOOL)dynamicThemeEnabled;
+ (void)setDynamicThemeEnabled:(BOOL)enabled;

// Pure Black (AMOLED #000000)
+ (BOOL)pureBlackEnabled;
+ (void)setPureBlackEnabled:(BOOL)enabled;

// Default Accent Palette
+ (NSUInteger)selectedPaletteIndex;
+ (void)setSelectedPaletteIndex:(NSUInteger)index;
+ (NSArray *)availablePaletteNames;
+ (NSArray *)availablePaletteColors;
+ (UIColor *)defaultAccentColor;

// Dynamic accent color manipulation
+ (void)setDynamicAccentColor:(UIColor *)color;
+ (void)resetDynamicAccentColor;

+ (UIColor *)background;             // app background
+ (UIColor *)surface;                // cards, sheets
+ (UIColor *)surfaceContainer;       // chips, mini player bg
+ (UIColor *)surfaceContainerHigh;   // nav bars
+ (UIColor *)surfaceContainerHighest;// tab indicator pill
+ (UIColor *)onSurface;              // primary text
+ (UIColor *)onSurfaceVariant;       // secondary text
+ (UIColor *)outline;                // borders, dividers (30% alpha onSurface)
+ (UIColor *)primary;                // active accent color (dynamic or default M3 pastel red)
+ (UIColor *)onPrimary;
+ (UIColor *)primaryContainer;
+ (UIColor *)onPrimaryContainer;
+ (UIColor *)error;

+ (UIFont *)fontTitleLarge;          // 22 bold
+ (UIFont *)fontTitleMedium;         // 17 bold
+ (UIFont *)fontTitleSmall;          // 14 bold
+ (UIFont *)fontBodyLarge;           // 16 regular
+ (UIFont *)fontBodyMedium;          // 14 regular
+ (UIFont *)fontBodySmall;           // 12 regular
+ (UIFont *)fontLabelMedium;         // 11 medium

// Flat solid-color image (for styling iOS 6 bars).
+ (UIImage *)solidImage:(UIColor *)color size:(CGSize)size;

// Circular slider thumb image for sleek seek bars.
+ (UIImage *)circleThumbWithColor:(UIColor *)color diameter:(CGFloat)diameter;

// Extracts a vibrant, dark-mode-friendly dominant color from album artwork.
+ (UIColor *)dominantColorForImage:(UIImage *)image;

// Color blending & seamless navigation bar gradient helpers.
+ (UIColor *)blendColor:(UIColor *)fg overBackground:(UIColor *)bg alpha:(CGFloat)alpha;
+ (UIImage *)verticalGradientImageFromColor:(UIColor *)topColor toColor:(UIColor *)bottomColor size:(CGSize)size;
+ (UIColor *)applyNavigationBarGradientWithAccent:(UIColor *)accentColor
                                     scrollOffset:(CGFloat)offsetY
                                     headerHeight:(CGFloat)headerH
                           toNavigationController:(UINavigationController *)nav;
+ (void)resetNavigationBarForNavigationController:(UINavigationController *)nav;
+ (void)setLeftNavigationTitle:(NSString *)title forViewController:(UIViewController *)vc;

// Modern iOS / arm64 Haptic Feedback (dynamic, no-op on iOS 6-9)
+ (void)triggerImpactHaptic;
+ (void)triggerSuccessHaptic;

// Safe Area insets (iOS 11+ notch / home indicator, fallback for iOS 6-10)
+ (UIEdgeInsets)safeAreaInsetsForView:(UIView *)view;
+ (CGFloat)safeAreaTopInsetForView:(UIView *)view;
+ (CGFloat)safeAreaBottomInsetForView:(UIView *)view;

@end

/*
 * Shared metrics, ported from Metrolist Dimensions.kt (dp ~ pt).
 */
extern const CGFloat MLLengthTabBar;        // 64 (slim nav bar pref)
extern const CGFloat MLLengthMiniPlayer;    // 64
extern const CGFloat MLLengthListItem;      // 64
extern const CGFloat MLLengthThumbnailList; // 48
extern const CGFloat MLLengthThumbnailGrid; // 128
extern const CGFloat MLRadiusThumbnail;     // 8
extern const CGFloat MLRadiusChip;          // 16
extern const CGFloat MLRadiusCard;          // 12
extern const CGFloat MLRadiusSheet;         // 28
