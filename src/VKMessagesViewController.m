#import "VKMessagesViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKImageLoader.h"
#import "VKChatViewController.h"
#import "VKPresence.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - Кастомная ячейка диалога (фикс. аватар 50pt)

@interface VKDialogCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UIView *onlineRing;
@property (nonatomic, strong) UIImageView *onlineDot;
- (void)setOnline:(BOOL)online mobile:(BOOL)mobile;
@end

@implementation VKDialogCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:style reuseIdentifier:rid];
    if (self) {
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
        _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(10, 7, 50, 50)];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = 0.0;
        [self.contentView addSubview:_avatar];

        // Зелёная точка ВК на белом кружке — иначе теряется на тёмных аватарах.
        _onlineRing = [[UIView alloc] initWithFrame:CGRectZero];
        _onlineRing.backgroundColor = [UIColor whiteColor];
        _onlineRing.hidden = YES;
        [self.contentView addSubview:_onlineRing];

        _onlineDot = [[UIImageView alloc] initWithFrame:CGRectZero];
        _onlineDot.contentMode = UIViewContentModeCenter;
        _onlineDot.hidden = YES;
        [self.contentView addSubview:_onlineDot];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
        _titleLabel.textColor = [VKTheme primaryTextColor];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.opaque = NO;
        [self.contentView addSubview:_titleLabel];

        _previewLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _previewLabel.font = [UIFont systemFontOfSize:13.0];
        _previewLabel.textColor = [VKTheme secondaryTextColor];
        _previewLabel.backgroundColor = [UIColor clearColor];
        _previewLabel.opaque = NO;
        [self.contentView addSubview:_previewLabel];
    }
    return self;
}
- (void)setOnline:(BOOL)online mobile:(BOOL)mobile {
    UIImage *dot = [VKPresence dotForOnline:online mobile:mobile];
    self.onlineDot.image = dot;
    self.onlineDot.hidden = (dot == nil);
    self.onlineRing.hidden = (dot == nil);
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 70, w = self.contentView.bounds.size.width - x - 12;
    self.titleLabel.frame = CGRectMake(x, 12, w, 20);
    self.previewLabel.frame = CGRectMake(x, 34, w, 18);

    // Правый нижний угол аватара.
    CGFloat side = 14.0;
    CGRect ring = CGRectMake(10.0 + 50.0 - side + 3.0, 7.0 + 50.0 - side + 3.0, side, side);
    self.onlineRing.frame = ring;
    self.onlineRing.layer.cornerRadius = side / 2.0;
    self.onlineDot.frame = ring;
}
@end

#pragma mark - Список диалогов

@interface VKMessagesViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *rows;
@end

@implementation VKMessagesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Сообщения";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64.0;
    [self.view addSubview:self.tableView];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSIndexPath *sel = [self.tableView indexPathForSelectedRow];
    if (sel) [self.tableView deselectRowAtIndexPath:sel animated:animated];
}

- (void)reload {
    if (![[VKSession shared] isAuthorized]) {
        [self showMessage:@"Войдите, чтобы загрузить диалоги."];
        return;
    }
    [self showMessage:nil];
    [self showLoading:YES];
    [[VKAPI shared] callMethod:@"messages.getConversations"
                        params:@{@"count": @"40", @"extended": @"1",
                                 @"fields": @"photo_100,online,online_mobile,last_seen,sex"}
                    completion:^(id response, NSError *error) {
        [self showLoading:NO];
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            if (error.code == 15) {
                [self showMessage:@"Нет доступа к сообщениям.\nПроверьте доступ к сообщениям на вашем сервере OpenVK."];
            } else {
                [self showMessage:error.localizedDescription ?: @"Не удалось загрузить диалоги"];
            }
            return;
        }
        self.rows = [self parseConversations:(NSDictionary *)response];
        if (self.rows.count == 0) [self showMessage:@"Диалогов нет"];
        [self.tableView reloadData];
    }];
}

