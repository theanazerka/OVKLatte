#import <UIKit/UIKit.h>

typedef void (^VKUploadCompletion)(NSString *attachment, NSError *error);

@interface VKUploader : NSObject
+ (void)uploadWallPhoto:(UIImage *)image
                ownerId:(long long)ownerId
             completion:(VKUploadCompletion)completion;

+ (void)uploadMessagesPhoto:(UIImage *)image
                     peerId:(long long)peerId
                 completion:(VKUploadCompletion)completion;

@end
