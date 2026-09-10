#import <UIKit/UIKit.h>
#import "VKVideo.h"

@interface VKVideoPlayerViewController : UIViewController

@property (nonatomic, strong) VKVideo *video;

- (id)initWithVideo:(VKVideo *)video;
- (id)initWithVideoId:(long long)videoId ownerId:(long long)ownerId;

@end
