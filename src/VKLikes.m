#import "VKLikes.h"
#import "VKPostCell.h"
#import "VKAPI.h"

@implementation VKLikes
+ (void)togglePost:(VKPost *)post changed:(void (^)(void))changed {
    if (!post || !post.postId || post.likePending) return;
    BOOL desired = !post.liked;
    post.likePending = YES;
    [[VKAPI shared] callMethod:(desired ? @"likes.add" : @"likes.delete")
                        params:@{@"type": @"post", @"owner_id": @(post.ownerId), @"item_id": @(post.postId)}
                    completion:^(id response, NSError *error) {
        post.likePending = NO;
        if (error) {
            [[[UIAlertView alloc] initWithTitle:@"Не удалось изменить отметку" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            return;
        }
        post.liked = desired;
        if ([response isKindOfClass:[NSDictionary class]] && [[response objectForKey:@"likes"] respondsToSelector:@selector(integerValue)]) post.likes = [[response objectForKey:@"likes"] integerValue];
        else post.likes = MAX(0, post.likes + (desired ? 1 : -1));
        if (changed) changed();
    }];
}
@end
