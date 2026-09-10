#import "VKMenuViewController.h"
#import "VKTheme.h"
#import "VKSession.h"
#import "VKAPI.h"
#import "VKBackend.h"
#import "VKImageLoader.h"
#import "VKAudioPlayer.h"
#import "VKAudioPlayerViewController.h"
#import "VKInstanceManager.h"
#import "VKSettings.h"
#import <QuartzCore/QuartzCore.h>

const CGFloat VKMenuWidth = 276.0;

// Геометрия и цвета сняты с оригинального сайдбара ВК (iPhone 5, 2x):
// поиск, шапка профиля и каждая строка — ровно 44pt.
static const CGFloat kRowHeight     = 44.0;
static const CGFloat kIconLeft      = 6.0;
static const CGFloat kIconSide      = 31.0;
static const CGFloat kTitleLeft     = 48.0;
static const CGFloat kBadgeRight    = 16.0;
static const CGFloat kBadgeHeight   = 24.0;
static const CGFloat kBadgeMinWidth = 29.0;
static const CGFloat kSearchInset   = 6.0;
static const CGFloat kSearchTop     = 7.0;
static const CGFloat kSearchHeight  = 30.0;

// #28313C — тело left_cell; им закрашиваем всё, что окажется ниже списка.
static UIColor *VKMenuBodyColor(void) {
    return [UIColor colorWithRed:0.157 green:0.192 blue:0.235 alpha:1.0];
}

// Тянем картинку по горизонтали; высота у всех ассетов уже ровно 44/30/27pt.
static UIImage *VKStretchH(NSString *name, NSInteger cap) {
    UIImage *img = [UIImage imageNamed:name];
    return img ? [img stretchableImageWithLeftCapWidth:cap topCapHeight:0] : nil;
}

// То же, но для синих ассетов подсветки: в режиме OpenVK они обесцвечиваются.
static UIImage *VKStretchHighlight(NSString *name, NSInteger cap) {
    UIImage *img = [[VKBackend shared] isOVK]
        ? [UIImage imageNamed:name]
        : [UIImage imageNamed:name];
    return img ? [img stretchableImageWithLeftCapWidth:cap topCapHeight:0] : nil;
}

@interface VKPlayerBarView : UIView @end
@implementation VKPlayerBarView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return point.y >= 24.0 && [super pointInside:point withEvent:event]; }
@end

#pragma mark - Ячейка раздела

@interface VKMenuCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, copy) NSString *iconName;
- (void)setBadgeCount:(NSInteger)count;
// Переприменить цвета подсветки (после смены бэкенда).
- (void)applyBackendStyle;
@end

@implementation VKMenuCell

- (id)initWithReuseIdentifier:(NSString *)ident {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    if (self) {
        self.backgroundColor = VKMenuBodyColor();
        self.opaque = YES;
        self.contentView.opaque = YES;

        // Фон строки и синяя подсветка — оригинальные left_cell / menu_cell_hl.
        UIImageView *bg = [[UIImageView alloc] initWithImage:VKStretchH(@"left_cell", 10)];
        bg.backgroundColor = VKMenuBodyColor();
        bg.opaque = YES;
        self.backgroundView = bg;

        UIImageView *sel = [[UIImageView alloc] initWithImage:VKStretchHighlight(@"menu_cell_hl", 10)];
        sel.backgroundColor = [VKTheme menuSelectionColor];
        sel.opaque = YES;
        self.selectedBackgroundView = sel;

        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_iconView];

        _badgeView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _badgeView.hidden = YES;
        [self.contentView addSubview:_badgeView];

        _badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _badgeLabel.backgroundColor = [UIColor clearColor];
        _badgeLabel.font = [UIFont boldSystemFontOfSize:13.0];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        // Цифры тёмные, с белым подсветом снизу — как на сером бейдже ВК.
        _badgeLabel.textColor = [UIColor colorWithRed:0.10 green:0.13 blue:0.18 alpha:1.0];
        _badgeLabel.shadowColor = [UIColor colorWithWhite:1.0 alpha:0.35];
        _badgeLabel.shadowOffset = CGSizeMake(0.0, 1.0);
        [_badgeView addSubview:_badgeLabel];

        self.textLabel.backgroundColor = [UIColor clearColor];
        self.textLabel.font = [UIFont boldSystemFontOfSize:17.0];
        [self applyState:NO];
    }
    return self;
}

