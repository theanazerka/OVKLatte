#import "VKChatViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKImageLoader.h"
#import "VKPhotoViewController.h"
#import "VKEmojiPanel.h"
#import "VKPresence.h"
#import "VKUploader.h"
#import "VKBackend.h"
#import "VKProfileViewController.h"
#import <QuartzCore/QuartzCore.h>

// Пикер диалога для пересылки (объявление; реализация ниже).
@interface VKForwardPickerViewController : UIViewController
@property (nonatomic, copy) void (^onPick)(long long peerId);
@end

// Текстовое поле с отступами, чтобы placeholder/текст стояли по центру «выемки».
@interface VKChatInputField : UITextField
@end
@implementation VKChatInputField
- (CGRect)insetRect:(CGRect)b {
    CGFloat lh = self.font.lineHeight;
    CGFloat y = floorf((b.size.height - lh) / 2.0);   // вертикальный центр
    return CGRectMake(b.origin.x + 14, y, b.size.width - 24, lh);
}
- (CGRect)textRectForBounds:(CGRect)b { return [self insetRect:b]; }
- (CGRect)editingRectForBounds:(CGRect)b { return [self insetRect:b]; }
- (CGRect)placeholderRectForBounds:(CGRect)b { return [self insetRect:b]; }
@end

#pragma mark - Ячейка-пузырь

@interface VKBubbleCell : UITableViewCell {
    UIImageView *_bubble;
    UILabel *_text;
    UILabel *_time;
    UIImageView *_sticker;
    NSString *_stickerURL;
    UIImageView *_photo;
    NSString *_photoURL;
    NSString *_photoBig;
    CGFloat _photoAspect;
    BOOL _outgoing;
    BOOL _forwardMode;
    long long _forwardOwnerId;
    UIImageView *_forwardAvatar;
    UILabel *_forwardName;
    UILabel *_forwardText;
}
@property (nonatomic, copy) void (^onPhotoTap)(NSString *bigURL, UIImage *img);
@property (nonatomic, copy) void (^onForwardAuthorTap)(long long ownerId, NSString *name);
- (void)setText:(NSString *)text outgoing:(BOOL)outgoing date:(NSTimeInterval)date;
- (void)setSticker:(NSString *)url outgoing:(BOOL)outgoing date:(NSTimeInterval)date;
- (void)setPhoto:(NSString *)url big:(NSString *)big aspect:(CGFloat)aspect outgoing:(BOOL)outgoing date:(NSTimeInterval)date;
- (void)setForward:(NSDictionary *)info outgoing:(BOOL)outgoing date:(NSTimeInterval)date;
+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width;
+ (CGFloat)stickerHeight;
+ (CGSize)photoSizeForAspect:(CGFloat)aspect cellWidth:(CGFloat)width;
+ (CGFloat)heightForForwardText:(NSString *)text width:(CGFloat)width;
@end

static UIFont *VKBubbleFont(void) { return [UIFont systemFontOfSize:15.0]; }
static const CGFloat kBubbleMaxFrac = 0.72;
static const CGFloat kPadX = 13.0, kPadY = 7.0, kBubbleMargin = 3.0;
static const CGFloat kStickerSize = 128.0;

static NSString *VKTimeString(NSTimeInterval ts) {
    if (ts <= 0) return @"";
    static NSDateFormatter *fmt = nil;
    if (!fmt) { fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"HH:mm"; }
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@implementation VKBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (self) {
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _bubble = [[UIImageView alloc] initWithFrame:CGRectZero];
        _bubble.userInteractionEnabled = YES;
        [self.contentView addSubview:_bubble];

        _text = [[UILabel alloc] initWithFrame:CGRectZero];
        _text.numberOfLines = 0;
        _text.backgroundColor = [UIColor clearColor];
        _text.font = VKBubbleFont();
        [_bubble addSubview:_text];

        _forwardAvatar = [[UIImageView alloc] initWithFrame:CGRectZero];
        _forwardAvatar.contentMode = UIViewContentModeScaleAspectFill;
        _forwardAvatar.clipsToBounds = YES;
        _forwardAvatar.userInteractionEnabled = YES;
        [_forwardAvatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(forwardAuthorTapped)]];
        [_bubble addSubview:_forwardAvatar];
        _forwardName = [[UILabel alloc] initWithFrame:CGRectZero];
        _forwardName.font = [UIFont boldSystemFontOfSize:13]; _forwardName.textColor = [VKTheme linkColor]; _forwardName.backgroundColor = [UIColor clearColor];
        [_bubble addSubview:_forwardName];
        _forwardText = [[UILabel alloc] initWithFrame:CGRectZero];
        _forwardText.font = [UIFont systemFontOfSize:13]; _forwardText.textColor = [UIColor colorWithWhite:.12 alpha:1]; _forwardText.backgroundColor = [UIColor clearColor]; _forwardText.numberOfLines = 0;
        [_bubble addSubview:_forwardText];

        // Время — СНАРУЖИ пузыря, сбоку.
        _time = [[UILabel alloc] initWithFrame:CGRectZero];
        _time.backgroundColor = [UIColor clearColor];
        _time.font = [UIFont systemFontOfSize:11.0];
        _time.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
        [self.contentView addSubview:_time];

        _sticker = [[UIImageView alloc] initWithFrame:CGRectZero];
        _sticker.contentMode = UIViewContentModeScaleAspectFit;
        _sticker.hidden = YES;
        [self.contentView addSubview:_sticker];

        _photo = [[UIImageView alloc] initWithFrame:CGRectZero];
        _photo.contentMode = UIViewContentModeScaleAspectFill;
        _photo.clipsToBounds = YES;
        _photo.layer.cornerRadius = 8.0;
        _photo.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        _photo.userInteractionEnabled = YES;
        _photo.hidden = YES;
        [_photo addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(photoTapped)]];
        [self.contentView addSubview:_photo];
    }
    return self;
}

- (void)photoTapped {
    if (self.onPhotoTap) self.onPhotoTap(_photoBig ?: _photoURL, _photo.image);
}
- (void)forwardAuthorTapped { if (self.onForwardAuthorTap && _forwardOwnerId) self.onForwardAuthorTap(_forwardOwnerId, _forwardName.text); }

+ (CGFloat)stickerHeight { return kStickerSize + kBubbleMargin * 2; }

+ (CGSize)photoSizeForAspect:(CGFloat)aspect cellWidth:(CGFloat)width {
    CGFloat dw = MIN(220.0, floorf(width * 0.6));
    if (aspect <= 0) aspect = 1.0;
    CGFloat dh = dw * aspect;
    if (dh > 280.0) dh = 280.0;
    if (dh < 90.0) dh = 90.0;
    return CGSizeMake(dw, dh);
}

