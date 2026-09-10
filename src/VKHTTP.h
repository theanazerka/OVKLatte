#import <Foundation/Foundation.h>

// Делегат-раннер HTTP-запросов на NSURLConnection (iOS 6) с ПРОВЕРКОЙ
// доверия против вшитых в приложение корневых сертификатов (Resources/roots/*.der).
//
// Зачем: под TLSFix современное рукопожатие делает сам твик, но финальное
// решение о доверии он отдаёт приложению (как при SSL pinning). Мы добавляем
// вшитые корни как anchor-сертификаты, поэтому соединение проходит даже без
// установленного на устройстве профиля с корнями (tlsroot.litten.ca).
@interface VKHTTP : NSObject

// GET/произвольный запрос. completion — на главном потоке.
+ (void)sendRequest:(NSURLRequest *)request
         completion:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completion;

@end
