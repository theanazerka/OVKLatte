#import "VKPostCell.h"
#import "VKTheme.h"
#import "VKImageLoader.h"
#import "VKSettings.h"
#import "VKAudio.h"
#import "VKVideo.h"
#import <QuartzCore/QuartzCore.h>

@implementation VKPost
@end

static const CGFloat kPad = 10.0;     // внутренний отступ карточки
static const CGFloat kAvatar = 40.0;  // размер аватара
static const CGFloat kOriginalAvatar = 32.0;
static const CGFloat kAudioAttachmentH = 54.0;
static const CGFloat kVideoAttachmentH = 76.0;
static const CGFloat kFooterH = 44.0; // Единая высота значков, счётчиков и области нажатия.

// Размер текста записи берём из настроек (13/14/16 pt).
static UIFont *VKTextFont(void)   { return [UIFont systemFontOfSize:[VKSettings shared].feedFontSize]; }
static UIFont *VKNameFont(void)   { return [UIFont boldSystemFontOfSize:14.0]; }
static UIFont *VKTimeFont(void)   { return [UIFont systemFontOfSize:11.0]; }
static UIFont *VKFooterFont(void) { return [UIFont systemFontOfSize:12.0]; }

// 15320 -> «15.3K»: просмотров у записей бывает много, в 1/4 футера не влезает.
static NSString *VKPostShortNum(NSInteger n) {
    if (n >= 1000000) return [NSString stringWithFormat:@"%.1fM", n / 1000000.0];
    if (n >= 10000) return [NSString stringWithFormat:@"%dK", (int)(n / 1000)];
    if (n >= 1000) return [NSString stringWithFormat:@"%.1fK", n / 1000.0];
    return [NSString stringWithFormat:@"%d", (int)n];
}

