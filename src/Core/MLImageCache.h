#import <UIKit/UIKit.h>

/*
 * Tiny async image loader with memory + disk cache.
 * Disk cache in Documents/mlimg, capped by file count (512MB device).
 */
@interface MLImageCache : NSObject

+ (void)loadImageAtURLString:(NSString *)urlString
                    intoView:(UIImageView *)imageView
                     fitSize:(CGSize)size
                cornerRadius:(CGFloat)radius
                 placeholder:(UIImage *)placeholder;

+ (void)loadImageAtURLString:(NSString *)urlString
                    intoView:(UIImageView *)imageView
                     fitSize:(CGSize)size
                cornerRadius:(CGFloat)radius
                 placeholder:(UIImage *)placeholder
                  completion:(void (^)(UIImage *image))completion;

+ (UIImage *)placeholderImageWithSize:(CGSize)size;

+ (void)prefetchImageAtURLString:(NSString *)urlString;

@end
