#import "VKFriendsViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKImageLoader.h"
#import "VKProfileViewController.h"
#import "VKFriendRequestsViewController.h"
#import <QuartzCore/QuartzCore.h>

// ---------- Кастомная ячейка друга ----------

static const CGFloat kFriendRowH  = 60.0;
static const CGFloat kAvatarSize  = 44.0;
static const CGFloat kAvatarPad   = 10.0;

@interface VKFriendCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel     *nameLabel;
@property (nonatomic, strong) UILabel     *statusLabel;
@property (nonatomic, strong) UIView      *onlineDot;
@end

@implementation VKFriendCell

- (instancetype)initWithReuseIdentifier:(NSString *)ident {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    if (!self) return nil;

    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    self.backgroundColor = [VKTheme contentBackgroundColor];
    self.contentView.backgroundColor = [VKTheme contentBackgroundColor];

    // Аватар — фиксированный размер, скруглённые углы
    _avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(kAvatarPad,
                                                                (kFriendRowH - kAvatarSize) / 2.0,
                                                                kAvatarSize, kAvatarSize)];
    _avatarView.contentMode = UIViewContentModeScaleAspectFill;
    _avatarView.clipsToBounds = YES;
    _avatarView.layer.cornerRadius = 0.0;
    [self.contentView addSubview:_avatarView];

    CGFloat textX = kAvatarPad + kAvatarSize + 10.0;

    // Имя
    _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _nameLabel.font = [UIFont boldSystemFontOfSize:15.0];
    _nameLabel.textColor = [VKTheme primaryTextColor];
    _nameLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:_nameLabel];

    // Статус «онлайн» / «не в сети»
    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.font = [UIFont systemFontOfSize:12.0];
    _statusLabel.backgroundColor = [UIColor clearColor];
    [self.contentView addSubview:_statusLabel];

    // Зелёная точка онлайн
    _onlineDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7.0, 7.0)];
    _onlineDot.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];
    _onlineDot.layer.cornerRadius = 3.5;
    _onlineDot.hidden = YES;
    [self.contentView addSubview:_onlineDot];

    (void)textX; // используется в layoutSubviews
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width - 30.0; // 30 = disclosure width

    // Аватар — вертикально по центру
    CGFloat avY = (kFriendRowH - kAvatarSize) / 2.0;
    self.avatarView.frame = CGRectMake(kAvatarPad, avY, kAvatarSize, kAvatarSize);

    CGFloat textX = kAvatarPad + kAvatarSize + 10.0;
    CGFloat textW = width - textX - kAvatarPad;

    // Имя чуть выше центра
    self.nameLabel.frame  = CGRectMake(textX, kFriendRowH / 2.0 - 19.0, textW, 20.0);
    self.statusLabel.frame = CGRectMake(textX + (self.onlineDot.hidden ? 0 : 11.0),
                                        kFriendRowH / 2.0 + 2.0, textW, 16.0);

    // Точка онлайн слева от статуса
    self.onlineDot.frame = CGRectMake(textX, kFriendRowH / 2.0 + 6.5, 7.0, 7.0);
}

@end

// ---------- Контроллер ----------

@interface VKFriendsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *friends; // массив NSDictionary из friends.get
@end

@implementation VKFriendsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Друзья";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Заявки" style:UIBarButtonItemStylePlain
        target:self action:@selector(openRequests)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.rowHeight = kFriendRowH;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    [self.view addSubview:self.tableView];

    [self reload];
}

- (void)openRequests {
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Назад" style:UIBarButtonItemStylePlain target:nil action:nil];
    [self.navigationController pushViewController:[[VKFriendRequestsViewController alloc] init] animated:YES];
}

- (void)reload {
    if (![[VKSession shared] isAuthorized]) {
        [self showMessage:@"Войдите с реальным access_token, чтобы загрузить друзей."];
        return;
    }
    [self showMessage:nil];
    [self showLoading:YES];

    [[VKAPI shared] callMethod:@"friends.get"
                        params:@{@"user_id": @(self.ownerId ?: [VKSession shared].userId),
                                 @"fields": @"photo_100,online",
                                 @"count": @"1000"}
                    completion:^(id response, NSError *error) {
        [self showLoading:NO];
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            [self showMessage:error.localizedDescription ?: @"Не удалось загрузить друзей"];
            return;
        }
        self.friends = [response objectForKey:@"items"];
        if (self.friends.count == 0) [self showMessage:@"Список друзей пуст"];
        [self.tableView reloadData];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.friends.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kFriendRowH;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKFriendCell";
    VKFriendCell *cell = (VKFriendCell *)[tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[VKFriendCell alloc] initWithReuseIdentifier:ident];
    }

    NSDictionary *f = [self.friends objectAtIndex:indexPath.row];
    cell.backgroundColor = cell.contentView.backgroundColor = [VKTheme contentBackgroundColor];
    cell.nameLabel.textColor = [VKTheme primaryTextColor];
    NSString *firstName = [f objectForKey:@"first_name"] ?: @"";
    NSString *lastName  = [f objectForKey:@"last_name"] ?: @"";
    NSString *name = [[NSString stringWithFormat:@"%@ %@", firstName, lastName]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL online = [[f objectForKey:@"online"] integerValue] == 1;

    cell.nameLabel.text = name;
    cell.statusLabel.text = online ? @"онлайн" : @"не в сети";
    cell.statusLabel.textColor = online ? [UIColor colorWithRed:0.15 green:0.6 blue:0.25 alpha:1.0]
                                        : [VKTheme secondaryTextColor];
    cell.onlineDot.hidden = !online;

    // Placeholder с инициалами
    NSString *initials = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    cell.avatarView.image = [VKTheme avatarWithInitials:initials size:kAvatarSize background:[VKTheme navBarColor]];

    NSString *url = [f objectForKey:@"photo_100"];
    if (url.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) {
            cell.avatarView.image = cached;
        } else {
            NSIndexPath *ip = indexPath;
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                VKFriendCell *c = (VKFriendCell *)[tableView cellForRowAtIndexPath:ip];
                if (image && c) { c.avatarView.image = image; }
            }];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *f = [self.friends objectAtIndex:indexPath.row];
    if (![f isKindOfClass:[NSDictionary class]]) return;
    id rawId = [f objectForKey:@"id"] ?: [f objectForKey:@"uid"];
    long long uid = [rawId respondsToSelector:@selector(longLongValue)] ? [rawId longLongValue] : 0;
    if (uid == 0) return;
    NSString *name = [[NSString stringWithFormat:@"%@ %@",
                       [f objectForKey:@"first_name"] ?: @"",
                       [f objectForKey:@"last_name"] ?: @""]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    VKProfileViewController *profile = [[VKProfileViewController alloc] initWithUserId:uid name:name];
    [self.navigationController pushViewController:profile animated:YES];
}

@end
