#import "OVKAlignedButton.h"
#import "VKVideoPlayerViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKBackend.h"
#import "VKImageLoader.h"
#import "VKProfileViewController.h"
#import "VKAudioPlayer.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

@interface VKVideoPlayerViewController () <UIActionSheetDelegate, UIWebViewDelegate> {
    long long _videoId;
    long long _ownerId;
}
@property (nonatomic, assign) BOOL likePending;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *playerContainer;
@property (nonatomic, strong) MPMoviePlayerController *moviePlayer;
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIImageView *posterImageView;
@property (nonatomic, strong) UIButton *playOverlayButton;
@property (nonatomic, strong) UIActivityIndicatorView *playerSpinner;

@property (nonatomic, strong) UIView *infoContainer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *viewsLabel;
@property (nonatomic, strong) UILabel *dateLabel;

@property (nonatomic, strong) UIView *authorContainer;
@property (nonatomic, strong) UIImageView *authorAvatarView;
@property (nonatomic, strong) UILabel *authorNameLabel;
@property (nonatomic, strong) UILabel *authorSubLabel;

@property (nonatomic, strong) UIView *actionsBar;
@property (nonatomic, strong) UIButton *likeButton;
@property (nonatomic, strong) UIButton *commentsButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *qualityButton;

@property (nonatomic, strong) UIView *descContainer;
@property (nonatomic, strong) UILabel *descHeaderLabel;
@property (nonatomic, strong) UILabel *descLabel;

@property (nonatomic, strong) NSString *currentQuality;
@property (nonatomic, assign) BOOL isPlaying;
@end

@implementation VKVideoPlayerViewController

- (id)initWithVideo:(VKVideo *)video {
    self = [super init];
    if (self) {
        _video = video;
        _videoId = video.videoId;
        _ownerId = video.ownerId;
    }
    return self;
}

