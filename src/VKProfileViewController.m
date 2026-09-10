#import "OVKAlignedButton.h"
#import "VKProfileViewController.h"
#import "VKTheme.h"
#import "VKSettings.h"
#import "VKAPI.h"
#import "OVKAPICompatibility.h"
#import "OVKCollectionViewController.h"
#import "VKFriendsViewController.h"
#import "VKSession.h"
#import "VKImageLoader.h"
#import "VKPhotoViewController.h"
#import "VKPostCell.h"
#import "VKChatViewController.h"
#import "VKFriendsViewController.h"
#import "VKWallPostViewController.h"
#import "VKBackend.h"
#import "VKLikes.h"
#import "VKCommentsViewController.h"
#import "VKVideosViewController.h"
#import "VKAudiosViewController.h"
#import "VKAudio.h"
#import "VKVideo.h"
#import "VKAudioPlayer.h"
#import "VKAudioPlayerViewController.h"
#import "VKVideoPlayerViewController.h"
#import "VKVideoPlayback.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// Метрики шапки взяты из оригинальных ассетов ВК: wall_block 97x46,
// wall_blue_btn h=33, wall_posts_panel h=38, wall_photostream_shadow h=100.
static const CGFloat kAvatarSide   = 78.0;
static const CGFloat kSideMargin   = 9.0;
static const CGFloat kTileGap      = 5.0;
static const CGFloat kTileHeight   = 46.0;
static const CGFloat kButtonHeight = 33.0;
static const CGFloat kStripHeight  = 100.0;
static const CGFloat kPanelHeight  = 38.0;
static const CGFloat kPanelShadow  = 3.0;

// ВК и OpenVK отдают одни и те же поля по-разному: где у ВК объект — у OpenVK
// строка, где значение — null. Поэтому всё читаем через проверки типа, иначе
// прилетает unrecognized selector (напр. objectForKey: у NSString в поле city).
static NSString *VKProfileStr(id v) {
    if ([v isKindOfClass:[NSString class]]) return [(NSString *)v length] ? v : nil;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
}

static NSDictionary *VKProfileDict(id v) {
    return [v isKindOfClass:[NSDictionary class]] ? (NSDictionary *)v : nil;
}

static NSArray *VKProfileArr(id v) {
    return [v isKindOfClass:[NSArray class]] ? (NSArray *)v : nil;
}