// В наборе ВК 2013 года иконки просмотров нет (их тогда не было в API),
// поэтому рисуем «глаз» кодом в тон остальным подписям футера.
static UIImage *VKEyeIcon(void) {
    static UIImage *icon = nil;
    if (icon) return icon;
    CGSize size = CGSizeMake(14.0, 10.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    UIColor *grey = [UIColor colorWithWhite:0.55 alpha:1.0];
    CGContextSetStrokeColorWithColor(c, grey.CGColor);
    CGContextSetLineWidth(c, 1.0);
    CGContextMoveToPoint(c, 1.0, 5.0);
    CGContextAddQuadCurveToPoint(c, 7.0, -0.5, 13.0, 5.0);
    CGContextAddQuadCurveToPoint(c, 7.0, 10.5, 1.0, 5.0);
    CGContextStrokePath(c);
    CGContextSetFillColorWithColor(c, grey.CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(5.0, 3.0, 4.0, 4.0));
    icon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return icon;
}

@interface VKPostCell () {
    CGFloat _textHeight; // кэш высоты текста, чтобы не считать в layoutSubviews
}
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *originalHeading;
@property (nonatomic, strong) UILabel *originalBody;
@property (nonatomic, strong) UIView *quoteLine;
@property (nonatomic, strong) UIImageView *originalAvatarView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *repostLabelView;
@property (nonatomic, strong) UILabel *textLabel_;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UIButton *audioAttachmentView;
@property (nonatomic, strong) UIImageView *audioArtworkView;
@property (nonatomic, strong) UILabel *audioArtistLabel;
@property (nonatomic, strong) UILabel *audioTitleLabel;
@property (nonatomic, strong) UILabel *audioDurationLabel;
@property (nonatomic, strong) UIButton *videoAttachmentView;
@property (nonatomic, strong) UIImageView *videoPreviewView;
@property (nonatomic, strong) UIImageView *videoPlayView;
@property (nonatomic, strong) UILabel *videoTitleLabel;
@property (nonatomic, strong) UILabel *videoInfoLabel;
@property (nonatomic, strong) UIImageView *likeIcon;
@property (nonatomic, strong) UIImageView *commentIcon;
@property (nonatomic, strong) UIImageView *repostIcon;
@property (nonatomic, strong) UIImageView *viewsIcon;
@property (nonatomic, strong) UILabel *likeLabel;
@property (nonatomic, strong) UILabel *commentLabel;
@property (nonatomic, strong) UILabel *repostLabel;
@property (nonatomic, strong) UILabel *viewsLabel;
@property (nonatomic, strong) UIButton *likeButton;
@property (nonatomic, strong) UIButton *commentButton;
@property (nonatomic, strong) UIButton *repostButton;
@property (nonatomic, strong) UIView *bottomLine;
@end

@implementation VKPostCell

+ (CGFloat)textWidthForCardWidth:(CGFloat)width {
    return width - kPad * 2;
}

+ (CGFloat)photoHeightForPost:(VKPost *)post width:(CGFloat)width {
    // Фото в ленте можно отключить в настройках — тогда и места под них не даём.
    if (![VKSettings shared].showFeedPhotos) return 0.0;
    if (!post.photoURL.length || post.photoAspect <= 0.0) return 0.0;
    CGFloat photoW = [self textWidthForCardWidth:width];
    CGFloat h = photoW * post.photoAspect;
    // Ограничим слишком высокие фото.
    if (h > 420.0) h = 420.0;
    return h;
}

+ (CGFloat)attachmentHeightForPost:(VKPost *)post {
    CGFloat h = 0.0;
    if (post.audioAttachment) h += kAudioAttachmentH;
    if (post.videoAttachment) h += (h > 0.0 ? 6.0 : 0.0) + kVideoAttachmentH;
    return h;
}

+ (CGFloat)heightForPost:(VKPost *)post width:(CGFloat)width {
    CGFloat textWidth = [self textWidthForCardWidth:width];
    CGFloat y = kPad + kAvatar; // 50.0
    if (post.text.length) {
        CGSize constraint = CGSizeMake(textWidth, CGFLOAT_MAX);
        CGFloat textH = ceilf([post.text sizeWithFont:VKTextFont()
                                    constrainedToSize:constraint
                                        lineBreakMode:NSLineBreakByWordWrapping].height);
        post.cachedTextHeight = textH;
        y = 56.0 + textH;
    } else {
        post.cachedTextHeight = 0.0;
    }
    if (post.originalName.length) {
        CGFloat bodyH = ceilf([post.originalText sizeWithFont:VKTextFont() constrainedToSize:CGSizeMake(textWidth - 52, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping].height);
        y += 12 + MAX(kOriginalAvatar, 24 + bodyH);
    }
    CGFloat attachmentH = [self attachmentHeightForPost:post];
    if (attachmentH > 0.0) y += 8.0 + attachmentH;
    CGFloat photoH = [self photoHeightForPost:post width:width];
    if (photoH > 0.0) {
        y += 8.0 + photoH;
    }
    // Разделитель + блок действий (лайки/комменты) + нижний отступ
    y += 8.0 + 1.0 + kFooterH + 12.0;
    post.cachedHeight = y;
    return post.cachedHeight;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.opaque = YES;
        self.contentView.opaque = YES;

        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.backgroundColor = [VKTheme cardColor];
        _card.opaque = YES;
        [self.contentView addSubview:_card];

        _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(kPad, kPad, kAvatar, kAvatar)];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.layer.cornerRadius = 0.0;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.userInteractionEnabled = YES;
        [_avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(authorTapped)]];
        [_card addSubview:_avatarView];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = VKNameFont();
        _nameLabel.textColor = [VKTheme linkColor];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.opaque = NO;
        _nameLabel.userInteractionEnabled = YES;
        [_nameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(authorTapped)]];
        [_card addSubview:_nameLabel];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = VKTimeFont();
        _timeLabel.textColor = [VKTheme secondaryTextColor];
        _timeLabel.backgroundColor = [UIColor clearColor];
        _timeLabel.opaque = NO;
        [_card addSubview:_timeLabel];
        _repostLabelView = [[UILabel alloc] initWithFrame:CGRectZero];
        _repostLabelView.text = @"↪ Репост";
        _repostLabelView.font = [UIFont boldSystemFontOfSize:10.0];
        _repostLabelView.textColor = [VKTheme linkColor];
        _repostLabelView.backgroundColor = [VKSettings shared].darkTheme
            ? [UIColor colorWithRed:0.26 green:0.19 blue:0.35 alpha:1.0]
            : [UIColor colorWithRed:0.93 green:0.96 blue:1.0 alpha:1.0];
        _repostLabelView.textAlignment = NSTextAlignmentCenter;
        _repostLabelView.layer.cornerRadius = 3.0;
        _repostLabelView.layer.masksToBounds = YES;
        [_card addSubview:_repostLabelView];

        _textLabel_ = [[UILabel alloc] initWithFrame:CGRectZero];
        _textLabel_.font = VKTextFont();
        _textLabel_.textColor = [VKTheme primaryTextColor];
        _textLabel_.numberOfLines = 0;
        _textLabel_.lineBreakMode = NSLineBreakByWordWrapping;
        _textLabel_.backgroundColor = [UIColor clearColor];
        _textLabel_.opaque = NO;
        [_card addSubview:_textLabel_];

        _originalHeading = [[UILabel alloc] initWithFrame:CGRectZero];
        _originalHeading.font = VKNameFont(); _originalHeading.textColor = [VKTheme linkColor];
        _originalHeading.backgroundColor = [UIColor clearColor];
        _originalBody = [[UILabel alloc] initWithFrame:CGRectZero];
        _originalBody.numberOfLines = 0; _originalBody.font = VKTextFont();
        _originalBody.backgroundColor = [UIColor clearColor];
        _originalAvatarView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _originalAvatarView.contentMode = UIViewContentModeScaleAspectFill;
        _originalAvatarView.clipsToBounds = YES;
        _originalAvatarView.layer.cornerRadius = 0.0;
        _originalAvatarView.userInteractionEnabled = YES;
        [_originalAvatarView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(originalAuthorTapped)]];
        _originalHeading.userInteractionEnabled = YES;
        [_originalHeading addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(originalAuthorTapped)]];
        _quoteLine = [[UIView alloc] initWithFrame:CGRectZero];
        _quoteLine.backgroundColor = [VKTheme navBarColor];
        [_card addSubview:_quoteLine]; [_card addSubview:_originalAvatarView]; [_card addSubview:_originalHeading]; [_card addSubview:_originalBody];
        // Тонкая линия-разделитель перед строкой действий.
        _divider = [[UIView alloc] initWithFrame:CGRectZero];
        _divider.backgroundColor = [VKTheme separatorColor];
        [_card addSubview:_divider];

        // Прикреплённое фото поста.
        _photoView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _photoView.contentMode = UIViewContentModeScaleAspectFill;
        _photoView.clipsToBounds = YES;
        _photoView.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
        _photoView.userInteractionEnabled = YES;
        _photoView.layer.cornerRadius = 2.0;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(photoTapped)];
        [_photoView addGestureRecognizer:tap];
        [_card addSubview:_photoView];

        _audioAttachmentView = [UIButton buttonWithType:UIButtonTypeCustom];
        _audioAttachmentView.backgroundColor = [VKTheme contentBackgroundColor];
        [_audioAttachmentView addTarget:self action:@selector(audioTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_audioAttachmentView];
        _audioArtworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _audioArtworkView.contentMode = UIViewContentModeScaleAspectFill; _audioArtworkView.clipsToBounds = YES;
        [_audioAttachmentView addSubview:_audioArtworkView];
        _audioArtistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _audioArtistLabel.font = [UIFont boldSystemFontOfSize:13.0]; _audioArtistLabel.textColor = [VKTheme linkColor]; _audioArtistLabel.backgroundColor = [UIColor clearColor];
        [_audioAttachmentView addSubview:_audioArtistLabel];
        _audioTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _audioTitleLabel.font = [UIFont systemFontOfSize:12.0]; _audioTitleLabel.textColor = [VKTheme primaryTextColor]; _audioTitleLabel.backgroundColor = [UIColor clearColor];
        [_audioAttachmentView addSubview:_audioTitleLabel];
        _audioDurationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _audioDurationLabel.font = [UIFont systemFontOfSize:11.0]; _audioDurationLabel.textColor = [VKTheme secondaryTextColor]; _audioDurationLabel.textAlignment = NSTextAlignmentRight; _audioDurationLabel.backgroundColor = [UIColor clearColor];
        [_audioAttachmentView addSubview:_audioDurationLabel];

        _videoAttachmentView = [UIButton buttonWithType:UIButtonTypeCustom];
        _videoAttachmentView.backgroundColor = [VKTheme contentBackgroundColor];
        [_videoAttachmentView addTarget:self action:@selector(videoTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_videoAttachmentView];
        _videoPreviewView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _videoPreviewView.contentMode = UIViewContentModeScaleAspectFill; _videoPreviewView.clipsToBounds = YES;
        [_videoAttachmentView addSubview:_videoPreviewView];
        _videoPlayView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"video_can_play"]];
        _videoPlayView.contentMode = UIViewContentModeScaleAspectFit;
        [_videoAttachmentView addSubview:_videoPlayView];
        _videoTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _videoTitleLabel.numberOfLines = 2; _videoTitleLabel.font = [UIFont boldSystemFontOfSize:13.0]; _videoTitleLabel.textColor = [VKTheme primaryTextColor]; _videoTitleLabel.backgroundColor = [UIColor clearColor];
        [_videoAttachmentView addSubview:_videoTitleLabel];
        _videoInfoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _videoInfoLabel.font = [UIFont systemFontOfSize:11.0]; _videoInfoLabel.textColor = [VKTheme secondaryTextColor]; _videoInfoLabel.backgroundColor = [UIColor clearColor];
        [_videoAttachmentView addSubview:_videoInfoLabel];

        _likeIcon = [self makeIcon:@"post_btn_like"];
        _commentIcon = [self makeIcon:@"post_btn_comment"];
        _repostIcon = [self makeIcon:@"post_btn_repost"];
        _viewsIcon = [[UIImageView alloc] initWithImage:VKEyeIcon()];
        _viewsIcon.contentMode = UIViewContentModeCenter;
        [_card addSubview:_viewsIcon];
        _likeLabel = [self makeActionLabel];
        _commentLabel = [self makeActionLabel];
        _repostLabel = [self makeActionLabel];
        _viewsLabel = [self makeActionLabel];

        _likeButton = [self makeActionButton:@selector(likeTapped)];
        _commentButton = [self makeActionButton:@selector(commentTapped)];
        _repostButton = [self makeActionButton:@selector(repostTapped)];

        // Тонкий разделитель между постами (посты склеены вместе)
        _bottomLine = [[UIView alloc] initWithFrame:CGRectZero];
        _bottomLine.backgroundColor = [VKTheme separatorColor];
        [_card addSubview:_bottomLine];
    }
    return self;
}

