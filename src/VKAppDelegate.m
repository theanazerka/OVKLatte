#import "VKAppDelegate.h"
#import "VKTheme.h"
#import "VKMenuViewController.h"
#import "VKNewsViewController.h"
#import "VKMessagesViewController.h"
#import "VKFriendsViewController.h"
#import "VKProfileViewController.h"
#import "VKWallPostViewController.h"
#import "VKPlaceholderViewController.h"
#import "VKSettingsViewController.h"
#import "VKSettings.h"
#import "VKVideosViewController.h"
#import "VKAudiosViewController.h"
#import "VKOVKLoginViewController.h"
#import "VKSession.h"
#import "VKBackend.h"
#import "VKAPI.h"
#import "OVKCollectionViewController.h"
#import "OVKSearchViewController.h"
#import "VKNotesViewController.h"
#import "VKWebViewController.h"
#import <APLSlideMenuViewController.h>

@interface VKAppDelegate () <VKMenuDelegate, APLSlideMenuViewControllerDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) APLSlideMenuViewController *slideMenu;
@property (nonatomic, strong) VKMenuViewController *menu;
@property (nonatomic, strong) NSMutableDictionary *sectionControllers;
@end

@implementation VKAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Единый стиль навбара для всего приложения.
    [VKTheme styleNavigationBar:[UINavigationBar appearance]];
    [application setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:NO];

    // Боковое меню.
    self.menu = [[VKMenuViewController alloc] init];
    self.menu.delegate = self;
    self.sectionControllers = [NSMutableDictionary dictionary];

    // Контейнер APLSlideMenu.
    self.slideMenu = [[APLSlideMenuViewController alloc] init];
    self.slideMenu.leftMenuViewController = self.menu;
    self.slideMenu.menuWidth = VKMenuWidth;
    self.slideMenu.tapOnContentViewToHideMenu = YES;
    self.slideMenu.bouncing = NO;
    self.slideMenu.slideDelegate = self;
    [self applySettings]; // поддержка жестов зависит от настроек

    // Стартовый раздел — Новости.
    self.menu.selectedItem = VKMenuItemNews;
    [self.slideMenu setContentViewController:[self navForItem:VKMenuItemNews] animated:NO];

    self.window.rootViewController = self.slideMenu;
    [self.window makeKeyAndVisible];

    // Подписываемся на успешный вход, чтобы обновить UI.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didLogin:)
                                                 name:@"VKDidLoginNotification" object:nil];
    // Сигналы от экрана «Настройки».
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(applySettings)
               name:VKSettingsDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(userDidUpdate:)
               name:VKUserDidUpdateNotification object:nil];
    [nc addObserver:self selector:@selector(performLogout)
               name:VKRequestLogoutNotification object:nil];
    // Смена бэкенда (ВК <-> OpenVK) и просьба показать вход.
    [nc addObserver:self selector:@selector(backendDidChange:)
               name:VKBackendDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(presentLogin)
               name:VKRequestLoginNotification object:nil];

    // Личность уже подставлена выше; если её всё же нет — показываем вход.
    if (![[VKSession shared] hasIdentity]) {
        [self presentLogin];
    } else {
        [self refreshCurrentUser];
    }
    return YES;
}

// Применяем пользовательские настройки к контейнеру меню.
- (void)applySettings {
    self.slideMenu.gestureSupport = [VKSettings shared].swipeToOpenMenu
        ? APLSlideMenuGestureSupportDrag
        : APLSlideMenuGestureSupportNone;
    [VKTheme styleNavigationBar:[UINavigationBar appearance]];
    if ([self.slideMenu.contentViewController isKindOfClass:[UINavigationController class]]) {
        [VKTheme styleNavigationBar:((UINavigationController *)self.slideMenu.contentViewController).navigationBar];
    }
}

// Настройки обновили профиль — перерисовываем шапку сайдбара.
- (void)userDidUpdate:(NSNotification *)note {
    [self.menu refreshHeader];
}

// Подтягиваем актуальные имя/аватар текущего пользователя и обновляем сайдбар.
- (void)refreshCurrentUser {
    [[VKAPI shared] callMethod:@"users.get"
                        params:@{@"fields": @"photo_100"}
                    completion:^(id response, NSError *error) {
        if (![response isKindOfClass:[NSArray class]] || [response count] == 0) return;
        NSDictionary *u = [response objectAtIndex:0];
        VKSession *s = [VKSession shared];
        s.userId = [[u objectForKey:@"id"] longLongValue];
        s.userName = [NSString stringWithFormat:@"%@ %@",
                      [u objectForKey:@"first_name"] ?: @"",
                      [u objectForKey:@"last_name"] ?: @""];
        if ([u objectForKey:@"photo_100"]) s.userPhoto = [u objectForKey:@"photo_100"];
        [s save];
        [self.menu refreshHeader];
    }];
}

- (void)presentLogin {
    UIViewController *login = [[VKOVKLoginViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:login];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    // Отложенный показ, чтобы окно успело стать key.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.slideMenu.presentedViewController) return;   // экран входа уже открыт
        [self.slideMenu presentViewController:nav animated:NO completion:nil];
    });
}

