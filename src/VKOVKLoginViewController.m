#import "VKOVKLoginViewController.h"
#import "VKTheme.h"
#import "VKSession.h"
#import "VKAPI.h"
#import "VKBackend.h"
#import "VKHTTP.h"
#import <QuartzCore/QuartzCore.h>

NSString *const VKDidLoginNotification = @"VKDidLoginNotification";

static const CGFloat VKLoginMargin = 20.0f;
static const CGFloat VKLoginFieldHeight = 44.0f;

@interface VKOVKLoginViewController () <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *form;
@property (nonatomic, strong) UITapGestureRecognizer *tapDismiss;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIView *options;
@property (nonatomic, strong) UIButton *optionsButton;
@property (nonatomic, assign) BOOL optionsExpanded;
@property (nonatomic, strong) UITextField *hostField;
@property (nonatomic, strong) UITextField *loginField;
@property (nonatomic, strong) UITextField *passField;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation VKOVKLoginViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithPatternImage:[self loginBackground]];

    self.form = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.form.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.form.alwaysBounceVertical = YES;
    [self.view addSubview:self.form];

    // Тап по пустому месту — спрятать клавиатуру.
    self.tapDismiss = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapToHideKeyboard:)];
    self.tapDismiss.delegate = self;
    self.tapDismiss.cancelsTouchesInView = NO;
    [self.form addGestureRecognizer:self.tapDismiss];

    // «Карточка» с полями логина и пароля.
    self.card = [[UIView alloc] init];
    self.card.backgroundColor = [UIColor whiteColor];
    self.card.layer.cornerRadius = 4.0f;
    self.card.layer.borderWidth = 1.0f;
    self.card.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1.0].CGColor;
    [self.form addSubview:self.card];

    self.loginField = [self fieldAt:CGRectMake(14, 0, 0, VKLoginFieldHeight) placeholder:@"Логин или e-mail"];
    self.loginField.keyboardType = UIKeyboardTypeEmailAddress;
    self.loginField.returnKeyType = UIReturnKeyNext;
    self.passField = [self fieldAt:CGRectMake(14, VKLoginFieldHeight, 0, VKLoginFieldHeight) placeholder:@"Пароль"];
    self.passField.secureTextEntry = YES;
    self.passField.returnKeyType = UIReturnKeyGo;
    [self.card addSubview:self.loginField];
    [self.card addSubview:self.passField];

    UIView *divider = [[UIView alloc] initWithFrame:CGRectMake(0, VKLoginFieldHeight, 0, 1)];
    divider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    divider.backgroundColor = [UIColor colorWithWhite:0.88 alpha:1.0];
    [self.card addSubview:divider];

    // Синяя кнопка «Войти».
    self.loginButton = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *loginNormal = [[UIImage imageNamed:@"login_btn"] stretchableImageWithLeftCapWidth:12 topCapHeight:0];
    UIImage *loginPressed = [[UIImage imageNamed:@"login_btn_hl"] stretchableImageWithLeftCapWidth:12 topCapHeight:0];
    [self.loginButton setBackgroundImage:loginNormal forState:UIControlStateNormal];
    [self.loginButton setBackgroundImage:(loginPressed ?: loginNormal) forState:UIControlStateHighlighted];
    [self.loginButton setTitle:@"Войти" forState:UIControlStateNormal];
    [self.loginButton setTitle:@"Входим…" forState:UIControlStateDisabled];
    [self.loginButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.loginButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.3] forState:UIControlStateNormal];
    self.loginButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    self.loginButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.loginButton addTarget:self action:@selector(doLogin) forControlEvents:UIControlEventTouchUpInside];
    [self.form addSubview:self.loginButton];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    [self.loginButton addSubview:self.spinner];

    // Ссылка на дополнительные настройки.
    self.optionsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.optionsButton setTitle:@"Другой сервер" forState:UIControlStateNormal];
    [self.optionsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.optionsButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.optionsButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
    self.optionsButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.optionsButton addTarget:self action:@selector(toggleOptions) forControlEvents:UIControlEventTouchUpInside];
    [self.form addSubview:self.optionsButton];

    // Дополнительные настройки: поле «Сервер OpenVK».
    self.options = [[UIView alloc] init];
    self.options.backgroundColor = [UIColor clearColor];
    [self.form addSubview:self.options];
    self.hostField = [self fieldAt:CGRectMake(0, 0, 0, VKLoginFieldHeight) placeholder:@"Сервер OpenVK"];
    self.hostField.text = [VKBackend shared].ovkHost;
    self.hostField.keyboardType = UIKeyboardTypeURL;
    self.hostField.returnKeyType = UIReturnKeyGo;
    UIImage *fieldBg = [[UIImage imageNamed:@"new_login_field"] stretchableImageWithLeftCapWidth:8 topCapHeight:0];
    self.hostField.background = fieldBg;
    [self.options addSubview:self.hostField];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor colorWithRed:0.55 green:0.18 blue:0.16 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.statusLabel setShadowColor:[UIColor whiteColor]];
    [self.statusLabel setShadowOffset:CGSizeMake(0, 1)];
    [self.form addSubview:self.statusLabel];
}