- (id)initWithVideoId:(long long)videoId ownerId:(long long)ownerId {
    self = [super init];
    if (self) {
        _videoId = videoId;
        _ownerId = ownerId;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Видео";
    self.view.backgroundColor = [VKTheme contentBackgroundColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.backgroundColor = [VKTheme contentBackgroundColor];
    [self.view addSubview:self.scrollView];

    [self buildUI];

    if (self.video) {
        [self applyVideoData];
    } else {
        [self loadVideoInfo];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.moviePlayer && self.moviePlayer.playbackState == MPMoviePlaybackStatePlaying) {
        [self.moviePlayer pause];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_moviePlayer) {
        [_moviePlayer stop];
        [_moviePlayer.view removeFromSuperview];
        _moviePlayer = nil;
    }
    if (_webView) {
        [_webView stopLoading];
        _webView.delegate = nil;
        _webView = nil;
    }
}

#pragma mark - UI Building

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat playerH = roundf(w * 9.0 / 16.0); // 16:9 соотношение

    // --- Контейнер плеера ---
    self.playerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, playerH)];
    self.playerContainer.backgroundColor = [UIColor blackColor];
    self.playerContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.playerContainer];

    self.posterImageView = [[UIImageView alloc] initWithFrame:self.playerContainer.bounds];
    self.posterImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.posterImageView.clipsToBounds = YES;
    self.posterImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.playerContainer addSubview:self.posterImageView];

    // Большая круглая кнопка Play поверх превью
    self.playOverlayButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playOverlayButton.frame = CGRectMake((w - 64.0) / 2.0, (playerH - 64.0) / 2.0, 64.0, 64.0);
    self.playOverlayButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                              UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.playOverlayButton setImage:[UIImage imageNamed:@"video_can_play"] forState:UIControlStateNormal];
    [self.playOverlayButton addTarget:self action:@selector(startPlayback) forControlEvents:UIControlEventTouchUpInside];
    [self.playerContainer addSubview:self.playOverlayButton];

    self.playerSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.playerSpinner.center = CGPointMake(w / 2.0, playerH / 2.0);
    self.playerSpinner.hidesWhenStopped = YES;
    self.playerSpinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                          UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.playerContainer addSubview:self.playerSpinner];

    // --- Блок информации (название, просмотры, дата) ---
    CGFloat curY = playerH;
    self.infoContainer = [[UIView alloc] initWithFrame:CGRectMake(0, curY, w, 60.0)];
    self.infoContainer.backgroundColor = [VKTheme cardColor];
    [self.scrollView addSubview:self.infoContainer];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, w - 24, 20)];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    self.titleLabel.textColor = [VKTheme primaryTextColor];
    self.titleLabel.numberOfLines = 0;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.infoContainer addSubview:self.titleLabel];

    self.viewsLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 34, (w - 24) / 2.0, 16)];
    self.viewsLabel.font = [UIFont systemFontOfSize:12.0];
    self.viewsLabel.textColor = [VKTheme secondaryTextColor];
    self.viewsLabel.backgroundColor = [UIColor clearColor];
    [self.infoContainer addSubview:self.viewsLabel];

    self.dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(12 + (w - 24) / 2.0, 34, (w - 24) / 2.0, 16)];
    self.dateLabel.font = [UIFont systemFontOfSize:12.0];
    self.dateLabel.textColor = [VKTheme secondaryTextColor];
    self.dateLabel.textAlignment = NSTextAlignmentRight;
    self.dateLabel.backgroundColor = [UIColor clearColor];
    [self.infoContainer addSubview:self.dateLabel];

    UIView *div1 = [[UIView alloc] initWithFrame:CGRectMake(0, 59.5, w, 0.5)];
    div1.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    div1.tag = 991;
    [self.infoContainer addSubview:div1];

    // --- Панель кнопок действий (Лайк, Комментарии, Поделиться, Качество) ---
    curY += 60.0;
    self.actionsBar = [[UIView alloc] initWithFrame:CGRectMake(0, curY, w, 44.0)];
    self.actionsBar.backgroundColor = [VKTheme contentBackgroundColor];
    [self.scrollView addSubview:self.actionsBar];

    self.likeButton = [OVKAlignedButton buttonWithType:UIButtonTypeCustom];
    [self.likeButton setTitle:@"Мне нравится" forState:UIControlStateNormal];
    [self.likeButton setTitleColor:[VKTheme linkColor] forState:UIControlStateNormal];
    self.likeButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [self.likeButton setImage:[UIImage imageNamed:@"post_btn_like"] forState:UIControlStateNormal];
    self.likeButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    [self.likeButton addTarget:self action:@selector(likeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionsBar addSubview:self.likeButton];

    self.commentsButton = [OVKAlignedButton buttonWithType:UIButtonTypeCustom];
    [self.commentsButton setTitle:@"Комментарии" forState:UIControlStateNormal];
    [self.commentsButton setTitleColor:[VKTheme linkColor] forState:UIControlStateNormal];
    self.commentsButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [self.commentsButton setImage:[UIImage imageNamed:@"post_btn_comment"] forState:UIControlStateNormal];
    self.commentsButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    [self.commentsButton addTarget:self action:@selector(commentsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionsBar addSubview:self.commentsButton];

    self.shareButton = [OVKAlignedButton buttonWithType:UIButtonTypeCustom];
    [self.shareButton setTitle:@"Поделиться" forState:UIControlStateNormal];
    [self.shareButton setTitleColor:[VKTheme linkColor] forState:UIControlStateNormal];
    self.shareButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [self.shareButton setImage:[UIImage imageNamed:@"post_btn_repost"] forState:UIControlStateNormal];
    self.shareButton.imageEdgeInsets = UIEdgeInsetsMake(0, -4, 0, 4);
    [self.shareButton addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionsBar addSubview:self.shareButton];

    self.qualityButton = [OVKAlignedButton buttonWithType:UIButtonTypeCustom];
    [self.qualityButton setTitle:@"SD" forState:UIControlStateNormal];
    [self.qualityButton setTitleColor:[VKTheme secondaryTextColor] forState:UIControlStateNormal];
    self.qualityButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.qualityButton.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
    self.qualityButton.layer.borderWidth = 1.0;
    self.qualityButton.layer.cornerRadius = 3.0;
    [self.qualityButton addTarget:self action:@selector(qualityTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.actionsBar addSubview:self.qualityButton];

    UIView *div2 = [[UIView alloc] initWithFrame:CGRectMake(0, 43.5, w, 0.5)];
    div2.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [self.actionsBar addSubview:div2];

    // --- Блок автора ---
    curY += 44.0;
    self.authorContainer = [[UIView alloc] initWithFrame:CGRectMake(0, curY, w, 54.0)];
    self.authorContainer.backgroundColor = [VKTheme cardColor];
    [self.scrollView addSubview:self.authorContainer];

    self.authorAvatarView = [[UIImageView alloc] initWithFrame:CGRectMake(12, 9, 36, 36)];
    self.authorAvatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.authorAvatarView.clipsToBounds = YES;
    self.authorAvatarView.layer.cornerRadius = 0.0;
    [self.authorContainer addSubview:self.authorAvatarView];

    self.authorNameLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 10, w - 80, 18)];
    self.authorNameLabel.font = [UIFont boldSystemFontOfSize:14.0];
    self.authorNameLabel.textColor = [VKTheme linkColor];
    self.authorNameLabel.backgroundColor = [UIColor clearColor];
    [self.authorContainer addSubview:self.authorNameLabel];

    self.authorSubLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 28, w - 80, 15)];
    self.authorSubLabel.font = [UIFont systemFontOfSize:11.0];
    self.authorSubLabel.textColor = [VKTheme secondaryTextColor];
    self.authorSubLabel.text = @"Автор видеозаписи";
    self.authorSubLabel.backgroundColor = [UIColor clearColor];
    [self.authorContainer addSubview:self.authorSubLabel];

    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"gray_arrow"]];
    arrow.frame = CGRectMake(w - 24, 20, 10, 14);
    [self.authorContainer addSubview:arrow];

    UIButton *authorBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    authorBtn.frame = self.authorContainer.bounds;
    [authorBtn addTarget:self action:@selector(authorTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.authorContainer addSubview:authorBtn];

    UIView *div3 = [[UIView alloc] initWithFrame:CGRectMake(0, 53.5, w, 0.5)];
    div3.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    [self.authorContainer addSubview:div3];

    // --- Описание видео ---
    curY += 54.0;
    self.descContainer = [[UIView alloc] initWithFrame:CGRectMake(0, curY, w, 60.0)];
    self.descContainer.backgroundColor = [VKTheme cardColor];
    [self.scrollView addSubview:self.descContainer];

    self.descHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, w - 24, 16)];
    self.descHeaderLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.descHeaderLabel.textColor = [VKTheme secondaryTextColor];
    self.descHeaderLabel.text = @"ОПИСАНИЕ";
    self.descHeaderLabel.backgroundColor = [UIColor clearColor];
    [self.descContainer addSubview:self.descHeaderLabel];

    self.descLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 28, w - 24, 20)];
    self.descLabel.font = [UIFont systemFontOfSize:13.0];
    self.descLabel.textColor = [VKTheme primaryTextColor];
    self.descLabel.numberOfLines = 0;
    self.descLabel.backgroundColor = [UIColor clearColor];
    [self.descContainer addSubview:self.descLabel];
}

