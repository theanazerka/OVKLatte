#import "VKAudiosViewController.h"
#import "VKAudio.h"
#import "VKAudioCell.h"
#import "VKAudioPlayer.h"
#import "VKAudioPlayerViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKBackend.h"

static const NSInteger kAudioPageCount = 50;

@interface VKAudiosViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate> {
    long long _ownerId;
    NSString *_customTitle;
    NSInteger _activeSegment; // 0: My, 1: Popular, 2: Search
    BOOL _isLoading;
    BOOL _hasMore;
    NSInteger _currentOffset;
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) NSMutableArray *audios;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, copy) NSString *searchQuery;

@property (nonatomic, strong) UIView *miniPlayerBar;
@property (nonatomic, strong) UIButton *miniPlayButton;
@property (nonatomic, strong) UILabel *miniTitleLabel;
@property (nonatomic, strong) UILabel *miniArtistLabel;
@property (nonatomic, strong) UIButton *miniNextButton;
@end

@implementation VKAudiosViewController

- (id)init {
    return [self initWithOwnerId:0 title:nil];
}

- (id)initWithOwnerId:(long long)ownerId title:(NSString *)title {
    self = [super init];
    if (self) {
        _ownerId = ownerId;
        _customTitle = [title copy];
        _audios = [NSMutableArray array];
        _hasMore = YES;
        _currentOffset = 0;
        _activeSegment = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = _customTitle.length ? _customTitle : @"Аудиозаписи";

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, w, h)
                                                  style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = [VKAudioCell rowHeight];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Шапка таблицы: Поиск + Сегменты
    [self buildTableHeader];

    // Нижний мини-плеер
    [self buildMiniPlayer];

    // Кнопка плеера в навбаре справа
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Плеер"
                style:UIBarButtonItemStyleBordered
               target:self
               action:@selector(openPlayerTapped)];

    // В корневом разделе оставляем кнопку сайдбара. «Назад» нужна только
    // для списка музыки, открытого из профиля.
    if (self.navigationController.viewControllers.count > 1 || self.presentingViewController) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
            initWithTitle:@"Назад"
                    style:UIBarButtonItemStyleBordered
                   target:self
                   action:@selector(closeTapped)];
    }

    // Pull-to-refresh
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refresh];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(trackDidChange:) name:VKAudioPlayerTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(stateDidChange:) name:VKAudioPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(reload) name:VKBackendDidChangeNotification object:nil];

    [self updateMiniPlayer];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UI Building

- (void)buildTableHeader {
    CGFloat w = self.view.bounds.size.width;
    BOOL isMainSection = (_ownerId == 0 || _ownerId == [VKSession shared].userId);

    CGFloat headerH = isMainSection ? 88.0 : 44.0;
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerH)];
    self.headerView.backgroundColor = [VKTheme cardColor];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, w, 44.0)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = @"Поиск музыки";
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

        self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Мои аудио", @"Популярное", @"Поиск"]];
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

