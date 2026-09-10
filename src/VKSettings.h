#import <UIKit/UIKit.h>

// Рассылается после изменения любой настройки: экраны перечитывают значения
// (лента — шрифт/количество записей, контейнер меню — поддержку жестов).
extern NSString *const VKSettingsDidChangeNotification;

// Пользовательские настройки клиента. Хранятся в NSUserDefaults, значения
// по умолчанию регистрируются в init — читать можно сразу после старта.
@interface VKSettings : NSObject

+ (instancetype)shared;

// Грузить картинки из сети. NO — режим экономии трафика: аватары и фото
// остаются заглушками, но то, что уже в кэше, продолжаем показывать.
@property (nonatomic, assign) BOOL loadImages;
// Показывать фото-вложения в записях ленты (влияет и на высоту ячейки).
@property (nonatomic, assign) BOOL showFeedPhotos;
// Размер основного текста записи, pt (13 / 14 / 16).
@property (nonatomic, assign) CGFloat feedFontSize;
// Сколько записей запрашивать у newsfeed.get (20 / 40 / 80).
@property (nonatomic, assign) NSInteger feedCount;
// Открывать боковое меню свайпом по контенту.
@property (nonatomic, assign) BOOL swipeToOpenMenu;
// Тёмное оформление клиента. NO — классический светлый iOS 6.
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, assign) BOOL showSidebarPlayer;
@property (nonatomic, copy) NSString *preferredVideoQuality;
// Подпись устройства, которую OpenVK сохраняет как название клиента при входе.
@property (nonatomic, assign) BOOL postAsAndroid;

// Вернуть все настройки к значениям по умолчанию.
- (void)resetToDefaults;

@end
