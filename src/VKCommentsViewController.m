#import "VKCommentsViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKImageLoader.h"
#import "VKProfileViewController.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kCAvatar = 36.0;
static const CGFloat kCPad = 10.0;
static const CGFloat kCGap = 8.0;

static UIFont *VKCommentFont(void) { return [UIFont systemFontOfSize:13.0]; }

// «5 минут назад» — как в ленте.
static NSString *VKCommentPlural(NSInteger n, NSString *one, NSString *few, NSString *many) {
    NSInteger a = ABS(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return many;
    if (b == 1) return one;
    if (b > 1 && b < 5) return few;
    return many;
}

static NSString *VKCommentTime(NSTimeInterval ts) {
    if (ts <= 0) return @"";
    NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - ts;
    if (diff < 60) return @"только что";
    if (diff < 3600) {
        int m = (int)(diff / 60);
        return [NSString stringWithFormat:@"%d %@ назад", m,
                VKCommentPlural(m, @"минуту", @"минуты", @"минут")];
    }
    if (diff < 86400) {
        int h = (int)(diff / 3600);
        return [NSString stringWithFormat:@"%d %@ назад", h,
                VKCommentPlural(h, @"час", @"часа", @"часов")];
    }
    int d = (int)(diff / 86400);
    return [NSString stringWithFormat:@"%d %@ назад", d,
            VKCommentPlural(d, @"день", @"дня", @"дней")];
}

#pragma mark - Ячейка комментария

@interface VKCommentCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UIImageView *likeIcon;
@property (nonatomic, strong) UILabel *likeLabel;
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) void (^onAuthorTap)(void);
+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width;
- (void)fill:(NSDictionary *)row;
@end

@implementation VKCommentCell

+ (CGFloat)textWidthForWidth:(CGFloat)width {
    return width - kCPad - kCAvatar - kCGap - kCPad;
}

+ (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
    CGFloat textH = 0.0;
    if (text.length) {
        textH = [text sizeWithFont:VKCommentFont()
                 constrainedToSize:CGSizeMake([self textWidthForWidth:width], CGFLOAT_MAX)
                     lineBreakMode:NSLineBreakByWordWrapping].height;
    }
    CGFloat h = 8.0 + 16.0 + 2.0 + textH + 10.0;
    return MAX(h, 8.0 + kCAvatar + 8.0);
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(kCPad, 8.0, kCAvatar, kCAvatar)];
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        _avatarView.clipsToBounds = YES;
        _avatarView.layer.cornerRadius = 0.0;
        _avatarView.userInteractionEnabled = YES;
        [_avatarView addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(authorTapped)]];
        [self.contentView addSubview:_avatarView];

        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont boldSystemFontOfSize:13.0];
        _nameLabel.textColor = [VKTheme linkColor];
        _nameLabel.userInteractionEnabled = YES;
        [_nameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(authorTapped)]];
        [self.contentView addSubview:_nameLabel];

        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.font = [UIFont systemFontOfSize:11.0];
        _timeLabel.textColor = [VKTheme secondaryTextColor];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_timeLabel];

        _bodyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _bodyLabel.font = VKCommentFont();
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
        _bodyLabel.textColor = [VKTheme primaryTextColor];
        [self.contentView addSubview:_bodyLabel];

        _likeIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"comment_like"]];
        _likeIcon.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_likeIcon];

        _likeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _likeLabel.font = [UIFont systemFontOfSize:11.0];
        _likeLabel.textColor = [VKTheme secondaryTextColor];
        [self.contentView addSubview:_likeLabel];
    }
    return self;
}

- (void)authorTapped {
    if (self.onAuthorTap) self.onAuthorTap();
}

