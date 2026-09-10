#import "VKFriendRequestsViewController.h"
#import "VKAPI.h"
#import "VKImageLoader.h"
#import "VKProfileViewController.h"
#import "VKTheme.h"
#import <QuartzCore/QuartzCore.h>

@interface VKFriendRequestCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIButton *acceptButton;
@property (nonatomic, strong) UIButton *declineButton;
@property (nonatomic, copy) void (^accept)(void);
@property (nonatomic, copy) void (^decline)(void);
@end

@implementation VKFriendRequestCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
        _avatar = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill; _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = 0.0; [self.contentView addSubview:_avatar];
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont boldSystemFontOfSize:15.0]; _nameLabel.textColor = [VKTheme linkColor];
        _nameLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_nameLabel];
        _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hintLabel.text = @"хочет добавить вас в друзья"; _hintLabel.font = [UIFont systemFontOfSize:12.0];
        _hintLabel.textColor = [VKTheme secondaryTextColor]; _hintLabel.backgroundColor = [UIColor clearColor]; [self.contentView addSubview:_hintLabel];
        _acceptButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_acceptButton setTitle:@"Принять" forState:UIControlStateNormal];
        [_acceptButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _acceptButton.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
        _acceptButton.backgroundColor = [VKTheme navBarColor]; _acceptButton.layer.cornerRadius = 4.0;
        [_acceptButton addTarget:self action:@selector(acceptTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_acceptButton];
        _declineButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_declineButton setTitle:@"Отклонить" forState:UIControlStateNormal];
        [_declineButton setTitleColor:[VKTheme linkColor] forState:UIControlStateNormal];
        _declineButton.titleLabel.font = [UIFont systemFontOfSize:12.0];
        [_declineButton addTarget:self action:@selector(declineTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_declineButton];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    self.avatar.frame = CGRectMake(10, 10, 50, 50);
    self.nameLabel.frame = CGRectMake(70, 10, w - 80, 20);
    self.hintLabel.frame = CGRectMake(70, 31, w - 80, 16);
    self.acceptButton.frame = CGRectMake(70, 52, 76, 26);
    self.declineButton.frame = CGRectMake(151, 52, 84, 26);
}
- (void)acceptTapped { if (self.accept) self.accept(); }
- (void)declineTapped { if (self.decline) self.decline(); }
@end

@interface VKFriendRequestsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *requests;
@end

@implementation VKFriendRequestsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Заявки в друзья";
    self.requests = [NSMutableArray array];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.rowHeight = 88.0; self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.tableView];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.isViewLoaded) [self reload];
}
- (void)reload {
    [self showLoading:YES]; [self showMessage:nil];
    [[VKAPI shared] callMethod:@"friends.getRequests" params:@{@"extended": @1, @"count": @100, @"fields": @"photo_100"} completion:^(id response, NSError *error) {
        [self showLoading:NO];
        NSArray *items = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"items"] : response;
        [self.requests removeAllObjects];
        if (!error && [items isKindOfClass:[NSArray class]]) [self.requests addObjectsFromArray:items];
        [self.tableView reloadData];
        if (error) [self showMessage:error.localizedDescription ?: @"Не удалось загрузить заявки"];
        else if (!self.requests.count) [self showMessage:@"Новых заявок нет"];
    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.requests.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VKFriendRequestCell *cell = (VKFriendRequestCell *)[tableView dequeueReusableCellWithIdentifier:@"Request"];
    if (!cell) cell = [[VKFriendRequestCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Request"];
    NSDictionary *request = [self.requests objectAtIndex:indexPath.row];
    NSString *name = [[NSString stringWithFormat:@"%@ %@", [request objectForKey:@"first_name"] ?: @"", [request objectForKey:@"last_name"] ?: @""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    cell.nameLabel.text = name.length ? name : @"Пользователь";
    cell.avatar.image = [UIImage imageNamed:@"user_placeholder_50px"];
    NSString *url = [request objectForKey:@"photo_100"] ?: [request objectForKey:@"photo_50"];
    if (url.length) [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) { if (image && cell) cell.avatar.image = image; }];
    __weak typeof(self) weakSelf = self;
    cell.accept = ^{ [weakSelf actOnRequest:request accept:YES]; };
    cell.decline = ^{ [weakSelf actOnRequest:request accept:NO]; };
    return cell;
}
- (void)actOnRequest:(NSDictionary *)request accept:(BOOL)accept {
    long long userId = [[request objectForKey:@"id"] longLongValue];
    if (!userId) return;
    NSString *method = accept ? @"friends.add" : @"friends.delete";
    [[VKAPI shared] callMethod:method params:@{@"user_id": @(userId)} completion:^(id response, NSError *error) {
        if (error) { [[[UIAlertView alloc] initWithTitle:@"Не удалось обновить заявку" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return; }
        // friends.add возвращает 2 именно при принятии входящей заявки.
        // Иначе это была не входящая заявка, и скрывать её как обработанную нельзя.
        if (accept && [response respondsToSelector:@selector(integerValue)] && [response integerValue] != 2) {
            [[[UIAlertView alloc] initWithTitle:@"Заявка не принята"
                                         message:@"OpenVK не подтвердил принятие заявки. Список обновлён."
                                        delegate:nil cancelButtonTitle:@"ОК" otherButtonTitles:nil] show];
        }
        // Не верим старой ячейке: после ответа всегда запрашиваем состояние снова.
        [self reload];
    }];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *request = [self.requests objectAtIndex:indexPath.row];
    NSString *name = [[NSString stringWithFormat:@"%@ %@", [request objectForKey:@"first_name"] ?: @"", [request objectForKey:@"last_name"] ?: @""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Назад" style:UIBarButtonItemStylePlain target:nil action:nil];
    [self.navigationController pushViewController:[[VKProfileViewController alloc] initWithUserId:[[request objectForKey:@"id"] longLongValue] name:name] animated:YES];
}
@end