+ (CGFloat)textWidthForCellWidth:(CGFloat)width {
    return floorf(width * kBubbleMaxFrac) - kPadX * 2;
}

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
    if (![text isKindOfClass:[NSString class]]) text = @"";
    NSString *t = text.length ? text : @" ";
    CGSize s = [t sizeWithFont:VKBubbleFont()
             constrainedToSize:CGSizeMake([self textWidthForCellWidth:width], CGFLOAT_MAX)
                 lineBreakMode:NSLineBreakByWordWrapping];
    return s.height + kPadY * 2 + kBubbleMargin * 2;
}
+ (CGFloat)heightForForwardText:(NSString *)text width:(CGFloat)width {
    CGSize s = [(text.length ? text : @"Запись") sizeWithFont:[UIFont systemFontOfSize:13] constrainedToSize:CGSizeMake([self textWidthForCellWidth:width] - 44, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(48.0, 20.0 + s.height) + kPadY * 2 + kBubbleMargin * 2;
}

- (void)setText:(NSString *)text outgoing:(BOOL)outgoing date:(NSTimeInterval)date {
    if (![text isKindOfClass:[NSString class]]) text = @"";
    _outgoing = outgoing;
    _forwardMode = NO; _forwardAvatar.hidden = YES; _forwardName.hidden = YES; _forwardText.hidden = YES; _text.hidden = NO;
    _stickerURL = nil; _sticker.hidden = YES; _sticker.image = nil;
    _photoURL = nil; _photo.hidden = YES; _photo.image = nil;
    _bubble.hidden = NO;
    _text.text = text.length ? text : @"[Вложение]";
    _time.text = VKTimeString(date);
    _time.textAlignment = outgoing ? NSTextAlignmentRight : NSTextAlignmentLeft;
    _text.textColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    UIImage *skin = [UIImage imageNamed:(outgoing ? @"Blue_Bubble" : @"Grey_Bubble")];
    _bubble.image = [skin stretchableImageWithLeftCapWidth:20 topCapHeight:15];
    [self setNeedsLayout];
}

- (void)setForward:(NSDictionary *)info outgoing:(BOOL)outgoing date:(NSTimeInterval)date {
    _outgoing = outgoing; _forwardMode = YES;
    _sticker.hidden = YES; _photo.hidden = YES; _text.hidden = YES; _bubble.hidden = NO;
    _forwardAvatar.hidden = NO; _forwardName.hidden = NO; _forwardText.hidden = NO;
    _forwardOwnerId = [[info objectForKey:@"owner"] longLongValue];
    NSString *name = [info objectForKey:@"name"] ?: (_forwardOwnerId < 0 ? @"Сообщество" : @"Автор записи");
    NSString *body = [info objectForKey:@"text"] ?: @"Запись";
    _forwardName.text = name; _forwardText.text = body;
    NSString *letter = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    _forwardAvatar.image = [VKTheme avatarWithInitials:letter size:34 background:[VKTheme navBarColor]];
    NSString *url = [info objectForKey:@"photo"];
    if (url.length) { [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) { if (image) _forwardAvatar.image = image; }]; }
    UIImage *skin = [UIImage imageNamed:(outgoing ? @"Blue_Bubble" : @"Grey_Bubble")];
    _bubble.image = [skin stretchableImageWithLeftCapWidth:20 topCapHeight:15];
    _time.text = VKTimeString(date); _time.textAlignment = outgoing ? NSTextAlignmentRight : NSTextAlignmentLeft;
    [self setNeedsLayout];
}

- (void)setSticker:(NSString *)url outgoing:(BOOL)outgoing date:(NSTimeInterval)date {
    _outgoing = outgoing;
    _forwardMode = NO; _forwardAvatar.hidden = YES; _forwardName.hidden = YES; _forwardText.hidden = YES;
    _bubble.hidden = YES;
    _photoURL = nil; _photo.hidden = YES; _photo.image = nil;
    _sticker.hidden = NO;
    _time.text = VKTimeString(date);
    _time.textAlignment = outgoing ? NSTextAlignmentRight : NSTextAlignmentLeft;

    _stickerURL = [url copy];
    _sticker.image = nil;
    if (url.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) {
            _sticker.image = cached;
        } else {
            NSString *want = url;
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                if (image && [_stickerURL isEqualToString:want]) _sticker.image = image;
            }];
        }
    }
    [self setNeedsLayout];
}