- (UIImage *)drawPlayButton {
    CGSize size = CGSizeMake(64.0, 64.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    // Полупрозрачный темный круг
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.0 alpha:0.65].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, 64, 64));

    // Белая обводка
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.85].CGColor);
    CGContextSetLineWidth(ctx, 2.0);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(1, 1, 62, 62));

    // Белый треугольник Play
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextMoveToPoint(ctx, 25.0, 18.0);
    CGContextAddLineToPoint(ctx, 45.0, 32.0);
    CGContextAddLineToPoint(ctx, 25.0, 46.0);
    CGContextClosePath(ctx);
    CGContextFillPath(ctx);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Data Loading & Display

- (void)loadVideoInfo {
    [self.playerSpinner startAnimating];
    NSString *idParam = [NSString stringWithFormat:@"%lld_%lld", _ownerId, _videoId];
    if (self.video.accessKey.length) {
        idParam = [NSString stringWithFormat:@"%@_%@", idParam, self.video.accessKey];
    }

    [[VKAPI shared] callMethod:@"video.get"
                        params:@{@"videos": idParam, @"extended": @"1"}
                    completion:^(id response, NSError *error) {
        [self.playerSpinner stopAnimating];
        if (error || !response) return;

        NSArray *videos = [VKVideo parseVideosResponse:response];
        if (videos.count > 0) {
            self.video = [videos objectAtIndex:0];
            [self applyVideoData];
        }
    }];
}

