#import "VKNotesViewController.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKTheme.h"

@interface VKNoteDetailViewController : UIViewController
@property (nonatomic, strong) NSDictionary *note;
@end

@implementation VKNoteDetailViewController
- (id)initWithNote:(NSDictionary *)note { if ((self = [super init])) _note = note; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.note objectForKey:@"title"] ?: @"Заметка";
    self.view.backgroundColor = [VKTheme contentBackgroundColor];
    UIWebView *web = [[UIWebView alloc] initWithFrame:self.view.bounds];
    web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    web.backgroundColor = [VKTheme cardColor]; web.opaque = NO;
    NSString *body = [self.note objectForKey:@"text"] ?: [self.note objectForKey:@"body"] ?: @"";
    NSString *html = [NSString stringWithFormat:@"<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{font-family:-apple-system,Helvetica,sans-serif;font-size:16px;line-height:1.45;margin:16px;color:#222}img{max-width:100%%;height:auto}a{color:#2c5989}</style></head><body>%@</body></html>", body];
    [web loadHTMLString:html baseURL:[NSURL URLWithString:@"https://openvk.org/"]];
    [self.view addSubview:web];
}
@end

@interface VKNoteComposeViewController : UIViewController
@property (nonatomic, strong) UITextField *titleField;
@property (nonatomic, strong) UITextView *bodyView;
@property (nonatomic, strong) UISegmentedControl *privacy;
@property (nonatomic, copy) void (^saved)(void);
@end
@implementation VKNoteComposeViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Новая заметка"; self.view.backgroundColor = [VKTheme contentBackgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Сохранить" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
    self.titleField = [[UITextField alloc] initWithFrame:CGRectMake(10, 10, self.view.bounds.size.width - 20, 42)];
    self.titleField.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.titleField.borderStyle = UITextBorderStyleRoundedRect; self.titleField.placeholder = @"Название";
    [self.view addSubview:self.titleField];
    self.privacy = [[UISegmentedControl alloc] initWithItems:@[@"Все", @"Друзья", @"Только я"]];
    self.privacy.frame = CGRectMake(10, 60, self.view.bounds.size.width - 20, 30); self.privacy.autoresizingMask = UIViewAutoresizingFlexibleWidth; self.privacy.selectedSegmentIndex = 0; self.privacy.segmentedControlStyle = UISegmentedControlStyleBar; self.privacy.tintColor = [VKTheme navBarColor]; [self.view addSubview:self.privacy];
    self.bodyView = [[UITextView alloc] initWithFrame:CGRectMake(10, 100, self.view.bounds.size.width - 20, self.view.bounds.size.height - 110)];
    self.bodyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; self.bodyView.font = [UIFont systemFontOfSize:15]; self.bodyView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.bodyView]; [self.titleField becomeFirstResponder];
}
- (void)save {
    NSString *title = [self.titleField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *body = [self.bodyView.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!title.length || !body.length) { [[[UIAlertView alloc] initWithTitle:@"Заметка" message:@"Заполните название и текст" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return; }
    self.navigationItem.rightBarButtonItem.enabled = NO;
    NSArray *values = @[@0, @1, @3]; NSNumber *privacy = [values objectAtIndex:self.privacy.selectedSegmentIndex];
    [[VKAPI shared] callMethod:@"notes.add" params:@{@"title": title, @"text": body, @"privacy": privacy, @"comment_privacy": privacy} completion:^(id response, NSError *error) {
        self.navigationItem.rightBarButtonItem.enabled = YES;
        if (error) { [[[UIAlertView alloc] initWithTitle:@"Не удалось сохранить" message:error.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return; }
        if (self.saved) self.saved(); [self.navigationController popViewControllerAnimated:YES];
    }];
}
@end

@interface VKNotesViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) NSArray *notes;
@end

@implementation VKNotesViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Мои заметки";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNote)];
    self.notes = @[];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.tableView];
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refresh];
    [self reload];
}
- (void)addNote { VKNoteComposeViewController *compose = [VKNoteComposeViewController new]; __weak typeof(self) weakSelf = self; compose.saved = ^{ [weakSelf reload]; }; [self.navigationController pushViewController:compose animated:YES]; }
- (void)reload {
    if (![VKSession shared].isAuthorized) { [self showMessage:@"Войдите, чтобы смотреть заметки"]; return; }
    [self showLoading:self.notes.count == 0];
    [[VKAPI shared] callMethod:@"notes.get" params:@{@"user_id": @([VKSession shared].userId), @"count": @100, @"sort": @0} completion:^(id response, NSError *error) {
        [self showLoading:NO]; [self.refresh endRefreshing];
        NSArray *items = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"items"] : response;
        if (error || ![items isKindOfClass:[NSArray class]]) { [self showMessage:error.localizedDescription ?: @"Не удалось загрузить заметки"]; return; }
        self.notes = items; [self.tableView reloadData];
        [self showMessage:self.notes.count ? nil : @"У вас пока нет заметок"];
    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.notes.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Note"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Note"];
    NSDictionary *note = [self.notes objectAtIndex:indexPath.row];
    cell.textLabel.text = [note objectForKey:@"title"] ?: @"Без названия";
    NSString *body = [note objectForKey:@"text"] ?: [note objectForKey:@"body"] ?: @"";
    cell.detailTextLabel.text = [body stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:[[VKNoteDetailViewController alloc] initWithNote:[self.notes objectAtIndex:indexPath.row]] animated:YES];
}
@end
