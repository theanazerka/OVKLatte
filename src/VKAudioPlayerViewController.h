#import <UIKit/UIKit.h>
#import "VKAudio.h"

@interface VKAudioPlayerViewController : UIViewController

+ (instancetype)sharedController;

- (void)presentFromViewController:(UIViewController *)parent;

@end
