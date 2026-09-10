#import <Foundation/Foundation.h>

// Хранит токен и данные текущего пользователя между запусками.
// ВНИМАНИЕ: токен лежит в NSUserDefaults (не защищено). Для боевого
// приложения перенести в Keychain — это TODO.
@interface VKSession : NSObject

+ (instancetype)shared;

@property (nonatomic, copy) NSString *accessToken;
// Отдельный токен только для messages.* (напр. Маруся). Может быть nil.
@property (nonatomic, copy) NSString *messagesToken;
@property (nonatomic, assign) long long userId;
@property (nonatomic, copy) NSString *userName;
@property (nonatomic, copy) NSString *userPhoto; // URL аватара (photo_100)

// VK ID silent_token (временный, требует обмена; НЕ равен accessToken).
@property (nonatomic, copy) NSString *silentToken;
@property (nonatomic, copy) NSString *silentHash;

// Есть сохранённая авторизация OpenVK.
- (BOOL)hasIdentity;
- (BOOL)isAuthorized;
- (void)save;
- (void)clear;
// Перечитать сессию из NSUserDefaults (после смены бэкенда — см. VKBackend).
- (void)reload;

@end
