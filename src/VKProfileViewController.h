#import "VKBaseContentController.h"

// Страница пользователя или паблика — как в оригинальном клиенте ВК для iOS 6:
// тёмный блок с аватаром, счётчиками-плитками и кнопками действий, ниже стена.
// userId == 0 — «Моя страница» (id берётся из сессии), отрицательный id — группа.
@interface VKProfileViewController : VKBaseContentController
- (id)initWithUserId:(long long)userId name:(NSString *)name;
@end