- (void)originalAuthorTapped { if (self.onOriginalAuthorTap) self.onOriginalAuthorTap(self.post); }

- (UIButton *)makeActionButton:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.card addSubview:b];
    return b;
}

- (void)likeTapped {
    if (self.onLikeTap && self.post) self.onLikeTap(self.post);
}

- (void)commentTapped {
    if (self.onCommentTap && self.post) self.onCommentTap(self.post);
}

- (void)repostTapped {
    if (self.onRepostTap && self.post) self.onRepostTap(self.post);
}

- (void)audioTapped { if (self.onAudioTap && self.post.audioAttachment) self.onAudioTap(self.post); }
- (void)videoTapped { if (self.onVideoTap && self.post.videoAttachment) self.onVideoTap(self.post); }

- (UIImageView *)makeIcon:(NSString *)name {
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:name]];
    iv.contentMode = UIViewContentModeCenter;
    [self.card addSubview:iv];
    return iv;
}

- (void)photoTapped {
    if (self.onPhotoTap && self.post.photoURL.length) {
        self.onPhotoTap(self.post, self.photoView.image);
    }
}

- (void)authorTapped {
    if (self.onAuthorTap && self.post.authorId != 0) {
        self.onAuthorTap(self.post);
    }
}

- (UILabel *)makeActionLabel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = VKFooterFont();
    l.textColor = [VKTheme secondaryTextColor];
    l.backgroundColor = [UIColor clearColor];
    l.opaque = NO;
    [self.card addSubview:l];
    return l;
}