static NSInteger VKProfileInt(id v) {
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

// Растягиваемая картинка из набора ВК (кнопки, плитки, панель).
static UIImage *VKStretch(NSString *name, NSInteger capW, NSInteger capH) {
    UIImage *img = [UIImage imageNamed:name];
    return img ? [img stretchableImageWithLeftCapWidth:capW topCapHeight:capH] : nil;
}

// Русские числительные для подписей плиток: 51 ДРУГ / 2 ДРУГА / 5 ДРУЗЕЙ.
static NSString *VKPlural(NSInteger n, NSString *one, NSString *few, NSString *many) {
    NSInteger a = ABS(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return many;
    if (b == 1) return one;
    if (b > 1 && b < 5) return few;
    return many;
}

// 837 -> «837», 182000 -> «182K» (как в оригинале).
static NSString *VKShortNum(NSInteger n) {
    if (n >= 1000000) return [NSString stringWithFormat:@"%.1fM", n / 1000000.0];
    if (n >= 100000) return [NSString stringWithFormat:@"%dK", (int)(n / 1000)];
    return [NSString stringWithFormat:@"%d", (int)n];
}

// Приблизительный родительный падеж имени для подписи вкладки «Записи Элвиса».
static NSString *VKGenitiveName(NSString *name) {
    if (!name.length) return nil;
    NSString *last = [name substringFromIndex:name.length - 1];
    NSString *stem = [name substringToIndex:name.length - 1];
    if ([last isEqualToString:@"й"] || [last isEqualToString:@"ь"]) return [stem stringByAppendingString:@"я"];
    if ([last isEqualToString:@"а"]) return [stem stringByAppendingString:@"ы"];
    if ([last isEqualToString:@"я"]) return [stem stringByAppendingString:@"и"];
    if ([last isEqualToString:@"о"] || [last isEqualToString:@"е"]) return name;
    return [name stringByAppendingString:@"а"];
}

@interface VKProfileViewController () <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, UIActionSheetDelegate> {
    long long _ownerId;   // 0 при создании = своя страница, отрицательный = группа
    BOOL _isSelf;
    BOOL _isGroup;
    BOOL _isMember;       // подписан ли на группу
    BOOL _canManageGroup;
    NSInteger _mode;      // 0 — стена, 1 — информация
    NSInteger _tab;       // 0 — все записи, 1 — только записи владельца
    NSInteger _friendStatus; // 0=не друзья, 1=заявка отправлена, 2=входящая заявка, 3=в друзьях
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSDictionary *user;
@property (nonatomic, strong) NSMutableDictionary *counters;
@property (nonatomic, strong) NSArray *photos;   // items из photos.getAll
@property (nonatomic, strong) NSArray *posts;    // VKPost из wall.get
@property (nonatomic, strong) NSMutableArray *infoTitles;
@property (nonatomic, strong) NSMutableArray *infoValues;
@property (nonatomic, strong) NSMutableArray *infoIcons;
@property (nonatomic, strong) UISegmentedControl *switcher;
@property (nonatomic, strong) UIButton *tabAll;
@property (nonatomic, strong) UIButton *tabOwn;
@property (nonatomic, copy) NSString *pendingTitle;
@property (nonatomic, weak) UIButton *friendButton; // слабая ссылка — для обновления без rebuild
@property (nonatomic, strong) VKPost *actionPost;
@end

@implementation VKProfileViewController

- (id)init {
    return [self initWithUserId:0 name:nil];
}

- (id)initWithUserId:(long long)userId name:(NSString *)name {
    self = [super init];
    if (self) {
        _ownerId = userId;
        _pendingTitle = [name copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _isGroup = (_ownerId < 0);
    _isSelf = (!_isGroup && (_ownerId == 0 || _ownerId == [VKSession shared].userId));
    if (_ownerId == 0) _ownerId = [VKSession shared].userId;
    self.title = _isSelf ? @"Моя страница" : (self.pendingTitle ?: @"Страница");
    self.counters = [NSMutableDictionary dictionary];
    self.infoTitles = [NSMutableArray array];
    self.infoValues = [NSMutableArray array];
    self.infoIcons = [NSMutableArray array];

    // Переключатель «Страница | Информация»: в ассетах ВК его нет, поэтому
    // берём системный сегмент-контрол в тон навбару.
    self.switcher = [[UISegmentedControl alloc] initWithItems:
        [NSArray arrayWithObjects:@"Страница", @"Информация", nil]];
    self.switcher.segmentedControlStyle = UISegmentedControlStyleBar;
    self.switcher.tintColor = [UIColor colorWithRed:0.23 green:0.33 blue:0.45 alpha:1.0];
    self.switcher.selectedSegmentIndex = 0;
    self.switcher.frame = CGRectMake(0.0, 0.0, 196.0, 30.0);
    [self.switcher addTarget:self action:@selector(modeChanged)
            forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.switcher;

    // «Поделиться» есть на любой странице — своей, чужой и у сообщества.
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                             target:self action:@selector(shareTapped)];
    if (!_isSelf) {
        // У чужой страницы слева «Назад», а не гамбургер из базового класса.
        self.navigationItem.leftBarButtonItem = nil;
    }

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [self.tableView addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(postLongPressed:)]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wallDidPost:)
                                                 name:VKWallDidPostNotification object:nil];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Загрузка

- (void)reload {
    if (![[VKSession shared] isAuthorized]) {
        [self showMessage:@"Войдите с реальным access_token."];
        return;
    }
    [self showMessage:nil];
    [self showLoading:YES];
    if (_isGroup) { [self reloadGroup]; return; }

    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:
        @"photo_200,photo_100,city,country,bdate,contacts,site,status,last_seen,"
        @"counters,online,screen_name,universities,education,occupation,relation,sex,"
        @"followers_count,common_count,friend_status" forKey:@"fields"];
    if (!_isSelf) {
        [params setObject:[NSString stringWithFormat:@"%lld", _ownerId] forKey:@"user_ids"];
    }

    [[VKAPI shared] callMethod:@"users.get" params:params completion:^(id response, NSError *error) {
        [self showLoading:NO];
        if (error || ![response isKindOfClass:[NSArray class]] || [response count] == 0) {
            [self showMessage:error.localizedDescription ?: @"Не удалось загрузить профиль"];
            return;
        }
        NSDictionary *u = VKProfileDict([response objectAtIndex:0]);
        if (!u) { [self showMessage:@"Профиль пришёл в неизвестном формате"]; return; }
        self.user = u;
        if (!_isSelf) {
            // friend_status: 0=не знакомы, 1=отправили заявку, 2=нам прислали заявку, 3=в друзьях
            _friendStatus = VKProfileInt([u objectForKey:@"friend_status"]);
        }
        if (_ownerId == 0) _ownerId = [[u objectForKey:@"id"] longLongValue];
        [self absorbCounters];
        [self buildInfo];
        [self rebuildHeader];
        [self.tableView reloadData];
        if (!_isSelf) { [self loadPhotos]; [self loadOtherCounts]; }
        [self loadWall];
    }];
}

// Счётчики своей страницы приходят прямо в users.get (поле counters).
- (void)absorbCounters {
    NSDictionary *c = VKProfileDict([self.user objectForKey:@"counters"]);
    NSArray *keys = [NSArray arrayWithObjects:@"friends", @"followers", @"groups",
                     @"photos", @"videos", @"audios", @"pages", nil];
    for (NSString *k in keys) {
        id v = c ? [c objectForKey:k] : nil;
        if (v) [self.counters setObject:[NSNumber numberWithInteger:VKProfileInt(v)] forKey:k];
    }
    id followers = [self.user objectForKey:@"followers_count"];
    if (followers) [self.counters setObject:[NSNumber numberWithInteger:VKProfileInt(followers)]
                                     forKey:@"followers"];
    id common = [self.user objectForKey:@"common_count"];
    if (common) [self.counters setObject:[NSNumber numberWithInteger:VKProfileInt(common)]
                                  forKey:@"mutual"];
}

// Страница паблика/группы: groups.getById вместо users.get.
- (void)reloadGroup {
    NSString *gid = [NSString stringWithFormat:@"%lld", -_ownerId];
    [[VKAPI shared] callMethod:@"groups.getById"
                        params:[NSDictionary dictionaryWithObjectsAndKeys:
                                gid, @"group_id",
                                @"members_count,counters,description,status,site,city,activity,verified,photo_200",
                                @"fields", nil]
                    completion:^(id response, NSError *error) {
        [self showLoading:NO];
        NSDictionary *g = nil;
        if ([response isKindOfClass:[NSArray class]] && [response count]) {
            g = VKProfileDict([response objectAtIndex:0]);
        } else if (VKProfileDict(response)) {
            NSArray *items = VKProfileArr([VKProfileDict(response) objectForKey:@"groups"]);
            g = items.count ? VKProfileDict([items objectAtIndex:0]) : VKProfileDict(response);
        }
        if (!g) {
            [self showMessage:error.localizedDescription ?: @"Не удалось загрузить сообщество"];
            return;
        }
        self.user = g;
        _canManageGroup = VKProfileInt([g objectForKey:@"is_admin"]) != 0 || VKProfileInt([g objectForKey:@"admin_level"]) > 0;
        self.title = VKProfileStr([g objectForKey:@"name"]) ?: @"Сообщество";
        [self absorbGroupCounters];
        [self buildInfo];
        [self rebuildHeader];
        [self.tableView reloadData];
        [self checkMembership];
        [self checkGroupManagement];
        [self loadGroupCounts];
        [self loadPhotos];
        [self loadWall];
    }];
}

- (void)checkGroupManagement {
    if (!_isGroup) return;
    [[VKAPI shared] callMethod:@"groups.getSettings" params:@{@"group_id": @(-_ownerId)} completion:^(id response, NSError *error) {
        BOOL allowed = (!error && [response isKindOfClass:[NSDictionary class]]);
        if (allowed != _canManageGroup) { _canManageGroup = allowed; [self rebuildHeader]; }
    }];
}

- (void)absorbGroupCounters {
    [self.counters setObject:[NSNumber numberWithInteger:
        VKProfileInt([self.user objectForKey:@"members_count"])] forKey:@"members"];
    NSDictionary *c = VKProfileDict([self.user objectForKey:@"counters"]);
    NSArray *keys = [NSArray arrayWithObjects:@"photos", @"videos", @"audios", @"topics", @"docs", nil];
    for (NSString *k in keys) {
        id v = c ? [c objectForKey:k] : nil;
        if (v) [self.counters setObject:[NSNumber numberWithInteger:VKProfileInt(v)] forKey:k];
    }
}

// Подписан ли пользователь — от этого зависит подпись кнопки.
- (void)checkMembership {
    [[VKAPI shared] callMethod:@"groups.isMember"
                        params:@{@"group_id": @(-_ownerId), @"user_id": @([VKSession shared].userId)}
                    completion:^(id response, NSError *error) {
        BOOL member = NO;
        if ([response respondsToSelector:@selector(integerValue)]) member = ([response integerValue] == 1);
        else if (VKProfileDict(response)) member = (VKProfileInt([VKProfileDict(response) objectForKey:@"member"]) == 1);
        if (member != _isMember) { _isMember = member; [self rebuildHeader]; }
    }];
}

- (void)joinTapped {
    if (![[VKSession shared] isAuthorized]) return;
    NSString *method = _isMember ? @"groups.leave" : @"groups.join";
    [[VKAPI shared] callMethod:method params:@{@"group_id": @(-_ownerId)} completion:^(id response, NSError *error) {
        if (error) { [self alertTitle:@"Не удалось изменить подписку" message:error.localizedDescription]; return; }
        [self checkMembership];
    }];
}

- (void)alertTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:title message:message
                        delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
}

// UIActionSheetDelegate — обработка подтверждения удаления/отзыва заявки
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (actionSheet.tag == 190) {
        if (buttonIndex == actionSheet.destructiveButtonIndex) [self performPostMethod:@"wall.delete"];
        else if (buttonIndex == 1) [self removeActionPostLocally];
        else if (buttonIndex == 2) [self performPostMethod:(self.actionPost.pinned ? @"wall.unpin" : @"wall.pin")];
        else if (buttonIndex == 3) [self shareActionPost];
        return;
    }
    if (actionSheet.tag == 77 || actionSheet.tag == 78) {
        // Оба варианта (удалить из друзей и отозвать заявку) = friends.delete
        [self doDeleteFriend];
    }
}

// Для чужой страницы counters не отдаётся — добираем счётчики отдельными
// запросами с count=1 (нужно только поле count в ответе).
- (void)loadOtherCounts {
    NSString *owner = [NSString stringWithFormat:@"%lld", _ownerId];
    NSArray *methods = [NSArray arrayWithObjects:@"friends.get", @"photos.getAll", @"video.get", nil];
    NSArray *keys = [NSArray arrayWithObjects:@"friends", @"photos", @"videos", nil];
    for (NSUInteger i = 0; i < methods.count; i++) {
        NSString *key = [keys objectAtIndex:i];
        NSString *ownerKey = [[methods objectAtIndex:i] isEqualToString:@"friends.get"]
            ? @"user_id" : @"owner_id";
        [[VKAPI shared] callMethod:[methods objectAtIndex:i]
                            params:[NSDictionary dictionaryWithObjectsAndKeys:
                                    owner, ownerKey, @"1", @"count", nil]
                        completion:^(id response, NSError *error) {
            NSDictionary *d = VKProfileDict(response);
            if (!d) return;
            NSInteger n = VKProfileInt([d objectForKey:@"count"]);
            if (n <= 0) return;
            [self.counters setObject:[NSNumber numberWithInteger:n] forKey:key];
            [self rebuildHeader];
        }];
    }
}

// groups.getById не отдаёт counters, поэтому цифры плиток берём отдельными
// запросами с count=1 (как и для чужой страницы).
- (void)loadGroupCounts {
    NSString *owner = [NSString stringWithFormat:@"%lld", _ownerId];   // отрицательный
    NSString *gid = [NSString stringWithFormat:@"%lld", -_ownerId];
    NSArray *methods = [NSArray arrayWithObjects:@"video.get", @"docs.get",
                        @"audio.get", @"board.getTopics", nil];
    NSArray *keys = [NSArray arrayWithObjects:@"videos", @"docs", @"audios", @"topics", nil];
    for (NSUInteger i = 0; i < methods.count; i++) {
        NSString *method = [methods objectAtIndex:i];
        NSString *key = [keys objectAtIndex:i];
        BOOL byGroup = [method isEqualToString:@"board.getTopics"];
        [[VKAPI shared] callMethod:method
                            params:[NSDictionary dictionaryWithObjectsAndKeys:
                                    (byGroup ? gid : owner), (byGroup ? @"group_id" : @"owner_id"),
                                    @"1", @"count", nil]
                        completion:^(id response, NSError *error) {
            // Часть методов закрыта для сторонних клиентов — просто пропускаем.
            NSDictionary *d = VKProfileDict(response);
            NSInteger n = d ? VKProfileInt([d objectForKey:@"count"]) : 0;
            if (n <= 0) return;
            [self.counters setObject:[NSNumber numberWithInteger:n] forKey:key];
            [self rebuildHeader];
        }];
    }
}

// Полоска фотографий в шапке чужой страницы.
- (void)loadPhotos {
    [[VKAPI shared] callMethod:@"photos.getAll"
                        params:[NSDictionary dictionaryWithObjectsAndKeys:
                                [NSString stringWithFormat:@"%lld", _ownerId], @"owner_id",
                                @"20", @"count", @"1", @"photo_sizes", nil]
                    completion:^(id response, NSError *error) {
        if ([self absorbPhotos:response]) return;
        // У сообществ photos.getAll обычно пустой — берём альбом со стены.
        if (_isGroup) [self loadWallAlbum];
    }];
}

- (void)loadWallAlbum {
    // OpenVK requires a numeric album ID and does not expose a VK "wall" alias.
    // Group albums are available through the photo tile.
}

// Кладёт items в полоску, а count — в плитку «фото». YES, если что-то пришло.
- (BOOL)absorbPhotos:(id)response {
    NSDictionary *d = VKProfileDict(response);
    NSArray *items = d ? VKProfileArr([d objectForKey:@"items"]) : nil;
    if (items.count == 0) return NO;
    self.photos = items;
    NSInteger total = VKProfileInt([d objectForKey:@"count"]);
    [self.counters setObject:[NSNumber numberWithInteger:MAX(total, (NSInteger)items.count)]
                      forKey:@"photos"];
    [self rebuildHeader];
    return YES;
}

- (void)loadWall {
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [NSString stringWithFormat:@"%lld", _ownerId], @"owner_id",
        @"20", @"count", @"1", @"extended", nil];
    [params setObject:(_tab == 1 ? @"owner" : @"all") forKey:@"filter"];
    [[VKAPI shared] callMethod:@"wall.get" params:params completion:^(id response, NSError *error) {
        NSDictionary *d = VKProfileDict(response);
        self.posts = d ? [self parseWall:d] : nil;
        if (_mode == 0) [self.tableView reloadData];
    }];
}

