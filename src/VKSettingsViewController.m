#import "VKSettingsViewController.h"
#import "VKSettings.h"
#import "VKTheme.h"
#import "VKSession.h"
#import "VKImageLoader.h"
#import "VKInstancesViewController.h"
#import "VKInstanceManager.h"
#import "VKBackend.h"

NSString *const VKRequestLogoutNotification = @"VKRequestLogoutNotification";
NSString *const VKUserDidUpdateNotification = @"VKUserDidUpdateNotification";

enum { VKSettingsGeneral, VKSettingsMedia, VKSettingsAccount, VKSettingsStorage, VKSettingsActions, VKSettingsSectionCount };
enum { VKSheetFont = 40, VKSheetCount, VKSheetDevice, VKSheetQuality };
enum { VKAlertCache = 70, VKAlertReset, VKAlertLogout };

@interface VKSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *swipeSwitch;
@property (nonatomic, strong) UISwitch *imagesSwitch;
@property (nonatomic, strong) UISwitch *photosSwitch;
@property (nonatomic, strong) UISwitch *playerSwitch;
@property (nonatomic, strong) UIImageView *profileAvatar;
@property (nonatomic, strong) UILabel *profileName;
@property (nonatomic, strong) UILabel *profileServer;
@end

@implementation VKSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Настройки";
    self.view.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 44.0;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorColor = [VKTheme separatorColor];
    [self.view addSubview:self.tableView];
    self.swipeSwitch = [self switchWithAction:@selector(swipeChanged:)];
    self.imagesSwitch = [self switchWithAction:@selector(imagesChanged:)];
    self.photosSwitch = [self switchWithAction:@selector(photosChanged:)];
    self.playerSwitch = [self switchWithAction:@selector(playerChanged:)];
    [self buildProfileHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self syncControls];
    [self updateProfileHeader];
    [self.tableView reloadData];
}

- (UISwitch *)switchWithAction:(SEL)action {
    UISwitch *s = [[UISwitch alloc] initWithFrame:CGRectZero];
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)buildProfileHeader {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 82)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor clearColor];
    self.profileAvatar = [[UIImageView alloc] initWithFrame:CGRectMake(18, 14, 54, 54)];
    self.profileAvatar.contentMode = UIViewContentModeScaleAspectFill;
    self.profileAvatar.clipsToBounds = YES;
    [header addSubview:self.profileAvatar];
    self.profileName = [[UILabel alloc] initWithFrame:CGRectMake(84, 18, header.bounds.size.width - 102, 24)];
    self.profileName.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.profileName.backgroundColor = [UIColor clearColor];
    self.profileName.font = [UIFont boldSystemFontOfSize:17];
    self.profileName.textColor = [VKTheme primaryTextColor];
    [header addSubview:self.profileName];
    self.profileServer = [[UILabel alloc] initWithFrame:CGRectMake(84, 42, header.bounds.size.width - 102, 20)];
    self.profileServer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.profileServer.backgroundColor = [UIColor clearColor];
    self.profileServer.font = [UIFont systemFontOfSize:12];
    self.profileServer.textColor = [VKTheme secondaryTextColor];
    [header addSubview:self.profileServer];
    self.tableView.tableHeaderView = header;
}

- (void)updateProfileHeader {
    VKSession *session = [VKSession shared];
    NSString *name = session.userName.length ? session.userName : @"OpenVK";
    self.profileName.text = name;
    self.profileServer.text = [NSString stringWithFormat:@"%@ · id%lld", [[VKInstanceManager shared] nameForHost:[VKBackend shared].ovkHost], session.userId];
    NSString *letter = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    self.profileAvatar.image = [VKTheme avatarWithInitials:letter size:54 background:[VKTheme navBarColor]];
    if (session.userPhoto.length) {
        __weak VKSettingsViewController *weakSelf = self;
        [[VKImageLoader shared] loadURL:session.userPhoto completion:^(UIImage *image) { if (image) weakSelf.profileAvatar.image = image; }];
    }
}