// Тайловый фон входа: на ретине берём @2x-версию.
- (UIImage *)loginBackground {
    NSString *name = ([[UIScreen mainScreen] scale] > 1.0) ? @"login_background@2x" : @"login_background";
    return [UIImage imageNamed:name] ?: [UIImage imageNamed:@"login_background"];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat w = W - VKLoginMargin * 2;
    CGFloat x = VKLoginMargin;

    // Основной блок: карточка (88) + отступ + кнопка (46). Центрируем чуть выше середины.
    const CGFloat cardH = VKLoginFieldHeight * 2;
    const CGFloat buttonH = 46.0f;
    CGFloat coreTop = (H - (cardH + 12 + buttonH)) / 2.0f - 8.0f;
    if (coreTop < 30.0f) coreTop = 30.0f;

    self.card.frame = CGRectMake(x, coreTop, w, cardH);
    for (UITextField *field in @[self.loginField, self.passField]) {
        CGRect f = field.frame;
        f.size.width = w - 28;
        field.frame = f;
    }

    self.loginButton.frame = CGRectMake(x, coreTop + cardH + 12, w, buttonH);
    self.spinner.center = CGPointMake(26, buttonH / 2.0f);

    self.optionsButton.frame = CGRectMake(x, coreTop + cardH + 12 + buttonH + 10, w, 36);
    self.options.hidden = !self.optionsExpanded;
    self.options.frame = CGRectMake(x, coreTop + cardH + 12 + buttonH + 52, w, VKLoginFieldHeight);
    self.hostField.frame = CGRectMake(0, 0, w, VKLoginFieldHeight);

    CGFloat bottom = self.optionsButton.frame.origin.y + 36 + (self.optionsExpanded ? VKLoginFieldHeight : 0);
    self.statusLabel.frame = CGRectMake(x, bottom + 6, w, 60);
    self.form.contentSize = CGSizeMake(W, bottom + 90);
}

#pragma mark - Тап по пустому месту

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.tapDismiss) {
        CGPoint p = [gestureRecognizer locationInView:self.form];
        UIView *hit = [self.form hitTest:p withEvent:nil];
        while (hit && hit != self.form) {
            if ([hit isKindOfClass:[UIControl class]] || [hit isKindOfClass:[UITextField class]] || hit == self.statusLabel) return NO;
            hit = hit.superview;
        }
    }
    return YES;
}

- (void)tapToHideKeyboard:(UITapGestureRecognizer *)gestureRecognizer {
    [self.view endEditing:YES];
}

#pragma mark - UI helpers

- (void)endInput { [self.view endEditing:YES]; }

- (void)toggleOptions {
    [self endInput];
    self.optionsExpanded = !self.optionsExpanded;
    [self.optionsButton setTitle:self.optionsExpanded ? @"Скрыть сервер" : @"Другой сервер" forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect keyboard = [self.view convertRect:[[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboard));
    self.form.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.form.scrollIndicatorInsets = self.form.contentInset;
    for (UITextField *field in @[self.hostField, self.loginField, self.passField]) {
        if (field.isFirstResponder) [self.form scrollRectToVisible:CGRectInset([field.superview convertRect:field.frame toView:self.form], 0, -12) animated:YES];
    }
}

- (UITextField *)fieldAt:(CGRect)f placeholder:(NSString *)ph {
    UITextField *t = [[UITextField alloc] initWithFrame:f];
    t.borderStyle = UITextBorderStyleNone;
    t.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    t.clearButtonMode = UITextFieldViewModeWhileEditing;
    t.placeholder = ph;
    t.font = [UIFont systemFontOfSize:15.0];
    t.autocorrectionType = UITextAutocorrectionTypeNo;
    t.autocapitalizationType = UITextAutocapitalizationTypeNone;
    t.delegate = self;
    return t;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.loginField) [self.passField becomeFirstResponder];
    else [self doLogin];
    return NO;
}

#pragma mark - Вход (password grant)

- (void)doLogin {
    if (!self.loginButton.enabled) return;
    NSString *login = [self.loginField.text stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceCharacterSet]];
    NSString *pass = self.passField.text;
    if (login.length < 1 || pass.length < 1) {
        self.statusLabel.text = @"Введите логин и пароль"; return;
    }
    [self.view endEditing:YES];
    NSString *host = [self.hostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([host rangeOfString:@"://"].location == NSNotFound) host = [@"https://" stringByAppendingString:host];
    NSURL *instance = [NSURL URLWithString:host];
    if (![[instance scheme] isEqualToString:@"https"] || !instance.host.length || instance.user || instance.password || instance.query || instance.fragment || (instance.path.length && ![instance.path isEqualToString:@"/"])) {
        self.statusLabel.text = @"Введите HTTPS-адрес сервера без пути и параметров"; return;
    }
    [VKBackend shared].ovkHost = host;   // сеттер нормализует хост
    self.hostField.text = [VKBackend shared].ovkHost;

    NSString *urlStr = [[VKBackend shared] tokenURLWithUsername:login password:pass code:@""];
    NSURL *tokenURL = [NSURL URLWithString:urlStr];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@/token", [VKBackend shared].ovkHost]];
    if (!url) { self.statusLabel.text = @"Некорректный адрес инстанса"; return; }

    self.statusLabel.text = @""; self.loginButton.enabled = NO; [self.spinner startAnimating];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    req.HTTPMethod = @"POST";
    req.HTTPBody = [[tokenURL query] dataUsingEncoding:NSUTF8StringEncoding];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"OpenVKiOS6/1.0" forHTTPHeaderField:@"User-Agent"];

    [VKHTTP sendRequest:req completion:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleTokenData:data error:err];
        });
    }];
}

