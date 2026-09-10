#import <UIKit/UIKit.h>

// Статус «в сети» для списка диалогов и шапки чата.
// online/last_seen приходят в users.get и в extended-ответах messages.*,
// поэтому формат подписи держим в одном месте.
@interface VKPresence : NSObject
// «в сети» / «в сети (моб.)» / «заходил(а) 5 минут назад» / «» если данных нет.
+ (NSString *)textForOnline:(BOOL)online
                     mobile:(BOOL)mobile
                   lastSeen:(NSTimeInterval)lastSeen
                     female:(BOOL)female;
// Зелёная точка ВК: Online.png (6x6) или online_mobile.png (8x12).
+ (UIImage *)dotForOnline:(BOOL)online mobile:(BOOL)mobile;
@end