// Белый текст + белая иконка на выбранной строке, серые — на остальных.
- (void)applyState:(BOOL)on {
    if (_iconName.length) {
        NSString *n = on ? [_iconName stringByAppendingString:@"_hl"] : _iconName;
        _iconView.image = [UIImage imageNamed:n];
    }
    self.textLabel.textColor = on
        ? [UIColor whiteColor]
        : [UIColor colorWithRed:0.87 green:0.89 blue:0.91 alpha:1.0];
    self.textLabel.shadowColor = on
        ? [VKTheme menuSelectionShadowColor]
        : [UIColor colorWithWhite:0.0 alpha:0.55];
    self.textLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    _badgeView.image = on ? VKStretchHighlight(@"left_badge_hl", 14)
                          : VKStretchH(@"left_badge", 14);
}

// Ячейки живут в пуле переиспользования и переживают смену бэкенда,
// поэтому подсветку переспрашиваем при каждой отдаче ячейки таблице.
- (void)applyBackendStyle {
    UIView *sel = self.selectedBackgroundView;
    if ([sel isKindOfClass:[UIImageView class]]) {
        [(UIImageView *)sel setImage:VKStretchHighlight(@"menu_cell_hl", 10)];
    }
    sel.backgroundColor = [VKTheme menuSelectionColor];
    [self applyState:(self.selected || self.highlighted)];
}

- (void)setIconName:(NSString *)iconName {
    _iconName = [iconName copy];
    if (!_iconName.length) _iconView.image = nil;
    [self applyState:(self.selected || self.highlighted)];
    [self setNeedsLayout];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    [self applyState:(selected || self.highlighted)];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self applyState:(highlighted || self.selected)];
}

- (void)setBadgeCount:(NSInteger)count {
    if (count > 0) {
        _badgeLabel.text = [NSString stringWithFormat:@"%d", (int)count];
        _badgeView.hidden = NO;
    } else {
        _badgeLabel.text = nil;
        _badgeView.hidden = YES;
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;

    _iconView.frame = CGRectMake(kIconLeft, roundf((h - kIconSide) / 2.0), kIconSide, kIconSide);

    CGFloat titleRight = w - kBadgeRight;
    if (!_badgeView.hidden) {
        CGSize ts = [_badgeLabel.text sizeWithFont:_badgeLabel.font];
        CGFloat bw = MAX(kBadgeMinWidth, roundf(ts.width) + 18.0);
        _badgeView.frame = CGRectMake(w - kBadgeRight - bw,
                                      roundf((h - kBadgeHeight) / 2.0), bw, kBadgeHeight);
        _badgeLabel.frame = CGRectMake(0.0, 0.0, bw, kBadgeHeight);
        titleRight = w - kBadgeRight - bw - 6.0;
    }
    CGFloat titleLeft = _iconName.length ? kTitleLeft : 16.0;
    self.textLabel.frame = CGRectMake(titleLeft, 0.0, MAX(0.0, titleRight - titleLeft), h);
}

@end

#pragma mark - Сайдбар

@interface VKMenuViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) NSArray *titles;            // 11 названий по порядку VKMenuItem
@property (nonatomic, strong) NSArray *icons;             // базовые имена картинок (+ "_hl")
@property (nonatomic, strong) NSMutableArray *counters;   // NSNumber на каждый раздел
@property (nonatomic, strong) NSArray *visible;           // NSNumber(VKMenuItem) после фильтра
@property (nonatomic, strong) UIView *playerBar;
@property (nonatomic, strong) UIImageView *playerArtworkView;
@property (nonatomic, strong) UIButton *playerPlayBtn;
@property (nonatomic, strong) UILabel *playerTitleLabel;
@property (nonatomic, strong) UILabel *playerArtistLabel;
@property (nonatomic, strong) UIButton *playerNextBtn;
@property (nonatomic, strong) UIButton *playerCloseBtn;
@end

@implementation VKMenuViewController