- (NSArray *)parseConversations:(NSDictionary *)response {
    NSMutableDictionary *dir = [NSMutableDictionary dictionary];
    for (NSDictionary *p in [response objectForKey:@"profiles"]) {
        NSString *key = [NSString stringWithFormat:@"%@", [p objectForKey:@"id"]];
        // online_mobile у VK иногда отдельным полем, иногда внутри last_seen.platform (>=6 — мобильные).
        NSInteger platform = [[[p objectForKey:@"last_seen"] objectForKey:@"platform"] integerValue];
        BOOL mobile = [[p objectForKey:@"online_mobile"] integerValue] != 0
                   || (platform > 0 && platform != 7);
        [dir setObject:@{@"name": [NSString stringWithFormat:@"%@ %@",
                                   [p objectForKey:@"first_name"] ?: @"",
                                   [p objectForKey:@"last_name"] ?: @""],
                         @"photo": [p objectForKey:@"photo_100"] ?: @"",
                         @"online": [NSNumber numberWithBool:[[p objectForKey:@"online"] integerValue] != 0],
                         @"mobile": [NSNumber numberWithBool:mobile]} forKey:key];
    }
    for (NSDictionary *g in [response objectForKey:@"groups"]) {
        NSString *key = [NSString stringWithFormat:@"-%@", [g objectForKey:@"id"]];
        [dir setObject:@{@"name": [g objectForKey:@"name"] ?: @"",
                         @"photo": [g objectForKey:@"photo_100"] ?: @""} forKey:key];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in [response objectForKey:@"items"]) {
        NSDictionary *conv = [item objectForKey:@"conversation"];
        NSDictionary *last = [item objectForKey:@"last_message"];
        NSDictionary *peer = [conv objectForKey:@"peer"];
        NSString *peerId = [NSString stringWithFormat:@"%@", [peer objectForKey:@"id"]];
        NSString *type = [peer objectForKey:@"type"];

        NSString *title, *photo = @"";
        BOOL online = NO, mobile = NO;
        if ([type isEqualToString:@"chat"]) {
            NSDictionary *settings = [conv objectForKey:@"chat_settings"];
            title = [settings objectForKey:@"title"] ?: @"Беседа";
            photo = [[settings objectForKey:@"photo"] objectForKey:@"photo_100"] ?: @"";
        } else {
            NSDictionary *info = [dir objectForKey:peerId];
            title = [info objectForKey:@"name"] ?: @"Диалог";
            photo = [info objectForKey:@"photo"] ?: @"";
            // Точку показываем только у личных диалогов — у беседы и паблика её нет.
            online = [type isEqualToString:@"user"] && [[info objectForKey:@"online"] boolValue];
            mobile = [[info objectForKey:@"mobile"] boolValue];
        }
        [result addObject:@{@"title": title,
                            @"preview": [last objectForKey:@"text"] ?: @"",
                            @"photo": photo ?: @"",
                            @"online": [NSNumber numberWithBool:online],
                            @"mobile": [NSNumber numberWithBool:mobile],
                            @"peer": [peer objectForKey:@"id"] ?: @0}];
    }
    return result;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKDialogCell";
    VKDialogCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[VKDialogCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    cell.backgroundColor = cell.contentView.backgroundColor = [VKTheme contentBackgroundColor];
    cell.titleLabel.textColor = [VKTheme primaryTextColor];
    NSDictionary *row = [self.rows objectAtIndex:indexPath.row];
    NSString *title = [row objectForKey:@"title"];
    cell.titleLabel.text = title;
    cell.previewLabel.text = [row objectForKey:@"preview"];
    [cell setOnline:[[row objectForKey:@"online"] boolValue]
             mobile:[[row objectForKey:@"mobile"] boolValue]];

    NSString *initials = title.length ? [[title substringToIndex:1] uppercaseString] : @"?";
    cell.avatar.image = [VKTheme avatarWithInitials:initials size:50.0 background:[VKTheme navBarColor]];
    NSString *url = [row objectForKey:@"photo"];
    if (url.length) {
        UIImage *cached = [[VKImageLoader shared] cachedImageForURL:url];
        if (cached) { cell.avatar.image = cached; }
        else {
            NSIndexPath *ip = indexPath;
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                VKDialogCell *c = (VKDialogCell *)[tableView cellForRowAtIndexPath:ip];
                if (image && c) c.avatar.image = image;
            }];
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.rows.count) return;
    NSDictionary *row = [self.rows objectAtIndex:indexPath.row];
    if (![row isKindOfClass:[NSDictionary class]]) return;
    long long peer = [[row objectForKey:@"peer"] longLongValue];
    NSString *title = [row objectForKey:@"title"];
    if (![title isKindOfClass:[NSString class]]) title = @"Диалог";
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Назад" style:UIBarButtonItemStyleBordered target:nil action:nil];
    VKChatViewController *chat = [[VKChatViewController alloc] initWithPeerId:peer title:title photo:[row objectForKey:@"photo"]];
    [self.navigationController pushViewController:chat animated:YES];
}

@end
