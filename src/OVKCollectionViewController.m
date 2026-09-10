#import "OVKListCell.h"
#import "OVKCollectionViewController.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKBackend.h"
#import "VKProfileViewController.h"
#import "VKPhotoViewController.h"
#import "VKImageLoader.h"
#import "VKTheme.h"
#import <QuartzCore/QuartzCore.h>

@interface OVKCollectionViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *section;
@property (nonatomic, assign) long long ownerId;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, strong) NSMutableArray *allItems;
@property (nonatomic, strong) UISegmentedControl *groupFilter;
@property (nonatomic, strong) NSMutableSet *managedGroupIds;
@property (nonatomic, assign) NSUInteger managedCursor;
@property (nonatomic, assign) NSInteger managedWorkers;
@property (nonatomic, assign) BOOL managedResolved;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL more;
@end

@interface OVKPhotoCell : UITableViewCell
@property (nonatomic, strong) NSArray *tiles;
@property (nonatomic, copy) NSArray *representedURLs;
@property (nonatomic, copy) void (^openPhoto)(NSInteger);
@end
@implementation OVKPhotoCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [VKTheme contentBackgroundColor];
        NSMutableArray *tiles = [NSMutableArray array];
        for (NSInteger i = 0; i < 3; i++) {
            UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
            tile.tag = i;
            tile.imageView.contentMode = UIViewContentModeScaleAspectFill;
            tile.clipsToBounds = YES;
            tile.backgroundColor = [UIColor colorWithWhite:0.88 alpha:1];
            [tile addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:tile]; [tiles addObject:tile];
        }
        self.tiles = tiles;
    }
    return self;
}
- (void)tapped:(UIButton *)sender { if (self.openPhoto) self.openPhoto(sender.tag); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = floorf((self.contentView.bounds.size.width - 16) / 3);
    for (NSInteger i = 0; i < 3; i++) ((UIButton *)[self.tiles objectAtIndex:i]).frame = CGRectMake(4 + i * (side + 4), 2, side, side);
}
@end