// Разбор wall.get (extended=1): имена и аватары авторов — из profiles/groups.
- (NSArray *)parseWall:(NSDictionary *)response {
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    NSMutableDictionary *avatars = [NSMutableDictionary dictionary];
    for (id raw in (VKProfileArr([response objectForKey:@"profiles"]) ?: [NSArray array])) {
        NSDictionary *p = VKProfileDict(raw);
        if (!p) continue;
        NSString *key = [NSString stringWithFormat:@"%lld", (long long)VKProfileInt([p objectForKey:@"id"])];
        [names setObject:[NSString stringWithFormat:@"%@ %@",
                          VKProfileStr([p objectForKey:@"first_name"]) ?: @"",
                          VKProfileStr([p objectForKey:@"last_name"]) ?: @""] forKey:key];
        NSString *ph = VKProfileStr([p objectForKey:@"photo_100"]) ?: VKProfileStr([p objectForKey:@"photo_50"]);
        if (ph) [avatars setObject:ph forKey:key];
    }
    for (id raw in (VKProfileArr([response objectForKey:@"groups"]) ?: [NSArray array])) {
        NSDictionary *g = VKProfileDict(raw);
        if (!g) continue;
        NSString *key = [NSString stringWithFormat:@"%lld", -(long long)VKProfileInt([g objectForKey:@"id"])];
        [names setObject:(VKProfileStr([g objectForKey:@"name"]) ?: @"") forKey:key];
        NSString *ph = VKProfileStr([g objectForKey:@"photo_100"]) ?: VKProfileStr([g objectForKey:@"photo_50"]);
        if (ph) [avatars setObject:ph forKey:key];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (id raw in (VKProfileArr([response objectForKey:@"items"]) ?: [NSArray array])) {
        NSDictionary *item = VKProfileDict(raw);
        if (!item) continue;
        long long rawPostId = (long long)VKProfileInt([item objectForKey:@"id"]);
        if ([self isLocallyArchivedPostId:rawPostId]) continue;
        NSString *text = [OVKAPICompatibility postText:item] ?: @"";
        NSString *photoURL = nil; CGFloat aspect = 0.0;
        VKAudio *audioAttachment = nil;
        VKVideo *videoAttachment = nil;
        for (id att in (VKProfileArr([item objectForKey:@"attachments"]) ?: [NSArray array])) {
            NSDictionary *a = VKProfileDict(att);
            NSString *type = VKProfileStr([a objectForKey:@"type"]);
            if ([type isEqualToString:@"audio"] && !audioAttachment) {
                audioAttachment = [VKAudio audioFromDictionary:VKProfileDict([a objectForKey:@"audio"])];
                continue;
            }
            if ([type isEqualToString:@"video"] && !videoAttachment) {
                videoAttachment = [VKVideo videoFromDictionary:VKProfileDict([a objectForKey:@"video"]) profiles:@{} groups:@{}];
                continue;
            }
            if (![type isEqualToString:@"photo"] || photoURL.length) continue;
            NSDictionary *photo = VKProfileDict([a objectForKey:@"photo"]);
            photoURL = [self photoURL:photo type:@"x" fallback:@"y"];
            aspect = [self aspectOfPhoto:photo];
        }
        if (text.length == 0 && !photoURL && !audioAttachment && !videoAttachment) continue;

        VKPost *post = [[VKPost alloc] init];
        id from = [item objectForKey:@"from_id"] ?: [item objectForKey:@"owner_id"];
        long long fromId = (long long)VKProfileInt(from);
        NSString *key = [NSString stringWithFormat:@"%lld", fromId];
        post.authorId = fromId;
        post.authorName = [names objectForKey:key] ?: (self.pendingTitle ?: @"Запись");
        post.avatarURL = [avatars objectForKey:key];
        post.text = text;
        post.photoURL = photoURL;
        post.photoAspect = aspect;
        post.audioAttachment = audioAttachment;
        post.videoAttachment = videoAttachment;
        post.timeText = [self relativeTime:(NSTimeInterval)VKProfileInt([item objectForKey:@"date"])];
        post.likes = VKProfileInt([VKProfileDict([item objectForKey:@"likes"]) objectForKey:@"count"]);
        post.comments = VKProfileInt([VKProfileDict([item objectForKey:@"comments"]) objectForKey:@"count"]);
        post.reposts = VKProfileInt([VKProfileDict([item objectForKey:@"reposts"]) objectForKey:@"count"]);
        // Стена, на которой лежит запись, — это владелец страницы, а не автор
        // (у чужих записей from_id может отличаться от owner_id).
        post.ownerId = _ownerId;
        post.postId = (long long)VKProfileInt([item objectForKey:@"id"]);
        post.pinned = VKProfileInt([item objectForKey:@"is_pinned"]) != 0;
        post.repost = ([[item objectForKey:@"copy_history"] isKindOfClass:[NSArray class]] && [[item objectForKey:@"copy_history"] count] > 0) ||
                       ([[item objectForKey:@"repost_history"] isKindOfClass:[NSArray class]] && [[item objectForKey:@"repost_history"] count] > 0);
        NSArray *history = [item objectForKey:@"copy_history"];
        if (![history isKindOfClass:[NSArray class]] || !history.count) history = [item objectForKey:@"repost_history"];
        NSDictionary *original = [history isKindOfClass:[NSArray class]] && history.count && [[history objectAtIndex:0] isKindOfClass:[NSDictionary class]] ? [history objectAtIndex:0] : nil;
        if (original) {
            long long author = [[original objectForKey:@"from_id"] longLongValue];
            if (!author) author = [[original objectForKey:@"owner_id"] longLongValue];
            post.originalAuthorId = author;
            NSString *key = [NSString stringWithFormat:@"%lld", author];
            post.originalName = [names objectForKey:key] ?: [NSString stringWithFormat:author < 0 ? @"Сообщество %lld" : @"Пользователь %lld", llabs(author)];
            post.originalAvatarURL = [avatars objectForKey:key];
            post.originalText = [OVKAPICompatibility postText:original];
            for (NSDictionary *attachment in [original objectForKey:@"attachments"]) {
                NSString *type = [attachment objectForKey:@"type"];
                if ([type isEqualToString:@"audio"] && !post.audioAttachment) {
                    post.audioAttachment = [VKAudio audioFromDictionary:[attachment objectForKey:@"audio"]];
                } else if ([type isEqualToString:@"video"] && !post.videoAttachment) {
                    post.videoAttachment = [VKVideo videoFromDictionary:[attachment objectForKey:@"video"] profiles:@{} groups:@{}];
                }
            }
            if (!post.photoURL.length) for (NSDictionary *attachment in [original objectForKey:@"attachments"]) {
                NSDictionary *photo = [attachment objectForKey:@"photo"];
                if (![photo isKindOfClass:[NSDictionary class]]) continue;
                NSString *url = [photo objectForKey:@"photo_604"] ?: [photo objectForKey:@"photo_130"];
                CGFloat ratio = 1;
                for (NSDictionary *size in [photo objectForKey:@"sizes"]) {
                    NSString *candidate = [size objectForKey:@"url"] ?: [size objectForKey:@"src"];
                    if ([candidate isKindOfClass:[NSString class]]) {
                        url = candidate;
                        CGFloat width = [[size objectForKey:@"width"] doubleValue];
                        if (width > 0) ratio = [[size objectForKey:@"height"] doubleValue] / width;
                    }
                }
                if ([url isKindOfClass:[NSString class]] && url.length) { post.photoURL = url; post.photoAspect = ratio > 0 ? ratio : 1; break; }
            }

            NSMutableDictionary *own = [item mutableCopy];
            [own removeObjectForKey:@"copy_history"]; [own removeObjectForKey:@"repost_history"];
            post.text = [OVKAPICompatibility postText:own];
        }

        post.liked = VKProfileInt([VKProfileDict([item objectForKey:@"likes"]) objectForKey:@"user_likes"]) != 0;
        post.views = VKProfileInt([VKProfileDict([item objectForKey:@"views"]) objectForKey:@"count"]);
        NSString *initials = post.authorName.length ? [[post.authorName substringToIndex:1] uppercaseString] : @"?";
        post.avatar = [VKTheme avatarWithInitials:initials size:40.0 background:[VKTheme navBarColor]];
        [result addObject:post];
    }
    return result;
}

// Достаёт URL нужного размера из объекта фото (учитывая плоские поля OpenVK).
- (NSString *)photoURL:(NSDictionary *)photo type:(NSString *)wanted fallback:(NSString *)fb {
    photo = VKProfileDict(photo);
    if (!photo) return nil;
    NSString *best = nil, *fallback = nil;
    for (id raw in (VKProfileArr([photo objectForKey:@"sizes"]) ?: [NSArray array])) {
        NSDictionary *s = VKProfileDict(raw);
        NSString *t = VKProfileStr([s objectForKey:@"type"]);
        if ([t isEqualToString:wanted]) best = VKProfileStr([s objectForKey:@"url"]);
        if ([t isEqualToString:fb]) fallback = VKProfileStr([s objectForKey:@"url"]);
    }
    if (best) return best;
    if (fallback) return fallback;
    NSArray *flat = [NSArray arrayWithObjects:@"photo_604", @"photo_130", @"src_big", @"src", @"url", nil];
    for (NSString *k in flat) {
        NSString *v = VKProfileStr([photo objectForKey:k]);
        if (v) return v;
    }
    return nil;
}

- (CGFloat)aspectOfPhoto:(NSDictionary *)photo {
    for (id raw in (VKProfileArr([photo objectForKey:@"sizes"]) ?: [NSArray array])) {
        NSDictionary *s = VKProfileDict(raw);
        NSString *t = VKProfileStr([s objectForKey:@"type"]);
        if (![t isEqualToString:@"x"] && ![t isEqualToString:@"y"]) continue;
        CGFloat w = VKProfileInt([s objectForKey:@"width"]);
        CGFloat h = VKProfileInt([s objectForKey:@"height"]);
        if (w > 0.0 && h > 0.0) return h / w;
    }
    return 0.0;
}

- (NSString *)relativeTime:(NSTimeInterval)ts {
    if (ts <= 0) return @"";
    NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - ts;
    if (diff < 60) return @"только что";
    if (diff < 3600) {
        int m = (int)(diff / 60);
        return [NSString stringWithFormat:@"%d %@ назад", m, VKPlural(m, @"минуту", @"минуты", @"минут")];
    }
    if (diff < 86400) {
        int h = (int)(diff / 3600);
        return [NSString stringWithFormat:@"%d %@ назад", h, VKPlural(h, @"час", @"часа", @"часов")];
    }
    int d = (int)(diff / 86400);
    return [NSString stringWithFormat:@"%d %@ назад", d, VKPlural(d, @"день", @"дня", @"дней")];
}

#pragma mark - Текстовые строки шапки

- (NSString *)cityTitle {
    id raw = [self.user objectForKey:@"city"];
    NSDictionary *d = VKProfileDict(raw);
    return d ? VKProfileStr([d objectForKey:@"title"]) : VKProfileStr(raw);
}

// «online» или «заходил(а) 45 минут назад».
- (NSString *)presenceLine {
    if (VKProfileInt([self.user objectForKey:@"online"]) == 1) return @"online";
    NSDictionary *ls = VKProfileDict([self.user objectForKey:@"last_seen"]);
    NSTimeInterval t = ls ? (NSTimeInterval)VKProfileInt([ls objectForKey:@"time"]) : 0.0;
    if (t <= 0.0) return @"не в сети";
    BOOL female = VKProfileInt([self.user objectForKey:@"sex"]) == 1;
    return [NSString stringWithFormat:@"%@ %@", female ? @"заходила" : @"заходил",
            [self relativeTime:t]];
}

// Вторая строка шапки паблика: тематика (activity), иначе тип сообщества.
- (NSString *)groupKindLine {
    NSString *activity = VKProfileStr([self.user objectForKey:@"activity"]);
    if (activity.length) return activity;
    NSString *type = VKProfileStr([self.user objectForKey:@"type"]);
    if ([type isEqualToString:@"page"]) return @"Публичная страница";
    if ([type isEqualToString:@"event"]) return @"Событие";
    return @"Группа";
}

// Третья строка: статус, иначе город, иначе число подписчиков.
- (NSString *)groupSubLine {
    NSString *status = VKProfileStr([self.user objectForKey:@"status"]);
    if (status.length) return status;
    NSString *city = [self cityTitle];
    if (city.length) return city;
    NSInteger n = VKProfileInt([self.counters objectForKey:@"members"]);
    if (n <= 0) return @"";
    return [NSString stringWithFormat:@"%d %@", (int)n,
            VKPlural(n, @"подписчик", @"подписчика", @"подписчиков")];
}

// bdate вида «19.1.1935» — полные годы. Без года рождения (только «19.1») — 0.
- (NSInteger)age {
    NSString *bdate = VKProfileStr([self.user objectForKey:@"bdate"]);
    NSArray *parts = [bdate componentsSeparatedByString:@"."];
    if (parts.count < 3) return 0;
    NSInteger day = [[parts objectAtIndex:0] integerValue];
    NSInteger month = [[parts objectAtIndex:1] integerValue];
    NSInteger year = [[parts objectAtIndex:2] integerValue];
    if (year < 1900) return 0;
    NSDateComponents *now = [[NSCalendar currentCalendar]
        components:(NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:[NSDate date]];
    NSInteger age = now.year - year;
    if (now.month < month || (now.month == month && now.day < day)) age--;
    return (age > 0 && age < 130) ? age : 0;
}

// «22 года, Волгоград».
- (NSString *)ageCityLine {
    NSMutableArray *parts = [NSMutableArray array];
    NSInteger age = [self age];
    if (age > 0) {
        [parts addObject:[NSString stringWithFormat:@"%d %@", (int)age,
                          VKPlural(age, @"год", @"года", @"лет")]];
    }
    NSString *city = [self cityTitle];
    if (city.length) [parts addObject:city];
    return [parts componentsJoinedByString:@", "];
}

#pragma mark - Вкладка «Информация»

- (void)addInfo:(NSString *)title value:(NSString *)value icon:(NSString *)icon {
    if (!value.length) return;
    [self.infoTitles addObject:title];
    [self.infoValues addObject:value];
    [self.infoIcons addObject:icon ?: @""];
}

// «19.1.1935» -> «19 января 1935 г.»
- (NSString *)humanBdate {
    NSString *bdate = VKProfileStr([self.user objectForKey:@"bdate"]);
    NSArray *parts = [bdate componentsSeparatedByString:@"."];
    if (parts.count < 2) return bdate;
    static NSArray *months = nil;
    if (!months) months = [NSArray arrayWithObjects:@"января", @"февраля", @"марта", @"апреля",
        @"мая", @"июня", @"июля", @"августа", @"сентября", @"октября", @"ноября", @"декабря", nil];
    NSInteger m = [[parts objectAtIndex:1] integerValue];
    if (m < 1 || m > 12) return bdate;
    NSString *head = [NSString stringWithFormat:@"%d %@", (int)[[parts objectAtIndex:0] integerValue],
                      [months objectAtIndex:m - 1]];
    if (parts.count < 3) return head;
    return [NSString stringWithFormat:@"%@ %@ г.", head, [parts objectAtIndex:2]];
}

- (void)buildInfo {
    [self.infoTitles removeAllObjects];
    [self.infoValues removeAllObjects];
    [self.infoIcons removeAllObjects];
    if (_isGroup) { [self buildGroupInfo]; return; }
    NSDictionary *u = self.user;

    NSString *domain = VKProfileStr([u objectForKey:@"screen_name"]);
    if (domain.length) {
        [self addInfo:@"Адрес страницы" value:[NSString stringWithFormat:@"%@/%@", [[VKBackend shared] webHost], domain]
                icon:@"profile_connection_screen_name"];
    }
    [self addInfo:@"Статус" value:VKProfileStr([u objectForKey:@"status"]) icon:@"profile_sp_icon"];
    [self addInfo:@"День рождения" value:[self humanBdate] icon:@"profile_birth_icon"];
    [self addInfo:@"Город" value:[self cityTitle] icon:@"profile_city_icon"];

    NSDictionary *uni = VKProfileArr([u objectForKey:@"universities"]).count
        ? VKProfileDict([VKProfileArr([u objectForKey:@"universities"]) objectAtIndex:0]) : nil;
    NSString *edu = uni ? VKProfileStr([uni objectForKey:@"name"])
                        : VKProfileStr([u objectForKey:@"university_name"]);
    [self addInfo:@"Образование" value:edu icon:@"profile_university_icon"];

    [self addInfo:@"Мобильный телефон" value:VKProfileStr([u objectForKey:@"mobile_phone"])
             icon:@"profile_mobile_icon"];
    [self addInfo:@"Домашний телефон" value:VKProfileStr([u objectForKey:@"home_phone"])
             icon:@"profile_phone_icon"];
    [self addInfo:@"Сайт" value:VKProfileStr([u objectForKey:@"site"]) icon:@"profile_site_icon"];
}

// Информация о сообществе: описание, тематика, город, сайт, подписчики.
- (void)buildGroupInfo {
    NSDictionary *g = self.user;
    NSString *domain = VKProfileStr([g objectForKey:@"screen_name"]);
    if (domain.length) {
        [self addInfo:@"Адрес страницы" value:[NSString stringWithFormat:@"%@/%@", [[VKBackend shared] webHost], domain]
                icon:@"profile_connection_screen_name"];
    }
    [self addInfo:@"Статус" value:VKProfileStr([g objectForKey:@"status"]) icon:@"profile_sp_icon"];
    [self addInfo:@"Тематика" value:VKProfileStr([g objectForKey:@"activity"]) icon:@"profile_sp_icon"];
    [self addInfo:@"Город" value:[self cityTitle] icon:@"profile_city_icon"];
    [self addInfo:@"Сайт" value:VKProfileStr([g objectForKey:@"site"]) icon:@"profile_site_icon"];
    NSInteger members = VKProfileInt([self.counters objectForKey:@"members"]);
    if (members > 0) {
        [self addInfo:@"Подписчики"
                value:[NSString stringWithFormat:@"%d %@", (int)members,
                       VKPlural(members, @"человек", @"человека", @"человек")]
                 icon:@"profile_friends_icon"];
    }
    [self addInfo:@"Описание" value:VKProfileStr([g objectForKey:@"description"])
             icon:@"profile_sp_icon"];
}

#pragma mark - Тёмная шапка

- (void)rebuildHeader {
    self.tableView.tableHeaderView = (_mode == 1) ? nil : [self buildHeader];
}

- (UIView *)buildHeader {
    CGFloat W = self.view.bounds.size.width;
    BOOL hasStrip = (!_isSelf && self.photos.count > 0);
    CGFloat buttonsY = 96.0 + kTileHeight * 2.0 + kTileGap + 8.0;
    // Чужая страница: две строки кнопок (сообщение+друзья, потом «написать на стену»)
    CGFloat extraRowH = (!_isSelf && !_isGroup) ? (kButtonHeight + 6.0) : 0.0;
    CGFloat blockH = buttonsY + kButtonHeight + 8.0 + extraRowH;
    if (hasStrip) blockH += kStripHeight;
    CGFloat totalH = blockH + kPanelShadow + kPanelHeight;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, W, totalH)];
    header.clipsToBounds = YES;
    header.backgroundColor = [VKSettings shared].darkTheme
        ? [UIColor colorWithRed:0.16 green:0.13 blue:0.22 alpha:1.0]
        : [UIColor colorWithRed:0.13 green:0.19 blue:0.28 alpha:1.0];

    // Оригинальный фон стены (320x568) прижат к верху — градиент совпадает с ВК.
    UIImage *bg = [UIImage imageNamed:([VKSettings shared].darkTheme ? @"dark_theme_wall" : @"wall_background")];
    if (bg) {
        UIImageView *bgv = [[UIImageView alloc] initWithImage:bg];
        bgv.frame = CGRectMake(0.0, 0.0, W, bg.size.height);
        [header addSubview:bgv];
    }
    UIImage *topShadow = VKStretch(@"wall_top_shadow", 7, 0);
    if (topShadow) {
        UIImageView *ts = [[UIImageView alloc] initWithImage:topShadow];
        ts.frame = CGRectMake(0.0, 0.0, W, topShadow.size.height);
        [header addSubview:ts];
    }

    [self addAvatarAndTitlesTo:header];
    [self addTilesTo:header y:96.0];
    [self addButtonsTo:header y:buttonsY];
    if (hasStrip) [self addStripTo:header y:blockH - kStripHeight];
    [self addPanelTo:header y:blockH];
    return header;
}

