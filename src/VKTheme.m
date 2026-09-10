#import "VKTheme.h"
#import "VKBackend.h"
#import "VKSettings.h"
#import <QuartzCore/QuartzCore.h>

static inline UIColor *VKRGB(int r, int g, int b) {
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

@implementation VKTheme

+ (UIColor *)navBarColor          { return [VKSettings shared].darkTheme ? VKRGB(61, 47, 76) : VKRGB(82, 129, 177); }
+ (UIColor *)menuBackgroundColor  { return VKRGB(43, 72, 112); }    // #2B4870
+ (UIColor *)menuSeparatorColor   { return VKRGB(58, 90, 133); }    // #3A5A85
+ (UIColor *)contentBackgroundColor {
    if (![VKSettings shared].darkTheme) return VKRGB(235, 238, 242);
    UIImage *image = [UIImage imageNamed:@"dark_theme_background"];
    return image ? [UIColor colorWithPatternImage:image] : VKRGB(16, 12, 26);
}
+ (UIColor *)cardColor            { return [VKSettings shared].darkTheme ? VKRGB(29, 23, 40) : [UIColor whiteColor]; }
+ (UIColor *)primaryTextColor     { return [VKSettings shared].darkTheme ? VKRGB(244, 240, 248) : VKRGB(26, 26, 26); }
+ (UIColor *)linkColor            { return [VKSettings shared].darkTheme ? VKRGB(181, 137, 241) : VKRGB(44, 89, 137); }
+ (UIColor *)secondaryTextColor   { return [VKSettings shared].darkTheme ? VKRGB(180, 168, 194) : VKRGB(147, 158, 173); }
+ (UIColor *)separatorColor       { return [VKSettings shared].darkTheme ? VKRGB(66, 53, 83) : [UIColor colorWithWhite:0.86 alpha:1.0]; }

// Во ВК нажатая строка сайдбара синяя, в OpenVK — серая.
+ (UIColor *)menuSelectionColor {
    return VKRGB(45, 110, 195);
}

+ (UIColor *)menuSelectionShadowColor {
    return [UIColor colorWithRed:0.07 green:0.24 blue:0.45 alpha:0.6];
}

// Светимость сохраняем, цвет убираем: синий градиент превращается в серый.
+ (UIImage *)grayscaleImageNamed:(NSString *)name {
    if (!name.length) return nil;
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    UIImage *cached = [cache objectForKey:name];
    if (cached) return cached;

    UIImage *src = [UIImage imageNamed:name];
    if (!src) return nil;
    CGRect r = CGRectMake(0.0, 0.0, src.size.width, src.size.height);
    UIGraphicsBeginImageContextWithOptions(src.size, NO, src.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [src drawInRect:r];
    CGContextSetBlendMode(ctx, kCGBlendModeColor);
    [[UIColor colorWithWhite:0.5 alpha:1.0] setFill];
    CGContextFillRect(ctx, r);
    // Возвращаем исходную альфу (у бейджа она есть).
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    [src drawInRect:r];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (out) [cache setObject:out forKey:name];
    return out;
}

+ (void)styleNavigationBar:(UINavigationBar *)bar {
    if (!bar) return;
    bar.tintColor = [self navBarColor];
    UIImage *headerBg = [VKSettings shared].darkTheme ? [UIImage imageNamed:@"dark_theme_header"] : [UIImage imageNamed:@"header"];
    if (!headerBg && ![VKSettings shared].darkTheme) headerBg = [UIImage imageNamed:@"blue_header"];
    if (headerBg) {
        [bar setBackgroundImage:headerBg forBarMetrics:UIBarMetricsDefault];
    } else {
        [bar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    }
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
        [UIColor whiteColor], UITextAttributeTextColor,
        [UIColor colorWithWhite:0.0 alpha:0.4], UITextAttributeTextShadowColor,
        [NSValue valueWithUIOffset:UIOffsetMake(0, -1)], UITextAttributeTextShadowOffset,
        [UIFont boldSystemFontOfSize:18.0], UITextAttributeFont,
        nil];
    [bar setTitleTextAttributes:attrs];
}

+ (UIImage *)hamburgerIconWithColor:(UIColor *)color {
    CGSize size = CGSizeMake(22, 18);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGFloat barHeight = 2.5;
    CGFloat gap = (size.height - barHeight * 3) / 2.0;
    for (int i = 0; i < 3; i++) {
        CGRect r = CGRectMake(0, i * (barHeight + gap), size.width, barHeight);
        CGContextFillRect(ctx, r);
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)menuCameraButtonHighlighted:(BOOL)highlighted {
    CGSize size = CGSizeMake(40.0, 28.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // Тело кнопки: скруглённый прямоугольник с вертикальным градиентом.
    CGRect body = CGRectMake(0.5, 0.5, size.width - 1.0, size.height - 1.0);
    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:4.0];
    CGContextSaveGState(ctx);
    [shape addClip];
    CGFloat k = highlighted ? 0.78 : 1.0;
    CGFloat comps[8] = { 0.478 * k, 0.510 * k, 0.545 * k, 1.0,
                         0.337 * k, 0.373 * k, 0.416 * k, 1.0 };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
    CGContextDrawLinearGradient(ctx, grad, CGPointZero, CGPointMake(0, size.height), 0);
    CGGradientRelease(grad);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);

    [VKRGB(30, 36, 44) setStroke];
    shape.lineWidth = 1.0;
    [shape stroke];

    // Глиф камеры: корпус, «горбик» видоискателя и объектив.
    UIColor *glyph = VKRGB(230, 235, 240);
    [glyph setFill];
    CGRect cam = CGRectMake(12.0, 10.0, 16.0, 11.0);
    [[UIBezierPath bezierPathWithRoundedRect:cam cornerRadius:2.0] fill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(16.0, 7.0, 7.0, 4.0) cornerRadius:1.5] fill];
    [VKRGB(70, 78, 88) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(16.5, 12.0, 7.0, 7.0)] fill];
    [glyph setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(18.0, 13.5, 4.0, 4.0)] fill];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                     background:(UIColor *)bg {
    static NSCache *s_initialsCache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s_initialsCache = [[NSCache alloc] init];
        s_initialsCache.countLimit = 100;
    });

    NSString *key = [NSString stringWithFormat:@"%@_%d_%ld", initials ?: @"", (int)size, (long)bg.hash];
    UIImage *cached = [s_initialsCache objectForKey:key];
    if (cached) return cached;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    // Общий стиль Latte: квадратные аватары без скругления.
    CGFloat radius = 0.0;
    CGRect rect = CGRectMake(0, 0, size, size);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
    [bg set];
    [path fill];

    // Инициалы по центру.
    UIFont *font = [UIFont boldSystemFontOfSize:size * 0.4];
    NSString *text = initials ? initials : @"";
    CGSize textSize = [text sizeWithFont:font];
    CGRect textRect = CGRectMake((size - textSize.width) / 2.0,
                                 (size - textSize.height) / 2.0,
                                 textSize.width, textSize.height);
    [[UIColor whiteColor] set];
    [text drawInRect:textRect withFont:font];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) [s_initialsCache setObject:img forKey:key];
    return img;
}

@end
