#import "VKInstancesViewController.h"
#import "VKInstanceManager.h"
#import "VKBackend.h"
#import "VKSession.h"
#import "VKSettings.h"
#import "VKHTTP.h"
#import "VKTheme.h"

static NSString *VKEscape(NSString *s) {
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)(s ?: @""), NULL, CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8));
}

@interface VKAddInstanceViewController : UITableViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSArray *fields;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation VKAddInstanceViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Новый инстанс"; self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *placeholder in @[@"Название, например VepurOVK", @"Сервер, например api.vepurovk.ru", @"Логин или e-mail", @"Пароль", @"Код подтверждения (необязательно)"]) {
        UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(15, 0, 270, 44)];
        f.autoresizingMask = UIViewAutoresizingFlexibleWidth; f.placeholder = placeholder; f.delegate = self;
        f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        [fields addObject:f];
    }
    ((UITextField *)[fields objectAtIndex:1]).keyboardType = UIKeyboardTypeURL;
    ((UITextField *)[fields objectAtIndex:2]).keyboardType = UIKeyboardTypeEmailAddress;
    ((UITextField *)[fields objectAtIndex:3]).secureTextEntry = YES;
    ((UITextField *)[fields objectAtIndex:4]).keyboardType = UIKeyboardTypeNumberPad;
    self.fields = fields;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Добавить" style:UIBarButtonItemStyleDone target:self action:@selector(addInstance)];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? self.fields.count : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return section == 0 ? @"Пароль используется только для получения токена и не сохраняется." : nil; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"InstanceField"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"InstanceField"];
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];
    if (indexPath.section == 0) [cell.contentView addSubview:[self.fields objectAtIndex:indexPath.row]];
    else { cell.textLabel.text = @"Можно добавить до пяти инстансов"; cell.textLabel.textColor = [VKTheme secondaryTextColor]; cell.textLabel.textAlignment = NSTextAlignmentCenter; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
    return cell;
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField { NSUInteger i = [self.fields indexOfObject:textField]; if (i + 1 < self.fields.count) [[self.fields objectAtIndex:i + 1] becomeFirstResponder]; else [self addInstance]; return NO; }
- (void)addInstance {
    NSString *name = [[self.fields objectAtIndex:0] text], *host = [[[self.fields objectAtIndex:1] text] lowercaseString];
    NSString *login = [[self.fields objectAtIndex:2] text], *pass = [[self.fields objectAtIndex:3] text], *code = [[self.fields objectAtIndex:4] text];
    host = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([host hasPrefix:@"https://"]) host = [host substringFromIndex:8];
    while ([host hasSuffix:@"/"]) host = [host substringToIndex:host.length - 1];
    if (!name.length || !host.length || !login.length || !pass.length) { [self alert:@"Заполните название, сервер, логин и пароль"]; return; }
    if ([[VKInstanceManager shared] instances].count >= 5) { [self alert:@"Можно сохранить не больше пяти дополнительных аккаунтов"]; return; }
    [self.view endEditing:YES]; self.navigationItem.rightBarButtonItem.enabled = NO; self.navigationItem.titleView = self.spinner; [self.spinner startAnimating];
    NSString *client = [VKSettings shared].postAsAndroid ? @"Latte for Android" : @"Latte for Apple";
    NSString *body = [NSString stringWithFormat:@"grant_type=password&username=%@&password=%@&client_name=%@%@", VKEscape(login), VKEscape(pass), VKEscape(client), code.length ? [NSString stringWithFormat:@"&code=%@", VKEscape(code)] : @""];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/token", host]]];
    request.HTTPMethod = @"POST"; request.timeoutInterval = 25; request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [VKHTTP sendRequest:request completion:^(NSData *data, NSURLResponse *response, NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{
        [self.spinner stopAnimating]; self.navigationItem.titleView = nil; self.navigationItem.rightBarButtonItem.enabled = YES;
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil; NSString *token = [json objectForKey:@"access_token"];
        if (error || !token.length) { [self alert:error.localizedDescription ?: [json objectForKey:@"error_description"] ?: [json objectForKey:@"error_msg"] ?: @"Не удалось войти на этот инстанс"]; return; }
        if (![[VKInstanceManager shared] addName:name host:host]) { [self alert:@"Не удалось сохранить инстанс"]; return; }
        [VKBackend shared].ovkHost = host; VKSession *s = [VKSession shared]; [s clear]; s.accessToken = token; s.userId = [[json objectForKey:@"user_id"] longLongValue]; [s save];
        [[NSNotificationCenter defaultCenter] postNotificationName:VKBackendDidChangeNotification object:nil];
    }); }];
}
- (void)alert:(NSString *)text { [[[UIAlertView alloc] initWithTitle:@"Инстанс" message:text delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; }
@end

@implementation VKInstancesViewController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Инстансы"; self.tableView.backgroundColor = [VKTheme contentBackgroundColor]; self.navigationItem.rightBarButtonItem = self.editButtonItem; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload:) name:VKInstancesDidChangeNotification object:nil]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (NSArray *)rows { NSMutableArray *a = [NSMutableArray arrayWithObject:@{@"name": @"OpenVK", @"host": VKBackendDefaultOVKHost}]; [a addObjectsFromArray:[[VKInstanceManager shared] instances]]; return a; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self rows].count + 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Нажмите «Изменить», чтобы удалить добавленный инстанс. Пароли не сохраняются."; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Instance"]; if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Instance"]; NSArray *rows = [self rows]; cell.textLabel.textColor = [VKTheme primaryTextColor]; cell.detailTextLabel.text = nil; cell.accessoryType = UITableViewCellAccessoryNone; if (indexPath.row == rows.count) { cell.textLabel.text = @"Добавить инстанс"; cell.textLabel.textColor = [VKTheme linkColor]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; } else { NSDictionary *d = [rows objectAtIndex:indexPath.row]; cell.textLabel.text = [d objectForKey:@"name"]; cell.detailTextLabel.text = [d objectForKey:@"host"]; cell.accessoryType = [[[d objectForKey:@"host"] lowercaseString] isEqualToString:[VKBackend shared].ovkHost] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone; } return cell; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.row > 0 && indexPath.row < [self rows].count; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath { if (style == UITableViewCellEditingStyleDelete) [[VKInstanceManager shared] removeHost:[[[self rows] objectAtIndex:indexPath.row] objectForKey:@"host"]]; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSArray *rows = [self rows]; if (indexPath.row == rows.count) { [self addTapped]; return; } NSDictionary *d = [rows objectAtIndex:indexPath.row]; [VKBackend shared].ovkHost = [d objectForKey:@"host"]; [[NSNotificationCenter defaultCenter] postNotificationName:VKBackendDidChangeNotification object:nil]; [tableView reloadData]; }
- (void)addTapped { if ([[VKInstanceManager shared] instances].count >= 5) { [[[UIAlertView alloc] initWithTitle:@"Инстансы" message:@"Уже сохранено пять дополнительных аккаунтов" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show]; return; } [self.navigationController pushViewController:[VKAddInstanceViewController new] animated:YES]; }
- (void)reload:(NSNotification *)note { [self.tableView reloadData]; }
@end
