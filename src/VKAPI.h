#import <Foundation/Foundation.h>

// Версия VK API, под которую строим запросы.
extern NSString *const VKAPIVersion;

// Блок результата: response — содержимое ключа "response" (id: NSDictionary/NSArray),
// error — сетевой либо API-ошибка (domain "VKAPI", code = error_code от ВК).
typedef void (^VKAPICompletion)(id response, NSError *error);

// Тонкий клиент к OpenVK /method/*. Работает по access_token из VKSession.
// Использует NSURLConnection (iOS 6, без NSURLSession).
@interface VKAPI : NSObject

+ (instancetype)shared;

// Вызвать метод OpenVK API. params — без access_token/v (добавляются автоматически).
- (void)callMethod:(NSString *)method
            params:(NSDictionary *)params
        completion:(VKAPICompletion)completion;

@end
