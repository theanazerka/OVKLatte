#import <UIKit/UIKit.h>

// Базовый контроллер контента: добавляет кнопку-гамбургер слева в навбаре,
// которая открывает боковое меню APLSlideMenu, а также общие состояния
// загрузки / пустого экрана / ошибки для экранов, работающих по VK API.
@interface VKBaseContentController : UIViewController
// Добавить левую кнопку-гамбургер (вызывается автоматически в viewDidLoad).
- (void)installMenuButton;

// Показать/скрыть индикатор загрузки по центру.
- (void)showLoading:(BOOL)show;
// Показать сообщение по центру (ошибка/пустой экран). nil — скрыть.
- (void)showMessage:(NSString *)message;
@end
