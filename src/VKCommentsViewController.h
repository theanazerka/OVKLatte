#import <UIKit/UIKit.h>

// Комментарии к записи на стене: список + поле для своего комментария.
// title — «Комментарии» с автором записи в подзаголовке навбара не рисуем,
// хватает счётчика в заголовке.
@interface VKCommentsViewController : UIViewController
- (id)initWithOwnerId:(long long)ownerId postId:(long long)postId;
@end