- (void)addAvatarAndTitlesTo:(UIView *)header {
    CGFloat W = header.bounds.size.width;
    CGRect frame = CGRectMake(kSideMargin, 9.0, kAvatarSide, kAvatarSide);

    NSString *fullName;
    if (_isGroup) {
        fullName = VKProfileStr([self.user objectForKey:@"name"]) ?: @"";
    } else {
        NSString *first = VKProfileStr([self.user objectForKey:@"first_name"]) ?: @"";
        NSString *last = VKProfileStr([self.user objectForKey:@"last_name"]) ?: @"";
        fullName = [[NSString stringWithFormat:@"%@ %@", first, last]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }

    // Никакой рамки вокруг фото — в оригинале аватар лежит прямо на фоне.
    UIImageView *avatar = [[UIImageView alloc] initWithFrame:frame];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 0.0;
    avatar.image = [UIImage imageNamed:@"user_placeholder"];
    if (!avatar.image) {
        NSString *initials = fullName.length ? [[fullName substringToIndex:1] uppercaseString] : @"?";
        avatar.image = [VKTheme avatarWithInitials:initials size:kAvatarSide
                                       background:[VKTheme navBarColor]];
    }
    NSString *photo = VKProfileStr([self.user objectForKey:@"photo_200"])
        ?: VKProfileStr([self.user objectForKey:@"photo_100"])
        ?: VKProfileStr([self.user objectForKey:@"photo_max_orig"]);
    if (photo.length) {
        [[VKImageLoader shared] loadURL:photo completion:^(UIImage *image) {
            if (image) avatar.image = image;
        }];
    }
    [header addSubview:avatar];

    CGFloat tx = kSideMargin + kAvatarSide + 10.0;
    CGFloat tw = W - tx - 10.0;
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(tx, 11.0, tw, 21.0)];
    name.text = fullName;
    name.font = [UIFont boldSystemFontOfSize:17.0];
    name.textColor = [UIColor whiteColor];
    name.backgroundColor = [UIColor clearColor];
    name.adjustsFontSizeToFitWidth = YES;
    name.minimumFontSize = 13.0;
    name.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    name.shadowOffset = CGSizeMake(0.0, -1.0);
    [header addSubview:name];

    UIColor *grey = [UIColor colorWithRed:0.49 green:0.56 blue:0.66 alpha:1.0];
    UILabel *presence = [[UILabel alloc] initWithFrame:CGRectMake(tx, 34.0, tw, 15.0)];
    presence.text = _isGroup ? [self groupKindLine] : [self presenceLine];
    presence.font = [UIFont systemFontOfSize:12.0];
    presence.textColor = grey;
    presence.backgroundColor = [UIColor clearColor];
    [header addSubview:presence];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(tx, 51.0, tw, 15.0)];
    sub.text = _isGroup ? [self groupSubLine] : [self ageCityLine];
    sub.font = [UIFont systemFontOfSize:12.0];
    sub.textColor = grey;
    sub.backgroundColor = [UIColor clearColor];
    [header addSubview:sub];
}