- (void)applyVideoData {
    if (!self.video) return;

    CGFloat w = self.view.bounds.size.width;

    // Превью постера
    if (self.video.photoURL.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:self.video.photoURL];
        if (cached) {
            self.posterImageView.image = cached;
        } else {
            __weak typeof(self) weakSelf = self;
            [[VKImageLoader shared] loadURL:self.video.photoURL completion:^(UIImage *img) {
                if (img) weakSelf.posterImageView.image = img;
            }];
        }
    }

    // Заголовок
    self.titleLabel.text = self.video.title.length ? self.video.title : @"Без названия";
    CGSize titleSize = [self.titleLabel.text sizeWithFont:self.titleLabel.font
                                        constrainedToSize:CGSizeMake(w - 24.0, CGFLOAT_MAX)
                                            lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat titleH = MAX(20.0, titleSize.height);
    self.titleLabel.frame = CGRectMake(12, 10, w - 24, titleH);

    self.viewsLabel.text = self.video.viewsString ?: @"";
    self.viewsLabel.frame = CGRectMake(12, 10 + titleH + 6.0, (w - 24) / 2.0, 16);

    self.dateLabel.text = self.video.timeString ?: @"";
    self.dateLabel.frame = CGRectMake(12 + (w - 24) / 2.0, 10 + titleH + 6.0, (w - 24) / 2.0, 16);

    CGFloat infoH = 10 + titleH + 6.0 + 16.0 + 10.0;
    self.infoContainer.frame = CGRectMake(0, self.playerContainer.bounds.size.height, w, infoH);
    UIView *div1 = [self.infoContainer viewWithTag:991];
    div1.frame = CGRectMake(0, infoH - 0.5, w, 0.5);

    // Панель кнопок действий
    CGFloat actY = self.infoContainer.frame.origin.y + infoH;
    self.actionsBar.frame = CGRectMake(0, actY, w, 44.0);

    // Настраиваем кнопки в actionsBar
    [self updateActionsButtons];

    // Блок автора
    CGFloat authorY = actY + 44.0;
    self.authorContainer.frame = CGRectMake(0, authorY, w, 54.0);
    self.authorNameLabel.text = self.video.authorName.length ? self.video.authorName : @"Автор";

    NSString *initials = self.video.authorName.length ? [[self.video.authorName substringToIndex:1] uppercaseString] : @"?";
    self.authorAvatarView.image = [VKTheme avatarWithInitials:initials size:36.0 background:[VKTheme navBarColor]];
    if (self.video.authorPhotoURL.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:self.video.authorPhotoURL];
        if (cached) {
            self.authorAvatarView.image = cached;
        } else {
            __weak typeof(self) weakSelf = self;
            [[VKImageLoader shared] loadURL:self.video.authorPhotoURL completion:^(UIImage *img) {
                if (img) weakSelf.authorAvatarView.image = img;
            }];
        }
    }

    // Блок описания
    CGFloat descY = authorY + 54.0;
    NSString *desc = self.video.videoDescription;
    if (desc.length > 0) {
        self.descContainer.hidden = NO;
        self.descLabel.text = desc;
        CGSize descSize = [desc sizeWithFont:self.descLabel.font
                           constrainedToSize:CGSizeMake(w - 24.0, CGFLOAT_MAX)
                               lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat descH = MAX(20.0, descSize.height);
        self.descLabel.frame = CGRectMake(12, 28, w - 24, descH);
        self.descContainer.frame = CGRectMake(0, descY, w, 28 + descH + 16);
        descY += 28 + descH + 16;
    } else {
        self.descContainer.hidden = YES;
    }

    self.scrollView.contentSize = CGSizeMake(w, descY + 20.0);
}

