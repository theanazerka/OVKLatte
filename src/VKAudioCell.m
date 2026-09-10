#import "VKAudioCell.h"
#import "VKAudioPlayer.h"
#import "VKTheme.h"
#import "VKImageLoader.h"

static const CGFloat kCellH = 50.0;
static const CGFloat kPlayBtnSize = 34.0;
static const CGFloat kPad = 8.0;

@interface VKAudioCell ()
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIButton *addButton;
@property (nonatomic, strong) UIView *bottomLine;
@end

@implementation VKAudioCell

+ (CGFloat)rowHeight {
    return kCellH;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleGray;

        _artworkView = [[UIImageView alloc] initWithFrame:CGRectMake(8, 5, 40, 40)];
        _artworkView.contentMode = UIViewContentModeScaleAspectFill;
        _artworkView.clipsToBounds = YES;
        _artworkView.image = [UIImage imageNamed:@"audio_preview_placeholder"];
        [self.contentView addSubview:_artworkView];

        // Кнопка воспроизведения слева поверх обложки
        _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _playButton.frame = CGRectMake(kPad, (kCellH - kPlayBtnSize) / 2.0, kPlayBtnSize, kPlayBtnSize);
        [_playButton setImage:[UIImage imageNamed:@"inplayer_play"] forState:UIControlStateNormal];
        [_playButton setImage:[UIImage imageNamed:@"inplayer_play_hl"] forState:UIControlStateHighlighted];
        [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_playButton];

        // Исполнитель
        _artistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _artistLabel.font = [UIFont boldSystemFontOfSize:14.0];
        _artistLabel.textColor = [VKTheme primaryTextColor];
        _artistLabel.backgroundColor = [UIColor clearColor];
        _artistLabel.opaque = NO;
        _artistLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_artistLabel];

        // Название трека
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:13.0];
        _titleLabel.textColor = [VKTheme secondaryTextColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.opaque = NO;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];

        // Длительность
        _durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _durationLabel.font = [UIFont systemFontOfSize:12.0];
        _durationLabel.textColor = [VKTheme secondaryTextColor];
        _durationLabel.backgroundColor = [UIColor clearColor];
        _durationLabel.opaque = NO;
        _durationLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_durationLabel];

        // Кнопка добавления в свои аудио
        _addButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_addButton setImage:[UIImage imageNamed:@"audioplayer_add"] forState:UIControlStateNormal];
        [_addButton addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
        _addButton.hidden = YES;
        [self.contentView addSubview:_addButton];

        // Тонкий разделитель
        _bottomLine = [[UIView alloc] initWithFrame:CGRectZero];
        _bottomLine.backgroundColor = [VKTheme separatorColor];
        [self.contentView addSubview:_bottomLine];
    }
    return self;
}

- (void)playTapped {
    void (^action)(void) = [self.onPlayTap copy];
    if (action) action();
}

- (void)addTapped {
    void (^action)(void) = [self.onAddTap copy];
    if (action) action();
}

- (void)setAudio:(VKAudio *)audio {
    _audio = audio;
    if (!audio) return;

    self.backgroundColor = self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
    self.artistLabel.textColor = [VKTheme primaryTextColor];
    self.bottomLine.backgroundColor = [VKTheme separatorColor];

    self.artistLabel.text = audio.artist.length ? audio.artist : @"Неизвестный исполнитель";
    self.titleLabel.text = audio.title.length ? audio.title : @"Без названия";
    self.durationLabel.text = audio.durationString ?: @"";
    self.artworkView.image = [UIImage imageNamed:@"audio_preview_placeholder"];
    NSString *url = audio.artworkURL;
    if (url.length) {
        __weak UIImageView *weakArtwork = self.artworkView;
        [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
            if (image && weakArtwork) weakArtwork.image = image;
        }];
    }

    [self updatePlayingState];
    [self setNeedsLayout];
}

- (void)updatePlayingState {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    BOOL isCurrent = (player.currentAudio && player.currentAudio.audioId == self.audio.audioId);
    BOOL isPlaying = isCurrent && player.isPlaying;

    if (isPlaying) {
        [self.playButton setImage:[UIImage imageNamed:@"inplayer_pause"] forState:UIControlStateNormal];
        [self.playButton setImage:[UIImage imageNamed:@"inplayer_pause_hl"] forState:UIControlStateHighlighted];
        self.artistLabel.textColor = [VKTheme linkColor];
    } else if (isCurrent) {
        [self.playButton setImage:[UIImage imageNamed:@"inplayer_play"] forState:UIControlStateNormal];
        [self.playButton setImage:[UIImage imageNamed:@"inplayer_play_hl"] forState:UIControlStateHighlighted];
        self.artistLabel.textColor = [VKTheme linkColor];
    } else {
        [self.playButton setImage:[UIImage imageNamed:@"inplayer_play"] forState:UIControlStateNormal];
        [self.playButton setImage:[UIImage imageNamed:@"inplayer_play_hl"] forState:UIControlStateHighlighted];
        self.artistLabel.textColor = [VKTheme primaryTextColor];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;

    self.playButton.frame = CGRectMake(kPad, (h - kPlayBtnSize) / 2.0, kPlayBtnSize, kPlayBtnSize);

    CGFloat textLeft = 56.0;
    self.addButton.hidden = self.audio.isAdded;
    self.addButton.frame = CGRectMake(w - 44, 0, 44, h);
    CGFloat rightPad = self.audio.isAdded ? 10 : 48;
    CGFloat durW = 45.0;

    self.durationLabel.frame = CGRectMake(w - rightPad - durW, (h - 16.0) / 2.0, durW, 16.0);

    CGFloat textWidth = w - textLeft - durW - rightPad - 8.0;
    self.artistLabel.frame = CGRectMake(textLeft, 7.0, textWidth, 18.0);
    self.titleLabel.frame = CGRectMake(textLeft, 25.0, textWidth, 18.0);

    self.bottomLine.frame = CGRectMake(textLeft, h - 0.5, w - textLeft, 0.5);
}

@end
