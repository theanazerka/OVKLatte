#import "VKPhotoViewController.h"
#import "VKImageLoader.h"

@interface VKPhotoViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImage *initialImage;
@property (nonatomic, copy) NSString *url;
@end

@implementation VKPhotoViewController

- (id)initWithImage:(UIImage *)image url:(NSString *)url {
    self = [super init];
    if (self) {
        _initialImage = image;
        _url = [url copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.delegate = self;
    self.scroll.minimumZoomScale = 1.0;
    self.scroll.maximumZoomScale = 4.0;
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:self.scroll];

    self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.image = self.initialImage;
    [self.scroll addSubview:self.imageView];

    // Закрытие по тапу, зум по двойному тапу.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    tap.numberOfTapsRequired = 1;
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [tap requireGestureRecognizerToFail:dbl];
    [self.view addGestureRecognizer:tap];
    [self.view addGestureRecognizer:dbl];

    // Кнопка закрытия.
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(self.view.bounds.size.width - 54, 24, 40, 40);
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [closeBtn setTitle:@"\u2715" forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:closeBtn];

    // Догружаем полноразмерную версию, если есть URL.
    if (self.url.length) {
        [[VKImageLoader shared] loadURL:self.url completion:^(UIImage *image) {
            if (image) self.imageView.image = image;
        }];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)doubleTap:(UITapGestureRecognizer *)g {
    if (self.scroll.zoomScale > 1.0) {
        [self.scroll setZoomScale:1.0 animated:YES];
    } else {
        [self.scroll setZoomScale:2.5 animated:YES];
    }
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)prefersStatusBarHidden { return YES; }

@end