@interface OVKGroupCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@end
@implementation OVKGroupCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleGray;
        self.backgroundColor = [VKTheme contentBackgroundColor];
        self.contentView.backgroundColor = [VKTheme contentBackgroundColor];
        _avatar = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, 56, 56)];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = 0.0;
        [self.contentView addSubview:_avatar];
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont boldSystemFontOfSize:15.0];
        _nameLabel.textColor = [VKTheme primaryTextColor];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_nameLabel];
        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.font = [UIFont systemFontOfSize:12.0];
        _subtitleLabel.textColor = [VKTheme secondaryTextColor];
        _subtitleLabel.numberOfLines = 2;
        [self.contentView addSubview:_subtitleLabel];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat x = 76.0, w = self.contentView.bounds.size.width - x - 25.0;
    self.nameLabel.frame = CGRectMake(x, 12, w, 19);
    self.subtitleLabel.frame = CGRectMake(x, 33, w, 32);
}
@end
@implementation OVKCollectionViewController
- (id)initWithSection:(NSString *)section ownerId:(long long)ownerId {
    if ((self = [super init])) { self.section = ([section isEqualToString:@"photos"] && ownerId < 0) ? @"albums" : section; self.ownerId = ownerId; self.items = [NSMutableArray array]; self.allItems = [NSMutableArray array]; self.managedGroupIds = [NSMutableSet set]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [@{@"albums": @"Альбомы", @"albumPhotos": @"Фотографии", @"groups": @"Группы", @"photos": @"Фотографии", @"notifications": @"Ответы"} objectForKey:self.section];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self; self.table.delegate = self;
    self.table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.table.rowHeight = [self.section isEqualToString:@"groups"] ? 76.0 : ([self.section isEqualToString:@"photos"] || [self.section isEqualToString:@"albumPhotos"] ? 188.0 : 68.0);
    self.table.separatorStyle = [self isPhotoGrid] ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
    self.table.backgroundColor = [VKTheme contentBackgroundColor];
    if ([self.section isEqualToString:@"groups"] && (self.ownerId == 0 || self.ownerId == [VKSession shared].userId)) {
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        header.backgroundColor = [VKTheme cardColor];
        self.groupFilter = [[UISegmentedControl alloc] initWithItems:@[@"Все", @"Управляемые"]];
        self.groupFilter.frame = CGRectMake(10, 7, header.bounds.size.width - 20, 30);
        self.groupFilter.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.groupFilter.selectedSegmentIndex = 0;
        self.groupFilter.segmentedControlStyle = UISegmentedControlStyleBar;
        self.groupFilter.tintColor = [VKTheme navBarColor];
        [self.groupFilter addTarget:self action:@selector(groupFilterChanged:) forControlEvents:UIControlEventValueChanged];
        [header addSubview:self.groupFilter];
        self.table.tableHeaderView = header;
    }
    [self.view addSubview:self.table];
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.table addSubview:self.refresh];
    [self reload];
}
- (void)reload { [self fetch:YES]; }
- (void)fetch:(BOOL)reset {
    if (self.loading) { [self.refresh endRefreshing]; return; }
    if (![VKSession shared].isAuthorized) { [self showMessage:@"Войдите в OpenVK"]; [self.refresh endRefreshing]; return; }
    self.loading = YES;
    [self showMessage:nil];
    [self showLoading:self.items.count == 0];
    long long owner = self.ownerId ?: [VKSession shared].userId;
    NSString *method = [@{@"albums": @"photos.getAlbums", @"albumPhotos": @"photos.get", @"groups": @"groups.get", @"photos": @"photos.getAll", @"notifications": @"notifications.get"} objectForKey:self.section];
    NSInteger currentCount = [self.section isEqualToString:@"groups"] ? self.allItems.count : self.items.count;
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{@"offset": @(reset ? 0 : currentCount), @"count": @([self.section isEqualToString:@"groups"] ? 100 : 40)}];
    if ([self.section isEqualToString:@"groups"]) [params addEntriesFromDictionary:@{@"user_id": @(owner), @"fields": @"photo_50,photo_100,photo_200,members_count,verified"}];
    if ([self.section isEqualToString:@"photos"]) [params addEntriesFromDictionary:@{@"owner_id": @(owner), @"photo_sizes": @1}];
    if ([self.section isEqualToString:@"albums"]) [params addEntriesFromDictionary:@{@"owner_id": @(owner), @"need_covers": @1, @"need_system": @1}];
    if ([self.section isEqualToString:@"albumPhotos"]) [params addEntriesFromDictionary:@{@"owner_id": @(owner), @"album_id": @(self.albumId), @"photo_sizes": @1}];
    [[VKAPI shared] callMethod:method params:params completion:^(id response, NSError *error) {
        self.loading = NO; [self.refresh endRefreshing]; [self showLoading:NO];
        NSArray *rows = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"items"] : nil;
        if (error || ![rows isKindOfClass:[NSArray class]]) {
            [self showMessage:error.localizedDescription ?: @"Некорректный ответ сервера"];
            return;
        }
        if ([self.section isEqualToString:@"groups"]) {
            if (reset) { [self.allItems removeAllObjects]; [self.managedGroupIds removeAllObjects]; self.managedResolved = NO; }
            for (id row in rows) if ([row isKindOfClass:[NSDictionary class]]) [self.allItems addObject:row];
            [self applyGroupFilter];
        } else {
            if (reset) [self.items removeAllObjects];
            for (id row in rows) if ([row isKindOfClass:[NSDictionary class]]) [self.items addObject:row];
        }
        self.more = rows.count == ([self.section isEqualToString:@"groups"] ? 100 : 40);
        [self.table reloadData];
        if (!self.items.count) [self showMessage:@"Пока ничего нет"];
        if ([self.section isEqualToString:@"notifications"] && reset && rows.count) [[VKAPI shared] callMethod:@"notifications.markAsViewed" params:nil completion:nil];
    }];
}
- (BOOL)isManagedGroup:(NSDictionary *)group {
    NSNumber *groupId = @([[group objectForKey:@"id"] longLongValue]);
    if ([self.managedGroupIds containsObject:groupId]) return YES;
    if ([[group objectForKey:@"is_admin"] boolValue] || [[group objectForKey:@"is_owner"] boolValue] || [[group objectForKey:@"is_creator"] boolValue]) return YES;
    if ([[group objectForKey:@"admin_level"] integerValue] > 0) return YES;
    return [[group objectForKey:@"owner_id"] longLongValue] == [VKSession shared].userId;
}
- (void)applyGroupFilter {
    if (![self.section isEqualToString:@"groups"]) return;
    [self.items removeAllObjects];
    BOOL managed = self.groupFilter.selectedSegmentIndex == 1;
    for (NSDictionary *group in self.allItems) if (!managed || [self isManagedGroup:group]) [self.items addObject:group];
}
- (void)groupFilterChanged:(UISegmentedControl *)sender {
    [self applyGroupFilter];
    [self.table reloadData];
    if (sender.selectedSegmentIndex == 1 && !self.managedResolved) {
        [self resolveManagedGroups];
    } else {
        [self showMessage:self.items.count ? nil : (sender.selectedSegmentIndex == 1 ? @"Управляемых сообществ нет" : @"Пока ничего нет")];
    }
}
- (void)resolveManagedGroups {
    if (self.managedWorkers > 0 || self.managedResolved) return;
    self.managedCursor = 0;
    self.managedWorkers = MIN(6, (NSInteger)self.allItems.count);
    if (self.managedWorkers == 0) { self.managedResolved = YES; [self showMessage:@"Управляемых сообществ нет"]; return; }
    [self showMessage:nil]; [self showLoading:YES];
    for (NSInteger i = 0; i < self.managedWorkers; i++) [self resolveNextManagedGroup];
}
- (void)resolveNextManagedGroup {
    if (self.managedCursor >= self.allItems.count) {
        self.managedWorkers--;
        if (self.managedWorkers == 0) {
            self.managedResolved = YES; [self showLoading:NO]; [self applyGroupFilter]; [self.table reloadData];
            if (self.groupFilter.selectedSegmentIndex == 1 && !self.items.count) [self showMessage:@"Управляемых сообществ нет"];
        }
        return;
    }
    NSDictionary *group = [self.allItems objectAtIndex:self.managedCursor++];
    NSNumber *groupId = @([[group objectForKey:@"id"] longLongValue]);
    [[VKAPI shared] callMethod:@"groups.getSettings" params:@{@"group_id": groupId} completion:^(id response, NSError *error) {
        if (!error && [response isKindOfClass:[NSDictionary class]]) {
            [self.managedGroupIds addObject:groupId];
            if (self.groupFilter.selectedSegmentIndex == 1) { [self applyGroupFilter]; [self.table reloadData]; }
        }
        [self resolveNextManagedGroup];
    }];
}
- (NSString *)photoURL:(NSDictionary *)photo {
    NSString *url = [photo objectForKey:@"photo_604"] ?: [photo objectForKey:@"photo_130"];
    NSInteger width = 0;
    for (NSDictionary *size in [photo objectForKey:@"sizes"]) {
        if ([[size objectForKey:@"width"] integerValue] > width && [[size objectForKey:@"url"] isKindOfClass:[NSString class]]) {
            width = [[size objectForKey:@"width"] integerValue]; url = [size objectForKey:@"url"];
        }
    }
    return url;
}
- (BOOL)isPhotoGrid { return [self.section isEqualToString:@"photos"] || [self.section isEqualToString:@"albumPhotos"]; }
- (NSInteger)displayCount { return [self isPhotoGrid] ? (self.items.count + 2) / 3 : self.items.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == [self displayCount]) return 48;
    return [self isPhotoGrid] ? floorf((tableView.bounds.size.width - 16) / 3) + 4 : 76;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self displayCount] + (self.more ? 1 : 0); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isPhotoGrid] && indexPath.row < [self displayCount]) {
        OVKPhotoCell *cell = (OVKPhotoCell *)[tableView dequeueReusableCellWithIdentifier:@"PhotoGrid"];
        if (!cell) cell = [[OVKPhotoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PhotoGrid"];
        NSMutableArray *urls = [NSMutableArray array];
        for (NSInteger column = 0; column < 3; column++) {
            NSInteger index = indexPath.row * 3 + column;
            [urls addObject:index < self.items.count ? ([self photoURL:[self.items objectAtIndex:index]] ?: @"") : @""];
        }
        cell.representedURLs = urls;
        for (NSInteger column = 0; column < 3; column++) {
            UIButton *tile = [cell.tiles objectAtIndex:column];
            tile.hidden = indexPath.row * 3 + column >= self.items.count;
            [tile setImage:[UIImage imageNamed:@"placeholder_photos_dark"] forState:UIControlStateNormal];
            NSString *url = [urls objectAtIndex:column];
            __weak OVKPhotoCell *weakCell = cell;
            [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
                if (image && [weakCell.representedURLs isEqualToArray:urls]) [(UIButton *)[weakCell.tiles objectAtIndex:column] setImage:image forState:UIControlStateNormal];
            }];
        }
        __weak typeof(self) weakSelf = self;
        cell.openPhoto = ^(NSInteger column) {
            NSInteger index = indexPath.row * 3 + column;
            if (index >= weakSelf.items.count) return;
            NSString *url = [weakSelf photoURL:[weakSelf.items objectAtIndex:index]];
            [weakSelf presentViewController:[[VKPhotoViewController alloc] initWithImage:[[VKImageLoader shared] cachedImageForURL:url] url:url] animated:YES completion:nil];
        };
        return cell;
    }
    if ([self.section isEqualToString:@"groups"] && indexPath.row < self.items.count) {
        OVKGroupCell *groupCell = (OVKGroupCell *)[tableView dequeueReusableCellWithIdentifier:@"OVKGroup"];
        if (!groupCell) groupCell = [[OVKGroupCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"OVKGroup"];
        NSDictionary *group = [self.items objectAtIndex:indexPath.row];
        groupCell.nameLabel.text = [group objectForKey:@"name"] ?: @"Группа";
        NSString *description = [group objectForKey:@"description"];
        groupCell.subtitleLabel.text = description.length ? description : ([group objectForKey:@"screen_name"] ?: @"Сообщество");
        groupCell.avatar.image = [UIImage imageNamed:@"group_placeholder_50px"];
        NSString *groupURL = [group objectForKey:@"photo_100"] ?: [group objectForKey:@"photo_50"];
        if (groupURL.length) {
            __weak OVKGroupCell *weakCell = groupCell;
            [[VKImageLoader shared] loadURL:groupURL completion:^(UIImage *image) {
                NSIndexPath *current = [self.table indexPathForCell:weakCell];
                if (image && [current isEqual:indexPath] && indexPath.row < self.items.count && [self.items objectAtIndex:indexPath.row] == group) weakCell.avatar.image = image;
            }];
        }
        return groupCell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"OVKItem"];
    if (!cell) cell = [[OVKListCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"OVKItem"];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:15]; cell.detailTextLabel.numberOfLines = 2;
    cell.textLabel.textColor = [VKTheme primaryTextColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.textColor = [VKTheme secondaryTextColor];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.textLabel.text = @"Загрузить ещё"; cell.detailTextLabel.text = nil;
    cell.imageView.image = nil; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.row >= [self displayCount]) { cell.textLabel.textAlignment = NSTextAlignmentCenter; cell.textLabel.textColor = [VKTheme linkColor]; cell.accessoryType = UITableViewCellAccessoryNone; return cell; }
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    NSDictionary *item = [self.items objectAtIndex:indexPath.row];
    NSString *url = nil;
    if ([self.section isEqualToString:@"groups"]) {
        cell.textLabel.text = [item objectForKey:@"name"] ?: @"Группа";
        cell.detailTextLabel.text = [item objectForKey:@"description"]; url = [item objectForKey:@"photo_100"];
    } else if ([self.section isEqualToString:@"photos"] || [self.section isEqualToString:@"albumPhotos"]) {
        cell.textLabel.text = @"Фотография"; cell.detailTextLabel.text = [item objectForKey:@"text"]; url = [self photoURL:item];
    } else if ([self.section isEqualToString:@"albums"]) {
        cell.textLabel.text = [item objectForKey:@"title"] ?: @"Альбом";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ фотографий", [item objectForKey:@"size"] ?: @0];
        cell.imageView.image = [UIImage imageNamed:@"placeholder_photos_dark"];
        url = [item objectForKey:@"thumb_src"];
    } else {
        NSString *type = [item objectForKey:@"type"] ?: @"";
        NSDictionary *names = @{@"like_post": @"Нравится запись", @"like_photo": @"Нравится фотография", @"like_video": @"Нравится видео", @"comment_post": @"Комментарий к записи", @"comment_photo": @"Комментарий к фотографии", @"comment_video": @"Комментарий к видео", @"reply_comment": @"Ответ на комментарий", @"follow": @"Новая подписка", @"friend_accepted": @"Заявка в друзья принята", @"mention": @"Упоминание", @"wall": @"Запись на стене"};
        cell.textLabel.text = [names objectForKey:type] ?: @"Новое уведомление";
        NSDictionary *parent = [item objectForKey:@"parent"];
        cell.detailTextLabel.text = [parent isKindOfClass:[NSDictionary class]] ? ([parent objectForKey:@"text"] ?: [parent objectForKey:@"title"]) : nil;
    }
    if ([self.section isEqualToString:@"groups"] && !url.length) {
        cell.imageView.image = [VKTheme avatarWithInitials:(cell.textLabel.text.length ? [[cell.textLabel.text substringToIndex:1] uppercaseString] : @"Г") size:52.0 background:[VKTheme navBarColor]];
    }
    if (url.length) {
        __weak UITableViewCell *weakCell = cell;
        [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
            NSIndexPath *current = [self.table indexPathForCell:weakCell];
            if (image && [current isEqual:indexPath] && indexPath.row < self.items.count && [self.items objectAtIndex:indexPath.row] == item) { weakCell.imageView.image = image; [weakCell setNeedsLayout]; }
        }];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= [self displayCount]) { [self fetch:NO]; return; }
    if ([self isPhotoGrid]) return;
    NSDictionary *item = [self.items objectAtIndex:indexPath.row];
    if ([self.section isEqualToString:@"groups"]) {
        VKProfileViewController *profile = [[VKProfileViewController alloc] initWithUserId:-llabs([[item objectForKey:@"id"] longLongValue]) name:[item objectForKey:@"name"]];
        [self.navigationController pushViewController:profile animated:YES];
    } else if ([self.section isEqualToString:@"photos"] || [self.section isEqualToString:@"albumPhotos"]) {
        VKPhotoViewController *photo = [[VKPhotoViewController alloc] initWithImage:nil url:[self photoURL:item]];
        [self presentViewController:photo animated:YES completion:nil];
    } else if ([self.section isEqualToString:@"albums"]) {
        OVKCollectionViewController *photos = [[OVKCollectionViewController alloc] initWithSection:@"albumPhotos" ownerId:self.ownerId];
        photos.albumId = [[item objectForKey:@"id"] longLongValue];
        [self.navigationController pushViewController:photos animated:YES];
    } else {
        UITableViewCell *selectedCell = [tableView cellForRowAtIndexPath:indexPath];
        NSString *text = selectedCell.detailTextLabel.text.length ? selectedCell.detailTextLabel.text : @"Подробностей нет";
        [[[UIAlertView alloc] initWithTitle:selectedCell.textLabel.text ?: @"Ответы" message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}
@end