// Набор плиток: своя страница, чужая страница или сообщество.
- (NSArray *)tileSpecs {
    if (_isGroup) {
        return [NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"members", @"подписчик", @"подписчика", @"подписчиков", nil],
            [NSArray arrayWithObjects:@"photos", @"фото", @"фото", @"фото", nil],
            [NSArray arrayWithObjects:@"videos", @"видео", @"видео", @"видео", nil],
            [NSArray arrayWithObjects:@"audios", @"аудио", @"аудио", @"аудио", nil],
            [NSArray arrayWithObjects:@"topics", @"обсуждение", @"обсуждения", @"обсуждений", nil],
            [NSArray arrayWithObjects:@"docs", @"документ", @"документа", @"документов", nil], nil];
    }
    if (_isSelf) {
        return [NSArray arrayWithObjects:
            [NSArray arrayWithObjects:@"friends", @"друг", @"друга", @"друзей", nil],
            [NSArray arrayWithObjects:@"followers", @"подписчик", @"подписчика", @"подписчиков", nil],
            [NSArray arrayWithObjects:@"groups", @"группа", @"группы", @"групп", nil],
            [NSArray arrayWithObjects:@"photos", @"фото", @"фото", @"фото", nil],
            [NSArray arrayWithObjects:@"videos", @"видео", @"видео", @"видео", nil],
            [NSArray arrayWithObjects:@"audios", @"аудио", @"аудио", @"аудио", nil], nil];
    }
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"friends", @"друг", @"друга", @"друзей", nil],
        [NSArray arrayWithObjects:@"mutual", @"общий", @"общих", @"общих", nil],
        [NSArray arrayWithObjects:@"followers", @"подписчик", @"подписчика", @"подписчиков", nil],
        [NSArray arrayWithObjects:@"photos", @"фото", @"фото", @"фото", nil],
        [NSArray arrayWithObjects:@"videos", @"видео", @"видео", @"видео", nil],
        [NSArray arrayWithObjects:@"audios", @"аудио", @"аудио", @"аудио", nil], nil];
}

// Сетка 3x2 из плиток wall_block.
- (void)addTilesTo:(UIView *)header y:(CGFloat)y {
    CGFloat W = header.bounds.size.width;
    CGFloat tileW = (W - kSideMargin * 2.0 - kTileGap * 2.0) / 3.0;
    NSArray *specs = [self tileSpecs];

    UIImage *normal = VKStretch(@"wall_block", 10, 10);
    UIImage *pressed = VKStretch(@"wall_block_hl", 10, 10);
    for (NSUInteger i = 0; i < specs.count; i++) {
        NSArray *s = [specs objectAtIndex:i];
        NSInteger n = VKProfileInt([self.counters objectForKey:[s objectAtIndex:0]]);
        CGFloat tx = kSideMargin + (i % 3) * (tileW + kTileGap);
        CGFloat ty = y + (i / 3) * (kTileHeight + kTileGap);

        UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
        tile.frame = CGRectMake(tx, ty, tileW, kTileHeight);
        [tile setBackgroundImage:normal forState:UIControlStateNormal];
        [tile setBackgroundImage:pressed forState:UIControlStateHighlighted];
        tile.tag = (NSInteger)i;
        [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];

        UILabel *num = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 6.0, tileW, 20.0)];
        num.text = VKShortNum(n);
        num.font = [UIFont boldSystemFontOfSize:17.0];
        num.textColor = [UIColor whiteColor];
        num.textAlignment = NSTextAlignmentCenter;
        num.backgroundColor = [UIColor clearColor];
        num.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.5];
        num.shadowOffset = CGSizeMake(0.0, -1.0);
        [tile addSubview:num];

        UILabel *cap = [[UILabel alloc] initWithFrame:CGRectMake(2.0, 27.0, tileW - 4.0, 12.0)];
        cap.text = [VKPlural(n, [s objectAtIndex:1], [s objectAtIndex:2], [s objectAtIndex:3]) uppercaseString];
        cap.font = [UIFont boldSystemFontOfSize:9.0];
        cap.textColor = [UIColor colorWithRed:0.52 green:0.60 blue:0.71 alpha:1.0];
        cap.textAlignment = NSTextAlignmentCenter;
        cap.backgroundColor = [UIColor clearColor];
        cap.adjustsFontSizeToFitWidth = YES;
        cap.minimumFontSize = 7.0;
        [tile addSubview:cap];

        [header addSubview:tile];
    }
}

