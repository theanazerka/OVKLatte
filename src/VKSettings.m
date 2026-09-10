#import "VKSettings.h"

NSString *const VKSettingsDidChangeNotification = @"VKSettingsDidChangeNotification";

static NSString *const kLoadImages   = @"vk_load_images";
static NSString *const kFeedPhotos   = @"vk_feed_photos";
static NSString *const kFeedFontSize = @"vk_feed_font_size";
static NSString *const kFeedCount    = @"vk_feed_count";
static NSString *const kSwipeMenu    = @"vk_swipe_menu";
static NSString *const kDarkTheme    = @"vk_dark_theme";
static NSString *const kPostAsAndroid = @"vk_post_as_android";
static NSString *const kSidebarPlayer = @"vk_sidebar_player";
static NSString *const kVideoQuality = @"vk_video_quality";

@implementation VKSettings

+ (instancetype)shared {
    static VKSettings *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VKSettings alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        // Дефолты: всё включено, лента 40 записей, текст 14pt.
        [[NSUserDefaults standardUserDefaults] registerDefaults:
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithBool:YES],     kLoadImages,
                [NSNumber numberWithBool:YES],     kFeedPhotos,
                [NSNumber numberWithFloat:14.0],   kFeedFontSize,
                [NSNumber numberWithInteger:20],   kFeedCount,
                [NSNumber numberWithBool:YES],     kSwipeMenu,
                [NSNumber numberWithBool:NO],      kDarkTheme,
                [NSNumber numberWithBool:NO],      kPostAsAndroid,
                [NSNumber numberWithBool:YES],     kSidebarPlayer,
                @"auto",                          kVideoQuality,
                nil]];
    }
    return self;
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

// Сохранить и разбудить подписчиков.
- (void)commit {
    [[self defaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:VKSettingsDidChangeNotification
                                                        object:self];
}

- (BOOL)loadImages { return [[self defaults] boolForKey:kLoadImages]; }
- (void)setLoadImages:(BOOL)value {
    [[self defaults] setBool:value forKey:kLoadImages];
    [self commit];
}

- (BOOL)showFeedPhotos { return [[self defaults] boolForKey:kFeedPhotos]; }
- (void)setShowFeedPhotos:(BOOL)value {
    [[self defaults] setBool:value forKey:kFeedPhotos];
    [self commit];
}

- (CGFloat)feedFontSize {
    CGFloat v = [[self defaults] floatForKey:kFeedFontSize];
    // Страховка от мусора в defaults (например, после ручной правки plist).
    return (v < 11.0 || v > 22.0) ? 14.0 : v;
}
- (void)setFeedFontSize:(CGFloat)value {
    if (value < 11.0) value = 11.0;
    if (value > 22.0) value = 22.0;
    [[self defaults] setFloat:value forKey:kFeedFontSize];
    [self commit];
}

- (NSInteger)feedCount {
    NSInteger v = [[self defaults] integerForKey:kFeedCount];
    if (v < 10) v = 10;
    if (v > 100) v = 100; // выше newsfeed.get всё равно не отдаёт за раз
    return v;
}
- (void)setFeedCount:(NSInteger)value {
    if (value < 10) value = 10;
    if (value > 100) value = 100;
    [[self defaults] setInteger:value forKey:kFeedCount];
    [self commit];
}

- (BOOL)swipeToOpenMenu { return [[self defaults] boolForKey:kSwipeMenu]; }
- (void)setSwipeToOpenMenu:(BOOL)value {
    [[self defaults] setBool:value forKey:kSwipeMenu];
    [self commit];
}

- (BOOL)darkTheme { return NO; }
- (void)setDarkTheme:(BOOL)value {
    [[self defaults] setBool:NO forKey:kDarkTheme];
    [self commit];
}

- (BOOL)postAsAndroid { return [[self defaults] boolForKey:kPostAsAndroid]; }
- (void)setPostAsAndroid:(BOOL)value {
    [[self defaults] setBool:value forKey:kPostAsAndroid];
    [self commit];
}

- (BOOL)showSidebarPlayer { return [[self defaults] boolForKey:kSidebarPlayer]; }
- (void)setShowSidebarPlayer:(BOOL)value { [[self defaults] setBool:value forKey:kSidebarPlayer]; [self commit]; }
- (NSString *)preferredVideoQuality { return [[self defaults] stringForKey:kVideoQuality] ?: @"auto"; }
- (void)setPreferredVideoQuality:(NSString *)value { [[self defaults] setObject:(value ?: @"auto") forKey:kVideoQuality]; [self commit]; }

- (void)resetToDefaults {
    NSUserDefaults *d = [self defaults];
    // Удаляем ключи — дальше отдадутся зарегистрированные дефолты.
    [d removeObjectForKey:kLoadImages];
    [d removeObjectForKey:kFeedPhotos];
    [d removeObjectForKey:kFeedFontSize];
    [d removeObjectForKey:kFeedCount];
    [d removeObjectForKey:kSwipeMenu];
    [d removeObjectForKey:kDarkTheme];
    [d removeObjectForKey:kPostAsAndroid];
    [d removeObjectForKey:kSidebarPlayer];
    [d removeObjectForKey:kVideoQuality];
    [self commit];
}

@end
