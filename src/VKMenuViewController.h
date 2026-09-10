#import <UIKit/UIKit.h>

@class VKMenuViewController;

// Разделы бокового меню — порядок ровно как в оригинальном клиенте ВК для iOS 6.
typedef enum {
    VKMenuItemNone = -1,
    VKMenuItemNews = 0,
    VKMenuItemAnswers,
    VKMenuItemMessages,
    VKMenuItemFriends,
    VKMenuItemGroups,
    VKMenuItemPhotos,
    VKMenuItemVideos,
    VKMenuItemAudio,
    VKMenuItemGames,
    VKMenuItemNotes,
    VKMenuItemBookmarks,
    VKMenuItemSettings,
    VKMenuItemSwapOVK,   // переключение ВК <-> OpenVK (не раздел, а действие)
    VKMenuItemCount
} VKMenuItem;

// Ширина сайдбара в оригинале — 276pt (замерено по скриншоту iPhone 5).
extern const CGFloat VKMenuWidth;

@protocol VKMenuDelegate <NSObject>
- (void)menu:(VKMenuViewController *)menu didSelectItem:(VKMenuItem)item;
@optional
// Тап по шапке с аватаром — «Моя страница».
- (void)menuDidSelectProfile:(VKMenuViewController *)menu;
// Серая кнопка-камера справа в шапке.
- (void)menuDidRequestCamera:(VKMenuViewController *)menu;
// Тап по строке SwapToOVK — переключить клиент на другой бэкенд.
- (void)menuDidRequestBackendSwap:(VKMenuViewController *)menu;
// Запрос из строки поиска в шапке.
- (void)menu:(VKMenuViewController *)menu didSubmitSearch:(NSString *)query;
- (void)menu:(VKMenuViewController *)menu didSelectInstanceHost:(NSString *)host;
@end

// Боковое меню как в оригинальном VK для iOS 6: поиск, компактная шапка
// профиля и тёмный список разделов с серыми бейджами-счётчиками.
@interface VKMenuViewController : UIViewController
@property (nonatomic, weak) id<VKMenuDelegate> delegate;
@property (nonatomic, assign) VKMenuItem selectedItem;
// Перестроить шапку (имя/аватар) после обновления данных пользователя.
- (void)refreshHeader;
// Подтянуть счётчики для бейджей (account.getCounters).
- (void)refreshCounters;
// Перерисовать список разделов (напр. после смены бэкенда).
- (void)reloadSections;
// Очистить строку поиска после перехода на экран результатов.
- (void)clearSearchText;
@end
