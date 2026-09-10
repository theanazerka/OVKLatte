#import "OVKListCell.h"
#import "VKTheme.h"
#import <QuartzCore/QuartzCore.h>
@implementation OVKListCell
- (void)layoutSubviews {
    [super layoutSubviews];
    self.backgroundColor = [VKTheme contentBackgroundColor];
    self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
    CGFloat w = self.contentView.bounds.size.width;
    self.imageView.frame = CGRectMake(10, (self.bounds.size.height - 50) / 2, 50, 50);
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    self.imageView.layer.cornerRadius = 0.0;
    CGFloat left = self.imageView.image ? 70 : 12;
    self.textLabel.frame = CGRectMake(left, self.detailTextLabel.text.length ? 12 : roundf((self.bounds.size.height - 20) / 2), MAX(0, w - left - 12), 20);
    self.detailTextLabel.frame = CGRectMake(left, 34, MAX(0, w - left - 12), 30);
    self.textLabel.textColor = [VKTheme linkColor];
    self.textLabel.backgroundColor = self.detailTextLabel.backgroundColor = [UIColor clearColor];
    self.detailTextLabel.numberOfLines = 2;
}
@end
