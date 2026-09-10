#import "VKEmojiPanel.h"
#import "VKAPI.h"
#import "VKImageLoader.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kPanelHeight     = 252.0;   // чуть выше портретной клавиатуры
static const CGFloat kBottomBarHeight = 40.0;
static const CGFloat kTabsHeight      = 30.0;    // полоса вкладок «Смайлы/Стикеры»
static const CGFloat kPackHeaderHeight = 20.0;   // заголовок с названием набора
static const NSInteger kCols = 8;
static const NSInteger kRows = 4;
static const NSInteger kStickerCols = 4;         // стикеры крупнее — 4 в ряд
static const NSInteger kGridStickerPx = 128;     // размер картинки для сетки панели
static const NSInteger kSendStickerPx = 256;     // размер картинки для бабла в чате
static const NSInteger kMaxParallelLoads = 4;    // больше соединений сразу только мешают

// Состояние загрузки наборов стикеров.
typedef enum {
    VKStickersIdle = 0,
    VKStickersLoading,
    VKStickersReady,
    VKStickersFailed
} VKStickersState;

// Кодовые точки из Unicode 6.0 — этот набор есть в Apple Color Emoji на iOS 5/6,
// поэтому ни одна клетка сетки не превратится в пустой квадрат.
static const uint32_t kEmojiCodePoints[] = {
    0x1F601, 0x1F602, 0x1F603, 0x1F604, 0x1F605, 0x1F606, 0x1F609, 0x1F60A,
    0x1F60B, 0x1F60C, 0x1F60D, 0x1F60F, 0x1F612, 0x1F613, 0x1F614, 0x1F616,
    0x1F618, 0x1F61A, 0x1F61C, 0x1F61D, 0x1F61E, 0x1F620, 0x1F621, 0x1F622,
    0x1F623, 0x1F624, 0x1F625, 0x1F628, 0x1F629, 0x1F62A, 0x1F62B, 0x1F62D,
    0x1F630, 0x1F631, 0x1F632, 0x1F633, 0x1F635, 0x1F637, 0x1F638, 0x1F639,
    0x1F63A, 0x1F63B, 0x1F63C, 0x1F63D, 0x1F63E, 0x1F63F, 0x1F640, 0x1F645,
    0x1F646, 0x1F647, 0x1F648, 0x1F649, 0x1F64A, 0x1F64B, 0x1F64C, 0x1F64D,
    0x1F64E, 0x1F64F, 0x1F44D, 0x1F44E, 0x1F44C, 0x1F44A, 0x1F44B, 0x1F44F,
    0x1F450, 0x1F446, 0x1F447, 0x1F448, 0x1F449, 0x1F4AA, 0x002764, 0x1F494,
    0x1F495, 0x1F496, 0x1F497, 0x1F498, 0x1F499, 0x1F49A, 0x1F49B, 0x1F49C,
    0x1F49D, 0x1F49E, 0x1F49F, 0x002B50, 0x1F31F, 0x002728, 0x1F4A5, 0x1F4A4,
    0x1F4A2, 0x1F4A3, 0x1F525, 0x1F4A9, 0x1F339, 0x1F338, 0x1F340, 0x1F34E,
    0x1F34C, 0x1F353, 0x1F349, 0x1F355, 0x1F354, 0x1F35F, 0x1F366, 0x1F382,
    0x1F37A, 0x1F37B, 0x1F36B, 0x1F3B5, 0x1F3B6, 0x0026BD, 0x1F3C0, 0x1F3AE,
    0x1F381, 0x1F389, 0x1F4B0, 0x1F4F7, 0x1F4F1, 0x1F697, 0x002708, 0x1F680,
    0x1F31A, 0x1F31B, 0x002600, 0x002601, 0x002614, 0x0026A1, 0x002744, 0x1F319
};