- (void)buildMiniPlayer {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat barH = 44.0;

    self.miniPlayerBar = [[UIView alloc] initWithFrame:CGRectMake(0, h - barH, w, barH)];
    self.miniPlayerBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.miniPlayerBar.backgroundColor = [UIColor colorWithRed:0.18 green:0.22 blue:0.27 alpha:1.0];
    self.miniPlayerBar.hidden = YES;

    // Верхняя тонкая разделительная полоса
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 0.5)];
    topLine.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.miniPlayerBar addSubview:topLine];

    // Кнопка play/pause
    self.miniPlayButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.miniPlayButton.frame = CGRectMake(6.0, 5.0, 34.0, 34.0);
    [self.miniPlayButton setImage:[UIImage imageNamed:@"inplayer_play"] forState:UIControlStateNormal];
    [self.miniPlayButton addTarget:self action:@selector(miniPlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.miniPlayerBar addSubview:self.miniPlayButton];

    // Текст трека (кликабелен для перехода в полный плеер)
    UIButton *textBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    textBtn.frame = CGRectMake(46.0, 0, w - 46.0 - 44.0, barH);
    textBtn.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [textBtn addTarget:self action:@selector(openPlayerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.miniPlayerBar addSubview:textBtn];

    self.miniTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(46.0, 5.0, w - 46.0 - 44.0, 18.0)];
    self.miniTitleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    self.miniTitleLabel.textColor = [UIColor whiteColor];
    self.miniTitleLabel.backgroundColor = [UIColor clearColor];
    self.miniTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.miniPlayerBar addSubview:self.miniTitleLabel];

    self.miniArtistLabel = [[UILabel alloc] initWithFrame:CGRectMake(46.0, 23.0, w - 46.0 - 44.0, 15.0)];
    self.miniArtistLabel.font = [UIFont systemFontOfSize:11.0];
    self.miniArtistLabel.textColor = [UIColor colorWithRed:0.65 green:0.72 blue:0.80 alpha:1.0];
    self.miniArtistLabel.backgroundColor = [UIColor clearColor];
    self.miniArtistLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.miniPlayerBar addSubview:self.miniArtistLabel];

    // Кнопка следующий трек
    self.miniNextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.miniNextButton.frame = CGRectMake(w - 40.0, 5.0, 34.0, 34.0);
    self.miniNextButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.miniNextButton setImage:[UIImage imageNamed:@"audioplayer_next"] forState:UIControlStateNormal];
    [self.miniNextButton addTarget:self action:@selector(miniNextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.miniPlayerBar addSubview:self.miniNextButton];

    [self.view addSubview:self.miniPlayerBar];
}

- (void)updateMiniPlayer {
    VKAudioPlayer *player = [VKAudioPlayer shared];
    if (player.currentAudio) {
        self.miniPlayerBar.hidden = NO;
        self.miniTitleLabel.text = player.currentAudio.title.length ? player.currentAudio.title : @"Без названия";
        self.miniArtistLabel.text = player.currentAudio.artist.length ? player.currentAudio.artist : @"Неизвестный";

        if (player.isPlaying) {
            [self.miniPlayButton setImage:[UIImage imageNamed:@"inplayer_pause"] forState:UIControlStateNormal];
        } else {
            [self.miniPlayButton setImage:[UIImage imageNamed:@"inplayer_play"] forState:UIControlStateNormal];
        }

        self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 44.0, 0);
        self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    } else {
        self.miniPlayerBar.hidden = YES;
        self.tableView.contentInset = UIEdgeInsetsZero;
        self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }
}

#pragma mark - Segment & Search

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

- (void)openPlayerTapped {
    [[VKAudioPlayerViewController sharedController] presentFromViewController:self];
}

- (void)closeTapped {
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        // На случай нестандартного контейнера: кнопка всё равно не должна быть
        // «пустой» и возвращает пользователя к корневому экрану.
        [self.navigationController popToRootViewControllerAnimated:YES];
    }
}

- (void)miniPlayTapped {
    [[VKAudioPlayer shared] togglePlayPause];
}

- (void)miniNextTapped {
    [[VKAudioPlayer shared] next];
}

#pragma mark - Data Loading

- (void)reload {
    if (![[VKSession shared] isAuthorized]) {
        [self showMessage:@"Войдите, чтобы слушать музыку."];
        return;
    }

    _isLoading = YES;
    _hasMore = YES;
    _currentOffset = 0;
    [self showMessage:nil];
    if (self.audios.count == 0) [self showLoading:YES];

    [self fetchAudiosOffset:0 append:NO];
}

- (void)loadMore {
    if (_isLoading || !_hasMore) return;
    _isLoading = YES;
    [self fetchAudiosOffset:_currentOffset append:YES];
}