- (void)syncControls {
    VKSettings *s = [VKSettings shared];
    self.swipeSwitch.on = s.swipeToOpenMenu;
    self.imagesSwitch.on = s.loadImages;
    self.photosSwitch.on = s.showFeedPhotos;
    self.playerSwitch.on = s.showSidebarPlayer;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return VKSettingsSectionCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == VKSettingsGeneral) return 3;
    if (section == VKSettingsMedia) return 4;
    if (section == VKSettingsAccount) return 2;
    return 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [@[@"Основное", @"Медиа", @"Аккаунт", @"Хранилище", @""] objectAtIndex:section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == VKSettingsAccount) return @"До пяти инстансов. Между ними можно переключаться из бокового меню.";
    if (section == VKSettingsActions) return [NSString stringWithFormat:@"OpenVK Latte %@", [self versionString]];
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:@"SettingsRow"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"SettingsRow"];
    c.accessoryView = nil; c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleBlue;
    c.textLabel.textAlignment = NSTextAlignmentLeft;
    c.textLabel.font = [UIFont systemFontOfSize:16];
    c.textLabel.textColor = [VKTheme primaryTextColor];
    c.detailTextLabel.text = nil; c.detailTextLabel.textColor = [VKTheme secondaryTextColor];
    VKSettings *s = [VKSettings shared];
    if (p.section == VKSettingsGeneral) {
        if (p.row == 0) { c.textLabel.text = @"Открывать меню свайпом"; c.accessoryView = self.swipeSwitch; c.selectionStyle = UITableViewCellSelectionStyleNone; }
        if (p.row == 1) { c.textLabel.text = @"Размер текста"; c.detailTextLabel.text = s.feedFontSize <= 13 ? @"Мелкий" : (s.feedFontSize >= 16 ? @"Крупный" : @"Обычный"); }
        if (p.row == 2) { c.textLabel.text = @"Записей в ленте"; c.detailTextLabel.text = [NSString stringWithFormat:@"%d", (int)s.feedCount]; }
    } else if (p.section == VKSettingsMedia) {
        if (p.row == 0) { c.textLabel.text = @"Загружать изображения"; c.accessoryView = self.imagesSwitch; c.selectionStyle = UITableViewCellSelectionStyleNone; }
        if (p.row == 1) { c.textLabel.text = @"Фото в записях"; c.accessoryView = self.photosSwitch; c.selectionStyle = UITableViewCellSelectionStyleNone; }
        if (p.row == 2) { c.textLabel.text = @"Плеер в боковом меню"; c.accessoryView = self.playerSwitch; c.selectionStyle = UITableViewCellSelectionStyleNone; }
        if (p.row == 3) { c.textLabel.text = @"Качество видео"; c.detailTextLabel.text = [s.preferredVideoQuality isEqualToString:@"auto"] ? @"Авто" : s.preferredVideoQuality; }
    } else if (p.section == VKSettingsAccount) {
        if (p.row == 0) { c.textLabel.text = @"Инстансы"; c.detailTextLabel.text = [[VKInstanceManager shared] nameForHost:[VKBackend shared].ovkHost]; c.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
        if (p.row == 1) { c.textLabel.text = @"Устройство в постах"; c.detailTextLabel.text = s.postAsAndroid ? @"Android" : @"Apple"; }
    } else if (p.section == VKSettingsStorage) {
        if (p.row == 0) { c.textLabel.text = @"Кэш изображений"; c.detailTextLabel.text = [self cacheSummary]; c.selectionStyle = UITableViewCellSelectionStyleNone; }
        if (p.row == 1) { c.textLabel.text = @"Очистить кэш"; c.textLabel.textColor = [VKTheme linkColor]; }
    } else {
        c.textLabel.textAlignment = NSTextAlignmentCenter;
        if (p.row == 0) { c.textLabel.text = @"Сбросить настройки"; c.textLabel.textColor = [VKTheme linkColor]; }
        else { c.textLabel.text = @"Выйти"; c.textLabel.textColor = [UIColor colorWithRed:.72 green:.12 blue:.12 alpha:1]; }
    }
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)p {
    [tableView deselectRowAtIndexPath:p animated:YES];
    if (p.section == VKSettingsGeneral && p.row == 1) [self showSheet:@"Размер текста" tag:VKSheetFont buttons:@[@"Мелкий", @"Обычный", @"Крупный"]];
    else if (p.section == VKSettingsGeneral && p.row == 2) [self showSheet:@"Записей в ленте" tag:VKSheetCount buttons:@[@"20", @"40", @"80"]];
    else if (p.section == VKSettingsMedia && p.row == 3) [self showSheet:@"Качество видео" tag:VKSheetQuality buttons:@[@"Автоматически", @"240p", @"360p", @"480p", @"720p"]];
    else if (p.section == VKSettingsAccount && p.row == 0) [self.navigationController pushViewController:[[VKInstancesViewController alloc] initWithStyle:UITableViewStyleGrouped] animated:YES];
    else if (p.section == VKSettingsAccount && p.row == 1) [self showSheet:@"Устройство в постах" tag:VKSheetDevice buttons:@[@"Apple", @"Android"]];
    else if (p.section == VKSettingsStorage && p.row == 1) [self confirm:@"Очистить кэш?" message:@"Изображения будут загружены заново." button:@"Очистить" tag:VKAlertCache];
    else if (p.section == VKSettingsActions && p.row == 0) [self confirm:@"Сбросить настройки?" message:@"Все параметры вернутся к исходным." button:@"Сбросить" tag:VKAlertReset];
    else if (p.section == VKSettingsActions && p.row == 1) [self confirm:@"Выйти из аккаунта?" message:nil button:@"Выйти" tag:VKAlertLogout];
}

