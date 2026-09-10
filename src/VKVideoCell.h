#import <UIKit/UIKit.h>
#import "VKVideo.h"

@interface VKVideoCell : UITableViewCell

@property (nonatomic, strong) VKVideo *video;

+ (CGFloat)rowHeight;

@end