- (void)fetchAudiosOffset:(NSInteger)offset append:(BOOL)append {
    NSString *method;
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params setObject:[NSString stringWithFormat:@"%d", (int)kAudioPageCount] forKey:@"count"];
    [params setObject:[NSString stringWithFormat:@"%d", (int)offset] forKey:@"offset"];

    if (_activeSegment == 2 || (_searchQuery.length > 0 && _ownerId == 0)) {
        method = @"audio.search";
        [params setObject:(_searchQuery.length ? _searchQuery : @"") forKey:@"q"];
        [params setObject:@"2" forKey:@"sort"]; // по популярности
    } else if (_activeSegment == 1 && _ownerId == 0) {
        method = @"audio.getPopular";
    } else {
        method = @"audio.get";
        long long targetOwner = (_ownerId != 0) ? _ownerId : [VKSession shared].userId;
        if (targetOwner != 0) {
            [params setObject:[NSString stringWithFormat:@"%lld", targetOwner] forKey:@"owner_id"];
        }
        [params setObject:@"1" forKey:@"need_user"];
    }

    [[VKAPI shared] callMethod:method params:params completion:^(id response, NSError *error) {
        _isLoading = NO;
        [self showLoading:NO];
        [self.refresh endRefreshing];

        if (error || !response) {
            if (self.audios.count == 0) {
                [self showMessage:error.localizedDescription ?: @"Не удалось загрузить аудиозаписи"];
            }
            return;
        }

        NSArray *parsed = [VKAudio parseAudioResponse:response];
        if (!append) {
            [self.audios removeAllObjects];
        }

        [self.audios addObjectsFromArray:parsed];
        _currentOffset = self.audios.count;
        _hasMore = (parsed.count >= kAudioPageCount);

        if (self.audios.count == 0) {
            NSString *empty = (_activeSegment == 2) ? @"По вашему запросу ничего не найдено" : @"Список аудиозаписей пуст";
            if (_activeSegment == 0 && (_ownerId == 0 || _ownerId == [VKSession shared].userId)) {
                empty = @"Здесь будут сохранённые аудиозаписи.\nОткройте «Популярное» или воспользуйтесь поиском сверху.";
            }
            [self showMessage:empty];
        } else {
            [self showMessage:nil];
        }

        [self.tableView reloadData];
    }];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.audios.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKAudioCell";
    VKAudioCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[VKAudioCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    }

    VKAudio *audio = [self.audios objectAtIndex:indexPath.row];
    audio.isAdded = (_activeSegment == 0 && (_ownerId == 0 || _ownerId == [VKSession shared].userId)) || audio.isAdded;
    cell.audio = audio;
    cell.onAddTap = ^{
        [[VKAPI shared] callMethod:@"audio.add" params:@{@"audio_id": @(audio.audioId), @"owner_id": @(audio.ownerId)} completion:^(id response, NSError *error) {
            if (!error) { audio.isAdded = YES; [self.tableView reloadData]; }
            else [[[UIAlertView alloc] initWithTitle:@"Не удалось добавить трек" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }];
    };

    __weak typeof(self) weakSelf = self;
    cell.onPlayTap = ^{
        [weakSelf playAudioAtIndex:indexPath.row];
    };

    return cell;
}

- (void)playAudioAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.audios.count) return;
    VKAudio *a = [self.audios objectAtIndex:index];
    VKAudioPlayer *player = [VKAudioPlayer shared];

    if ([player isPlayingAudio:a]) {
        [player pause];
    } else {
        [player playAudio:a inPlaylist:self.audios];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.searchBar resignFirstResponder];

    [self playAudioAtIndex:indexPath.row];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat bottomEdge = scrollView.contentOffset.y + scrollView.frame.size.height;
    if (bottomEdge >= scrollView.contentSize.height - 150.0 && scrollView.contentSize.height > 0) {
        [self loadMore];
    }
}

#pragma mark - Notification Handlers

- (void)trackDidChange:(NSNotification *)note {
    [self updateMiniPlayer];
    [self.tableView reloadData];
}

- (void)stateDidChange:(NSNotification *)note {
    [self updateMiniPlayer];
    [self.tableView reloadData];
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