- (void)updateActionsButtons {
    CGFloat w = self.view.bounds.size.width;
    NSArray *qualities = [self.video availableQualities];
    BOOL hasQualities = (qualities.count > 0);

    CGFloat btnW = hasQualities ? (w - 60.0) / 3.0 : w / 3.0;

    self.likeButton.frame = CGRectMake(0, 0, btnW, 44.0);
    NSString *likeTitle = self.video.likesCount > 0
        ? [NSString stringWithFormat:@" %d", (int)self.video.likesCount]
        : @" Лайк";
    [self.likeButton setTitle:likeTitle forState:UIControlStateNormal];
    [self.likeButton setImage:[UIImage imageNamed:self.video.liked ? @"post_btn_like_in" : @"post_btn_like"]
                     forState:UIControlStateNormal];

    self.commentsButton.frame = CGRectMake(btnW, 0, btnW, 44.0);
    NSString *commTitle = self.video.commentsCount > 0
        ? [NSString stringWithFormat:@" %d", (int)self.video.commentsCount]
        : @" Коммент.";
    [self.commentsButton setTitle:commTitle forState:UIControlStateNormal];

    self.shareButton.frame = CGRectMake(btnW * 2.0, 0, btnW, 44.0);

    if (hasQualities) {
        self.qualityButton.hidden = NO;
        self.qualityButton.frame = CGRectMake(w - 54.0, 7.0, 44.0, 30.0);
        if (!self.currentQuality) {
            self.currentQuality = [qualities objectAtIndex:0];
        }
        [self.qualityButton setTitle:self.currentQuality forState:UIControlStateNormal];
    } else {
        self.qualityButton.hidden = YES;
    }
}

#pragma mark - Playback