- (UIButton *)blueButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *b = [OVKAlignedButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:VKStretch(@"wall_blue_btn", 7, 0) forState:UIControlStateNormal];
    [b setBackgroundImage:VKStretch(@"wall_blue_btn_hl", 7, 0) forState:UIControlStateHighlighted];
    if (title.length) {
        [b setTitle:title forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.4] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        b.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumFontSize = 10.0;
    }
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)grayButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *b = [OVKAlignedButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:VKStretch(@"wall_gray_btn", 7, 0) forState:UIControlStateNormal];
    [b setBackgroundImage:VKStretch(@"wall_gray_btn_hl", 7, 0) forState:UIControlStateHighlighted];
    if (title.length) {
        [b setTitle:title forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleShadowColor:[UIColor colorWithWhite:0.0 alpha:0.4] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
        b.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumFontSize = 10.0;
    }
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

// Своя страница: «Добавить запись» + камера. Чужая: сообщение + в друзья.
// Сообщество: подписка на всю ширину.
- (void)addButtonsTo:(UIView *)header y:(CGFloat)y {
    CGFloat W = header.bounds.size.width;
    if (_isGroup) {
        if (_canManageGroup) {
            CGFloat half = (W - kSideMargin * 2.0 - 6.0) / 2.0;
            UIButton *write = [self blueButtonWithTitle:@"Добавить запись" action:@selector(addPostTapped)];
            write.frame = CGRectMake(kSideMargin, y, half, kButtonHeight);
            [header addSubview:write];
            UIButton *join = [self grayButtonWithTitle:(_isMember ? @"Вы подписаны" : @"Подписаться") action:@selector(joinTapped)];
            join.frame = CGRectMake(kSideMargin + half + 6.0, y, half, kButtonHeight);
            [header addSubview:join];
            return;
        }
        UIButton *join = [self blueButtonWithTitle:(_isMember ? @"Вы подписаны" : @"Подписаться")
                                           action:@selector(joinTapped)];
        join.frame = CGRectMake(kSideMargin, y, W - kSideMargin * 2.0, kButtonHeight);
        [header addSubview:join];
        return;
    }
    if (_isSelf) {
        CGFloat camW = 46.0;
        UIButton *add = [self blueButtonWithTitle:@"Добавить запись" action:@selector(addPostTapped)];
        add.frame = CGRectMake(kSideMargin, y, W - kSideMargin * 2.0 - camW - 6.0, kButtonHeight);
        [header addSubview:add];

        UIButton *cam = [self blueButtonWithTitle:nil action:@selector(cameraTapped)];
        cam.frame = CGRectMake(W - kSideMargin - camW, y, camW, kButtonHeight);
        UIImage *icon = [UIImage imageNamed:@"wall_addphoto_icon"];
        if (icon) [cam setImage:icon forState:UIControlStateNormal];
        [header addSubview:cam];
    } else {
        CGFloat w = (W - kSideMargin * 2.0 - 6.0) / 2.0;
        UIButton *msg = [self blueButtonWithTitle:@"Личное сообщение" action:@selector(messageTapped)];
        msg.frame = CGRectMake(kSideMargin, y, w, kButtonHeight);
        [header addSubview:msg];

        // Текст и действие зависят от friend_status:
        // 0 = незнакомы     → «Добавить в друзья» (friends.add)
        // 1 = заявка нами отправлена → «Заявка отправлена» (серая, тап = отозвать)
        // 2 = нам прислали заявку   → «Принять заявку» (синяя, tap = friends.add)
        // 3 = в друзьях             → «В друзьях ✓» (серая, тап = удалить)
        NSString *friendTitle;
        SEL friendAction;
        BOOL friendGray = NO;
        switch (_friendStatus) {
            case 3:
                friendTitle  = @"В друзьях ✓";
                friendAction = @selector(removeFriendTapped);
                friendGray   = YES;
                break;
            case 1:
                friendTitle  = @"Заявка отправлена";
                friendAction = @selector(cancelFriendRequestTapped);
                friendGray   = YES;
                break;
            case 2:
                friendTitle  = @"Принять заявку";
                friendAction = @selector(addFriendTapped);
                break;
            default: // 0
                friendTitle  = @"Добавить в друзья";
                friendAction = @selector(addFriendTapped);
                break;
        }

        UIButton *add;
        if (friendGray) {
            add = [self grayButtonWithTitle:friendTitle action:friendAction];
        } else {
            add = [self blueButtonWithTitle:friendTitle action:friendAction];
        }
        add.frame = CGRectMake(kSideMargin + w + 6.0, y, w, kButtonHeight);
        [header addSubview:add];
        self.friendButton = add;

        // Вторая строка: «Написать на стену» + кнопка-фото
        CGFloat y2 = y + kButtonHeight + 6.0;
        CGFloat camW2 = 46.0;
        UIButton *writeBtn = [self blueButtonWithTitle:@"Написать на стену"
                                               action:@selector(addPostTapped)];
        // Иконка карандаша слева от текста
        UIImage *writeIcon = [UIImage imageNamed:@"wall_addpost_icon"];
        if (writeIcon) {
            [writeBtn setImage:writeIcon forState:UIControlStateNormal];
            writeBtn.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 6.0);
            writeBtn.titleEdgeInsets = UIEdgeInsetsMake(0, 4.0, 0, 0);
        }
        writeBtn.frame = CGRectMake(kSideMargin, y2,
                                    W - kSideMargin * 2.0 - camW2 - 6.0, kButtonHeight);
        [header addSubview:writeBtn];

        UIButton *cam2 = [self blueButtonWithTitle:nil action:@selector(cameraTapped)];
        UIImage *camIcon = [UIImage imageNamed:@"wall_addphoto_icon"];
        if (camIcon) {
            [cam2 setImage:camIcon forState:UIControlStateNormal];
            UIImage *camHl = [UIImage imageNamed:@"wall_addphoto_icon"];
            if (camHl) [cam2 setImage:camHl forState:UIControlStateHighlighted];
        }
        cam2.frame = CGRectMake(W - kSideMargin - camW2, y2, camW2, kButtonHeight);
        [header addSubview:cam2];
    }
}

// Полоска фотографий (только у чужой страницы, как в оригинале).
- (void)addStripTo:(UIView *)header y:(CGFloat)y {
    CGFloat W = header.bounds.size.width;
    CGFloat thumb = 84.0, pad = 8.0, gap = 4.0;
    UIScrollView *strip = [[UIScrollView alloc] initWithFrame:CGRectMake(0.0, y, W, kStripHeight)];
    strip.backgroundColor = [UIColor clearColor];
    strip.showsHorizontalScrollIndicator = NO;
    CGFloat x = pad;
    for (NSUInteger i = 0; i < self.photos.count; i++) {
        NSDictionary *photo = VKProfileDict([self.photos objectAtIndex:i]);
        NSString *thumbURL = [self photoURL:photo type:@"m" fallback:@"s"];
        NSString *bigURL = [self photoURL:photo type:@"x" fallback:@"y"];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:
            CGRectMake(x, (kStripHeight - thumb) / 2.0, thumb, thumb)];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
        iv.userInteractionEnabled = YES;
        if (thumbURL) {
            [[VKImageLoader shared] loadURL:thumbURL completion:^(UIImage *image) {
                if (image) iv.image = image;
            }];
        }
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(openPhoto:)];
        [iv addGestureRecognizer:tap];
        objc_setAssociatedObject(iv, "bigURL", bigURL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [strip addSubview:iv];
        x += thumb + gap;
    }
    strip.contentSize = CGSizeMake(x + pad - gap, kStripHeight);
    [header addSubview:strip];

    UIImage *shadow = VKStretch(@"wall_photostream_shadow", 7, 0);
    if (shadow) {
        UIImageView *ov = [[UIImageView alloc] initWithImage:shadow];
        ov.frame = CGRectMake(0.0, y, W, kStripHeight);
        ov.userInteractionEnabled = NO;
        [header addSubview:ov];
    }
}

