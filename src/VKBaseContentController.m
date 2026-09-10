#import "VKBaseContentController.h"
#import "VKTheme.h"
#import <APLSlideMenuViewController.h>

@interface VKBaseContentController ()
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIImageView *emptyIcon;
@end

@implementation VKBaseContentController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [VKTheme contentBackgroundColor];
    [self installMenuButton];
}

- (void)installMenuButton {
    if (self.navigationController.viewControllers.count > 1) { self.navigationItem.leftBarButtonItem = nil; return; }
    // Оригинальная иконка меню ВК (menu_icon), с фолбэком на нарисованную.
    UIImage *icon = [UIImage imageNamed:@"menu_icon"];
    if (!icon) {
        icon = [VKTheme hamburgerIconWithColor:[UIColor whiteColor]];
    }
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:icon
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(toggleMenu)];
    self.navigationItem.leftBarButtonItem = item;
}

- (void)toggleMenu {
    [[self slideMenuController] switchLeftMenu:YES];
}

- (void)showLoading:(BOOL)show {
    if (!self.spinner) {
        self.spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.spinner.hidesWhenStopped = YES;
        self.spinner.center = CGPointMake(self.view.bounds.size.width / 2.0,
                                          self.view.bounds.size.height / 2.0);
        self.spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                                        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self.view addSubview:self.spinner];
    }
    if (show) { [self showMessage:nil]; [self.spinner startAnimating]; }
    else { [self.spinner stopAnimating]; }
    [self.view bringSubviewToFront:self.spinner];
}

- (void)showMessage:(NSString *)message {
    if (!message) { self.messageLabel.hidden = YES; self.emptyIcon.hidden = YES; return; }
    if (!self.messageLabel) {
        self.messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(28, MAX(100, self.view.bounds.size.height * 0.42), self.view.bounds.size.width - 56, 100)];
        self.messageLabel.backgroundColor = [UIColor clearColor];
        self.messageLabel.numberOfLines = 0;
        self.messageLabel.textAlignment = NSTextAlignmentCenter;
        self.messageLabel.font = [UIFont systemFontOfSize:14.0];
        self.messageLabel.textColor = [VKTheme secondaryTextColor];
        self.messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self.view addSubview:self.messageLabel];
    }
    if (!self.emptyIcon) {
        NSString *name = @"placeholder_newsfeed";
        NSString *type = NSStringFromClass([self class]);
        if ([type rangeOfString:@"Audio"].location != NSNotFound) name = @"placeholder_audio";
        else if ([type rangeOfString:@"Video"].location != NSNotFound) name = @"placeholder_videos";
        else if ([type rangeOfString:@"Search"].location != NSNotFound) name = @"placeholder_friends";
        else if ([self.title isEqualToString:@"Группы"]) name = @"placeholder_groups";
        else if ([self.title isEqualToString:@"Фотографии"] || [self.title isEqualToString:@"Альбомы"]) name = @"placeholder_photos_dark";
        else if ([self.title isEqualToString:@"Закладки"]) name = @"placeholder_favorites_dark";
        self.emptyIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:name]];
        self.emptyIcon.contentMode = UIViewContentModeScaleAspectFit;
        self.emptyIcon.frame = CGRectMake((self.view.bounds.size.width - 72) / 2, self.messageLabel.frame.origin.y - 76, 72, 64);
        self.emptyIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [self.view addSubview:self.emptyIcon];
    }
    self.emptyIcon.hidden = NO;
    [self.view bringSubviewToFront:self.emptyIcon];
    self.messageLabel.text = message;
    self.messageLabel.hidden = NO;
    [self.view bringSubviewToFront:self.messageLabel];
}

@end