// Создаёт контроллер раздела, обёрнутый в UINavigationController.
- (UINavigationController *)navForItem:(VKMenuItem)item {
    NSNumber *key = @(item);
    UINavigationController *cached = [self.sectionControllers objectForKey:key];
    if (cached) return cached;
    UIViewController *vc = nil;
    switch (item) {
        case VKMenuItemNews:      vc = [[VKNewsViewController alloc] init]; break;
        case VKMenuItemMessages:  vc = [[VKMessagesViewController alloc] init]; break;
        case VKMenuItemFriends:   vc = [[VKFriendsViewController alloc] init]; break;
        case VKMenuItemSettings:  vc = [[VKSettingsViewController alloc] init]; break;
        case VKMenuItemAnswers:
            vc = [[OVKCollectionViewController alloc] initWithSection:@"notifications" ownerId:0]; break;
        case VKMenuItemGroups:
            vc = [[OVKCollectionViewController alloc] initWithSection:@"groups" ownerId:0]; break;
        case VKMenuItemPhotos:
            vc = [[OVKCollectionViewController alloc] initWithSection:@"photos" ownerId:0]; break;
        case VKMenuItemVideos:
            vc = [[VKVideosViewController alloc] init]; break;
        case VKMenuItemAudio:
            vc = [[VKAudiosViewController alloc] init]; break;
        case VKMenuItemGames:
            vc = [[VKWebViewController alloc] initWithTitle:@"Игры" URL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/apps", [[VKBackend shared] webHost]]]]; break;
        case VKMenuItemNotes:
            vc = [[VKNotesViewController alloc] init]; break;
        case VKMenuItemBookmarks:
            vc = [[VKPlaceholderViewController alloc] initWithTitle:@"Закладки" glyph:@"\U00002B50"]; break;
        default: vc = [[VKNewsViewController alloc] init]; break;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self.sectionControllers setObject:nav forKey:key];
    return nav;
}

#pragma mark - VKMenuDelegate

- (void)menu:(VKMenuViewController *)menu didSelectItem:(VKMenuItem)item {
    [self.slideMenu setContentViewController:[self navForItem:item] animated:NO];
    [self.slideMenu hideMenu:YES];
}

- (void)menu:(VKMenuViewController *)menu didSubmitSearch:(NSString *)query {
    menu.selectedItem = VKMenuItemNone;
    [menu clearSearchText];
    OVKSearchViewController *search = [[OVKSearchViewController alloc] initWithQuery:query];
    [self.slideMenu setContentViewController:[[UINavigationController alloc] initWithRootViewController:search] animated:NO];
    [self.slideMenu hideMenu:YES];
}

- (void)menu:(VKMenuViewController *)menu didSelectInstanceHost:(NSString *)host {
    [VKBackend shared].ovkHost = host;
    [[NSNotificationCenter defaultCenter] postNotificationName:VKBackendDidChangeNotification object:nil];
    [self.slideMenu hideMenu:YES];
}

// Шапка сайдбара — «Моя страница».
- (void)menuDidSelectProfile:(VKMenuViewController *)menu {
    VKProfileViewController *profile = [[VKProfileViewController alloc] init];
    [self.slideMenu setContentViewController:
        [[UINavigationController alloc] initWithRootViewController:profile] animated:NO];
    [self.slideMenu hideMenu:YES];
}

// Кнопка-камера в шапке сайдбара — загрузка фото с подписью на свою стену.
- (void)menuDidRequestCamera:(VKMenuViewController *)menu {
    [self.slideMenu hideMenu:YES];
    if (![[VKSession shared] isAuthorized]) { [self presentLogin]; return; }
    VKWallPostViewController *compose = [[VKWallPostViewController alloc]
        initWithOwnerId:[VKSession shared].userId photoMode:YES];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:compose];
    [self.slideMenu presentViewController:nav animated:YES completion:nil];
}

// Бэкенд сменился: сбрасываем контент и подписи разделов.
- (void)backendDidChange:(NSNotification *)note {
    // Шапка навбара своя у каждого бэкенда — переприменяем до пересборки контроллеров.
    [VKTheme styleNavigationBar:[UINavigationBar appearance]];
    [self.sectionControllers removeAllObjects];
    self.menu.selectedItem = VKMenuItemNews;
    [self.slideMenu setContentViewController:[self navForItem:VKMenuItemNews] animated:NO];
    [self.menu reloadSections];
    [self.menu refreshHeader];
    if ([[VKSession shared] isAuthorized]) [self refreshCurrentUser]; else [self presentLogin];
}

#pragma mark - APLSlideMenuViewControllerDelegate

// Каждое открытие сайдбара — повод обновить счётчики в бейджах.
- (void)willShowMenu:(APLSlideMenuViewController *)aViewController {
    [self.menu refreshCounters];
}

// Общий выход: из настроек (подтверждение спрашивает сам экран).
- (void)performLogout {
    [[VKSession shared] clear];
    [self.sectionControllers removeAllObjects];
    [self.slideMenu hideMenu:NO];
    // Сбрасываем контент на стартовый раздел и показываем экран входа.
    self.menu.selectedItem = VKMenuItemNews;
    [self.slideMenu setContentViewController:[self navForItem:VKMenuItemNews] animated:NO];
    [self.menu refreshHeader];
    [self presentLogin];
}

// После входа обновляем шапку и перезагружаем стартовый раздел.
- (void)didLogin:(NSNotification *)note {
    [self.sectionControllers removeAllObjects];
    [self refreshCurrentUser];
    self.menu.selectedItem = VKMenuItemNews;
    [self.slideMenu setContentViewController:[self navForItem:VKMenuItemNews] animated:NO];
    [self.menu refreshHeader];
    [self.menu refreshCounters];
}

@end
