#import "VKVideoCell.h"
#import "VKTheme.h"
#import "VKImageLoader.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kThumbW = 116.0;
static const CGFloat kThumbH = 68.0;
static const CGFloat kMargin = 8.0;

@interface VKVideoCell ()
@property (nonatomic, strong) UIImageView *thumbnailView;
@property (nonatomic, strong) UIView *durationBadge;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UIView *bottomLine;
@end

@implementation VKVideoCell

+ (CGFloat)rowHeight {
    return 84.0;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleGray;

        // Превью видео
        _thumbnailView = [[UIImageView alloc] initWithFrame:CGRectMake(kMargin, kMargin, kThumbW, kThumbH)];
        _thumbnailView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailView.clipsToBounds = YES;
        _thumbnailView.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];
        _thumbnailView.layer.cornerRadius = 3.0;
        _thumbnailView.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1.0].CGColor;
        _thumbnailView.layer.borderWidth = 0.5;
        [self.contentView addSubview:_thumbnailView];

        // Бейдж длительности в правом нижнем углу превью
        _durationBadge = [[UIView alloc] initWithFrame:CGRectZero];
        _durationBadge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
        _durationBadge.layer.cornerRadius = 2.0;
        _durationBadge.clipsToBounds = YES;
        [_thumbnailView addSubview:_durationBadge];

        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.backgroundColor = [UIColor clearColor];
        _durationLabel.font = [UIFont boldSystemFontOfSize:10.0];
        _durationLabel.textColor = [UIColor whiteColor];
        _durationLabel.textAlignment = NSTextAlignmentCenter;
        [_durationBadge addSubview:_durationLabel];

        // Заголовок видео (2 строки)
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        _titleLabel.textColor = [VKTheme primaryTextColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        // Автор / сообщество
        _authorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _authorLabel.backgroundColor = [UIColor clearColor];
        _authorLabel.font = [UIFont systemFontOfSize:12.0];
        _authorLabel.textColor = [VKTheme linkColor];
        _authorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_authorLabel];

        // Просмотры и дата
        _infoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _infoLabel.backgroundColor = [UIColor clearColor];
        _infoLabel.font = [UIFont systemFontOfSize:11.0];
        _infoLabel.textColor = [VKTheme secondaryTextColor];
        _infoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_infoLabel];

        // Разделитель строк
        _bottomLine = [[UIView alloc] initWithFrame:CGRectZero];
        _bottomLine.backgroundColor = [VKTheme separatorColor];
        [self.contentView addSubview:_bottomLine];
    }
    return self;
}

- (void)setVideo:(VKVideo *)video {
    _video = video;
    if (!video) return;

    self.backgroundColor = self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
    self.titleLabel.textColor = [VKTheme primaryTextColor];
    self.bottomLine.backgroundColor = [VKTheme separatorColor];

    self.titleLabel.text = video.title.length ? video.title : @"Без названия";
    self.authorLabel.text = video.authorName.length ? video.authorName : @"";

    NSMutableArray *parts = [NSMutableArray array];
    if (video.viewsString.length) [parts addObject:video.viewsString];
    if (video.timeString.length) [parts addObject:video.timeString];
    self.infoLabel.text = [parts componentsJoinedByString:@" • "];

    // Длительность
    if (video.durationString.length) {
        self.durationLabel.text = video.durationString;
        self.durationBadge.hidden = NO;
    } else {
        self.durationBadge.hidden = YES;
    }

    // Загрузка превью
    self.thumbnailView.image = [UIImage imageNamed:@"placeholder_videos"];
    if (video.photoURL.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:video.photoURL];
        if (cached) {
            self.thumbnailView.image = cached;
        } else {
            __weak typeof(self) weakSelf = self;
            [[VKImageLoader shared] loadURL:video.photoURL completion:^(UIImage *img) {
                if (img && weakSelf.video == video) {
                    weakSelf.thumbnailView.image = img;
                }
            }];
        }
    }

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;

    self.thumbnailView.frame = CGRectMake(kMargin, kMargin, kThumbW, kThumbH);

    // Длительность внутри thumbnail
    if (!self.durationBadge.hidden) {
        CGSize s = [self.durationLabel.text sizeWithFont:self.durationLabel.font];
        CGFloat bw = s.width + 6.0;
        CGFloat bh = 14.0;
        self.durationBadge.frame = CGRectMake(kThumbW - bw - 3.0, kThumbH - bh - 3.0, bw, bh);
        self.durationLabel.frame = CGRectMake(0, 0, bw, bh);
    }

    CGFloat textLeft = kMargin + kThumbW + 8.0;
    CGFloat textWidth = w - textLeft - kMargin;

    // Рассчитываем высоту заголовка (1 или 2 строки)
    CGSize titleSize = [self.titleLabel.text sizeWithFont:self.titleLabel.font
                                        constrainedToSize:CGSizeMake(textWidth, 34.0)
                                            lineBreakMode:NSLineBreakByTruncatingTail];
    CGFloat titleH = MAX(16.0, MIN(34.0, titleSize.height));
    self.titleLabel.frame = CGRectMake(textLeft, kMargin, textWidth, titleH);

    self.authorLabel.frame = CGRectMake(textLeft, kMargin + titleH + 3.0, textWidth, 15.0);
    self.infoLabel.frame = CGRectMake(textLeft, h - kMargin - 15.0, textWidth, 15.0);

    self.bottomLine.frame = CGRectMake(0, h - 0.5, w, 0.5);
}

@end
