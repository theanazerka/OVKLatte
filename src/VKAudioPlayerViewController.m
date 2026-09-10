#import "VKAudioPlayerViewController.h"
#import "VKAudioPlayer.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKImageLoader.h"
#import <QuartzCore/QuartzCore.h>

static UIImage *VKSliderTrackImage(UIColor *color) {
    CGSize size = CGSizeMake(12.0, 6.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectMake(0, 1, size.width, 4);
    CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:0.05 alpha:0.75].CGColor);
    CGContextFillRect(c, CGRectInset(r, 0, -1));
    CGContextSetFillColorWithColor(c, color.CGColor);
    CGContextFillRect(c, r);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image stretchableImageWithLeftCapWidth:5 topCapHeight:2];
}

static UIImage *VKSliderThumbImage(void) {
    CGSize size = CGSizeMake(22.0, 22.0);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect shadow = CGRectMake(2, 3, 18, 18);
    CGContextSetFillColorWithColor(c, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
    CGContextFillEllipseInRect(c, shadow);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)[UIColor whiteColor].CGColor, (id)[UIColor colorWithWhite:0.68 alpha:1].CGColor];
    CGFloat locations[] = {0.0, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, CGRectMake(2, 1, 18, 18));
    CGContextClip(c);
    CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 1), CGPointMake(0, 19), 0);
    CGContextRestoreGState(c);
    CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:0.30 alpha:1].CGColor);
    CGContextSetLineWidth(c, 1.0);
    CGContextStrokeEllipseInRect(c, CGRectMake(2.5, 1.5, 17, 17));
    CGGradientRelease(gradient); CGColorSpaceRelease(space);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface VKAudioPlayerViewController () {
    BOOL _isScrubbing;
}
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;

@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *currentTimeLabel;
@property (nonatomic, strong) UILabel *remainingTimeLabel;

@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *nextButton;

@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *addButton;

@property (nonatomic, strong) UISlider *volumeSlider;
@end

@implementation VKAudioPlayerViewController

+ (instancetype)sharedController {
    static VKAudioPlayerViewController *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VKAudioPlayerViewController alloc] init]; });
    return s;
}