// Светлая панель с вкладками записей — низ шапки.
- (void)addPanelTo:(UIView *)header y:(CGFloat)y {
    CGFloat W = header.bounds.size.width;
    UIImage *shadow = VKStretch(@"wall_posts_panel_shadow", 7, 0);
    if (shadow) {
        UIImageView *sv = [[UIImageView alloc] initWithImage:shadow];
        sv.frame = CGRectMake(0.0, y, W, kPanelShadow);
        [header addSubview:sv];
    }
    UIImage *panelImg = VKStretch(@"wall_posts_panel", 7, 0);
    UIView *panel = panelImg ? [[UIImageView alloc] initWithImage:panelImg] : [[UIView alloc] init];
    panel.frame = CGRectMake(0.0, y + kPanelShadow, W, kPanelHeight);
    if (!panelImg) panel.backgroundColor = [VKTheme contentBackgroundColor];
    panel.userInteractionEnabled = YES;
    [header addSubview:panel];

    NSString *ownTitle;
    if (_isGroup) {
        ownTitle = @"Записи сообщества";
    } else if (_isSelf) {
        ownTitle = @"Мои записи";
    } else {
        NSString *first = VKProfileStr([self.user objectForKey:@"first_name"]);
        ownTitle = [NSString stringWithFormat:@"Записи %@", VKGenitiveName(first) ?: @"автора"];
    }
    self.tabAll = [self pillWithTitle:@"Все записи" tag:0];
    self.tabOwn = [self pillWithTitle:ownTitle tag:1];

    CGFloat x = 6.0, pillH = 24.0, pillY = (kPanelHeight - pillH) / 2.0;
    NSArray *pills = [NSArray arrayWithObjects:self.tabAll, self.tabOwn, nil];
    for (UIButton *pill in pills) {
        CGSize size = [pill.titleLabel.text sizeWithFont:pill.titleLabel.font];
        CGFloat w = MIN(size.width + 22.0, (W - 60.0) / 2.0);
        pill.frame = CGRectMake(x, pillY, w, pillH);
        [panel addSubview:pill];
        x += w + 4.0;
    }
    [self syncTabs];

    UIImage *compose = [UIImage imageNamed:@"wall_addpost_icon"];
    if (compose && (!_isGroup || _canManageGroup)) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(W - compose.size.width - 2.0, (kPanelHeight - compose.size.height) / 2.0,
                             compose.size.width, compose.size.height);
        [b setImage:compose forState:UIControlStateNormal];
        UIImage *hl = [UIImage imageNamed:@"wall_addpost_icon_hl"];
        if (hl) [b setImage:hl forState:UIControlStateHighlighted];
        [b addTarget:self action:@selector(addPostTapped) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:b];
    }
}

- (UIButton *)pillWithTitle:(NSString *)title tag:(NSInteger)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [b setTitleColor:[UIColor colorWithWhite:0.42 alpha:1.0] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateSelected];
    [b setBackgroundImage:VKStretch(@"wall_tab_hl", 12, 12) forState:UIControlStateSelected];
    b.tag = tag;
    [b addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)syncTabs {
    self.tabAll.selected = (_tab == 0);
    self.tabOwn.selected = (_tab == 1);
}

#pragma mark - Действия

- (void)modeChanged {
    _mode = self.switcher.selectedSegmentIndex;
    self.tableView.separatorStyle = (_mode == 1)
        ? UITableViewCellSeparatorStyleSingleLine : UITableViewCellSeparatorStyleNone;
    [self rebuildHeader];
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointZero animated:NO];
}

- (void)tabTapped:(UIButton *)sender {
    if (_tab == sender.tag) return;
    _tab = sender.tag;
    [self syncTabs];
    self.posts = nil;
    [self.tableView reloadData];
    [self loadWall];
}

- (void)tileTapped:(UIButton *)sender {
    NSArray *names;
    if (_isGroup) {
        names = [NSArray arrayWithObjects:@"Подписчики", @"Фотографии", @"Видеозаписи",
                 @"Аудиозаписи", @"Обсуждения", @"Документы", nil];
    } else if (_isSelf) {
        names = [NSArray arrayWithObjects:@"Друзья", @"Подписчики", @"Группы",
                 @"Фотографии", @"Видеозаписи", @"Аудиозаписи", nil];
    } else {
        names = [NSArray arrayWithObjects:@"Друзья", @"Общие друзья", @"Подписчики",
                 @"Фотографии", @"Видеозаписи", @"Аудиозаписи", nil];
    }
    NSInteger i = sender.tag;
    if (i < 0 || i >= (NSInteger)names.count) return;
    NSString *sec = [names objectAtIndex:i];
    if ([sec isEqualToString:@"Видеозаписи"]) {
        VKVideosViewController *videosVC = [[VKVideosViewController alloc] initWithOwnerId:_ownerId title:@"Видеозаписи"];
        [self.navigationController pushViewController:videosVC animated:YES];
        return;
    }
    if ([sec isEqualToString:@"Аудиозаписи"]) {
        VKAudiosViewController *audiosVC = [[VKAudiosViewController alloc] initWithOwnerId:_ownerId title:@"Аудиозаписи"];
        [self.navigationController pushViewController:audiosVC animated:YES];
        return;
    }
    if ([sec isEqualToString:@"Фотографии"] || [sec isEqualToString:@"Группы"]) {
        OVKCollectionViewController *list = [[OVKCollectionViewController alloc] initWithSection:([sec isEqualToString:@"Группы"] ? @"groups" : @"photos") ownerId:_ownerId];
        [self.navigationController pushViewController:list animated:YES]; return;
    }
    if ([sec isEqualToString:@"Друзья"]) {
        VKFriendsViewController *friends = [[VKFriendsViewController alloc] init]; friends.ownerId = _ownerId;
        [self.navigationController pushViewController:friends animated:YES]; return;
    }
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[self profileLink]]];
}

- (void)notImplemented:(NSString *)section {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:section
                        message:@"Раздел ещё не реализован."
                        delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
}

- (void)addPostTapped { [self composeWithPhoto:NO]; }
- (void)cameraTapped  { [self composeWithPhoto:YES]; }

// Своя стена — пишем от себя, чужая — запись на стену владельца.
- (void)composeWithPhoto:(BOOL)photoMode {
    VKWallPostViewController *compose = [[VKWallPostViewController alloc]
        initWithOwnerId:_ownerId photoMode:photoMode];
    [self.navigationController pushViewController:compose animated:YES];
}

- (void)wallDidPost:(NSNotification *)note {
    [self loadWall];
}

// Ссылка на страницу: домен, если он есть, иначе idN / clubN.
- (NSString *)profileLink {
    NSString *host = [[VKBackend shared] webHost];
    NSString *domain = VKProfileStr([self.user objectForKey:@"screen_name"]);
    if (domain.length) return [NSString stringWithFormat:@"https://%@/%@", host, domain];
    if (_isGroup) return [NSString stringWithFormat:@"https://%@/club%lld", host, -_ownerId];
    return [NSString stringWithFormat:@"https://%@/id%lld", host, _ownerId];
}