- (void)handleTokenData:(NSData *)data error:(NSError *)err {
    if (err || !data) {
        [self failWith:err.localizedDescription ?: @"Сервер не ответил"];
        return;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        [self failWith:@"Некорректный ответ инстанса"];
        return;
    }
    NSDictionary *d = (NSDictionary *)json;
    NSString *token = [d objectForKey:@"access_token"];
    if (![token isKindOfClass:[NSString class]] || token.length == 0) {
        [self failWith:[self messageFromError:d]];
        return;
    }
    long long uid = [[d objectForKey:@"user_id"] longLongValue];
    [self finishWithToken:token userId:uid];
}

// OpenVK отвечает то error_msg, то oauth-подобным error/error_description.
- (NSString *)messageFromError:(NSDictionary *)d {
    if ([[d objectForKey:@"error"] isKindOfClass:[NSDictionary class]]) return [self messageFromError:[d objectForKey:@"error"]];
    id msg = [d objectForKey:@"error_msg"];
    if (![msg isKindOfClass:[NSString class]]) msg = [d objectForKey:@"error_description"];
    if (![msg isKindOfClass:[NSString class]]) msg = [d objectForKey:@"error"];
    if ([msg isKindOfClass:[NSString class]] && [(NSString *)msg length]) return msg;
    return @"Неверный логин или пароль";
}

- (void)failWith:(NSString *)message {
    [self.spinner stopAnimating];
    self.loginButton.enabled = YES;
    self.statusLabel.text = message;
}

- (void)finishWithToken:(NSString *)token userId:(long long)userId {
    VKSession *s = [VKSession shared];
    [s clear];
    self.passField.text = @"";
    s.accessToken = token;
    s.messagesToken = nil;   // в OpenVK один токен на все методы
    s.userId = userId;
    [s save];

    // Профиль подтягиваем тем же users.get — API OpenVK повторяет ВК.
    [[VKAPI shared] callMethod:@"users.get" params:@{@"fields": @"photo_100"}
                    completion:^(id response, NSError *error) {
        [self.spinner stopAnimating];
        self.loginButton.enabled = YES;
        if ([response isKindOfClass:[NSArray class]] && [response count]) {
            [self applyUser:[response objectAtIndex:0]];
        }
        [[VKSession shared] save];
        [[NSNotificationCenter defaultCenter] postNotificationName:VKDidLoginNotification
                                                            object:nil];
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
}

- (void)applyUser:(NSDictionary *)user {
    if (![user isKindOfClass:[NSDictionary class]]) return;
    VKSession *s = [VKSession shared];
    long long uid = [[user objectForKey:@"id"] longLongValue];
    if (uid == 0) uid = [[user objectForKey:@"uid"] longLongValue];
    if (uid != 0) s.userId = uid;
    NSString *name = [NSString stringWithFormat:@"%@ %@",
                      [user objectForKey:@"first_name"] ?: @"",
                      [user objectForKey:@"last_name"] ?: @""];
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (name.length) s.userName = name;
    id photo = [user objectForKey:@"photo_100"];
    if (![photo isKindOfClass:[NSString class]]) photo = [user objectForKey:@"photo_50"];
    if (![photo isKindOfClass:[NSString class]]) photo = [user objectForKey:@"photo"];
    if ([photo isKindOfClass:[NSString class]] && [(NSString *)photo length]) s.userPhoto = photo;
}

@end