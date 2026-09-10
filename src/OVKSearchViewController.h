#import "VKBaseContentController.h"

// Поиск пользователей и сообществ через users.search / groups.search.
@interface OVKSearchViewController : VKBaseContentController
- (id)initWithQuery:(NSString *)query;
@end
