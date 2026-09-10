#import "OVKAlignedButton.h"
@implementation OVKAlignedButton
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect area = UIEdgeInsetsInsetRect(self.bounds, UIEdgeInsetsMake(0, 6, 0, 6));
    UIImage *image = self.currentImage;
    NSString *title = self.currentTitle;
    CGFloat imageH = image ? MIN(20, area.size.height - 6) : 0;
    CGFloat imageW = image && image.size.height > 0 ? MIN(24, imageH * image.size.width / image.size.height) : 0;
    CGFloat gap = image && title.length ? 5 : 0;
    CGFloat titleW = title.length ? MIN(ceilf([title sizeWithFont:self.titleLabel.font].width), MAX(0, area.size.width - imageW - gap)) : 0;
    CGFloat x = roundf(CGRectGetMidX(area) - (imageW + gap + titleW) / 2);
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = CGRectMake(x, roundf(CGRectGetMidY(area) - imageH / 2), imageW, imageH);
    self.titleLabel.frame = CGRectMake(x + imageW + gap, area.origin.y, titleW, area.size.height);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumFontSize = 10;
}
@end