- (void)setPost:(VKPost *)post {
    _post = post;
    self.backgroundColor = [VKTheme contentBackgroundColor];
    self.card.backgroundColor = [VKTheme cardColor];
    self.textLabel_.textColor = [VKTheme primaryTextColor];
    self.divider.backgroundColor = self.bottomLine.backgroundColor = [VKTheme separatorColor];
    self.audioAttachmentView.backgroundColor = self.videoAttachmentView.backgroundColor = [VKTheme contentBackgroundColor];
    self.nameLabel.text = post.authorName;
    self.timeLabel.text = post.timeText;
    self.repostLabelView.hidden = !post.repost;
    self.textLabel_.text = post.text;
    [self refreshCounters];

    self.avatarView.image = post.avatar;
    NSString *url = post.avatarURL;
    if (url.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) {
            self.avatarView.image = cached;
        } else {
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                if (image && self.post == post) self.avatarView.image = image;
            }];
        }
    }

    self.photoView.image = nil;
    NSString *purl = post.photoURL;
    if (purl.length && [VKSettings shared].showFeedPhotos) {
        self.photoView.hidden = NO;
        UIImage *pc = [[VKImageLoader shared] cachedImageForURL:purl];
        if (pc) {
            self.photoView.image = pc;
        } else {
            [[VKImageLoader shared] loadURL:purl completion:^(UIImage *image) {
                if (image && self.post == post) self.photoView.image = image;
            }];
        }
    } else {
        self.photoView.hidden = YES;
    }

    VKAudio *audio = post.audioAttachment;
    self.audioAttachmentView.hidden = !audio;
    if (audio) {
        self.audioArtistLabel.text = audio.artist;
        self.audioTitleLabel.text = audio.title;
        self.audioDurationLabel.text = audio.durationString;
        self.audioArtworkView.image = [UIImage imageNamed:@"audio_preview_placeholder"];
        NSString *artworkURL = audio.artworkURL;
        if (artworkURL.length) [[VKImageLoader shared] loadURL:artworkURL completion:^(UIImage *image) {
            if (image && self.post == post && self.post.audioAttachment == audio) self.audioArtworkView.image = image;
        }];
    }
    VKVideo *video = post.videoAttachment;
    self.videoAttachmentView.hidden = !video;
    if (video) {
        self.videoTitleLabel.text = video.title;
        self.videoInfoLabel.text = video.durationString.length ? [NSString stringWithFormat:@"%@ · %@", video.authorName, video.durationString] : video.authorName;
        self.videoPreviewView.image = [UIImage imageNamed:@"placeholder_videos"];
        NSString *previewURL = video.photoURL;
        if (previewURL.length) [[VKImageLoader shared] loadURL:previewURL completion:^(UIImage *image) {
            if (image && self.post == post && self.post.videoAttachment == video) self.videoPreviewView.image = image;
        }];
    }

    NSString *originalInitial = post.originalName.length ? [[post.originalName substringToIndex:1] uppercaseString] : @"?";
    self.originalAvatarView.image = [VKTheme avatarWithInitials:originalInitial size:kOriginalAvatar background:[VKTheme navBarColor]];
    NSString *originalURL = post.originalAvatarURL;
    if (originalURL.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:originalURL];
        if (cached) {
            self.originalAvatarView.image = cached;
        } else {
            [[VKImageLoader shared] loadURL:originalURL completion:^(UIImage *image) {
                if (image && self.post == post && [self.post.originalAvatarURL isEqualToString:originalURL]) self.originalAvatarView.image = image;
            }];
        }
    }

    self.textLabel_.font = VKTextFont();
    if (post.cachedTextHeight > 0.0) {
        _textHeight = post.cachedTextHeight;
    } else {
        CGFloat textWidth = [VKPostCell textWidthForCardWidth:self.contentView.bounds.size.width];
        _textHeight = post.text.length ? ceilf([post.text sizeWithFont:VKTextFont()
                            constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                lineBreakMode:NSLineBreakByWordWrapping].height) : 0.0;
        post.cachedTextHeight = _textHeight;
    }
    [self setNeedsLayout];
}

