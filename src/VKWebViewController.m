#import "VKWebViewController.h"
#import "VKTheme.h"

@interface VKWebViewController () <UIWebViewDelegate>
@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) UIWebView *webView;
@end

@implementation VKWebViewController

- (id)initWithTitle:(NSString *)title URL:(NSURL *)URL {
    if ((self = [super init])) { _pageTitle = [title copy]; _URL = URL; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.pageTitle;
    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    self.webView.scalesPageToFit = YES;
    self.webView.backgroundColor = [VKTheme contentBackgroundColor];
    [self.view addSubview:self.webView];
    [self showLoading:YES];
    if (self.URL) [self.webView loadRequest:[NSURLRequest requestWithURL:self.URL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:30.0]];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView { [self showLoading:NO]; }
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    [self showLoading:NO];
    if (error.code != NSURLErrorCancelled) [self showMessage:error.localizedDescription ?: @"Не удалось открыть страницу"];
}

@end
