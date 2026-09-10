#import <UIKit/UIKit.h>

// Полноэкранный просмотрщик фото с зумом (iOS 6, UIScrollView).
@interface VKPhotoViewController : UIViewController
- (id)initWithImage:(UIImage *)image url:(NSString *)url;
@end
