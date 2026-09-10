#import <UIKit/UIKit.h>
#import "VKAudio.h"

@interface VKAudioCell : UITableViewCell

@property (nonatomic, strong) VKAudio *audio;
@property (nonatomic, copy) void (^onPlayTap)(void);
@property (nonatomic, copy) void (^onAddTap)(void);

+ (CGFloat)rowHeight;

- (void)updatePlayingState;

@end