- (void)fill:(NSDictionary *)row {
    NSString *name = [row objectForKey:@"name"] ?: @"";
    self.nameLabel.text = name;
    self.timeLabel.text = VKCommentTime([[row objectForKey:@"date"] doubleValue]);
    self.bodyLabel.text = [row objectForKey:@"text"] ?: @"";

    NSInteger likes = [[row objectForKey:@"likes"] integerValue];
    self.likeLabel.text = likes > 0 ? [NSString stringWithFormat:@"%d", (int)likes] : @"";
    self.likeIcon.hidden = (likes <= 0);

    NSString *initials = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    self.avatarView.image = [VKTheme avatarWithInitials:initials size:kCAvatar
                                            background:[VKTheme navBarColor]];
    NSString *url = [row objectForKey:@"photo"];
    self.avatarURL = url;
    if (url.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) {
            self.avatarView.image = cached;
        } else {
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                if (image && [self.avatarURL isEqualToString:url]) self.avatarView.image = image;
            }];
        }
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat x = kCPad + kCAvatar + kCGap;
    CGFloat w = [VKCommentCell textWidthForWidth:width];
    self.nameLabel.frame = CGRectMake(x, 8.0, w * 0.6, 16.0);
    self.timeLabel.frame = CGRectMake(x + w * 0.6, 8.0, w * 0.4, 16.0);

    CGFloat textH = 0.0;
    if (self.bodyLabel.text.length) {
        textH = [self.bodyLabel.text sizeWithFont:VKCommentFont()
                                constrainedToSize:CGSizeMake(w, CGFLOAT_MAX)
                                    lineBreakMode:NSLineBreakByWordWrapping].height;
    }
    self.bodyLabel.frame = CGRectMake(x, 26.0, w, textH);

    CGFloat likeY = 26.0 + textH - 4.0;
    self.likeIcon.frame = CGRectMake(width - kCPad - 34.0, likeY, 14.0, 14.0);
    self.likeLabel.frame = CGRectMake(width - kCPad - 18.0, likeY, 18.0, 14.0);
}

@end

#pragma mark - Поле ввода

// Текстовое поле с отступами под текстуру MessageEntryInputField — как в чате.
@interface VKCommentInputField : UITextField
@end
@implementation VKCommentInputField
- (CGRect)insetRect:(CGRect)b {
    CGFloat lh = self.font.lineHeight;
    CGFloat y = floorf((b.size.height - lh) / 2.0);
    return CGRectMake(b.origin.x + 14, y, b.size.width - 24, lh);
}
- (CGRect)textRectForBounds:(CGRect)b { return [self insetRect:b]; }
- (CGRect)editingRectForBounds:(CGRect)b { return [self insetRect:b]; }
- (CGRect)placeholderRectForBounds:(CGRect)b { return [self insetRect:b]; }
@end

#pragma mark - Экран комментариев

@interface VKCommentsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    long long _ownerId;
    long long _postId;
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) VKCommentInputField *inputField;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSMutableDictionary *rowHeightCache;
@property (nonatomic, assign) CGFloat kbOverlap;
@property (nonatomic, assign) BOOL sending;
@end

@implementation VKCommentsViewController

- (id)initWithOwnerId:(long long)ownerId postId:(long long)postId {
    self = [super init];
    if (self) {
        _ownerId = ownerId;
        _postId = postId;
        _rows = [NSMutableArray array];
        _rowHeightCache = [NSMutableDictionary dictionary];
        self.title = @"Комментарии";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [VKTheme contentBackgroundColor];
    [VKTheme styleNavigationBar:self.navigationController.navigationBar];

    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat barH = 41.0; // нативная высота текстур MessageEntry*

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, w, h - barH)
                                                 style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorColor = [VKTheme separatorColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 60.0, w, 20.0)];
    self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.font = [UIFont systemFontOfSize:14.0];
    self.emptyLabel.textColor = [VKTheme secondaryTextColor];
    self.emptyLabel.text = @"Загрузка…";
    [self.tableView addSubview:self.emptyLabel];

    [self buildInputBarWidth:w height:barH top:h - barH];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbChange:)
                                                 name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbChange:)
                                                 name:UIKeyboardWillHideNotification object:nil];

    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Панель ввода один в один как в чате: текстура фона, поле и кнопка «Отправить».
