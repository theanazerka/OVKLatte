#import <UIKit/UIKit.h>

// Централизованная тема "как в оригинальном VK" для iOS 6.
// Цвета подобраны под классический клиент ВКонтакте 2013 года.
@interface VKTheme : NSObject

// Синий цвет навбара ВК (~ #5281B1).
+ (UIColor *)navBarColor;
// Тёмно-синий фон бокового меню (~ #2B4870).
+ (UIColor *)menuBackgroundColor;
// Подсветка выбранной строки меню (в режиме OpenVK — серая).
+ (UIColor *)menuSelectionColor;
// Цвет тени текста выбранной строки меню.
+ (UIColor *)menuSelectionShadowColor;
// Разделитель в меню.
+ (UIColor *)menuSeparatorColor;
// Фон ленты/таблиц контента (~ #EBEEF2).
+ (UIColor *)contentBackgroundColor;
// Основной синий для ссылок/имён.
+ (UIColor *)linkColor;
// Вторичный серый текст.
+ (UIColor *)secondaryTextColor;
// Цвет карточек/строк и основной цвет текста с учётом темы.
+ (UIColor *)cardColor;
+ (UIColor *)primaryTextColor;
+ (UIColor *)separatorColor;

// Применяет фирменный стиль ВК к навбару.
+ (void)styleNavigationBar:(UINavigationBar *)bar;

// Иконка-гамбургер (3 полоски) заданного цвета.
+ (UIImage *)hamburgerIconWithColor:(UIColor *)color;

// Серая кнопка-камера из шапки сайдбара (в наборе ассетов её нет — рисуем).
+ (UIImage *)menuCameraButtonHighlighted:(BOOL)highlighted;

// Обесцвеченная копия картинки (светимость сохраняется) — синие ассеты ВК
// становятся серыми для режима OpenVK. Результат кэшируется по имени.
+ (UIImage *)grayscaleImageNamed:(NSString *)name;

// Круглый placeholder-аватар с инициалами.
+ (UIImage *)avatarWithInitials:(NSString *)initials
                           size:(CGFloat)size
                     background:(UIColor *)bg;

@end