- (void)setPhoto:(NSString *)url big:(NSString *)big aspect:(CGFloat)aspect outgoing:(BOOL)outgoing date:(NSTimeInterval)date {
    _outgoing = outgoing;
    _forwardMode = NO; _forwardAvatar.hidden = YES; _forwardName.hidden = YES; _forwardText.hidden = YES;
    _bubble.hidden = YES;
    _sticker.hidden = YES; _sticker.image = nil; _stickerURL = nil;
    _photo.hidden = NO;
    _photoAspect = aspect;
    _photoBig = [big copy];
    _time.text = VKTimeString(date);
    _time.textAlignment = outgoing ? NSTextAlignmentRight : NSTextAlignmentLeft;

    _photoURL = [url copy];
    _photo.image = nil;
    if (url.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) {
            _photo.image = cached;
        } else {
            NSString *want = url;
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                if (image && [_photoURL isEqualToString:want]) _photo.image = image;
            }];
        }
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;

    if (!_photo.hidden) {
        CGSize ps = [VKBubbleCell photoSizeForAspect:_photoAspect cellWidth:width];
        CGFloat x = _outgoing ? (width - ps.width - 8) : 8;
        _photo.frame = CGRectMake(x, kBubbleMargin, ps.width, ps.height);
        CGFloat timeW = 42.0, timeY = kBubbleMargin + (ps.height - 14.0) / 2.0;
        if (_outgoing) _time.frame = CGRectMake(x - timeW - 6, timeY, timeW, 14.0);
        else _time.frame = CGRectMake(x + ps.width + 6, timeY, timeW, 14.0);
        _bubble.frame = CGRectZero;
        _sticker.frame = CGRectZero;
        return;
    }

    if (_forwardMode) {
        CGFloat tw = [VKBubbleCell textWidthForCellWidth:width];
        CGSize s = [(_forwardText.text.length ? _forwardText.text : @"Запись") sizeWithFont:_forwardText.font constrainedToSize:CGSizeMake(tw - 44, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat bh = MAX(48.0, 20.0 + s.height) + kPadY * 2;
        CGFloat bw = MIN(floorf(width * kBubbleMaxFrac), MAX(150.0, s.width + 44 + kPadX * 2));
        CGFloat x = _outgoing ? width - bw - 8 : 8;
        _bubble.frame = CGRectMake(x, kBubbleMargin, bw, bh);
        _forwardAvatar.frame = CGRectMake(kPadX, kPadY + 2, 34, 34);
        _forwardName.frame = CGRectMake(kPadX + 42, kPadY, bw - kPadX * 2 - 42, 18);
        _forwardText.frame = CGRectMake(kPadX + 42, kPadY + 19, bw - kPadX * 2 - 42, s.height);
        CGFloat timeW = 42, timeY = kBubbleMargin + (bh - 14) / 2;
        _time.frame = _outgoing ? CGRectMake(x - timeW - 6, timeY, timeW, 14) : CGRectMake(x + bw + 6, timeY, timeW, 14);
        return;
    }

    if (!_sticker.hidden) {
        CGFloat x = _outgoing ? (width - kStickerSize - 8) : 8;
        _sticker.frame = CGRectMake(x, kBubbleMargin, kStickerSize, kStickerSize);
        CGFloat timeW = 42.0, timeY = kBubbleMargin + (kStickerSize - 14.0) / 2.0;
        if (_outgoing) _time.frame = CGRectMake(x - timeW - 6, timeY, timeW, 14.0);
        else _time.frame = CGRectMake(x + kStickerSize + 6, timeY, timeW, 14.0);
        _bubble.frame = CGRectZero;
        _photo.frame = CGRectZero;
        return;
    }

    NSString *t = _text.text;
    if (![t isKindOfClass:[NSString class]] || !t.length) t = @"[Вложение]";
    CGFloat tw = [VKBubbleCell textWidthForCellWidth:width];
    CGSize s = [t sizeWithFont:VKBubbleFont()
             constrainedToSize:CGSizeMake(tw, CGFLOAT_MAX)
                 lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat bw = s.width + kPadX * 2, bh = s.height + kPadY * 2;
    CGFloat x = _outgoing ? (width - bw - 8) : 8;
    _bubble.frame = CGRectMake(x, kBubbleMargin, bw, bh);
    _text.frame = CGRectMake(kPadX, kPadY, s.width, s.height);
    _photo.frame = CGRectZero;
    _sticker.frame = CGRectZero;

    CGFloat timeW = 42.0;
    CGFloat timeY = kBubbleMargin + (bh - 14.0) / 2.0;
    if (_outgoing) {
        _time.frame = CGRectMake(x - timeW - 6, timeY, timeW, 14.0);
    } else {
        _time.frame = CGRectMake(x + bw + 6, timeY, timeW, 14.0);
    }
}

@end

#pragma mark - Экран чата

@interface VKChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIActionSheetDelegate, VKEmojiPanelDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, assign) long long peerId;
@property (nonatomic, assign) CGFloat kbOverlap;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, assign) BOOL sending;
@property (nonatomic, assign) BOOL historyLoading;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIButton *emojiButton;        // переключатель панели смайликов
@property (nonatomic, strong) VKEmojiPanel *emojiPanel;     // сама панель (inputView поля)
@property (nonatomic, strong) NSMutableArray *messages; // словари getHistory
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) NSDictionary *actionMessage; // сообщение под действием
@property (nonatomic, assign) long long editId;            // id редактируемого (0 — нет)
@property (nonatomic, assign) long long replyId;           // id для ответа (0 — нет)
@property (nonatomic, strong) UIView *banner;              // плашка ответа/редактирования
@property (nonatomic, strong) UILabel *bannerLabel;
@property (nonatomic, strong) UIView *attachPreviewBar;
@property (nonatomic, strong) UIImageView *attachThumbnailView;
@property (nonatomic, strong) UIButton *attachRemoveButton;
@property (nonatomic, strong) UIImage *pendingImage;
@property (nonatomic, strong) UILabel *navTitleLabel;      // имя в две строки с статусом
@property (nonatomic, strong) UILabel *navStatusLabel;     // «в сети» / «заходил(а) …»
@property (nonatomic, strong) UIImageView *navAvatarView;
@property (nonatomic, copy) NSString *peerPhoto;
@property (nonatomic, assign) NSInteger pollTicks;         // чтобы статус дёргать реже истории
@property (nonatomic, strong) NSMutableDictionary *rowHeightCache;

- (void)buildAttachPreviewBar;
- (void)showAttachPreview:(BOOL)show;
- (void)relayoutBars;
- (void)sendTapped;
@end

@implementation VKChatViewController

- (id)initWithPeerId:(long long)peerId title:(NSString *)title {
    return [self initWithPeerId:peerId title:title photo:nil];
}