// Строка из кодовой точки. Для символов из BMP добавляем вариационный
// селектор U+FE0F, иначе они рисуются чёрно-белым текстовым начертанием.
static NSString *VKEmojiString(uint32_t cp) {
    uint32_t buf[2];
    NSUInteger n = 0;
    buf[n++] = CFSwapInt32HostToLittle(cp);
    if (cp < 0x10000) buf[n++] = CFSwapInt32HostToLittle(0xFE0F);
    return [[NSString alloc] initWithBytes:buf
                                    length:n * sizeof(uint32_t)
                                  encoding:NSUTF32LittleEndianStringEncoding];
}

// Классический эндпоинт картинки стикера — отдаёт PNG и без токена.
// В сетке панели грузим 128px (клетка ~72pt), в переписку отправляем 256px.
static NSString *VKStickerURL(long long stickerId, NSInteger px) {
    return @""; // Use only image URLs returned by the OpenVK instance.
}

@interface VKEmojiPanel () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UISegmentedControl *tabs;
@property (nonatomic, strong) UILabel *statusLabel;   // «Загрузка…» / ошибка
@property (nonatomic, strong) NSArray *emoji;
@property (nonatomic, strong) NSArray *stickers;      // плоский список @{id, url} — по тегам клеток
@property (nonatomic, strong) NSArray *stickerPacks;  // @{title, items} в порядке отображения
@property (nonatomic, strong) NSMutableArray *stickerButtons;   // клетки сетки стикеров
@property (nonatomic, strong) NSMutableArray *loadQueue;        // клетки, ждущие картинку
@property (nonatomic, strong) NSMutableSet *requestedURLs;      // чтобы не дублировать запросы
@property (nonatomic, assign) NSInteger inFlight;               // сколько загрузок идёт сейчас
@property (nonatomic, assign) VKStickersState stickersState;
@property (nonatomic, assign) CGFloat builtWidth;
@property (nonatomic, assign) NSInteger builtMode;    // какой режим уже разложен
@end

@implementation VKEmojiPanel

+ (CGFloat)panelHeight { return kPanelHeight; }

- (id)initWithFrame:(CGRect)frame {
    if (frame.size.height <= 0.0) frame.size.height = kPanelHeight;
    self = [super initWithFrame:frame];
    if (self) {
        // Фон под цвет светлой клавиатуры iOS 6.
        self.backgroundColor = [UIColor colorWithRed:0.82 green:0.84 blue:0.86 alpha:1.0];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        NSUInteger total = sizeof(kEmojiCodePoints) / sizeof(kEmojiCodePoints[0]);
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:total];
        for (NSUInteger i = 0; i < total; i++) {
            [list addObject:VKEmojiString(kEmojiCodePoints[i])];
        }
        self.emoji = list;

        _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scroll.pagingEnabled = YES;
        _scroll.showsHorizontalScrollIndicator = NO;
        _scroll.backgroundColor = [UIColor clearColor];
        _scroll.delegate = self;
        [self addSubview:_scroll];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.backgroundColor = [UIColor clearColor];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        _statusLabel.font = [UIFont systemFontOfSize:14.0];
        _statusLabel.textColor = [UIColor colorWithWhite:0.3 alpha:1.0];
        _statusLabel.hidden = YES;
        [self addSubview:_statusLabel];

        _builtMode = -1;
        _loadQueue = [NSMutableArray array];
        _requestedURLs = [NSMutableSet set];
        [self buildTabs];
        [self buildBottomBar];
    }
    return self;
}