- (NSString *)profileDisplayName {
    if (_isGroup) return VKProfileStr([self.user objectForKey:@"name"]) ?: @"Сообщество";
    NSString *first = VKProfileStr([self.user objectForKey:@"first_name"]) ?: @"";
    NSString *last = VKProfileStr([self.user objectForKey:@"last_name"]) ?: @"";
    return [[NSString stringWithFormat:@"%@ %@", first, last]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

// Системный шаринг iOS 6: почта, SMS, копирование ссылки, Twitter/Facebook.
- (void)shareTapped {
    NSString *link = [self profileLink];
    NSString *name = [self profileDisplayName];
    NSMutableArray *items = [NSMutableArray array];
    if (name.length) [items addObject:[NSString stringWithFormat:@"%@ — %@", name, link]];
    NSURL *url = [NSURL URLWithString:link];
    if (url) [items addObject:url];
    if (items.count == 0) return;

    Class activity = NSClassFromString(@"UIActivityViewController");
    if (!activity) {   // очень старая прошивка — хотя бы копируем ссылку
        [[UIPasteboard generalPasteboard] setString:link];
        [self alertTitle:@"Ссылка скопирована" message:link];
        return;
    }
    UIActivityViewController *sheet = [[UIActivityViewController alloc]
        initWithActivityItems:items applicationActivities:nil];
    sheet.excludedActivityTypes = [NSArray arrayWithObjects:
        UIActivityTypeAssignToContact, UIActivityTypePrint,
        UIActivityTypeSaveToCameraRoll, nil];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)messageTapped {
    NSString *first = VKProfileStr([self.user objectForKey:@"first_name"]) ?: @"";
    NSString *last = VKProfileStr([self.user objectForKey:@"last_name"]) ?: @"";
    NSString *name = [[NSString stringWithFormat:@"%@ %@", first, last]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    VKChatViewController *chat = [[VKChatViewController alloc] initWithPeerId:_ownerId title:name];
    [self.navigationController pushViewController:chat animated:YES];
}

- (void)addFriendTapped {
    // Принять входящую заявку или добавить нового друга
    NSString *uid = [NSString stringWithFormat:@"%lld", _ownerId];
    [[VKAPI shared] callMethod:@"friends.add"
                        params:[NSDictionary dictionaryWithObject:uid forKey:@"user_id"]
                    completion:^(id response, NSError *error) {
        if (error) {
            [self alertTitle:@"Ошибка" message:error.localizedDescription ?: @"Не удалось отправить заявку"];
            return;
        }
        // response == 1 → заявка отправлена, response == 2 → заявка принята (были входящие)
        NSInteger result = [response respondsToSelector:@selector(integerValue)] ? [response integerValue] : 1;
        if (result == 2) {
            _friendStatus = 3; // теперь в друзьях
        } else {
            _friendStatus = 1; // заявка отправлена
        }
        [self updateFriendButton];
    }];
}

- (void)removeFriendTapped {
    // Подтверждение через UIActionSheet перед удалением
    UIActionSheet *sheet = [[UIActionSheet alloc]
        initWithTitle:@"Удалить из друзей?"
             delegate:self
    cancelButtonTitle:@"Отмена"
destructiveButtonTitle:@"Удалить из друзей"
    otherButtonTitles:nil];
    sheet.tag = 77;
    [sheet showInView:self.view];
}

- (void)cancelFriendRequestTapped {
    // Отозвать нашу заявку = тот же friends.delete
    UIActionSheet *sheet = [[UIActionSheet alloc]
        initWithTitle:@"Отозвать заявку в друзья?"
             delegate:self
    cancelButtonTitle:@"Отмена"
destructiveButtonTitle:@"Отозвать заявку"
    otherButtonTitles:nil];
    sheet.tag = 78;
    [sheet showInView:self.view];
}

- (void)doDeleteFriend {
    NSString *uid = [NSString stringWithFormat:@"%lld", _ownerId];
    [[VKAPI shared] callMethod:@"friends.delete"
                        params:[NSDictionary dictionaryWithObject:uid forKey:@"user_id"]
                    completion:^(id response, NSError *error) {
        if (error) {
            [self alertTitle:@"Ошибка" message:error.localizedDescription ?: @"Не удалось выполнить действие"];
            return;
        }
        _friendStatus = 0;
        [self updateFriendButton];
    }];
}

// Обновляет кнопку дружбы без полной перестройки хэдера
- (void)updateFriendButton {
    if (!self.friendButton) return;
    NSString *newTitle;
    SEL newAction;
    NSString *normalBg, *hlBg;
    switch (_friendStatus) {
        case 3:
            newTitle  = @"В друзьях ✓";
            newAction = @selector(removeFriendTapped);
            normalBg  = @"wall_gray_btn";
            hlBg      = @"wall_gray_btn_hl";
            break;
        case 1:
            newTitle  = @"Заявка отправлена";
            newAction = @selector(cancelFriendRequestTapped);
            normalBg  = @"wall_gray_btn";
            hlBg      = @"wall_gray_btn_hl";
            break;
        case 2:
            newTitle  = @"Принять заявку";
            newAction = @selector(addFriendTapped);
            normalBg  = @"wall_blue_btn";
            hlBg      = @"wall_blue_btn_hl";
            break;
        default:
            newTitle  = @"Добавить в друзья";
            newAction = @selector(addFriendTapped);
            normalBg  = @"wall_blue_btn";
            hlBg      = @"wall_blue_btn_hl";
            break;
    }
    [self.friendButton setTitle:newTitle forState:UIControlStateNormal];
    [self.friendButton setBackgroundImage:VKStretch(normalBg, 7, 0) forState:UIControlStateNormal];
    [self.friendButton setBackgroundImage:VKStretch(hlBg, 7, 0) forState:UIControlStateHighlighted];
    [self.friendButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self.friendButton addTarget:self action:newAction forControlEvents:UIControlEventTouchUpInside];
}

// Открыть страницу автора: тот же контроллер, только с другим owner id.
// Повторно на себя же не уходим — иначе стек забивается копиями страницы.
- (void)openOwner:(long long)ownerId name:(NSString *)name {
    if (ownerId == 0 || ownerId == _ownerId) return;
    VKProfileViewController *page = [[VKProfileViewController alloc]
        initWithUserId:ownerId name:name];
    [self.navigationController pushViewController:page animated:YES];
}

- (void)openPhoto:(UITapGestureRecognizer *)g {
    UIImageView *iv = (UIImageView *)g.view;
    NSString *bigURL = objc_getAssociatedObject(iv, "bigURL");
    VKPhotoViewController *viewer = [[VKPhotoViewController alloc] initWithImage:iv.image url:bigURL];
    viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:viewer animated:YES completion:nil];
}

#pragma mark - Таблица

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (_mode == 1) ? (NSInteger)self.infoTitles.count : (NSInteger)self.posts.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (_mode == 1) return self.infoTitles.count ? @"Основная информация" : nil;
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_mode == 1) return 52.0;
    VKPost *p = [self.posts objectAtIndex:indexPath.row];
    return [VKPostCell heightForPost:p width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_mode == 1) {
        static NSString *ident = @"VKProfileInfoCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:ident];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.backgroundColor = [UIColor whiteColor];
            cell.textLabel.font = [UIFont systemFontOfSize:15.0];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
            cell.detailTextLabel.textColor = [VKTheme secondaryTextColor];
        }
        cell.textLabel.text = [self.infoValues objectAtIndex:indexPath.row];
        cell.detailTextLabel.text = [self.infoTitles objectAtIndex:indexPath.row];
        NSString *icon = [self.infoIcons objectAtIndex:indexPath.row];
        cell.imageView.image = icon.length ? [UIImage imageNamed:icon] : nil;
        return cell;
    }

    static NSString *ident = @"VKPostCell";
    VKPostCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[VKPostCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    }
    cell.post = [self.posts objectAtIndex:indexPath.row];
    __weak VKProfileViewController *weakSelf = self;
    cell.onPhotoTap = ^(VKPost *post, UIImage *image) {
        VKPhotoViewController *viewer = [[VKPhotoViewController alloc] initWithImage:image url:post.photoURL];
        viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [weakSelf presentViewController:viewer animated:YES completion:nil];
    };
    // Тап по аватару/имени — страница автора записи (у паблика id отрицательный).
    cell.onAuthorTap = ^(VKPost *post) {
        [weakSelf openOwner:post.authorId name:post.authorName];
    };
    cell.onOriginalAuthorTap = ^(VKPost *post) {
        if (!post.originalAuthorId) return;
        [weakSelf.navigationController pushViewController:[[VKProfileViewController alloc] initWithUserId:post.originalAuthorId name:post.originalName] animated:YES];
    };
    __weak VKPostCell *weakCell = cell;
    cell.onLikeTap = ^(VKPost *post) {
        [VKLikes togglePost:post changed:^{
            if (weakCell.post == post) [weakCell refreshCounters];
        }];
    };
    cell.onCommentTap = ^(VKPost *post) {
        VKCommentsViewController *comments = [[VKCommentsViewController alloc]
            initWithOwnerId:post.ownerId postId:post.postId];
        [weakSelf.navigationController pushViewController:comments animated:YES];
    };
    cell.onAudioTap = ^(VKPost *post) {
        VKAudio *audio = post.audioAttachment;
        if (!audio) return;
        [[VKAudioPlayer shared] playAudio:audio inPlaylist:@[audio]];
        [[VKAudioPlayerViewController sharedController] presentFromViewController:weakSelf];
    };
    cell.onVideoTap = ^(VKPost *post) {
        if (!post.videoAttachment) return;
        [VKVideoPlayback playVideo:post.videoAttachment from:weakSelf];
    };
    return cell;
}

- (void)postLongPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || _mode != 0) return;
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:[g locationInView:self.tableView]];
    if (!path || path.row >= (NSInteger)self.posts.count) return;
    VKPost *post = [self.posts objectAtIndex:path.row];
    BOOL own = post.authorId == [VKSession shared].userId || (_isGroup && _canManageGroup && post.ownerId == _ownerId);
    if (!own) return;
    self.actionPost = post;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Действия с записью" delegate:self cancelButtonTitle:nil destructiveButtonTitle:@"Удалить" otherButtonTitles:@"Архивировать", post.pinned ? @"Открепить" : @"Закрепить", @"Поделиться", nil];
    sheet.tag = 190; [sheet addButtonWithTitle:@"Отмена"]; sheet.cancelButtonIndex = sheet.numberOfButtons - 1; [sheet showInView:self.view];
}

- (NSString *)archiveKeyForPostId:(long long)postId {
    return [NSString stringWithFormat:@"%@|%lld|%lld", [VKBackend shared].ovkHost ?: @"", _ownerId, postId];
}

- (BOOL)isLocallyArchivedPostId:(long long)postId {
    NSArray *items = [[NSUserDefaults standardUserDefaults] objectForKey:@"VKArchivedWallPosts"];
    return [items containsObject:[self archiveKeyForPostId:postId]];
}

- (void)archiveActionPost {
    if (!self.actionPost) return;
    NSMutableArray *items = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"VKArchivedWallPosts"] ?: @[]];
    NSString *key = [self archiveKeyForPostId:self.actionPost.postId];
    if (![items containsObject:key]) [items addObject:key];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:@"VKArchivedWallPosts"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self removeActionPostLocally];
}

- (void)removeActionPostLocally {
    if (!self.actionPost) return;
    NSMutableArray *posts = [self.posts mutableCopy]; [posts removeObject:self.actionPost]; self.posts = posts; self.actionPost = nil; [self.tableView reloadData];
}

- (void)performPostMethod:(NSString *)method {
    VKPost *post = self.actionPost; if (!post) return;
    [[VKAPI shared] callMethod:method params:@{@"owner_id": @(post.ownerId), @"post_id": @(post.postId)} completion:^(id response, NSError *error) {
        if (error) { [self alertTitle:@"Запись" message:error.localizedDescription]; return; }
        if ([method isEqualToString:@"wall.delete"]) [self removeActionPostLocally];
        else { post.pinned = [method isEqualToString:@"wall.pin"]; self.actionPost = nil; [self loadWall]; }
    }];
}

- (void)shareActionPost {
    VKPost *post = self.actionPost; if (!post) return;
    NSString *link = [NSString stringWithFormat:@"https://%@/wall%lld_%lld", [VKBackend shared].ovkHost, post.ownerId, post.postId];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[link] applicationActivities:nil];
    [self presentViewController:share animated:YES completion:nil]; self.actionPost = nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