- (void)presentFromViewController:(UIViewController *)parent {
    if (self.presentingViewController || parent.presentedViewController) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self];
    [VKTheme styleNavigationBar:nav.navigationBar];
    [parent presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Сейчас играет";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Добавить" style:UIBarButtonItemStyleBordered target:self action:@selector(addTapped)];
    self.view.backgroundColor = [UIColor colorWithRed:0.16 green:0.19 blue:0.24 alpha:1.0];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Закрыть"
                style:UIBarButtonItemStyleBordered
               target:self
               action:@selector(closeTapped)];

    [self buildUI];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(trackDidChange:) name:VKAudioPlayerTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(stateDidChange:) name:VKAudioPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(progressDidChange:) name:VKAudioPlayerProgressDidChangeNotification object:nil];

    [self updateTrackInfo];
    [self updatePlayState];
    [self updateProgress];
    [self updateModes];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UI Building

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // --- Обложка / винил трека ---
    CGFloat artSize = MIN(w - 60.0, 220.0);
    CGFloat artY = 20.0;
    if (h > 480) artY = 30.0; // на 4-дюймовых экранах (iPhone 5)

    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectMake((w - artSize) / 2.0, artY, artSize, artSize)];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFit;
    self.artworkView.image = [UIImage imageNamed:@"placeholder_audio@2x"] ?: [UIImage imageNamed:@"audio_preview_placeholder"];
    self.artworkView.layer.cornerRadius = 6.0;
    self.artworkView.layer.masksToBounds = YES;
    self.artworkView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.15].CGColor;
    self.artworkView.layer.borderWidth = 1.0;
    [self.view addSubview:self.artworkView];

    // --- Название и исполнитель ---
    CGFloat textY = artY + artSize + 16.0;
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, textY, w - 40.0, 22.0)];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.6];
    self.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.view addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(20.0, textY + 22.0, w - 40.0, 18.0)];
    self.artistLabel.font = [UIFont systemFontOfSize:13.0];
    self.artistLabel.textColor = [UIColor colorWithRed:0.60 green:0.68 blue:0.78 alpha:1.0];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.artistLabel];

    // --- Скраббер (полоса прогресса) ---
    CGFloat scrubY = textY + 46.0;
    self.progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(55.0, scrubY, w - 110.0, 20.0)];
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    self.progressSlider.value = 0.0;
    [self.progressSlider setMinimumTrackImage:VKSliderTrackImage([UIColor colorWithRed:0.25 green:0.55 blue:0.88 alpha:1.0]) forState:UIControlStateNormal];
    [self.progressSlider setMaximumTrackImage:VKSliderTrackImage([UIColor colorWithWhite:0.38 alpha:1.0]) forState:UIControlStateNormal];
    UIImage *sliderThumb = VKSliderThumbImage();
    [self.progressSlider setThumbImage:sliderThumb forState:UIControlStateNormal];
    [self.progressSlider setThumbImage:sliderThumb forState:UIControlStateHighlighted];
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:self.progressSlider];

    self.currentTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(10.0, scrubY + 2.0, 40.0, 16.0)];
    self.currentTimeLabel.font = [UIFont systemFontOfSize:11.0];
    self.currentTimeLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.currentTimeLabel.textAlignment = NSTextAlignmentRight;
    self.currentTimeLabel.backgroundColor = [UIColor clearColor];
    self.currentTimeLabel.text = @"0:00";
    [self.view addSubview:self.currentTimeLabel];

    self.remainingTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(w - 50.0, scrubY + 2.0, 40.0, 16.0)];
    self.remainingTimeLabel.font = [UIFont systemFontOfSize:11.0];
    self.remainingTimeLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.remainingTimeLabel.textAlignment = NSTextAlignmentLeft;
    self.remainingTimeLabel.backgroundColor = [UIColor clearColor];
    self.remainingTimeLabel.text = @"-0:00";
    [self.view addSubview:self.remainingTimeLabel];

    // --- Основные кнопки управления воспроизведением ---
    CGFloat ctrlY = scrubY + 30.0;
    CGFloat playBtnSize = 54.0;
    CGFloat skipBtnSize = 44.0;

    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playPauseButton.frame = CGRectMake((w - playBtnSize) / 2.0, ctrlY, playBtnSize, playBtnSize);
    [self.playPauseButton setImage:[UIImage imageNamed:@"audioplayer_play"] forState:UIControlStateNormal];
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playPauseButton];

    self.prevButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.prevButton.frame = CGRectMake(self.playPauseButton.frame.origin.x - skipBtnSize - 20.0, ctrlY + 5.0, skipBtnSize, skipBtnSize);
    [self.prevButton setImage:[UIImage imageNamed:@"audioplayer_previous"] forState:UIControlStateNormal];
    [self.prevButton addTarget:self action:@selector(prevTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.prevButton];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.nextButton.frame = CGRectMake(CGRectGetMaxX(self.playPauseButton.frame) + 20.0, ctrlY + 5.0, skipBtnSize, skipBtnSize);
    [self.nextButton setImage:[UIImage imageNamed:@"audioplayer_next"] forState:UIControlStateNormal];
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];

    // --- Дополнительные кнопки (Shuffle, Repeat, Add) ---
    CGFloat modeY = ctrlY + playBtnSize + 14.0;
    CGFloat modeBtnW = 40.0;

    self.shuffleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.shuffleButton.frame = CGRectMake(40.0, modeY, modeBtnW, 30.0);
    [self.shuffleButton setImage:[UIImage imageNamed:@"audioplayer_shuffle"] forState:UIControlStateNormal];
    [self.shuffleButton addTarget:self action:@selector(shuffleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shuffleButton];

    self.addButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.addButton.frame = CGRectMake((w - modeBtnW) / 2.0, modeY, modeBtnW, 30.0);
    [self.addButton setImage:[UIImage imageNamed:@"audioplayer_add"] forState:UIControlStateNormal];
    [self.addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.addButton];

    self.repeatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.repeatButton.frame = CGRectMake(w - 40.0 - modeBtnW, modeY, modeBtnW, 30.0);
    [self.repeatButton setImage:[UIImage imageNamed:@"audioplayer_replay"] forState:UIControlStateNormal];
    [self.repeatButton addTarget:self action:@selector(repeatTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.repeatButton];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat side = MAX(72, MIN(w - 48, h - 222));
    self.artworkView.frame = CGRectMake((w - side) / 2, 12, side, side);
    CGFloat y = side + 24;
    self.titleLabel.frame = CGRectMake(16, y, w - 32, 22);
    self.artistLabel.frame = CGRectMake(16, y + 24, w - 32, 18);
    self.progressSlider.frame = CGRectMake(48, y + 39, w - 96, 44);
    self.currentTimeLabel.frame = CGRectMake(4, y + 53, 40, 16);
    self.remainingTimeLabel.frame = CGRectMake(w - 44, y + 53, 40, 16);
    self.playPauseButton.frame = CGRectMake(w / 2 - 27, y + 79, 54, 54);
    self.prevButton.frame = CGRectMake(w / 2 - 102, y + 84, 44, 44);
    self.nextButton.frame = CGRectMake(w / 2 + 58, y + 84, 44, 44);
    self.shuffleButton.frame = CGRectMake(32, y + 139, 44, 40);
    self.addButton.frame = CGRectMake(w / 2 - 22, y + 139, 44, 40);
    self.repeatButton.frame = CGRectMake(w - 76, y + 139, 44, 40);
}

#pragma mark - Updates

- (void)updateTrackInfo {
    VKAudio *audio = [VKAudioPlayer shared].currentAudio;
    if (audio) {
        self.titleLabel.text = audio.title.length ? audio.title : @"Без названия";
        self.artistLabel.text = audio.artist.length ? audio.artist : @"Неизвестный исполнитель";
        self.artworkView.image = [UIImage imageNamed:@"audio_preview_placeholder"];
        if (audio.artworkURL.length) {
            __weak UIImageView *weakArtwork = self.artworkView;
            [[VKImageLoader shared] loadURL:audio.artworkURL completion:^(UIImage *image) {
                if (image && weakArtwork && [VKAudioPlayer shared].currentAudio == audio) weakArtwork.image = image;
            }];
        }
    } else {
        self.titleLabel.text = @"Нет трека";
        self.artistLabel.text = @"";
        self.artworkView.image = [UIImage imageNamed:@"audio_preview_placeholder"];
    }
}

- (void)updatePlayState {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    if (player.isPlaying) {
        [self.playPauseButton setImage:[UIImage imageNamed:@"audioplayer_pause"] forState:UIControlStateNormal];
    } else {
        [self.playPauseButton setImage:[UIImage imageNamed:@"audioplayer_play"] forState:UIControlStateNormal];
    }
}

- (void)updateProgress {
    if (_isScrubbing) return;

    VKAudioPlayer *player = [VKAudioPlayer shared];
    self.progressSlider.enabled = player.duration > 0;
    self.progressSlider.value = player.progress;

    NSInteger cur = (NSInteger)player.currentTime;
    NSInteger rem = (NSInteger)(player.duration - player.currentTime);
    if (rem < 0) rem = 0;

    self.currentTimeLabel.text = [NSString stringWithFormat:@"%d:%02d", (int)(cur / 60), (int)(cur % 60)];
    self.remainingTimeLabel.text = [NSString stringWithFormat:@"-%d:%02d", (int)(rem / 60), (int)(rem % 60)];
}

- (void)updateModes {
    VKAudioPlayer *player = [VKAudioPlayer shared];

    if (player.shuffle) {
        [self.shuffleButton setImage:[UIImage imageNamed:@"audioplayer_shuffle_hl"] forState:UIControlStateNormal];
    } else {
        [self.shuffleButton setImage:[UIImage imageNamed:@"audioplayer_shuffle"] forState:UIControlStateNormal];
    }

    if (player.repeatMode != VKAudioRepeatOff) {
        [self.repeatButton setImage:[UIImage imageNamed:@"audioplayer_replay_hl"] forState:UIControlStateNormal];
    } else {
        [self.repeatButton setImage:[UIImage imageNamed:@"audioplayer_replay"] forState:UIControlStateNormal];
    }
}

#pragma mark - Notification Handlers

- (void)trackDidChange:(NSNotification *)note {
    [self updateTrackInfo];
    [self updateProgress];
}

- (void)stateDidChange:(NSNotification *)note {
    [self updatePlayState];
}

- (void)progressDidChange:(NSNotification *)note {
    [self updateProgress];
}

#pragma mark - Actions

- (void)playPauseTapped {
    [[VKAudioPlayer shared] togglePlayPause];
}

- (void)prevTapped {
    [[VKAudioPlayer shared] previous];
}

- (void)nextTapped {
    [[VKAudioPlayer shared] next];
}

- (void)shuffleTapped {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    player.shuffle = !player.shuffle;
    [self updateModes];
}

- (void)repeatTapped {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    if (player.repeatMode == VKAudioRepeatOff) {
        player.repeatMode = VKAudioRepeatAll;
    } else if (player.repeatMode == VKAudioRepeatAll) {
        player.repeatMode = VKAudioRepeatOne;
    } else {
        player.repeatMode = VKAudioRepeatOff;
    }
    [self updateModes];
}

- (void)addTapped {
    VKAudio *audio = [VKAudioPlayer shared].currentAudio;
    if (!audio) return;

    NSDictionary *params = @{
        @"audio_id": [NSString stringWithFormat:@"%lld", audio.audioId],
        @"owner_id": [NSString stringWithFormat:@"%lld", audio.ownerId]
    };
    [[VKAPI shared] callMethod:@"audio.add" params:params completion:^(id response, NSError *error) {
        if (!error) audio.isAdded = YES;
        NSString *msg = error ? error.localizedDescription : @"Трек добавлен в ваши аудиозаписи";
        UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Аудиозаписи"
                                                    message:msg
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
        [a show];
    }];
}

#pragma mark - Scrubbing

- (void)sliderTouchDown:(UISlider *)slider {
    _isScrubbing = YES;
}

- (void)sliderValueChanged:(UISlider *)slider {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    NSTimeInterval targetTime = player.duration * slider.value;
    NSInteger cur = (NSInteger)targetTime;
    NSInteger rem = (NSInteger)(player.duration - targetTime);
    if (rem < 0) rem = 0;

    self.currentTimeLabel.text = [NSString stringWithFormat:@"%d:%02d", (int)(cur / 60), (int)(cur % 60)];
    self.remainingTimeLabel.text = [NSString stringWithFormat:@"-%d:%02d", (int)(rem / 60), (int)(rem % 60)];
}

- (void)sliderTouchUp:(UISlider *)slider {
    _isScrubbing = NO;
    [[VKAudioPlayer shared] seekToProgress:slider.value];
}

@end
