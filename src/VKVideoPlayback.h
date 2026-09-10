#import <UIKit/UIKit.h>
@class VKVideo;
@interface VKVideoPlayback : NSObject
+ (void)playVideo:(VKVideo *)video from:(UIViewController *)controller;
@end