- (void)startPlayback {
    if (self.isPlaying) return;

    NSString *directURL = self.currentQuality
        ? [self.video videoURLForQuality:self.currentQuality]
        : [self.video bestDirectVideoURL];

    if (directURL.length > 0) {
        [self playDirectVideoURL:directURL];
    } else if (self.video.playerURL.length > 0) {
        [self playWebEmbedURL:self.video.playerURL];
    } else {
        [self loadVideoInfo];
        [[[UIAlertView alloc] initWithTitle:@"Видео недоступно" message:@"OpenVK не передал ссылку для воспроизведения этого ролика." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}

// У видео должен быть свой audio session: иначе на iOS 6 MPMoviePlayer
// подхватывает беззвучный режим устройства и картинка идёт без дорожки.
- (void)activateVideoAudioSession {
    [[VKAudioPlayer shared] pause];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;
    [session setActive:NO error:nil];
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    [session setActive:YES error:&error];
    UInt32 category = kAudioSessionCategory_MediaPlayback;
    AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(category), &category);
    AudioSessionSetActive(true);
}

- (void)playDirectVideoURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    self.isPlaying = YES;
    [self activateVideoAudioSession];
    self.playOverlayButton.hidden = YES;
    self.posterImageView.hidden = YES;

    if (self.moviePlayer) {
        [self.moviePlayer stop];
        [self.moviePlayer.view removeFromSuperview];
        self.moviePlayer = nil;
    }

    self.moviePlayer = [[MPMoviePlayerController alloc] initWithContentURL:url];
    self.moviePlayer.view.frame = self.playerContainer.bounds;
    self.moviePlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.moviePlayer.controlStyle = MPMovieControlStyleEmbedded;
    self.moviePlayer.scalingMode = MPMovieScalingModeAspectFit;
    self.moviePlayer.shouldAutoplay = YES;
    self.moviePlayer.useApplicationAudioSession = NO;

    [self.playerContainer addSubview:self.moviePlayer.view];
    [self.moviePlayer prepareToPlay];
    [self.moviePlayer play];
}

- (void)playWebEmbedURL:(NSString *)urlString {
    self.isPlaying = YES;
    [self activateVideoAudioSession];
    self.playOverlayButton.hidden = YES;
    self.posterImageView.hidden = YES;

    if (!self.webView) {
        self.webView = [[UIWebView alloc] initWithFrame:self.playerContainer.bounds];
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.webView.backgroundColor = [UIColor blackColor];
        self.webView.opaque = NO;
        self.webView.scalesPageToFit = YES;
        self.webView.allowsInlineMediaPlayback = YES;
        self.webView.mediaPlaybackRequiresUserAction = NO;
        [self.playerContainer addSubview:self.webView];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

#pragma mark - Actions

- (void)likeTapped {
    if (!self.video || self.likePending) return;
    self.likePending = YES;
    BOOL desired = !self.video.liked;
    [[VKAPI shared] callMethod:(desired ? @"likes.add" : @"likes.delete")
        params:@{@"type": @"video", @"owner_id": @(self.video.ownerId), @"item_id": @(self.video.videoId)}
        completion:^(id response, NSError *error) {
            self.likePending = NO;
            if (error) {
                [[[UIAlertView alloc] initWithTitle:@"Не удалось изменить отметку" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
                return;
            }
            self.video.liked = desired;
            self.video.likesCount = [[response objectForKey:@"likes"] integerValue];
            [self updateActionsButtons];
        }];
}

- (void)commentsTapped {
    if (!self.video) return;
    NSString *url = [NSString stringWithFormat:@"https://%@/video%lld_%lld", [[VKBackend shared] webHost], self.video.ownerId, self.video.videoId];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

- (void)shareTapped {
    if (!self.video) return;

    NSString *host = [[VKBackend shared] webHost];
    NSString *link = [NSString stringWithFormat:@"https://%@/video%lld_%lld", host, self.video.ownerId, self.video.videoId];
    NSString *text = [NSString stringWithFormat:@"%@ — %@", self.video.title ?: @"Видео", link];

    Class activity = NSClassFromString(@"UIActivityViewController");
    if (activity) {
        UIActivityViewController *sheet = [[UIActivityViewController alloc]
            initWithActivityItems:@[text, [NSURL URLWithString:link]] applicationActivities:nil];
        [self presentViewController:sheet animated:YES completion:nil];
    } else {
        [[UIPasteboard generalPasteboard] setString:link];
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Ссылка скопирована"
                                                    message:link
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
        [a show];
    }
}

- (void)qualityTapped {
    NSArray *qualities = [self.video availableQualities];
    if (qualities.count == 0) return;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Качество видео"
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSString *q in qualities) {
        [sheet addButtonWithTitle:q];
    }
    [sheet addButtonWithTitle:@"Отмена"];
    sheet.cancelButtonIndex = qualities.count;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSArray *qualities = [self.video availableQualities];
    if (buttonIndex < 0 || buttonIndex >= (NSInteger)qualities.count) return;

    NSString *chosen = [qualities objectAtIndex:buttonIndex];
    self.currentQuality = chosen;
    [self updateActionsButtons];

    if (self.isPlaying) {
        NSString *url = [self.video videoURLForQuality:chosen];
        if (url.length > 0) {
            [self playDirectVideoURL:url];
        }
    }
}

- (void)authorTapped {
    if (self.video.ownerId == 0) return;
    VKProfileViewController *profile = [[VKProfileViewController alloc]
        initWithUserId:self.video.ownerId name:self.video.authorName];
    [self.navigationController pushViewController:profile animated:YES];
}

@end