- (id)init {
    self = [super init];
    if (self) {
        _selectedItem = VKMenuItemNews;
        _titles = @[ @"Новости", @"Ответы", @"Сообщения", @"Друзья", @"Группы",
                     @"Фотографии", @"Видеозаписи", @"Аудиозаписи", @"Игры",
                     @"Мои заметки", @"Закладки", @"Настройки", @"OpenVK Latte" ];
        _icons = @[ @"left_news", @"left_answers", @"left_messages", @"left_friends",
                    @"left_groups", @"left_photos", @"left_videos", @"left_audio",
                    @"left_games", @"left_bookmarks", @"left_bookmarks", @"left_settings", @"left_swapovk" ];
        _counters = [NSMutableArray array];
        for (NSInteger i = 0; i < VKMenuItemCount; i++) {
            [_counters addObject:@0];
        }
        [self rebuildVisible];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VKMenuBodyColor();
    self.view.opaque = YES;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = VKMenuBodyColor();
    self.tableView.opaque = YES;
    // Разделители нарисованы прямо в left_cell — свои не нужны.
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = kRowHeight;
    self.tableView.scrollsToTop = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.tableHeaderView = [self buildHeader];
    [self.view addSubview:self.tableView];

    [self buildPlayerBar];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(audioDidChange:) name:VKAudioPlayerTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(audioDidChange:) name:VKAudioPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(audioDidChange:) name:VKSettingsDidChangeNotification object:nil];

    [self updatePlayerBar];
    [self refreshCounters];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(instancesDidChange:) name:VKInstancesDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self syncSelection];
}

#pragma mark - Шапка: поиск + профиль

- (UIView *)buildHeader {
    CGFloat w = VKMenuWidth;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, kRowHeight * 2.0)];
    header.backgroundColor = VKMenuBodyColor();
    header.opaque = YES;

    // --- Полоса поиска (фон left_header) ---
    UIImageView *searchBg = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, w, kRowHeight)];
    searchBg.image = VKStretchH(@"left_header", 20);
    searchBg.backgroundColor = [UIColor colorWithRed:0.19 green:0.22 blue:0.26 alpha:1.0];
    searchBg.opaque = YES;
    searchBg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:searchBg];

    CGFloat fieldW = w - kSearchInset * 2.0;
    UIImageView *inputBg = [[UIImageView alloc] initWithFrame:
        CGRectMake(kSearchInset, kSearchTop, fieldW, kSearchHeight)];
    inputBg.image = VKStretchH(@"left_search_input", 15);
    inputBg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:inputBg];

    UIImageView *glass = [[UIImageView alloc] initWithFrame:CGRectMake(15.0, 15.0, 15.0, 15.0)];
    glass.image = [UIImage imageNamed:@"left_search_icon"];
    [header addSubview:glass];

    self.searchField = [[UITextField alloc] initWithFrame:
        CGRectMake(36.0, kSearchTop, w - 36.0 - 12.0, kSearchHeight)];
    self.searchField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchField.borderStyle = UITextBorderStyleNone;
    self.searchField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.searchField.backgroundColor = [UIColor clearColor];
    self.searchField.textColor = [UIColor whiteColor];
    self.searchField.font = [UIFont systemFontOfSize:15.0];
    self.searchField.placeholder = @"Поиск";
    self.searchField.returnKeyType = UIReturnKeySearch;
    self.searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchField.keyboardAppearance = UIKeyboardAppearanceAlert;
    self.searchField.delegate = self;
    [self.searchField addTarget:self action:@selector(searchChanged:)
               forControlEvents:UIControlEventEditingChanged];

    // Своя кнопка очистки — системная на тёмном фоне выглядит чужеродно.
    UIImage *clear = [UIImage imageNamed:@"left_search_clear"];
    if (clear) {
        UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        clearBtn.frame = CGRectMake(0, 0, clear.size.width + 8.0, kSearchHeight);
        [clearBtn setImage:clear forState:UIControlStateNormal];
        [clearBtn setImage:[UIImage imageNamed:@"left_search_clear_hl"]
                  forState:UIControlStateHighlighted];
        [clearBtn addTarget:self action:@selector(clearSearch)
           forControlEvents:UIControlEventTouchUpInside];
        self.searchField.rightView = clearBtn;
        self.searchField.rightViewMode = UITextFieldViewModeWhileEditing;
    }
    [header addSubview:self.searchField];

    [self buildProfileRowInHeader:header width:w];
    return header;
}