- (id)initWithPeerId:(long long)peerId title:(NSString *)title photo:(NSString *)photo {
    self = [super init];
    if (self) {
        _peerId = peerId;
        _peerPhoto = [photo copy];
        self.title = title.length ? title : @"Диалог";
        _messages = [NSMutableArray array];
        _rowHeightCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [VKTheme contentBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Назад" style:UIBarButtonItemStyleBordered target:self action:@selector(backTapped)];

    CGFloat h = self.view.bounds.size.height, w = self.view.bounds.size.width;
    CGFloat barH = 41.0; // нативная высота текстур MessageEntry* (без искажений)

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, w, h - barH) style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Тап по пустому месту / скролл — скрывает клавиатуру.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];

    // Долгое нажатие по сообщению — меню действий.
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.tableView addGestureRecognizer:lp];

    // Панель ввода — текстуры из оригинального VK.
    self.inputBar = [[UIView alloc] initWithFrame:CGRectMake(0, h - barH, w, barH)];
    self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    UIImage *barBg = [[UIImage imageNamed:@"MessageEntryBackground"]
                      resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
    if (barBg) {
        UIImageView *bg = [[UIImageView alloc] initWithFrame:self.inputBar.bounds];
        bg.image = barBg;
        bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.inputBar addSubview:bg];
    } else {
        self.inputBar.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    }

    // Кнопка отправки (текстура VK, нативная высота 29pt).
    UIButton *send = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat sendW = 70.0, sendH = 29.0;
    send.frame = CGRectMake(w - sendW - 6, (barH - sendH) / 2.0, sendW, sendH);
    send.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    UIImage *sb = [[UIImage imageNamed:@"send_button"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 12, 0, 12)];
    UIImage *sbh = [[UIImage imageNamed:@"send_button_hl"] resizableImageWithCapInsets:UIEdgeInsetsMake(0, 12, 0, 12)];
    if (sb) {
        [send setBackgroundImage:sb forState:UIControlStateNormal];
        [send setBackgroundImage:(sbh ?: sb) forState:UIControlStateHighlighted];
    } else {
        send.backgroundColor = [VKTheme navBarColor];
        send.layer.cornerRadius = 5.0;
    }
    [send setTitle:@"Отправить" forState:UIControlStateNormal];
    [send setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    send.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    send.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.3];
    send.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [send addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];

    // Кнопка панели смайликов (иконка VK 32x32) — слева от «Отправить».
    CGFloat emojiSide = 32.0;
    CGFloat emojiX = w - sendW - 6.0 - 6.0 - emojiSide;
    self.emojiButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.emojiButton.frame = CGRectMake(emojiX, roundf((barH - emojiSide) / 2.0), emojiSide, emojiSide);
    self.emojiButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.emojiButton setImage:[UIImage imageNamed:@"messages_input_selector_emoji"]
                      forState:UIControlStateNormal];
    self.emojiButton.alpha = 0.8;
    [self.emojiButton addTarget:self action:@selector(emojiTapped)
               forControlEvents:UIControlEventTouchUpInside];

    // Кнопка прикрепления фото (слева от поля ввода)
    BOOL showAttach = ![[VKBackend shared] isOVK];
    CGFloat attachSide = 32.0;
    CGFloat attachX = 4.0;
    CGFloat fieldX = showAttach ? (attachX + attachSide + 4.0) : 6.0;

    if (showAttach) {
        self.attachButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.attachButton.frame = CGRectMake(attachX, roundf((barH - attachSide) / 2.0), attachSide, attachSide);
        self.attachButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
        UIImage *cam = [UIImage imageNamed:@"wall_addphoto_icon"];
        if (cam) {
            [self.attachButton setImage:cam forState:UIControlStateNormal];
        } else {
            [self.attachButton setTitle:@"+" forState:UIControlStateNormal];
            [self.attachButton setTitleColor:[VKTheme linkColor] forState:UIControlStateNormal];
            self.attachButton.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
        }
        [self.attachButton addTarget:self action:@selector(attachTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.inputBar addSubview:self.attachButton];
    }

    // Текстовое поле (текстура VK на нативную высоту bar'а — как было, без искажений).
    self.inputField = [[VKChatInputField alloc] initWithFrame:
        CGRectMake(fieldX, 0, MAX(40.0, emojiX - fieldX - 6.0), barH)];
    self.inputField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.inputField.font = [UIFont systemFontOfSize:15.0];
    self.inputField.placeholder = @"Сообщение";
    self.inputField.returnKeyType = UIReturnKeySend;
    self.inputField.delegate = self;
    UIImage *fieldBg = [[UIImage imageNamed:@"MessageEntryInputField"]
                        resizableImageWithCapInsets:UIEdgeInsetsMake(0, 17, 0, 17)];
    if (fieldBg) {
        self.inputField.borderStyle = UITextBorderStyleNone;
        self.inputField.background = fieldBg;
    } else {
        self.inputField.borderStyle = UITextBorderStyleRoundedRect;
    }

    [self.inputBar addSubview:self.inputField];
    [self.inputBar addSubview:self.emojiButton];
    [self.inputBar addSubview:send];
    [self.view addSubview:self.inputBar];

    [self buildAttachPreviewBar];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbChange:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbChange:)
                                                 name:UIKeyboardWillHideNotification object:nil];

    [self setupTitleView];
    [self refreshPresence];
    [self loadHistory:YES];
}

// Заголовок в две строки: имя сверху, статус «в сети» снизу — как в оригинале.
- (void)setupTitleView {
    if (![self isUserPeer]) return;
    UIControl *box = [[UIControl alloc] initWithFrame:CGRectMake(0, 0, 220.0, 40.0)];
    box.backgroundColor = [UIColor clearColor];
    [box addTarget:self action:@selector(peerTapped) forControlEvents:UIControlEventTouchUpInside];

    self.navAvatarView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 4, 32, 32)];
    self.navAvatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.navAvatarView.clipsToBounds = YES;
    NSString *initial = self.title.length ? [[self.title substringToIndex:1] uppercaseString] : @"?";
    self.navAvatarView.image = [VKTheme avatarWithInitials:initial size:32 background:[VKTheme navBarColor]];
    [box addSubview:self.navAvatarView];

    self.navTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(38, 1.0, 182.0, 20.0)];
    self.navTitleLabel.backgroundColor = [UIColor clearColor];
    self.navTitleLabel.textAlignment = NSTextAlignmentLeft;
    self.navTitleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    self.navTitleLabel.textColor = [UIColor whiteColor];
    self.navTitleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.4];
    self.navTitleLabel.shadowOffset = CGSizeMake(0, -1);
    self.navTitleLabel.text = self.title;
    [box addSubview:self.navTitleLabel];

    self.navStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(38, 20.0, 182.0, 14.0)];
    self.navStatusLabel.backgroundColor = [UIColor clearColor];
    self.navStatusLabel.textAlignment = NSTextAlignmentLeft;
    self.navStatusLabel.font = [UIFont systemFontOfSize:11.0];
    self.navStatusLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    self.navStatusLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.4];
    self.navStatusLabel.shadowOffset = CGSizeMake(0, -1);
    [box addSubview:self.navStatusLabel];

    self.navigationItem.titleView = box;
    [self loadPeerPhoto:self.peerPhoto];
}

- (void)backTapped { [self.navigationController popViewControllerAnimated:YES]; }
- (void)peerTapped {
    if (![self isUserPeer]) return;
    [self.navigationController pushViewController:[[VKProfileViewController alloc] initWithUserId:self.peerId name:self.title] animated:YES];
}

- (void)loadPeerPhoto:(NSString *)url {
    if (!url.length || !self.navAvatarView) return;
    UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
    if (cached) { self.navAvatarView.image = cached; return; }
    __weak VKChatViewController *weakSelf = self;
    [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) { if (image) weakSelf.navAvatarView.image = image; }];
}

// Статус есть только у человека: у беседы (peer >= 2000000000) и паблика его нет.
- (BOOL)isUserPeer {
    return self.peerId > 0 && self.peerId < 2000000000;
}

