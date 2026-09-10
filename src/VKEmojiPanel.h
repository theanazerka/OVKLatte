#import <UIKit/UIKit.h>

@class VKEmojiPanel;

@protocol VKEmojiPanelDelegate <NSObject>
- (void)emojiPanel:(VKEmojiPanel *)panel didPickEmoji:(NSString *)emoji;
@optional
// Тап по стикеру: id для messages.send и картинка для локального превью.
- (void)emojiPanel:(VKEmojiPanel *)panel
   didPickStickerId:(long long)stickerId
         previewURL:(NSString *)previewURL;
// Стрелка «удалить» справа внизу.
- (void)emojiPanelDidTapBackspace:(VKEmojiPanel *)panel;
// Кнопка «АБВ» — вернуть обычную клавиатуру.
- (void)emojiPanelDidRequestKeyboard:(VKEmojiPanel *)panel;
@end

// Панель выбора смайликов и стикеров для инпутбара: вкладка «Смайлы» —
// страницы-сетки 8x4 из Apple Color Emoji, вкладка «Стикеры» — купленные
// наборы пользователя (store.getProducts). Ставится полю как inputView,
// поэтому высота совпадает с портретной клавиатурой iOS 6.
@interface VKEmojiPanel : UIView
@property (nonatomic, weak) id<VKEmojiPanelDelegate> pickerDelegate;
// Высота панели (как у системной клавиатуры в портрете) — 216pt.
+ (CGFloat)panelHeight;
@end
