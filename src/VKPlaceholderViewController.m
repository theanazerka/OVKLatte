#import "VKPlaceholderViewController.h"
#import "VKTheme.h"

@interface VKPlaceholderViewController ()
@property (nonatomic, copy) NSString *glyph;
@end

@implementation VKPlaceholderViewController

- (id)initWithTitle:(NSString *)title glyph:(NSString *)glyph {
    self = [super init];
    if (self) {
        self.title = title;
        _glyph = [glyph copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self showMessage:[self.title isEqualToString:@"Закладки"] ? @"Закладки пока недоступны.\nЭтот раздел появится после поддержки в OpenVK." : @"Этот раздел пока недоступен."];
}
@end