// Компактная строка профиля: маленький квадратный аватар, имя и кнопка-камера.
- (void)buildProfileRowInHeader:(UIView *)header width:(CGFloat)w {
    CGFloat top = kRowHeight;

    UIImageView *rowBg = [[UIImageView alloc] initWithFrame:CGRectMake(0, top, w, kRowHeight)];
    rowBg.image = VKStretchH(@"left_cell", 10);
    rowBg.backgroundColor = VKMenuBodyColor();
    rowBg.opaque = YES;
    rowBg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:rowBg];

    // Вся строка кликабельна — это «Моя страница».
    UIButton *rowBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    rowBtn.frame = CGRectMake(0, top, w, kRowHeight);
    rowBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [rowBtn addTarget:self action:@selector(profileTapped)
     forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:rowBtn];

    self.avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(kIconLeft, top + 6.0, 31.0, 31.0)];
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
    self.avatarView.clipsToBounds = YES;
    self.avatarView.layer.cornerRadius = 0.0;
    [header addSubview:self.avatarView];

    // Рамка-тень поверх аватара (оригинальный left_userpic — 31x32).
    UIImageView *frame = [[UIImageView alloc] initWithFrame:CGRectMake(kIconLeft, top + 6.0, 31.0, 32.0)];
    frame.image = [UIImage imageNamed:@"left_userpic"];
    [header addSubview:frame];

    self.nameLabel = [[UILabel alloc] initWithFrame:
        CGRectMake(kTitleLeft, top, w - kTitleLeft - 62.0, kRowHeight)];
    self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.nameLabel.backgroundColor = VKMenuBodyColor();
    self.nameLabel.opaque = YES;
    self.nameLabel.font = [UIFont boldSystemFontOfSize:17.0];
    self.nameLabel.textColor = [UIColor whiteColor];
    self.nameLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    self.nameLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    [header addSubview:self.nameLabel];

    // Камеры в наборе ассетов нет — рисуем кнопку кодом по образцу оригинала.
    UIButton *cam = [UIButton buttonWithType:UIButtonTypeCustom];
    cam.frame = CGRectMake(w - 54.0, top + 8.0, 40.0, 28.0);
    cam.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [cam setImage:[VKTheme menuCameraButtonHighlighted:NO] forState:UIControlStateNormal];
    [cam setImage:[VKTheme menuCameraButtonHighlighted:YES] forState:UIControlStateHighlighted];
    [cam addTarget:self action:@selector(cameraTapped)
  forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:cam];

    [self applyProfileToHeader];
}

- (void)applyProfileToHeader {
    VKSession *s = [VKSession shared];
    NSString *displayName = s.userName.length ? s.userName : @"Гость";
    self.nameLabel.text = displayName;

    NSString *initials = displayName.length ? [[displayName substringToIndex:1] uppercaseString] : @"?";
    self.avatarView.image = [VKTheme avatarWithInitials:initials size:31.0
                                            background:[VKTheme navBarColor]];
    if (s.userPhoto.length) {
        __weak UIImageView *weakAvatar = self.avatarView;
        [[VKImageLoader shared] loadURL:s.userPhoto completion:^(UIImage *image) {
            if (image) weakAvatar.image = image;
        }];
    }
}

- (void)refreshHeader {
    if ([self isViewLoaded]) [self applyProfileToHeader];
}

- (void)profileTapped {
    self.selectedItem = VKMenuItemNone;
    if ([self.delegate respondsToSelector:@selector(menuDidSelectProfile:)]) {
        [self.delegate menuDidSelectProfile:self];
    }
}

- (void)cameraTapped {
    if ([self.delegate respondsToSelector:@selector(menuDidRequestCamera:)]) {
        [self.delegate menuDidRequestCamera:self];
    }
}

#pragma mark - Поиск по разделам

// Подпись строки SwapToOVK зависит от того, на каком бэкенде мы сейчас.
- (NSString *)titleForItem:(NSInteger)item {
    if (item == VKMenuItemSwapOVK) {
        return @"OpenVK Latte";
    }
    return [self.titles objectAtIndex:item];
}

- (void)reloadSections {
    if (![self isViewLoaded]) return;
    [self rebuildVisible];
    [self.tableView reloadData];
    [self syncSelection];
}

- (void)instancesDidChange:(NSNotification *)note { [self reloadSections]; }

// Глобального поиска по ВК тут нет — поле фильтрует список разделов.
- (void)rebuildVisible {
    NSMutableArray *all = [NSMutableArray array];
    for (NSInteger i = 0; i < VKMenuItemSwapOVK; i++) {
        if (i == VKMenuItemAnswers || i == VKMenuItemGames || i == VKMenuItemBookmarks) continue;
        [all addObject:@(i)];
    }
    [all addObjectsFromArray:[[VKInstanceManager shared] switchTargets]];
    self.visible = all;
}

- (void)searchChanged:(id)sender {
    [self rebuildVisible];
    [self.tableView reloadData];
    [self syncSelection];
}

- (void)clearSearch {
    self.searchField.text = @"";
    [self searchChanged:nil];
}

