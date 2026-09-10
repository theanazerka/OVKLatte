#import <UIKit/UIKit.h>

// Экран переписки: история сообщений + отправка (messages.getHistory / messages.send).
@interface VKChatViewController : UIViewController
- (id)initWithPeerId:(long long)peerId title:(NSString *)title;
- (id)initWithPeerId:(long long)peerId title:(NSString *)title photo:(NSString *)photo;
@end
