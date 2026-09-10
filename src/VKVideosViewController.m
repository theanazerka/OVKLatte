#import "VKVideosViewController.h"
#import "VKVideo.h"
#import "VKVideoCell.h"
#import "VKVideoPlayerViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKBackend.h"

static const NSInteger kPageCount = 30;

@interface VKVideosViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate> {
    long long _ownerId;
    NSString *_customTitle;
    NSInteger _activeSegment; // 0: My, 1: Catalog/Popular, 2: Search
    BOOL _isLoading;
    BOOL _hasMore;
    NSInteger _currentOffset;
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) NSMutableArray *videos;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, copy) NSString *searchQuery;
@end

@implementation VKVideosViewController

- (id)init {
    return [self initWithOwnerId:0 title:nil];
}

- (id)initWithOwnerId:(long long)ownerId title:(NSString *)title {
    self = [super init];
    if (self) {
        _ownerId = ownerId;
        _customTitle = [title copy];
        _videos = [NSMutableArray array];
        _hasMore = YES;
        _currentOffset = 0;
        _activeSegment = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = _customTitle.length ? _customTitle : @"Видеозаписи";

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, w, h)
                                                  style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = [VKVideoCell rowHeight];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Шапка таблицы: Поиск + Сегменты
    [self buildTableHeader];

    // Pull-to-refresh
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refresh];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:VKBackendDidChangeNotification
                                               object:nil];

    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildTableHeader {
    CGFloat w = self.view.bounds.size.width;
    BOOL isMainSection = (_ownerId == 0 || _ownerId == [VKSession shared].userId);

    CGFloat headerH = isMainSection ? 88.0 : 44.0;
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerH)];
    self.headerView.backgroundColor = [VKTheme cardColor];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, w, 44.0)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = @"Поиск видеозаписей";
    self.searchBar.delegate = self;
    self.searchBar.showsCancelButton = NO;
    if ([self.searchBar respondsToSelector:@selector(setTintColor:)]) {
        self.searchBar.tintColor = [VKTheme navBarColor];
    }
    [self.headerView addSubview:self.searchBar];

    if (isMainSection) {
        UIView *segContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 44.0, w, 44.0)];
        segContainer.backgroundColor = [VKTheme cardColor];
        segContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Мои видео", @"Каталог", @"Поиск"]];
        self.segmentedControl.frame = CGRectMake(10.0, 7.0, w - 20.0, 30.0);
        self.segmentedControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.segmentedControl.selectedSegmentIndex = 0;
        self.segmentedControl.segmentedControlStyle = UISegmentedControlStyleBar;
        if ([self.segmentedControl respondsToSelector:@selector(setTintColor:)]) {
            self.segmentedControl.tintColor = [VKTheme navBarColor];
        }
        [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [segContainer addSubview:self.segmentedControl];

        UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, 43.5, w, 0.5)];
        div.backgroundColor = [VKTheme separatorColor];
        div.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [segContainer addSubview:div];

        [self.headerView addSubview:segContainer];
    } else {
        UIView *div = [[UIView alloc] initWithFrame:CGRectMake(0, 43.5, w, 0.5)];
        div.backgroundColor = [VKTheme separatorColor];
        div.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self.headerView addSubview:div];
    }

    self.tableView.tableHeaderView = self.headerView;
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    _activeSegment = sender.selectedSegmentIndex;
    if (_activeSegment == 2) {
        [self.searchBar becomeFirstResponder];
    } else {
        [self.searchBar resignFirstResponder];
        self.searchBar.text = @"";
        self.searchQuery = nil;
    }
    [self reload];
}

#pragma mark - Data Loading

- (void)reload {
    if (![[VKSession shared] isAuthorized]) {
        [self showMessage:@"Войдите, чтобы просматривать видеозаписи."];
        return;
    }

    _isLoading = YES;
    _hasMore = YES;
    _currentOffset = 0;
    [self showMessage:nil];
    if (self.videos.count == 0) [self showLoading:YES];

    [self fetchVideosOffset:0 append:NO];
}

- (void)loadMore {
    if (_isLoading || !_hasMore) return;
    _isLoading = YES;
    [self fetchVideosOffset:_currentOffset append:YES];
}

- (void)fetchVideosOffset:(NSInteger)offset append:(BOOL)append {
    NSString *method;
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params setObject:[NSString stringWithFormat:@"%d", (int)kPageCount] forKey:@"count"];
    [params setObject:[NSString stringWithFormat:@"%d", (int)offset] forKey:@"offset"];

    if (_activeSegment == 2 || (_searchQuery.length > 0 && _ownerId == 0)) {
        method = @"video.search";
        [params setObject:(_searchQuery.length ? _searchQuery : @"") forKey:@"q"];
    } else if (_activeSegment == 1 && _ownerId == 0) {
        // Каталог популярных видео
        method = @"video.search";
        [params setObject:@"фильм клип шоу" forKey:@"q"];
    } else {
        method = @"video.get";
        long long targetOwner = (_ownerId != 0) ? _ownerId : [VKSession shared].userId;
        if (targetOwner != 0) {
            [params setObject:[NSString stringWithFormat:@"%lld", targetOwner] forKey:@"owner_id"];
        }
    }

    [[VKAPI shared] callMethod:method params:params completion:^(id response, NSError *error) {
        _isLoading = NO;
        [self showLoading:NO];
        [self.refresh endRefreshing];

        if (error || !response) {
            if (self.videos.count == 0) {
                [self showMessage:error.localizedDescription ?: @"Не удалось загрузить видеозаписи"];
            }
            return;
        }

        NSArray *parsed = [VKVideo parseVideosResponse:response];
        if (!append) {
            [self.videos removeAllObjects];
        }

        [self.videos addObjectsFromArray:parsed];
        _currentOffset = self.videos.count;
        _hasMore = (parsed.count >= kPageCount);

        if (self.videos.count == 0) {
            if (_activeSegment == 0 && _ownerId == 0) {
                [self showMessage:@"В ваших видеозаписях пока ничего нет.\nВыберите «Каталог» или воспользуйтесь поиском."];
            } else if (_activeSegment == 2) {
                [self showMessage:@"По вашему запросу ничего не найдено"];
            } else {
                [self showMessage:@"Список видеозаписей пуст"];
            }
        } else {
            [self showMessage:nil];
        }

        [self.tableView reloadData];
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.videos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKVideoCell";
    VKVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[VKVideoCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    }
    cell.video = [self.videos objectAtIndex:indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBar resignFirstResponder];

    VKVideo *v = [self.videos objectAtIndex:indexPath.row];
    VKVideoPlayerViewController *playerVC = [[VKVideoPlayerViewController alloc] initWithVideo:v];
    [self.navigationController pushViewController:playerVC animated:YES];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat bottomEdge = scrollView.contentOffset.y + scrollView.frame.size.height;
    if (bottomEdge >= scrollView.contentSize.height - 150.0 && scrollView.contentSize.height > 0) {
        [self loadMore];
    }
}

#pragma mark - Search Bar Delegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    self.searchQuery = nil;
    if (self.segmentedControl && self.segmentedControl.selectedSegmentIndex == 2) {
        self.segmentedControl.selectedSegmentIndex = 0;
        _activeSegment = 0;
    }
    [self reload];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    self.searchQuery = [searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _activeSegment = 2;
    if (self.segmentedControl) {
        self.segmentedControl.selectedSegmentIndex = 2;
    }
    [self reload];
}

@end