- (void)clearSearchText {
    [self clearSearch];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *query = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [textField resignFirstResponder];
    if (query.length && [self.delegate respondsToSelector:@selector(menu:didSubmitSearch:)]) {
        [self.delegate menu:self didSubmitSearch:query];
    }
    return NO;
}

#pragma mark - Счётчики

- (void)refreshCounters {
    if (![[VKSession shared] isAuthorized]) return;
    [[VKAPI shared] callMethod:@"account.getCounters"
                        params:@{@"filter": @"friends,messages,photos,videos,groups"}
                    completion:^(id response, NSError *error) {
        if (![response isKindOfClass:[NSDictionary class]]) return;
        // Метод отдаёт только ненулевые поля — остальное обнуляем сами.
        NSDictionary *map = @{ @(VKMenuItemMessages): @"messages",
                               @(VKMenuItemFriends):  @"friends",
                               @(VKMenuItemGroups):   @"groups",
                               @(VKMenuItemPhotos):   @"photos",
                               @(VKMenuItemVideos):   @"videos" };
        for (NSNumber *item in map) {
            id v = [response objectForKey:[map objectForKey:item]];
            NSInteger n = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
            [self.counters replaceObjectAtIndex:[item integerValue] withObject:@(n)];
        }
        [self.tableView reloadData];
        [self syncSelection];
    }];
}

#pragma mark - Таблица

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.visible.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKMenuCell";
    VKMenuCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) cell = [[VKMenuCell alloc] initWithReuseIdentifier:ident];

    id row = [self.visible objectAtIndex:indexPath.row];
    if ([row isKindOfClass:[NSDictionary class]]) {
        cell.textLabel.text = [NSString stringWithFormat:@"Перейти в %@", [row objectForKey:@"name"]];
        cell.iconName = nil; [cell setBadgeCount:0];
    } else {
        NSInteger item = [row integerValue];
        cell.textLabel.text = [self titleForItem:item]; cell.iconName = [self.icons objectAtIndex:item];
        [cell setBadgeCount:[[self.counters objectAtIndex:item] integerValue]];
    }
    [cell applyBackendStyle];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    id row = [self.visible objectAtIndex:indexPath.row];
    [self.searchField resignFirstResponder];
    if ([row isKindOfClass:[NSDictionary class]]) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        if ([self.delegate respondsToSelector:@selector(menu:didSelectInstanceHost:)]) [self.delegate menu:self didSelectInstanceHost:[row objectForKey:@"host"]];
        return;
    }
    NSInteger item = [row integerValue];
    // Строка переключения — действие, а не раздел: выделение возвращаем как было.
    if (item == VKMenuItemSwapOVK) {
        [tableView deselectRowAtIndexPath:indexPath animated:NO];
        [self syncSelection];
        if ([self.delegate respondsToSelector:@selector(menuDidRequestBackendSwap:)]) {
            [self.delegate menuDidRequestBackendSwap:self];
        }
        return;
    }
    _selectedItem = (VKMenuItem)item;
    if ([self.delegate respondsToSelector:@selector(menu:didSelectItem:)]) {
        [self.delegate menu:self didSelectItem:(VKMenuItem)item];
    }
}

// Подсветку держит сама таблица через selectedBackgroundView.
- (void)syncSelection {
    if (![self isViewLoaded]) return;
    NSUInteger row = (self.selectedItem == VKMenuItemNone)
        ? NSNotFound
        : [self.visible indexOfObject:@((NSInteger)self.selectedItem)];
    if (row == NSNotFound) {
        NSIndexPath *cur = [self.tableView indexPathForSelectedRow];
        if (cur) [self.tableView deselectRowAtIndexPath:cur animated:NO];
        return;
    }
    [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                                animated:NO
                          scrollPosition:UITableViewScrollPositionNone];
}

- (void)setSelectedItem:(VKMenuItem)selectedItem {
    _selectedItem = selectedItem;
    [self syncSelection];
}

#pragma mark - Сайдбар Мини-Плеер