- (void)refreshPresence {
    if (![self isUserPeer]) return;
    __weak VKChatViewController *weakSelf = self;
    [[VKAPI shared] callMethod:@"users.get"
                        params:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSString stringWithFormat:@"%lld", self.peerId], @"user_ids",
                                @"online,online_mobile,last_seen,sex,photo_100", @"fields", nil]
                    completion:^(id response, NSError *error) {
        VKChatViewController *me = weakSelf;
        if (!me || error) return;
        NSDictionary *u = nil;
        if ([response isKindOfClass:[NSArray class]] && [(NSArray *)response count]) {
            id first = [(NSArray *)response objectAtIndex:0];
            if ([first isKindOfClass:[NSDictionary class]]) u = (NSDictionary *)first;
        } else if ([response isKindOfClass:[NSDictionary class]]) {
            id items = [(NSDictionary *)response objectForKey:@"items"];
            if ([items isKindOfClass:[NSArray class]] && [(NSArray *)items count]) {
                id first = [(NSArray *)items objectAtIndex:0];
                if ([first isKindOfClass:[NSDictionary class]]) u = (NSDictionary *)first;
            } else {
                u = (NSDictionary *)response;
            }
        }
        if (![u isKindOfClass:[NSDictionary class]]) return;
        [me loadPeerPhoto:[u objectForKey:@"photo_100"]];

        id lsObj = [u objectForKey:@"last_seen"];
        NSDictionary *ls = [lsObj isKindOfClass:[NSDictionary class]] ? (NSDictionary *)lsObj : nil;
        NSInteger platform = ls ? [[ls objectForKey:@"platform"] integerValue] : 0;
        BOOL mobile = [[u objectForKey:@"online_mobile"] integerValue] != 0
                   || (platform > 0 && platform != 7);
        NSTimeInterval lastSeenTime = ls ? (NSTimeInterval)[[ls objectForKey:@"time"] doubleValue] : 0.0;
        me.navStatusLabel.text = [VKPresence textForOnline:[[u objectForKey:@"online"] integerValue] != 0
                                                   mobile:mobile
                                                 lastSeen:lastSeenTime
                                                   female:[[u objectForKey:@"sex"] integerValue] == 1];
    }];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Панель смайликов

// Переключаем inputView поля: панель смайликов ↔ обычная клавиатура.
- (void)emojiTapped {
    if (self.inputField.inputView) {
        self.inputField.inputView = nil;
    } else {
        if (!self.emojiPanel) {
            self.emojiPanel = [[VKEmojiPanel alloc] initWithFrame:
                CGRectMake(0.0, 0.0, self.view.bounds.size.width, [VKEmojiPanel panelHeight])];
            self.emojiPanel.pickerDelegate = self;
        }
        self.inputField.inputView = self.emojiPanel;
    }
    self.emojiButton.alpha = self.inputField.inputView ? 1.0 : 0.8;
    if ([self.inputField isFirstResponder]) {
        [self.inputField reloadInputViews];
    } else {
        [self.inputField becomeFirstResponder];
    }
}

- (void)emojiPanel:(VKEmojiPanel *)panel didPickEmoji:(NSString *)emoji {
    UITextRange *range = self.inputField.selectedTextRange;
    if (range) {
        [self.inputField replaceRange:range withText:emoji];
    } else {
        NSString *cur = self.inputField.text ?: @"";
        self.inputField.text = [cur stringByAppendingString:emoji];
    }
}

- (void)emojiPanelDidTapBackspace:(VKEmojiPanel *)panel {
    if ([self.inputField hasText]) [self.inputField deleteBackward];
}

- (void)emojiPanelDidRequestKeyboard:(VKEmojiPanel *)panel {
    self.inputField.inputView = nil;
    self.emojiButton.alpha = 0.8;
    [self.inputField reloadInputViews];
}

// Стикер уходит отдельным сообщением (текст с ним VK не принимает),
// поэтому набранный черновик остаётся в поле нетронутым.
- (void)emojiPanel:(VKEmojiPanel *)panel
   didPickStickerId:(long long)stickerId
         previewURL:(NSString *)previewURL {
    [self alert:@"Стикеры" msg:@"OpenVK пока не поддерживает отправку стикеров через API."];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Автообновление переписки, пока экран открыт (входящие появляются сами).
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self
                        selector:@selector(pollTick) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)pollTick {
    [self loadHistory:NO];
    // Статус меняется медленнее переписки — обновляем раз в ~30 секунд.
    self.pollTicks += 1;
    if (self.pollTicks % 10 == 0) [self refreshPresence];
}

- (void)dealloc {
    [self.pollTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadHistory:(BOOL)initial {
    if (self.historyLoading) return;
    self.historyLoading = YES;
    [[VKAPI shared] callMethod:@"messages.getHistory"
                        params:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSString stringWithFormat:@"%lld", self.peerId], @"peer_id",
                                @"60", @"count", nil]
                    completion:^(id response, NSError *error) {
        self.historyLoading = NO;
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            if (initial) [self alert:@"Не удалось загрузить переписку" msg:error.localizedDescription ?: @"Некорректный ответ сервера"];
            return;
        }
        NSArray *items = [response objectForKey:@"items"];
        if (![items isKindOfClass:[NSArray class]]) return;
        // getHistory отдаёт от новых к старым — переворачиваем.
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSInteger i = items.count - 1; i >= 0; i--) [ordered addObject:[items objectAtIndex:i]];

        // Определяем, появились ли новые сообщения (по id последнего).
        long long oldLast = [self lastMessageId:self.messages];
        long long newLast = [self lastMessageId:ordered];
        BOOL grew = (ordered.count != self.messages.count) || (newLast != oldLast);

        BOOL wasAtBottom = [self isNearBottom];
        self.messages = ordered;
        [self.tableView reloadData];
        if (initial || (grew && wasAtBottom)) {
            [self scrollToBottom:!initial];
        }
    }];
}

- (long long)lastMessageId:(NSArray *)arr {
    NSDictionary *m = [arr lastObject];
    return m ? [[m objectForKey:@"id"] longLongValue] : 0;
}

- (BOOL)isNearBottom {
    CGFloat offY = self.tableView.contentOffset.y;
    CGFloat maxY = self.tableView.contentSize.height - self.tableView.bounds.size.height;
    return (maxY - offY) < 120.0 || maxY <= 0;
}

- (void)scrollToBottom:(BOOL)animated {
    NSInteger n = self.messages.count;
    if (n > 0) {
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0]
                              atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    }
}

#pragma mark - Фото-вложения

- (void)buildAttachPreviewBar {
    CGFloat w = self.view.bounds.size.width;
    CGFloat prevH = 44.0;
    self.attachPreviewBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, prevH)];
    self.attachPreviewBar.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    self.attachPreviewBar.hidden = YES;

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5)];
    topLine.backgroundColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.attachPreviewBar addSubview:topLine];

    self.attachThumbnailView = [[UIImageView alloc] initWithFrame:CGRectMake(8.0, 5.0, 34.0, 34.0)];
    self.attachThumbnailView.contentMode = UIViewContentModeScaleAspectFill;
    self.attachThumbnailView.clipsToBounds = YES;
    self.attachThumbnailView.layer.cornerRadius = 4.0;
    self.attachThumbnailView.layer.borderColor = [UIColor colorWithWhite:0.7 alpha:1.0].CGColor;
    self.attachThumbnailView.layer.borderWidth = 0.5;
    [self.attachPreviewBar addSubview:self.attachThumbnailView];

    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(50.0, 12.0, w - 90.0, 20.0)];
    lbl.text = @"Прикреплена фотография";
    lbl.font = [UIFont systemFontOfSize:13.0];
    lbl.textColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    lbl.backgroundColor = [UIColor clearColor];
    lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.attachPreviewBar addSubview:lbl];

    self.attachRemoveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.attachRemoveButton.frame = CGRectMake(w - 36.0, 6.0, 30.0, 30.0);
    self.attachRemoveButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.attachRemoveButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.attachRemoveButton setTitleColor:[UIColor colorWithWhite:0.4 alpha:1.0] forState:UIControlStateNormal];
    self.attachRemoveButton.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    [self.attachRemoveButton addTarget:self action:@selector(removeAttachTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.attachPreviewBar addSubview:self.attachRemoveButton];

    [self.view addSubview:self.attachPreviewBar];
}

