#import "VKBaseContentController.h"

// Просьба выйти из аккаунта: настройки уже спросили подтверждение,
// делегат приложения просто выполняет выход.
extern NSString *const VKRequestLogoutNotification;
// Данные текущего пользователя обновились — сайдбару нужно перерисовать шапку.
extern NSString *const VKUserDidUpdateNotification;

// Экран «Настройки»: аккаунт, параметры ленты и картинок, кэш, о программе.
@interface VKSettingsViewController : VKBaseContentController
@end