- (void)buildPlayerBar {
    CGFloat w = VKMenuWidth;
    CGFloat h = self.view.bounds.size.height;
    // Оригинальная текстура left_player имеет высоту 70 pt: верхние 24 pt
    // прозрачные, сама панель занимает нижние 46 pt.
    CGFloat barH = 70.0;

    self.playerBar = [[VKPlayerBarView alloc] initWithFrame:CGRectMake(0, h - barH, w, barH)];
    self.playerBar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    self.playerBar.backgroundColor = [UIColor clearColor];
    UIImageView *background = [[UIImageView alloc] initWithFrame:self.playerBar.bounds];
    background.image = VKStretchH(@"left_player", 6);
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.playerBar addSubview:background];

    // Обложка превращала панель в современный вид. В старом клиенте здесь
    // оставалась только компактная кнопка и две строки названия.
    self.playerArtworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.playerArtworkView.hidden = YES;
    [self.playerBar addSubview:self.playerArtworkView];

    self.playerPlayBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playerPlayBtn.frame = CGRectMake(5.0, 29.0, 36.0, 36.0);
    [self.playerPlayBtn setImage:[UIImage imageNamed:@"left_player_play"] forState:UIControlStateNormal];
    [self.playerPlayBtn addTarget:self action:@selector(playerPlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playerBar addSubview:self.playerPlayBtn];

    UIButton *openBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    openBtn.frame = CGRectMake(44.0, 24.0, w - 112.0, 46.0);
    openBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [openBtn addTarget:self action:@selector(playerOpenTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playerBar addSubview:openBtn];

    self.playerTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(45.0, 29.0, w - 116.0, 18.0)];
    self.playerTitleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    self.playerTitleLabel.textColor = [UIColor whiteColor];
    self.playerTitleLabel.backgroundColor = [UIColor clearColor];
    self.playerTitleLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    self.playerTitleLabel.shadowOffset = CGSizeMake(0, -1);
    self.playerTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.playerBar addSubview:self.playerTitleLabel];

    self.playerArtistLabel = [[UILabel alloc] initWithFrame:CGRectMake(45.0, 48.0, w - 116.0, 16.0)];
    self.playerArtistLabel.font = [UIFont systemFontOfSize:11.0];
    self.playerArtistLabel.textColor = [UIColor colorWithRed:0.75 green:0.78 blue:0.82 alpha:1.0];
    self.playerArtistLabel.backgroundColor = [UIColor clearColor];
    self.playerArtistLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.playerBar addSubview:self.playerArtistLabel];

    self.playerNextBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playerNextBtn.frame = CGRectMake(w - 68.0, 29.0, 36.0, 36.0);
    self.playerNextBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.playerNextBtn setImage:[UIImage imageNamed:@"left_player_arrow"] forState:UIControlStateNormal];
    [self.playerNextBtn addTarget:self action:@selector(playerNextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playerBar addSubview:self.playerNextBtn];

    self.playerCloseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playerCloseBtn.frame = CGRectMake(w - 31.0, 31.0, 27.0, 32.0);
    self.playerCloseBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.playerCloseBtn setTitle:@"×" forState:UIControlStateNormal];
    [self.playerCloseBtn setTitleColor:[UIColor colorWithWhite:0.80 alpha:1.0] forState:UIControlStateNormal];
    self.playerCloseBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [self.playerCloseBtn addTarget:self action:@selector(playerCloseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playerBar addSubview:self.playerCloseBtn];

    [self.view addSubview:self.playerBar];
}

- (void)playerPlayTapped {
    [[VKAudioPlayer shared] togglePlayPause];
}

- (void)playerNextTapped {
    [[VKAudioPlayer shared] next];
}

- (void)playerCloseTapped {
    [[VKAudioPlayer shared] stop];
    [self updatePlayerBar];
}

- (void)playerOpenTapped {
    [[VKAudioPlayerViewController sharedController] presentFromViewController:self];
}

- (void)audioDidChange:(NSNotification *)note {
    [self updatePlayerBar];
}

- (void)updatePlayerBar {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    BOOL visible = [VKSettings shared].showSidebarPlayer && player.currentAudio && player.state != VKAudioStateStopped && player.state != VKAudioStateError;
    if (visible) {
        self.playerBar.hidden = NO;
        self.playerTitleLabel.text = player.currentAudio.title.length ? player.currentAudio.title : @"Без названия";
        self.playerArtistLabel.text = player.currentAudio.artist.length ? player.currentAudio.artist : @"Неизвестный";

        if (player.isPlaying) {
            [self.playerPlayBtn setImage:[UIImage imageNamed:@"left_player_pause"] forState:UIControlStateNormal];
        } else {
            [self.playerPlayBtn setImage:[UIImage imageNamed:@"left_player_play"] forState:UIControlStateNormal];
        }
        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 46.0, 0);
        self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    } else {
        self.playerBar.hidden = YES;
        self.tableView.contentInset = UIEdgeInsetsZero;
        self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }
}

@end