- (void)showAttachPreview:(BOOL)show {
    if (show && self.pendingImage) {
        self.attachThumbnailView.image = self.pendingImage;
        self.attachPreviewBar.hidden = NO;
    } else {
        self.attachPreviewBar.hidden = YES;
        self.pendingImage = nil;
    }
    [self relayoutBars];
}

- (void)removeAttachTapped {
    [self showAttachPreview:NO];
}

- (void)attachTapped {
    [self.inputField resignFirstResponder];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Прикрепить фотографию"
                                                       delegate:self
                                              cancelButtonTitle:@"Отмена"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Сделать снимок", @"Выбрать из галереи", nil];
    sheet.tag = 888;
    [sheet showInView:self.view];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *img = [info objectForKey:UIImagePickerControllerEditedImage] ?: [info objectForKey:UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (img) {
        self.pendingImage = img;
        [self showAttachPreview:YES];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark Send / Edit

- (void)sendTapped {
    if (self.sending) return;
    NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UIImage *photo = self.pendingImage;
    long long editId = self.editId;
    if (!text.length && !photo) return;
    self.sending = YES;
    self.inputField.enabled = NO;
    void (^finish)(id, NSError *) = ^(id response, NSError *error) {
        self.sending = NO;
        self.inputField.enabled = YES;
        if (error) {
            [self alert:@"Не отправлено" msg:error.localizedDescription];
            return; // Keep the draft and attachment for an explicit retry.
        }
        self.inputField.text = @"";
        self.pendingImage = nil;
        [self showAttachPreview:NO];
        [self clearComposeState];
        [self loadHistory:NO];
    };
    void (^send)(NSString *) = ^(NSString *attachment) {
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{@"peer_id": @(self.peerId), @"message": text ?: @""}];
        if (attachment.length) [params setObject:attachment forKey:@"attachment"];
        if (editId) [params setObject:@(editId) forKey:@"message_id"];
        [[VKAPI shared] callMethod:(editId ? @"messages.edit" : @"messages.send") params:params completion:finish];
    };
    if (photo) {
        [VKUploader uploadMessagesPhoto:photo peerId:self.peerId completion:^(NSString *attachment, NSError *error) {
            if (error || !attachment.length) {
                finish(nil, error ?: [NSError errorWithDomain:@"OpenVK" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Не удалось загрузить фото"}]);
            } else send(attachment);
        }];
    } else send(nil);
}

- (void)alert:(NSString *)title msg:(NSString *)msg {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:title message:msg delegate:nil
                        cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendTapped];
    return NO;
}

#pragma mark Keyboard

- (void)kbChange:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect endInView = [self.view convertRect:end fromView:nil];
    self.kbOverlap = MAX(0, self.view.bounds.size.height - endInView.origin.y);
    NSTimeInterval dur = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur animations:^{
        [self relayoutBars];
    } completion:^(BOOL f){ [self scrollToBottom:NO]; }];
}

#pragma mark Долгое нажатие / действия

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:[g locationInView:self.tableView]];
    if (!ip) return;
    self.actionMessage = [self.messages objectAtIndex:ip.row];
    BOOL own = [[self.actionMessage objectForKey:@"from_id"] longLongValue] == [VKSession shared].userId;
    BOOL canEdit = own && [[self.actionMessage objectForKey:@"id"] longLongValue] != 0;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self
                            cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:@"Цитировать текст"];
    [sheet addButtonWithTitle:@"Скопировать"];
    [sheet addButtonWithTitle:@"Переслать текст"];
    if (canEdit) [sheet addButtonWithTitle:@"Редактировать"];
    sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Удалить"];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Отмена"];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;

    if (actionSheet.tag == 888) {
        if (buttonIndex == 0) {
            // Камера
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
                UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                picker.sourceType = UIImagePickerControllerSourceTypeCamera;
                picker.delegate = self;
                [self presentViewController:picker animated:YES completion:nil];
            } else {
                [self alert:@"Камера" msg:@"Камера недоступна на этом устройстве"];
            }
        } else if (buttonIndex == 1) {
            // Галерея
            if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
                UIImagePickerController *picker = [[UIImagePickerController alloc] init];
                picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                picker.delegate = self;
                [self presentViewController:picker animated:YES completion:nil];
            }
        }
        return;
    }

    NSString *title = [actionSheet buttonTitleAtIndex:buttonIndex];
    if ([title isEqualToString:@"Цитировать текст"]) [self doReply];
    else if ([title isEqualToString:@"Скопировать"]) [self doCopy];
    else if ([title isEqualToString:@"Переслать текст"]) [self doForward];
    else if ([title isEqualToString:@"Редактировать"]) [self doEdit];
    else if ([title isEqualToString:@"Удалить"]) [self doDelete];
}

- (void)doCopy {
    NSString *t = [self.actionMessage objectForKey:@"text"];
    if (t) [UIPasteboard generalPasteboard].string = t;
}

- (void)doReply {
    NSString *quote = [self.actionMessage objectForKey:@"text"] ?: @"";
    if (!quote.length) { [self alert:@"Цитата" msg:@"В этом сообщении нет текста для цитирования."]; return; }
    [self clearComposeState];
    self.inputField.text = [NSString stringWithFormat:@"«%@» — %@", quote, self.inputField.text ?: @""];
    [self.inputField becomeFirstResponder];
}

- (void)doEdit {
    self.replyId = 0;
    self.editId = [[self.actionMessage objectForKey:@"id"] longLongValue];
    self.inputField.text = [self.actionMessage objectForKey:@"text"];
    [self showBanner:@"Редактирование сообщения"];
    [self.inputField becomeFirstResponder];
}

- (void)doDelete {
    long long mid = [[self.actionMessage objectForKey:@"id"] longLongValue];
    if (!mid) return;
    [[VKAPI shared] callMethod:@"messages.delete" params:@{@"message_ids": @(mid)} completion:^(id response, NSError *error) {
        NSString *key = [NSString stringWithFormat:@"%lld", mid];
        if (error || ![[response objectForKey:key] boolValue]) {
            [self alert:@"Не удалось удалить" msg:error.localizedDescription ?: @"Сервер не подтвердил удаление"];
            return;
        }
        [self loadHistory:NO];
    }];
}