// Полоса вкладок сверху: смайлы или стикеры.
- (void)buildTabs {
    CGFloat w = self.bounds.size.width;
    UIView *strip = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, w, kTabsHeight)];
    strip.backgroundColor = [UIColor colorWithRed:0.72 green:0.75 blue:0.78 alpha:1.0];
    strip.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self addSubview:strip];

    _tabs = [[UISegmentedControl alloc] initWithItems:
             [NSArray arrayWithObject:@"Смайлы"]];
    _tabs.segmentedControlStyle = UISegmentedControlStyleBar;
    _tabs.frame = CGRectMake(roundf((w - 180.0) / 2.0), 3.0, 180.0, kTabsHeight - 6.0);
    _tabs.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    _tabs.selectedSegmentIndex = 0;
    [_tabs addTarget:self action:@selector(tabChanged)
    forControlEvents:UIControlEventValueChanged];
    [strip addSubview:_tabs];
}

- (void)tabChanged {
    if (self.tabs.selectedSegmentIndex == 1) [self loadStickersIfNeeded];
    [self rebuildPages];
}

// Нижняя полоса: «АБВ», точки-страницы и удаление символа.
- (void)buildBottomBar {
    CGFloat w = self.bounds.size.width;
    CGFloat top = self.bounds.size.height - kBottomBarHeight;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0.0, top, w, kBottomBarHeight)];
    bar.backgroundColor = [UIColor colorWithRed:0.72 green:0.75 blue:0.78 alpha:1.0];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self addSubview:bar];

    UIButton *abc = [self barButtonWithTitle:@"АБВ" action:@selector(keyboardTapped)];
    abc.frame = CGRectMake(4.0, 4.0, 56.0, kBottomBarHeight - 8.0);
    [bar addSubview:abc];

    UIButton *del = [self barButtonWithTitle:@"⌫" action:@selector(backspaceTapped)];
    del.frame = CGRectMake(w - 60.0, 4.0, 56.0, kBottomBarHeight - 8.0);
    del.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [bar addSubview:del];

    _pageControl = [[UIPageControl alloc] initWithFrame:
        CGRectMake(60.0, 0.0, MAX(0.0, w - 120.0), kBottomBarHeight)];
    _pageControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // Страницы листаются свайпом — точки только показывают позицию.
    _pageControl.userInteractionEnabled = NO;
    [bar addSubview:_pageControl];
}

- (UIButton *)barButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.backgroundColor = [UIColor colorWithRed:0.60 green:0.63 blue:0.67 alpha:1.0];
    b.layer.cornerRadius = 4.0;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.15 alpha:1.0] forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    CGFloat gridH = self.bounds.size.height - kTabsHeight - kBottomBarHeight;
    self.scroll.frame = CGRectMake(0.0, kTabsHeight, w, gridH);
    self.statusLabel.frame = self.scroll.frame;
    if (fabs(w - self.builtWidth) > 0.5 || self.builtMode != self.tabs.selectedSegmentIndex) {
        self.builtWidth = w;
        [self rebuildPages];
    }
}

- (void)rebuildPages {
    for (UIView *v in [self.scroll.subviews copy]) [v removeFromSuperview];
    self.builtMode = self.tabs.selectedSegmentIndex;
    if (self.builtMode == 1) {
        [self buildStickerGrid];
    } else {
        [self buildEmojiPages];
    }
}