- (void)showSheet:(NSString *)title tag:(NSInteger)tag buttons:(NSArray *)buttons {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *button in buttons) [sheet addButtonWithTitle:button];
    [sheet addButtonWithTitle:@"Отмена"]; sheet.cancelButtonIndex = sheet.numberOfButtons - 1; sheet.tag = tag; [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i < 0 || i == sheet.cancelButtonIndex) return;
    VKSettings *s = [VKSettings shared];
    if (sheet.tag == VKSheetFont && i < 3) s.feedFontSize = ((CGFloat[]){13,14,16})[i];
    if (sheet.tag == VKSheetCount && i < 3) s.feedCount = ((NSInteger[]){20,40,80})[i];
    if (sheet.tag == VKSheetDevice && i < 2) s.postAsAndroid = (i == 1);
    if (sheet.tag == VKSheetQuality && i < 5) s.preferredVideoQuality = [@[@"auto", @"240p", @"360p", @"480p", @"720p"] objectAtIndex:i];
    [self.tableView reloadData];
}

- (void)confirm:(NSString *)title message:(NSString *)message button:(NSString *)button tag:(NSInteger)tag {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:@"Отмена" otherButtonTitles:button, nil]; a.tag = tag; [a show];
}
- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)i {
    if (i != 1) return;
    if (alert.tag == VKAlertCache) [[VKImageLoader shared] clearCache];
    if (alert.tag == VKAlertReset) { [[VKSettings shared] resetToDefaults]; [self syncControls]; }
    if (alert.tag == VKAlertLogout) [[NSNotificationCenter defaultCenter] postNotificationName:VKRequestLogoutNotification object:nil];
    [self.tableView reloadData];
}

- (void)swipeChanged:(UISwitch *)s { [VKSettings shared].swipeToOpenMenu = s.on; }
- (void)imagesChanged:(UISwitch *)s { [VKSettings shared].loadImages = s.on; }
- (void)photosChanged:(UISwitch *)s { [VKSettings shared].showFeedPhotos = s.on; }
- (void)playerChanged:(UISwitch *)s { [VKSettings shared].showSidebarPlayer = s.on; }

- (NSString *)cacheSummary {
    unsigned long long bytes = [[VKImageLoader shared] cachedImageBytes];
    NSUInteger count = [[VKImageLoader shared] cachedImageCount];
    if (!count) return @"Пусто";
    NSString *size = bytes < 1048576 ? [NSString stringWithFormat:@"%.0f КБ", bytes / 1024.0] : [NSString stringWithFormat:@"%.1f МБ", bytes / 1048576.0];
    return [NSString stringWithFormat:@"%d · %@", (int)count, size];
}
- (NSString *)versionString { return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] ?: @"1.0"; }

@end