- (void)buildInputBarWidth:(CGFloat)w height:(CGFloat)barH top:(CGFloat)top {
    self.inputBar = [[UIView alloc] initWithFrame:CGRectMake(0, top, w, barH)];
    self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    UIImage *barBg = [[UIImage imageNamed:@"MessageEntryBackground"]
                      resizableImageWithCapInsets:UIEdgeInsetsMake(0, 4, 0, 4)];
    if (barBg) {
        UIImageView *bg = [[UIImageView alloc] initWithFrame:self.inputBar.bounds];
        bg.image = barBg;
        bg.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.inputBar addSubview:bg];
    } else {
        self.inputBar.backgroundColor = [VKTheme cardColor];
    }

    UIButton *send = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat sendW = 70.0, sendH = 29.0;
    send.frame = CGRectMake(w - sendW - 6.0, (barH - sendH) / 2.0, sendW, sendH);
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

    self.inputField = [[VKCommentInputField alloc] initWithFrame:
        CGRectMake(6.0, 0.0, MAX(40.0, w - sendW - 18.0), barH)];
    self.inputField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.inputField.font = [UIFont systemFontOfSize:15.0];
    self.inputField.placeholder = @"Комментарий";
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
    [self.inputBar addSubview:send];
    [self.view addSubview:self.inputBar];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)kbChange:(NSNotification *)note {
    CGRect end = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect endInView = [self.view convertRect:end fromView:nil];
    self.kbOverlap = MAX(0.0, self.view.bounds.size.height - endInView.origin.y);
    NSTimeInterval dur = [[note.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:dur animations:^{ [self relayoutBars]; }];
}

- (void)relayoutBars {
    CGFloat w = self.view.bounds.size.width;
    CGFloat bottom = self.view.bounds.size.height - self.kbOverlap;
    CGFloat barH = self.inputBar.bounds.size.height > 0 ? self.inputBar.bounds.size.height : 41.0;
    self.inputBar.frame = CGRectMake(0, bottom - barH, w, barH);
    self.tableView.frame = CGRectMake(0, 0, w, bottom - barH);
}

#pragma mark - Загрузка

- (void)reload {
    __weak VKCommentsViewController *weakSelf = self;
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSString stringWithFormat:@"%lld", _ownerId], @"owner_id",
        [NSString stringWithFormat:@"%lld", _postId], @"post_id",
        @"100", @"count",
        @"asc", @"sort",
        @"1", @"extended",
        @"1", @"need_likes",
        @"photo_100", @"fields", nil];
    [[VKAPI shared] callMethod:@"wall.getComments" params:params completion:^(id response, NSError *error) {
        VKCommentsViewController *me = weakSelf;
        if (!me) return;
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            me.emptyLabel.text = @"Не удалось загрузить комментарии";
            me.emptyLabel.hidden = NO;
            return;
        }
        [me parseComments:(NSDictionary *)response];
    }];
}

// В extended-ответе имена и аватары лежат отдельно от комментариев —
// собираем справочник id -> {name, photo} (у групп id отрицательный).
- (NSDictionary *)directoryFrom:(NSDictionary *)response {
    NSMutableDictionary *dir = [NSMutableDictionary dictionary];
    id profiles = [response objectForKey:@"profiles"];
    if ([profiles isKindOfClass:[NSArray class]]) {
        for (id p in (NSArray *)profiles) {
            if (![p isKindOfClass:[NSDictionary class]]) continue;
            NSString *first = [p objectForKey:@"first_name"] ?: @"";
            NSString *last = [p objectForKey:@"last_name"] ?: @"";
            NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *key = [NSString stringWithFormat:@"%lld", [[p objectForKey:@"id"] longLongValue]];
            [dir setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            name, @"name",
                            ([p objectForKey:@"photo_100"] ?: @""), @"photo", nil] forKey:key];
        }
    }
    id groups = [response objectForKey:@"groups"];
    if ([groups isKindOfClass:[NSArray class]]) {
        for (id g in (NSArray *)groups) {
            if (![g isKindOfClass:[NSDictionary class]]) continue;
            long long gid = [[g objectForKey:@"id"] longLongValue];
            NSString *key = [NSString stringWithFormat:@"%lld", -ABS(gid)];
            [dir setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            ([g objectForKey:@"name"] ?: @""), @"name",
                            ([g objectForKey:@"photo_100"] ?: @""), @"photo", nil] forKey:key];
        }
    }
    return dir;
}