// Смайлики: страницы-сетки 8x4 с горизонтальным листанием.
- (void)buildEmojiPages {
    self.statusLabel.hidden = YES;
    self.scroll.pagingEnabled = YES;
    self.pageControl.hidden = NO;

    CGFloat w = self.scroll.bounds.size.width;
    CGFloat h = self.scroll.bounds.size.height;
    if (w <= 0.0 || h <= 0.0) return;

    NSInteger count = (NSInteger)self.emoji.count;
    NSInteger perPage = kCols * kRows;
    NSInteger pages = (count + perPage - 1) / perPage;
    CGFloat cw = w / (CGFloat)kCols;
    CGFloat ch = h / (CGFloat)kRows;

    for (NSInteger i = 0; i < count; i++) {
        NSInteger page = i / perPage;
        NSInteger idx  = i % perPage;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake((CGFloat)page * w + (CGFloat)(idx % kCols) * cw,
                             (CGFloat)(idx / kCols) * ch, cw, ch);
        b.titleLabel.font = [UIFont systemFontOfSize:MIN(28.0, MIN(cw, ch) - 8.0)];
        [b setTitle:[self.emoji objectAtIndex:i] forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:self action:@selector(cellTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:b];
    }

    self.scroll.contentSize = CGSizeMake((CGFloat)pages * w, h);
    self.scroll.contentOffset = CGPointZero;
    self.pageControl.numberOfPages = pages;
    self.pageControl.currentPage = 0;
}

// Стикеры: вертикальная сетка по 4 в ряд, все наборы пользователя подряд.
- (void)buildStickerGrid {
    self.scroll.pagingEnabled = NO;
    self.pageControl.hidden = YES;
    self.scroll.contentOffset = CGPointZero;

    CGFloat w = self.scroll.bounds.size.width;
    CGFloat h = self.scroll.bounds.size.height;
    if (w <= 0.0 || h <= 0.0) return;

    if (self.stickersState != VKStickersReady || self.stickers.count == 0) {
        self.scroll.contentSize = CGSizeMake(w, h);
        self.statusLabel.hidden = NO;
        if (self.stickersState == VKStickersFailed) {
            self.statusLabel.text = @"Не удалось загрузить стикеры";
        } else if (self.stickersState == VKStickersReady) {
            self.statusLabel.text = @"Наборов стикеров нет";
        } else {
            self.statusLabel.text = @"Загрузка стикеров…";
        }
        return;
    }
    self.statusLabel.hidden = YES;

    CGFloat cw = w / (CGFloat)kStickerCols;
    NSInteger count = (NSInteger)self.stickers.count;
    self.stickerButtons = [NSMutableArray arrayWithCapacity:count];
    // Клетки пересоздаются — старая очередь указывает в никуда.
    [self.loadQueue removeAllObjects];
    [self.requestedURLs removeAllObjects];
    CGFloat y = 0.0;
    NSInteger flat = 0;

    for (NSDictionary *pack in self.stickerPacks) {
        NSArray *items = [pack objectForKey:@"items"];
        if (items.count == 0) continue;

        // Название набора над его стикерами.
        UILabel *hdr = [[UILabel alloc] initWithFrame:CGRectMake(8.0, y, w - 16.0, kPackHeaderHeight)];
        hdr.text = [pack objectForKey:@"title"];
        hdr.font = [UIFont boldSystemFontOfSize:12.0];
        hdr.textColor = [UIColor colorWithWhite:0.28 alpha:1.0];
        hdr.backgroundColor = [UIColor clearColor];
        [self.scroll addSubview:hdr];
        y += kPackHeaderHeight;

        for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectInset(CGRectMake((CGFloat)(i % kStickerCols) * cw,
                                            y + (CGFloat)(i / kStickerCols) * cw, cw, cw), 4.0, 4.0);
            b.tag = flat++;
            // Картинка стикера 256px вписывается в клетку без искажений.
            b.imageView.contentMode = UIViewContentModeScaleAspectFit;
            b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
            b.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
            [b addTarget:self action:@selector(stickerTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.scroll addSubview:b];
            [self.stickerButtons addObject:b];
        }
        NSInteger rows = ((NSInteger)items.count + kStickerCols - 1) / kStickerCols;
        y += (CGFloat)rows * cw;
    }

    self.scroll.contentSize = CGSizeMake(w, y);
    // 256px картинки грузим только под видимой областью — иначе на 4S/5
    // сотня распакованных стикеров съедает десятки мегабайт.
    [self loadVisibleStickers];
}

// Догружаем картинки клеток, попавших в видимую область (плюс ряд запаса).
- (void)loadVisibleStickers {
    if (self.stickerButtons.count == 0) return;
    for (UIButton *b in self.stickerButtons) {
        if ([b imageForState:UIControlStateNormal]) continue;
        if (![self buttonNearVisible:b]) continue;
        NSString *url = [self gridURLForTag:b.tag];
        if (!url.length) continue;
        // Уже в кэше — ставим сразу, без сети и очереди.
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) {
            [b setImage:cached forState:UIControlStateNormal];
            continue;
        }
        if ([self.requestedURLs containsObject:url]) continue;
        [self.requestedURLs addObject:url];
        [self.loadQueue addObject:b];
    }
    [self pumpLoadQueue];
}

