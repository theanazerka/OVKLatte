#import "OVKListCell.h"
#import "OVKSearchViewController.h"
#import "VKAPI.h"
#import "VKImageLoader.h"
#import "VKProfileViewController.h"
#import "VKTheme.h"

@interface OVKSearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIActionSheetDelegate>
@property (nonatomic, copy) NSString *query;
@property (nonatomic, assign) NSInteger scope;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *scopeControl;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) NSUInteger requestVersion;
@end

@implementation OVKSearchViewController

- (id)initWithQuery:(NSString *)query {
    if ((self = [super init])) {
        _query = [query copy];
        _scope = 0;
        _items = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Расширенный поиск";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Фильтры"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(filtersTapped)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = [VKTheme contentBackgroundColor];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 76.0;
    self.table.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.table];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 84.0)];
    header.backgroundColor = [VKTheme cardColor];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, header.bounds.size.width, 44.0)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = @"Люди, группы и паблики";
    self.searchBar.text = self.query;
    self.searchBar.delegate = self;
    self.searchBar.tintColor = [VKTheme navBarColor];
    [header addSubview:self.searchBar];
    self.scopeControl = [[UISegmentedControl alloc] initWithItems:@[@"Люди", @"Сообщества"]];
    self.scopeControl.frame = CGRectMake(10, 48, header.bounds.size.width - 20, 29);
    self.scopeControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.scopeControl.selectedSegmentIndex = self.scope;
    self.scopeControl.segmentedControlStyle = UISegmentedControlStyleBar;
    self.scopeControl.tintColor = [VKTheme navBarColor];
    [self.scopeControl addTarget:self action:@selector(scopeChanged:) forControlEvents:UIControlEventValueChanged];
    [header addSubview:self.scopeControl];
    self.table.tableHeaderView = header;
    [self search];
}

- (void)filtersTapped {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Искать"
                                                       delegate:self
                                              cancelButtonTitle:@"Отмена"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Людей", @"Группы и паблики", nil];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)index {
    if (index < 0 || index > 1) return;
    self.scope = index;
    self.scopeControl.selectedSegmentIndex = index;
    [self search];
}

- (void)scopeChanged:(UISegmentedControl *)sender {
    self.scope = sender.selectedSegmentIndex;
    [self search];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    self.query = [searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self search];
}

- (void)search {

    NSString *q = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) { ++self.requestVersion; self.loading = NO; [self showLoading:NO]; [self.items removeAllObjects]; [self.table reloadData]; [self showMessage:@"Введите запрос сверху"]; return; }
    NSUInteger version = ++self.requestVersion;
    [self.items removeAllObjects]; [self.table reloadData];
    self.loading = YES;
    [self showMessage:nil];
    [self showLoading:YES];
    NSString *method = self.scope == 0 ? @"users.search" : @"groups.search";
    NSDictionary *params = self.scope == 0
        ? @{ @"q": q, @"count": @50, @"fields": @"photo_100,screen_name,city,country" }
        : @{ @"q": q, @"count": @50, @"extended": @1, @"fields": @"photo_100,screen_name,description" };
    [[VKAPI shared] callMethod:method params:params completion:^(id response, NSError *error) {
        if (version != self.requestVersion) return;
        self.loading = NO;
        [self showLoading:NO];
        NSArray *found = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"items"] : response;
        [self.items removeAllObjects];
        if (!error && [found isKindOfClass:[NSArray class]]) [self.items addObjectsFromArray:found];
        [self.table reloadData];
        if (error) [self showMessage:error.localizedDescription ?: @"Не удалось выполнить поиск"];
        else if (!self.items.count) [self showMessage:@"Ничего не найдено"];
        else [self showMessage:nil];
    }];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.items.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchItem"];
    if (!cell) cell = [[OVKListCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SearchItem"];
    NSDictionary *item = [self.items objectAtIndex:indexPath.row];
    BOOL group = self.scope == 1;
    NSString *name = group ? [item objectForKey:@"name"] : [NSString stringWithFormat:@"%@ %@", [item objectForKey:@"first_name"] ?: @"", [item objectForKey:@"last_name"] ?: @""];
    NSString *detail = group ? ([item objectForKey:@"description"] ?: [item objectForKey:@"screen_name"] ?: @"Сообщество") : ([item objectForKey:@"screen_name"] ?: @"Пользователь");
    cell.textLabel.text = name.length ? name : (group ? @"Сообщество" : @"Пользователь");
    cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.detailTextLabel.textColor = [VKTheme secondaryTextColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [UIImage imageNamed:(group ? @"group_placeholder_50px" : @"user_placeholder_50px")];
    NSString *url = [item objectForKey:@"photo_100"] ?: [item objectForKey:@"photo_50"];
    ((OVKListCell *)cell).representedURL = url;
    if (url.length) {
        __weak UITableViewCell *weakCell = cell;
        [[VKImageLoader shared] loadURL:url completion:^(UIImage *image) {
            NSIndexPath *current = [self.table indexPathForCell:weakCell];
            if (image && [current isEqual:indexPath] && [((OVKListCell *)weakCell).representedURL isEqual:url]) { weakCell.imageView.image = image; [weakCell setNeedsLayout]; }
        }];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = [self.items objectAtIndex:indexPath.row];
    BOOL group = self.scope == 1;
    long long ident = [[item objectForKey:@"id"] longLongValue];
    if (group) ident = -llabs(ident);
    NSString *name = group ? [item objectForKey:@"name"] : [NSString stringWithFormat:@"%@ %@", [item objectForKey:@"first_name"] ?: @"", [item objectForKey:@"last_name"] ?: @""];
    // Не показываем длинное «Расширенный поиск» в системной кнопке возврата.
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Назад" style:UIBarButtonItemStylePlain target:nil action:nil];
    [self.navigationController pushViewController:[[VKProfileViewController alloc] initWithUserId:ident name:name] animated:YES];
}

@end