- (void)parseComments:(NSDictionary *)response {
    NSDictionary *dir = [self directoryFrom:response];
    id items = [response objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) items = [NSArray array];

    NSMutableArray *rows = [NSMutableArray array];
    for (id item in (NSArray *)items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        long long from = [[item objectForKey:@"from_id"] longLongValue];
        NSDictionary *who = [dir objectForKey:[NSString stringWithFormat:@"%lld", from]];
        NSInteger likes = 0;
        id likesObj = [item objectForKey:@"likes"];
        if ([likesObj isKindOfClass:[NSDictionary class]]) {
            likes = [[(NSDictionary *)likesObj objectForKey:@"count"] integerValue];
        }
        NSString *text = [item objectForKey:@"text"];
        if (![text isKindOfClass:[NSString class]]) text = @"";
        [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            ([who objectForKey:@"name"] ?: @"DELETED"), @"name",
            ([who objectForKey:@"photo"] ?: @""), @"photo",
            text, @"text",
            ([item objectForKey:@"date"] ?: [NSNumber numberWithInt:0]), @"date",
            [NSNumber numberWithInteger:likes], @"likes",
            [NSNumber numberWithLongLong:from], @"from_id", nil]];
    }

    self.rows = rows;
    NSInteger total = [[response objectForKey:@"count"] integerValue];
    self.title = total > 0 ? [NSString stringWithFormat:@"Комментарии %d", (int)total] : @"Комментарии";
    self.emptyLabel.text = @"Комментариев пока нет";
    self.emptyLabel.hidden = (rows.count > 0);
    [self.tableView reloadData];
}

#pragma mark - Таблица

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *row = [self.rows objectAtIndex:ip.row];
    id cid = [row objectForKey:@"id"] ?: [NSNumber numberWithInteger:ip.row];
    NSNumber *cached = [self.rowHeightCache objectForKey:cid];
    if (cached) return [cached floatValue];
    CGFloat h = [VKCommentCell heightForText:[row objectForKey:@"text"] width:tv.bounds.size.width];
    [self.rowHeightCache setObject:[NSNumber numberWithFloat:h] forKey:cid];
    return h;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *rid = @"VKCommentCell";
    VKCommentCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) cell = [[VKCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];

    NSDictionary *row = [self.rows objectAtIndex:ip.row];
    [cell fill:row];

    __weak VKCommentsViewController *weakSelf = self;
    long long from = [[row objectForKey:@"from_id"] longLongValue];
    NSString *name = [row objectForKey:@"name"];
    cell.onAuthorTap = ^{
        if (from == 0) return;
        VKProfileViewController *page = [[VKProfileViewController alloc] initWithUserId:from name:name];
        [weakSelf.navigationController pushViewController:page animated:YES];
    };
    return cell;
}

#pragma mark - Отправка

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [self sendTapped];
    return NO;
}

- (void)sendTapped {
    NSString *text = [self.inputField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length || self.sending) return;
    self.sending = YES;
    self.inputField.text = @"";
    [self.inputField resignFirstResponder];

    __weak VKCommentsViewController *weakSelf = self;
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSString stringWithFormat:@"%lld", _ownerId], @"owner_id",
        [NSString stringWithFormat:@"%lld", _postId], @"post_id",
        text, @"message", nil];
    [[VKAPI shared] callMethod:@"wall.createComment" params:params completion:^(id response, NSError *error) {
        VKCommentsViewController *me = weakSelf;
        if (!me) return;
        me.sending = NO;
        if (error) {
            // Вернём текст в поле, чтобы не потерялся, и честно скажем об ошибке.
            me.inputField.text = text;
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:@"Не отправлено"
                message:[error localizedDescription] ?: @"Ошибка сети"
                delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [a show];
            return;
        }
        [me reload];
    }];
}

@end