// Не больше kMaxParallelLoads соединений разом: NSURLConnection'ы, запущенные
// пачкой на всю сетку, душат друг друга и картинки ползут по одной.
- (void)pumpLoadQueue {
    while (self.inFlight < kMaxParallelLoads && self.loadQueue.count > 0) {
        UIButton *b = [self.loadQueue objectAtIndex:0];
        [self.loadQueue removeObjectAtIndex:0];
        NSString *url = [self gridURLForTag:b.tag];
        if (!url.length) continue;
        // Клетка уже уехала далеко за экран — соединение на неё не тратим.
        if (![self buttonNearVisible:b]) {
            [self.requestedURLs removeObject:url];
            continue;
        }
        self.inFlight++;
        __weak VKEmojiPanel *weakSelf = self;
        [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
            VKEmojiPanel *strong = weakSelf;
            if (!strong) return;
            strong.inFlight--;
            if (image) {
                [strong applyImage:image forURL:url];
            } else {
                [strong.requestedURLs removeObject:url];   // дадим шанс повторить
            }
            [strong pumpLoadQueue];
        }];
    }
}

// Одна картинка может стоять в нескольких клетках (набор попал в ответ дважды).
- (void)applyImage:(UIImage *)image forURL:(NSString *)url {
    for (UIButton *b in self.stickerButtons) {
        if ([b imageForState:UIControlStateNormal]) continue;
        if ([[self gridURLForTag:b.tag] isEqualToString:url]) {
            [b setImage:image forState:UIControlStateNormal];
        }
    }
}

- (BOOL)buttonNearVisible:(UIButton *)button {
    CGRect visible = self.scroll.bounds;
    visible.origin = self.scroll.contentOffset;
    visible = CGRectInset(visible, 0.0, -visible.size.height / 2.0);
    return CGRectIntersectsRect(visible, button.frame);
}

- (NSString *)gridURLForTag:(NSInteger)tag {
    if (tag < 0 || tag >= (NSInteger)self.stickers.count) return nil;
    return [[self.stickers objectAtIndex:tag] objectForKey:@"url"];
}

#pragma mark - Загрузка наборов

// Наборы стикеров пользователя. Ответ у разных версий отличается,
// поэтому разбираем терпимо: и `stickers`, и `sticker_ids`, и вложенный `product`.
- (void)loadStickersIfNeeded {
    if (self.stickersState == VKStickersLoading || self.stickersState == VKStickersReady) return;
    self.stickersState = VKStickersReady;
    self.stickers = @[];
    self.stickerPacks = @[];
    if (self.tabs.selectedSegmentIndex == 1) [self rebuildPages];
}

