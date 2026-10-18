#import <UIKit/UIKit.h>

/*
 * Vector icon engine: draws Material icons from embedded SVG path data
 * (Material Icons, Apache 2.0). No image assets needed.
 *
 * All path data lives in a 24x24 viewport, scaled to the requested size.
 */
@interface MLIcon : NSObject

typedef enum {
	MLIconVariantAny = 0,
	MLIconVariantFilled,
	MLIconVariantOutlined,
} MLIconVariant;

// Tinted icon image, cached. `name` is a material icon name, e.g. @"home".
+ (UIImage *)icon:(NSString *)name variant:(int)variant size:(CGFloat)size color:(UIColor *)color;
// Convenience: filled == outlined for icons without an outlined variant.
+ (UIImage *)icon:(NSString *)name size:(CGFloat)size color:(UIColor *)color;

// Parsed bezier path in the target rect (24-unit viewport, centered).
+ (UIBezierPath *)path:(NSString *)name variant:(int)variant inRect:(CGRect)rect;

@end
