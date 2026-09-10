#import <UIKit/UIKit.h>

// Рассылается после успешной wall.post — стена перезагружается.
extern NSString *const VKWallDidPostNotification;

// Экран новой записи: текст + прикреплённая фотография с подписью.
// photoMode == YES — сразу спрашиваем, откуда взять фото (камера/галерея),
// а текст подписывается к снимку.
@interface VKWallPostViewController : UIViewController
- (id)initWithOwnerId:(long long)ownerId photoMode:(BOOL)photoMode;
@end
