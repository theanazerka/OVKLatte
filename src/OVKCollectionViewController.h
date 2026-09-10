#import "VKBaseContentController.h"
// Native API-backed menu lists. ownerId 0 means the signed-in user.
@interface OVKCollectionViewController : VKBaseContentController
- (id)initWithSection:(NSString *)section ownerId:(long long)ownerId;
@property (nonatomic, assign) long long albumId;
@end