- (void)doForward {
    NSString *text = [self.actionMessage objectForKey:@"text"];
    if (!text.length) { [self alert:@"Пересылка текста" msg:@"В этом сообщении нет текста. Пересылка вложений не поддерживается сервером."]; return; }
    NSString *forward = [NSString stringWithFormat:@"Пересланный текст:\n%@", text];
    VKForwardPickerViewController *picker = [[VKForwardPickerViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    picker.onPick = ^(long long targetPeer) {
        [[VKAPI shared] callMethod:@"messages.send" params:@{@"peer_id": @(targetPeer), @"message": forward} completion:^(id r, NSError *e) {
            [weakSelf alert:(e ? @"Не отправлено" : @"Текст отправлен") msg:e.localizedDescription ?: @""];
        }];
    };
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}

#pragma mark Плашка ответа/редактирования

- (void)showBanner:(NSString *)text {
    if (!self.banner) {
        self.banner = [[UIView alloc] initWithFrame:CGRectZero];
        self.banner.backgroundColor = [UIColor colorWithRed:0.90 green:0.93 blue:0.97 alpha:1.0];
        self.bannerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.bannerLabel.font = [UIFont systemFontOfSize:13.0];
        self.bannerLabel.textColor = [VKTheme linkColor];
        [self.banner addSubview:self.bannerLabel];
        UIButton *x = [UIButton buttonWithType:UIButtonTypeCustom];
        x.tag = 91;
        [x setTitle:@"✕" forState:UIControlStateNormal];
        [x setTitleColor:[VKTheme secondaryTextColor] forState:UIControlStateNormal];
        x.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
        [x addTarget:self action:@selector(cancelCompose) forControlEvents:UIControlEventTouchUpInside];
        [self.banner addSubview:x];
        [self.view addSubview:self.banner];
    }
    self.bannerLabel.text = text;
    self.banner.hidden = NO;
    [self relayoutBars];
}

- (void)cancelCompose {
    if (self.editId != 0) self.inputField.text = @"";
    [self clearComposeState];
}

- (void)clearComposeState {
    self.editId = 0;
    self.replyId = 0;
    self.banner.hidden = YES;
    [self relayoutBars];
}

- (void)relayoutBars {
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat barH = self.inputBar.bounds.size.height > 0 ? self.inputBar.bounds.size.height : 41.0;
    CGFloat bannerH = (self.banner && !self.banner.hidden) ? 34.0 : 0.0;
    CGFloat attachPrevH = (self.attachPreviewBar && !self.attachPreviewBar.hidden) ? 44.0 : 0.0;
    CGFloat extraH = bannerH + attachPrevH;
    CGFloat bottom = h - self.kbOverlap;

    self.inputBar.frame = CGRectMake(0, bottom - barH, w, barH);
    if (self.attachPreviewBar) {
        self.attachPreviewBar.frame = CGRectMake(0, bottom - barH - attachPrevH, w, attachPrevH);
    }
    if (self.banner) {
        self.banner.frame = CGRectMake(0, bottom - barH - attachPrevH - bannerH, w, bannerH);
        self.bannerLabel.frame = CGRectMake(12, 0, w - 50, bannerH);
        [[self.banner viewWithTag:91] setFrame:CGRectMake(w - 38, 0, 34, bannerH)];
    }
    self.tableView.frame = CGRectMake(0, 0, w, bottom - barH - extraH);
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *m = [self.messages objectAtIndex:indexPath.row];
    id mid = [m objectForKey:@"id"] ?: [NSNumber numberWithInteger:indexPath.row];
    NSNumber *cached = [self.rowHeightCache objectForKey:mid];
    if (cached) return [cached floatValue];

    CGFloat h = 0.0;
    NSDictionary *forward = [self forwardInfo:m];
    if (forward) {
        h = [VKBubbleCell heightForForwardText:[forward objectForKey:@"text"] width:tableView.bounds.size.width];
    } else if ([self stickerURL:m]) {
        h = [VKBubbleCell stickerHeight];
    } else {
        NSDictionary *ph = [self photoInfo:m];
        if (ph) {
            CGSize ps = [VKBubbleCell photoSizeForAspect:[[ph objectForKey:@"aspect"] floatValue]
                                               cellWidth:tableView.bounds.size.width];
            h = ps.height + kBubbleMargin * 2;
        } else {
            h = [VKBubbleCell heightForText:[m objectForKey:@"text"] width:tableView.bounds.size.width];
        }
    }
    [self.rowHeightCache setObject:[NSNumber numberWithFloat:h] forKey:mid];
    return h;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKBubbleCell";
    VKBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) cell = [[VKBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    NSDictionary *m = [self.messages objectAtIndex:indexPath.row];
    BOOL outgoing = [[m objectForKey:@"from_id"] longLongValue] == [VKSession shared].userId;
    NSTimeInterval date = [[m objectForKey:@"date"] doubleValue];
    NSString *sticker = [self stickerURL:m];
    NSDictionary *ph = [self photoInfo:m];
    NSDictionary *forward = [self forwardInfo:m];
    __weak VKChatViewController *weakSelf = self;
    cell.onPhotoTap = ^(NSString *bigURL, UIImage *img) {
        VKPhotoViewController *v = [[VKPhotoViewController alloc] initWithImage:img url:bigURL];
        v.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [weakSelf presentViewController:v animated:YES completion:nil];
    };
    cell.onForwardAuthorTap = ^(long long ownerId, NSString *name) {
        [weakSelf.navigationController pushViewController:[[VKProfileViewController alloc] initWithUserId:ownerId name:name] animated:YES];
    };
    if (forward) [cell setForward:forward outgoing:outgoing date:date];
    else if (sticker) [cell setSticker:sticker outgoing:outgoing date:date];
    else if (ph) [cell setPhoto:[ph objectForKey:@"thumb"] big:[ph objectForKey:@"big"]
                         aspect:[[ph objectForKey:@"aspect"] floatValue] outgoing:outgoing date:date];
    else [cell setText:[m objectForKey:@"text"] outgoing:outgoing date:date];
    return cell;
}

- (NSDictionary *)forwardInfo:(NSDictionary *)message {
    NSDictionary *wall = nil;
    for (id raw in [message objectForKey:@"attachments"]) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [raw objectForKey:@"type"];
        if ([type isEqualToString:@"wall"] || [type isEqualToString:@"post"]) {
            wall = [raw objectForKey:type]; if (![wall isKindOfClass:[NSDictionary class]]) wall = [raw objectForKey:@"wall"];
            break;
        }
    }
    if (!wall) {
        NSArray *forwarded = [message objectForKey:@"fwd_messages"];
        if ([forwarded isKindOfClass:[NSArray class]] && forwarded.count && [[forwarded objectAtIndex:0] isKindOfClass:[NSDictionary class]]) wall = [forwarded objectAtIndex:0];
    }
    if (!wall) return nil;
    long long owner = [[wall objectForKey:@"from_id"] longLongValue];
    if (!owner) owner = [[wall objectForKey:@"owner_id"] longLongValue];
    NSString *name = [wall objectForKey:@"author_name"] ?: [wall objectForKey:@"name"];
    NSString *photo = [wall objectForKey:@"author_photo"] ?: [wall objectForKey:@"photo_100"];
    NSString *body = [wall objectForKey:@"text"];
    if (![body isKindOfClass:[NSString class]] || !body.length) body = @"Пересланная запись";
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:@(owner), @"owner", body, @"text", nil];
    if ([name isKindOfClass:[NSString class]] && name.length) [result setObject:name forKey:@"name"];
    if ([photo isKindOfClass:[NSString class]] && photo.length) [result setObject:photo forKey:@"photo"];
    return result;
}

// Фото-вложение сообщения: thumb (~x/m), big (~y/z) и соотношение сторон.
- (NSDictionary *)photoInfo:(NSDictionary *)m {
    if ([m objectForKey:@"photo_local"]) {
        NSString *localKey = [m objectForKey:@"photo_local"];
        return [NSDictionary dictionaryWithObjectsAndKeys:
                localKey, @"thumb",
                localKey, @"big",
                [NSNumber numberWithFloat:1.0], @"aspect", nil];
    }
    for (NSDictionary *att in [m objectForKey:@"attachments"]) {
        if (![[att objectForKey:@"type"] isEqualToString:@"photo"]) continue;
        NSDictionary *ph = [att objectForKey:@"photo"];
        NSArray *sizes = [ph objectForKey:@"sizes"];
        NSString *thumb = nil, *big = nil; CGFloat aspect = 0.0;
        if ([sizes isKindOfClass:[NSArray class]] && sizes.count > 0) {
            for (NSDictionary *sz in sizes) {
                NSString *t = [sz objectForKey:@"type"];
                if ([t isEqualToString:@"x"] || [t isEqualToString:@"m"]) {
                    thumb = [sz objectForKey:@"url"] ?: [sz objectForKey:@"src"];
                    CGFloat w = [[sz objectForKey:@"width"] floatValue], h = [[sz objectForKey:@"height"] floatValue];
                    if (w > 0 && h > 0) aspect = h / w;
                }
                if ([t isEqualToString:@"y"] || [t isEqualToString:@"z"] || [t isEqualToString:@"w"]) {
                    big = [sz objectForKey:@"url"] ?: [sz objectForKey:@"src"];
                }
            }
        }
        if (!thumb) thumb = [ph objectForKey:@"photo_604"] ?: [ph objectForKey:@"photo_130"] ?: [ph objectForKey:@"src_big"] ?: [ph objectForKey:@"src"];
        if (!big) big = [ph objectForKey:@"photo_1280"] ?: [ph objectForKey:@"photo_800"] ?: [ph objectForKey:@"photo_604"] ?: thumb;
        if (!thumb) thumb = big;
        if (!big) big = thumb;
        if (thumb) return [NSDictionary dictionaryWithObjectsAndKeys:
                           thumb, @"thumb", big, @"big",
                           [NSNumber numberWithFloat:(aspect > 0 ? aspect : 1.0)], @"aspect", nil];
    }
    return nil;
}

// URL стикера из вложений сообщения (берём картинку ~256px — бабл 128pt,
// на retina это ровно 2x), иначе nil.
- (NSString *)stickerURL:(NSDictionary *)m {
    for (NSDictionary *att in [m objectForKey:@"attachments"]) {
        if (![[att objectForKey:@"type"] isEqualToString:@"sticker"]) continue;
        NSDictionary *st = [att objectForKey:@"sticker"];
        NSArray *images = [st objectForKey:@"images"];
        NSString *best = nil; CGFloat bestDelta = 1e9;
        for (NSDictionary *img in images) {
            CGFloat wdt = [[img objectForKey:@"width"] floatValue];
            CGFloat d = fabs(wdt - 256.0);
            if (d < bestDelta) { bestDelta = d; best = [img objectForKey:@"url"]; }
        }
        return best;
    }
    return nil;
}

@end

#pragma mark - Пикер диалога для пересылки

@interface VKForwardPickerViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tv;
@property (nonatomic, strong) NSArray *rows; // @{title, peer}
@end

@implementation VKForwardPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Переслать в…";
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(cancel)];
    self.tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tv.dataSource = self; self.tv.delegate = self;
    [self.view addSubview:self.tv];

    [[VKAPI shared] callMethod:@"messages.getConversations"
                        params:@{@"count": @"40", @"extended": @"1"}
                    completion:^(id response, NSError *error) {
        if (![response isKindOfClass:[NSDictionary class]]) return;
        NSMutableDictionary *dir = [NSMutableDictionary dictionary];
        for (NSDictionary *p in [response objectForKey:@"profiles"])
            [dir setObject:[NSString stringWithFormat:@"%@ %@", [p objectForKey:@"first_name"] ?: @"",
                            [p objectForKey:@"last_name"] ?: @""]
                    forKey:[NSString stringWithFormat:@"%@", [p objectForKey:@"id"]]];
        for (NSDictionary *g in [response objectForKey:@"groups"])
            [dir setObject:([g objectForKey:@"name"] ?: @"")
                    forKey:[NSString stringWithFormat:@"-%@", [g objectForKey:@"id"]]];
        NSMutableArray *r = [NSMutableArray array];
        for (NSDictionary *item in [response objectForKey:@"items"]) {
            NSDictionary *peer = [[item objectForKey:@"conversation"] objectForKey:@"peer"];
            NSString *pid = [NSString stringWithFormat:@"%@", [peer objectForKey:@"id"]];
            NSString *title = [dir objectForKey:pid];
            if (!title) {
                NSDictionary *cs = [[item objectForKey:@"conversation"] objectForKey:@"chat_settings"];
                title = [cs objectForKey:@"title"] ?: @"Диалог";
            }
            [r addObject:@{@"title": title, @"peer": [peer objectForKey:@"id"] ?: @0}];
        }
        self.rows = r;
        [self.tv reloadData];
    }];
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"fwd"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"fwd"];
    c.textLabel.text = [[self.rows objectAtIndex:indexPath.row] objectForKey:@"title"];
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    long long peer = [[[self.rows objectAtIndex:indexPath.row] objectForKey:@"peer"] longLongValue];
    if (self.onPick) self.onPick(peer);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