- (NSArray *)parseStickerPacks:(NSArray *)items {
    NSMutableArray *packs = [NSMutableArray array];
    for (id raw in items) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *product = [(NSDictionary *)raw objectForKey:@"product"];
        if (![product isKindOfClass:[NSDictionary class]]) product = raw;

        NSString *title = [(NSDictionary *)raw objectForKey:@"title"];
        if (![title isKindOfClass:[NSString class]]) title = [product objectForKey:@"title"];
        if (![title isKindOfClass:[NSString class]] || title.length == 0) title = @"Стикеры недоступны";

        NSMutableArray *out = [NSMutableArray array];
        NSArray *list = [product objectForKey:@"stickers"];
        if ([list isKindOfClass:[NSArray class]]) {
            for (id s in list) {
                if (![s isKindOfClass:[NSDictionary class]]) continue;
                id sid = [s objectForKey:@"sticker_id"];
                if (!sid) sid = [s objectForKey:@"id"];
                if (![sid respondsToSelector:@selector(longLongValue)]) continue;
                long long n = [sid longLongValue];
                if (n <= 0) continue;
                [out addObject:[self stickerEntryWithId:n images:[s objectForKey:@"images"]]];
            }
        } else {
            NSArray *ids = [product objectForKey:@"sticker_ids"];
            if (![ids isKindOfClass:[NSArray class]]) ids = [product objectForKey:@"stickers_ids"];
            if (![ids isKindOfClass:[NSArray class]]) continue;
            for (id sid in ids) {
                if (![sid respondsToSelector:@selector(longLongValue)]) continue;
                long long n = [sid longLongValue];
                if (n <= 0) continue;
                [out addObject:[self stickerEntryWithId:n images:nil]];
            }
        }
        if (out.count == 0) continue;
        [packs addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                          title, @"title", out, @"items", nil]];
    }
    return packs;
}

// Одна клетка: мелкая картинка для сетки и крупная для отправки в чат.
- (NSDictionary *)stickerEntryWithId:(long long)stickerId images:(id)images {
    NSString *grid = [self bestImageURL:images target:(CGFloat)kGridStickerPx];
    if (!grid.length) grid = VKStickerURL(stickerId, kGridStickerPx);
    NSString *big = [self bestImageURL:images target:(CGFloat)kSendStickerPx];
    if (!big.length) big = VKStickerURL(stickerId, kSendStickerPx);
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithLongLong:stickerId], @"id",
            grid, @"url",
            big, @"bigURL", nil];
}

// Из массива images берём вариант, ближайший к нужному размеру.
- (NSString *)bestImageURL:(id)images target:(CGFloat)target {
    if (![images isKindOfClass:[NSArray class]]) return nil;
    NSString *best = nil;
    CGFloat bestDelta = 1e9;
    for (id img in images) {
        if (![img isKindOfClass:[NSDictionary class]]) continue;
        CGFloat wdt = [[img objectForKey:@"width"] floatValue];
        CGFloat d = fabs(wdt - target);
        if (d < bestDelta) {
            bestDelta = d;
            best = [img objectForKey:@"url"];
        }
    }
    return best;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (!scrollView.pagingEnabled) {   // стикеры: точек-страниц нет, но нужна догрузка
        [self loadVisibleStickers];
        return;
    }
    CGFloat w = scrollView.bounds.size.width;
    if (w <= 0.0) return;
    self.pageControl.currentPage = (NSInteger)floorf(scrollView.contentOffset.x / w + 0.5);
}

#pragma mark - Действия

- (void)cellTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.emoji.count) return;
    [self.pickerDelegate emojiPanel:self didPickEmoji:[self.emoji objectAtIndex:sender.tag]];
}

- (void)stickerTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.stickers.count) return;
    if (![self.pickerDelegate respondsToSelector:@selector(emojiPanel:didPickStickerId:previewURL:)]) return;
    NSDictionary *st = [self.stickers objectAtIndex:sender.tag];
    [self.pickerDelegate emojiPanel:self
                  didPickStickerId:[[st objectForKey:@"id"] longLongValue]
                        previewURL:[st objectForKey:@"bigURL"]];
}

- (void)backspaceTapped {
    if ([self.pickerDelegate respondsToSelector:@selector(emojiPanelDidTapBackspace:)]) {
        [self.pickerDelegate emojiPanelDidTapBackspace:self];
    }
}

- (void)keyboardTapped {
    if ([self.pickerDelegate respondsToSelector:@selector(emojiPanelDidRequestKeyboard:)]) {
        [self.pickerDelegate emojiPanelDidRequestKeyboard:self];
    }
}

@end