- (void)refreshCounters {
    VKPost *post = self.post;
    self.likeLabel.text = VKPostShortNum(post.likes);
    self.commentLabel.text = VKPostShortNum(post.comments);
    self.repostLabel.text = VKPostShortNum(post.reposts);
    self.viewsLabel.text = post.views > 0 ? VKPostShortNum(post.views) : @"";

    UIImage *like = [UIImage imageNamed:(post.liked ? @"post_btn_blue_like_in" : @"post_btn_like")];
    if (like) self.likeIcon.image = like;
    self.likeLabel.textColor = post.liked ? [VKTheme linkColor] : [VKTheme secondaryTextColor];

    BOOL hasViews = (post.views > 0);
    self.viewsIcon.hidden = !hasViews;
    self.viewsLabel.hidden = !hasViews;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    self.card.frame = CGRectMake(0, 0, width, h - 8);

    CGFloat headerX = kPad + kAvatar + 10.0;
    CGFloat headerW = width - headerX - kPad;
    self.nameLabel.frame = CGRectMake(headerX, kPad + 2.0, MAX(0, headerW - (self.post.repost ? 65 : 0)), 20.0);
    self.timeLabel.frame = CGRectMake(headerX, kPad + 23.0, headerW, 14.0);
    self.repostLabelView.frame = CGRectMake(width - kPad - 57.0, kPad + 4.0, 57.0, 17.0);

    CGFloat textWidth = [VKPostCell textWidthForCardWidth:width];
    _textHeight = self.post.text.length ? ceilf([self.post.text sizeWithFont:VKTextFont() constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping].height) : 0;
    CGFloat y = kPad + kAvatar; // 50.0

    if (_textHeight > 0.0) {
        CGFloat textY = 56.0;
        self.textLabel_.frame = CGRectMake(kPad, textY, textWidth, _textHeight);
        self.textLabel_.hidden = NO;
        y = textY + _textHeight;
    } else {
        self.textLabel_.frame = CGRectZero;
        self.textLabel_.hidden = YES;
    }

    BOOL quote = self.post.originalName.length > 0;
    self.originalHeading.hidden = self.originalBody.hidden = self.quoteLine.hidden = self.originalAvatarView.hidden = !quote;
    if (quote) {
        y += 12;
        CGFloat quoteX = kPad + 12;
        CGFloat textX = quoteX + kOriginalAvatar + 8.0;
        CGFloat textW = textWidth - (textX - kPad);
        CGFloat bodyH = ceilf([self.post.originalText sizeWithFont:VKTextFont() constrainedToSize:CGSizeMake(textW, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping].height);
        CGFloat quoteH = MAX(kOriginalAvatar, 24.0 + bodyH);
        self.originalHeading.text = self.post.originalName;
        self.originalBody.text = self.post.originalText; self.originalBody.font = VKTextFont();
        self.originalAvatarView.frame = CGRectMake(quoteX, y, kOriginalAvatar, kOriginalAvatar);
        self.originalHeading.frame = CGRectMake(textX, y, textW, 20);
        self.originalBody.frame = CGRectMake(textX, y + 24, textW, bodyH);
        self.quoteLine.frame = CGRectMake(kPad, y, 2, quoteH);
        y += quoteH;
    }
    CGFloat attachmentH = [VKPostCell attachmentHeightForPost:self.post];
    if (attachmentH > 0.0) {
        y += 8.0;
        if (self.post.audioAttachment) {
            self.audioAttachmentView.frame = CGRectMake(kPad, y, textWidth, kAudioAttachmentH);
            self.audioArtworkView.frame = CGRectMake(6.0, 5.0, 44.0, 44.0);
            self.audioArtistLabel.frame = CGRectMake(58.0, 8.0, textWidth - 115.0, 17.0);
            self.audioTitleLabel.frame = CGRectMake(58.0, 27.0, textWidth - 115.0, 16.0);
            self.audioDurationLabel.frame = CGRectMake(textWidth - 52.0, 19.0, 44.0, 16.0);
            y += kAudioAttachmentH;
        }
        if (self.post.videoAttachment) {
            if (self.post.audioAttachment) y += 6.0;
            self.videoAttachmentView.frame = CGRectMake(kPad, y, textWidth, kVideoAttachmentH);
            self.videoPreviewView.frame = CGRectMake(6.0, 4.0, 104.0, 68.0);
            self.videoPlayView.frame = CGRectMake(40.0, 21.0, 36.0, 36.0);
            self.videoTitleLabel.frame = CGRectMake(118.0, 8.0, textWidth - 126.0, 34.0);
            self.videoInfoLabel.frame = CGRectMake(118.0, 48.0, textWidth - 126.0, 16.0);
            y += kVideoAttachmentH;
        }
    }
    CGFloat photoH = [VKPostCell photoHeightForPost:self.post width:width];
    if (photoH > 0.0) {
        y += 8.0;
        self.photoView.frame = CGRectMake(kPad, y, textWidth, photoH);
        y += photoH;
    }

    CGFloat dividerY = y + 8.0;
    self.divider.frame = CGRectMake(kPad, dividerY, textWidth, 0.5);

    CGFloat actY = dividerY + 1.0;
    CGFloat actH = kFooterH;
    BOOL hasViews = (self.post.views > 0);
    NSInteger segments = hasViews ? 4 : 3;
    CGFloat segW = textWidth / (CGFloat)segments;
    CGFloat iconW = 18.0;
    for (int i = 0; i < 4; i++) {
        UIImageView *icon = (i == 0) ? self.likeIcon : (i == 1) ? self.commentIcon
                          : (i == 2) ? self.repostIcon : self.viewsIcon;
        UILabel *label = (i == 0) ? self.likeLabel : (i == 1) ? self.commentLabel
                       : (i == 2) ? self.repostLabel : self.viewsLabel;
        if (i == 3 && !hasViews) break;
        CGFloat segX = kPad + segW * i;
        CGFloat labelW = MIN(ceilf([label.text sizeWithFont:label.font].width), MAX(0, segW - iconW - 12));
        CGFloat groupX = roundf(segX + (segW - iconW - 5 - labelW) / 2);
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.frame = CGRectMake(groupX, roundf(actY + (actH - 18) / 2), iconW, 18);
        label.frame = CGRectMake(groupX + iconW + 5, actY, labelW, actH);
    }
    self.likeButton.frame = CGRectMake(kPad, actY, segW, actH);
    self.commentButton.frame = CGRectMake(kPad + segW, actY, segW, actH);
    self.repostButton.frame = CGRectMake(kPad + segW * 2, actY, segW, actH);

    self.bottomLine.frame = CGRectMake(0, self.card.bounds.size.height - 0.5, width, 0.5);
}

@end
