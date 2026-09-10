#import <UIKit/UIKit.h>

// Простой асинхронный загрузчик картинок по URL с памятью-кэшем (iOS 6).
@interface VKImageLoader : NSObject

+ (instancetype)shared;

// Загружает картинку по URL; completion вызывается на главном потоке.
// Если картинка уже в кэше — completion вызывается синхронно.
- (void)loadURL:(NSString *)urlString completion:(void (^)(UIImage *image))completion;

- (UIImage *)cachedImageForURL:(NSString *)urlString;
- (void)setCachedImage:(UIImage *)image forURL:(NSString *)urlString;

// Статистика кэша для экрана настроек (учитываются только живые объекты:
// то, что NSCache уже выкинул под давлением памяти, не считаем).
- (NSUInteger)cachedImageCount;
- (unsigned long long)cachedImageBytes;

// Выбросить всё из кэша.
- (void)clearCache;

@end
