#import "VKWallPostViewController.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "VKSession.h"
#import "VKUploader.h"
#import <QuartzCore/QuartzCore.h>

NSString *const VKWallDidPostNotification = @"VKWallDidPostNotification";

static const CGFloat kThumbSide = 72.0;
static const CGFloat kRowHeight = 33.0;

@interface VKWallPostViewController () <UITextViewDelegate, UIActionSheetDelegate,
                                        UIImagePickerControllerDelegate, UINavigationControllerDelegate> {
    long long _ownerId;
    BOOL _photoMode;
    BOOL _askedForPhoto;
    BOOL _sending;
}
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholder;
@property (nonatomic, strong) UIImageView *thumb;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *attachButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImage *photo;
@end

@implementation VKWallPostViewController

- (id)initWithOwnerId:(long long)ownerId photoMode:(BOOL)photoMode {
    self = [super init];
    if (self) {
        _ownerId = ownerId;
        _photoMode = photoMode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _photoMode ? @"Новая фотография" : @"Новая запись";
    self.view.backgroundColor = [VKTheme contentBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Отмена" style:UIBarButtonItemStyleBordered
               target:self action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Отправить" style:UIBarButtonItemStyleDone
               target:self action:@selector(sendTapped)];

    CGFloat W = self.view.bounds.size.width;

    self.attachButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.attachButton setBackgroundImage:
        [[UIImage imageNamed:@"wall_gray_btn"] stretchableImageWithLeftCapWidth:7 topCapHeight:0]
        forState:UIControlStateNormal];
    [self.attachButton setBackgroundImage:
        [[UIImage imageNamed:@"wall_gray_btn_hl"] stretchableImageWithLeftCapWidth:7 topCapHeight:0]
        forState:UIControlStateHighlighted];
    [self.attachButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.attachButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    self.attachButton.titleLabel.shadowOffset = CGSizeMake(0.0, -1.0);
    [self.attachButton addTarget:self action:@selector(attachTapped)
                forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.attachButton];

    self.thumb = [[UIImageView alloc] initWithFrame:CGRectMake(8.0, 8.0, kThumbSide, kThumbSide)];
    self.thumb.contentMode = UIViewContentModeScaleAspectFill;
    self.thumb.clipsToBounds = YES;
    self.thumb.layer.cornerRadius = 3.0;
    self.thumb.layer.borderWidth = 1.0;
    self.thumb.layer.borderColor = [UIColor colorWithWhite:0.72 alpha:1.0].CGColor;
    self.thumb.hidden = YES;
    [self.view addSubview:self.thumb];

    self.deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.deleteButton setTitle:@"×" forState:UIControlStateNormal];
    self.deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:20.0];
    [self.deleteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.deleteButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    self.deleteButton.layer.cornerRadius = 11.0;
    self.deleteButton.hidden = YES;
    [self.deleteButton addTarget:self action:@selector(removePhoto)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.deleteButton];

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8.0, 49.0, W - 16.0, 130.0)];
    self.textView.font = [UIFont systemFontOfSize:15.0];
    self.textView.backgroundColor = [UIColor whiteColor];
    self.textView.delegate = self;
    self.textView.layer.cornerRadius = 4.0;
    self.textView.layer.borderWidth = 1.0;
    self.textView.layer.borderColor = [UIColor colorWithWhite:0.78 alpha:1.0].CGColor;
    [self.view addSubview:self.textView];

    self.placeholder = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, W - 40.0, 20.0)];
    self.placeholder.text = _photoMode ? @"Подпись к фотографии" : @"Что у вас нового?";
    self.placeholder.font = [UIFont systemFontOfSize:15.0];
    self.placeholder.textColor = [VKTheme secondaryTextColor];
    self.placeholder.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.placeholder];

    [self layoutContent];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_photoMode && !_askedForPhoto) {
        _askedForPhoto = YES;
        [self attachTapped];
    } else if (!_photoMode) {
        [self.textView becomeFirstResponder];
    }
}

// Раскладка зависит от того, прикреплено ли фото.
- (void)layoutContent {
    CGFloat W = self.view.bounds.size.width;
    BOOL has = (self.photo != nil);
    self.thumb.hidden = !has;
    self.deleteButton.hidden = !has;
    self.thumb.image = self.photo;
    [self.attachButton setTitle:(has ? @"Заменить фотографию" : @"Прикрепить фотографию")
                       forState:UIControlStateNormal];

    if (has) {
        self.thumb.frame = CGRectMake(8.0, 8.0, kThumbSide, kThumbSide);
        self.deleteButton.frame = CGRectMake(8.0 + kThumbSide - 16.0, 2.0, 22.0, 22.0);
        self.attachButton.frame = CGRectMake(8.0 + kThumbSide + 8.0, 8.0 + (kThumbSide - kRowHeight) / 2.0,
                                            W - 16.0 - kThumbSide - 8.0, kRowHeight);
    } else {
        self.attachButton.frame = CGRectMake(8.0, 8.0, W - 16.0, kRowHeight);
    }
    CGFloat top = has ? (8.0 + kThumbSide + 8.0) : (8.0 + kRowHeight + 8.0);
    self.textView.frame = CGRectMake(8.0, top, W - 16.0, 130.0);
    self.placeholder.frame = CGRectMake(14.0, top + 8.0, W - 44.0, 20.0);
    self.placeholder.hidden = (self.textView.text.length > 0);
}

- (void)textViewDidChange:(UITextView *)textView {
    self.placeholder.hidden = (textView.text.length > 0);
}

#pragma mark - Выбор фотографии

- (void)attachTapped {
    [self.textView resignFirstResponder];
    BOOL camera = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Фотография"
                                                      delegate:self
                                             cancelButtonTitle:nil
                                        destructiveButtonTitle:nil
                                             otherButtonTitles:nil];
    if (camera) [sheet addButtonWithTitle:@"Сделать снимок"];
    [sheet addButtonWithTitle:@"Выбрать из галереи"];
    if (self.photo) [sheet addButtonWithTitle:@"Удалить фотографию"];
    [sheet addButtonWithTitle:@"Отмена"];
    sheet.cancelButtonIndex = sheet.numberOfButtons - 1;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
    NSString *title = [sheet buttonTitleAtIndex:index];
    if ([title isEqualToString:@"Сделать снимок"]) {
        [self pickFromSource:UIImagePickerControllerSourceTypeCamera];
    } else if ([title isEqualToString:@"Выбрать из галереи"]) {
        [self pickFromSource:UIImagePickerControllerSourceTypePhotoLibrary];
    } else if ([title isEqualToString:@"Удалить фотографию"]) {
        [self removePhoto];
    } else if (_photoMode && !self.photo) {
        // Отменили выбор в режиме «загрузить фото» — уходим с экрана.
        [self closeScreen];
    }
}

- (void)pickFromSource:(UIImagePickerControllerSourceType)source {
    if (![UIImagePickerController isSourceTypeAvailable:source]) {
        source = UIImagePickerControllerSourceTypePhotoLibrary;
    }
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = source;
    picker.delegate = self;
    picker.allowsEditing = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *image = [info objectForKey:UIImagePickerControllerEditedImage];
    if (![image isKindOfClass:[UIImage class]]) {
        image = [info objectForKey:UIImagePickerControllerOriginalImage];
    }
    if ([image isKindOfClass:[UIImage class]]) self.photo = image;
    [self dismissViewControllerAnimated:YES completion:^{
        [self layoutContent];
        [self.textView becomeFirstResponder];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:^{
        if (_photoMode && !self.photo) [self closeScreen];
    }];
}

- (void)removePhoto {
    self.photo = nil;
    [self layoutContent];
}

#pragma mark - Отправка

- (void)setSending:(BOOL)sending {
    _sending = sending;
    self.navigationItem.rightBarButtonItem.enabled = !sending;
    self.textView.editable = !sending;
    if (sending) {
        if (!self.spinner) {
            self.spinner = [[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            self.spinner.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
            self.spinner.frame = self.view.bounds;
            self.spinner.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.view addSubview:self.spinner];
        }
        [self.view bringSubviewToFront:self.spinner];
        [self.spinner startAnimating];
        [self.textView resignFirstResponder];
    } else {
        [self.spinner stopAnimating];
        self.spinner.hidden = YES;
    }
    self.spinner.hidden = !sending;
}

- (void)sendTapped {
    if (_sending) return;
    NSString *text = [self.textView.text stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length && !self.photo) {
        [self alert:@"Новая запись" message:@"Напишите текст или прикрепите фотографию."];
        return;
    }
    [self setSending:YES];
    if (self.photo) {
        [VKUploader uploadWallPhoto:self.photo ownerId:_ownerId
                         completion:^(NSString *attachment, NSError *error) {
            if (!attachment) {
                [self setSending:NO];
                [self alert:@"Фотография" message:error.localizedDescription
                    ?: @"Не удалось загрузить фотографию"];
                return;
            }
            [self postMessage:text attachments:attachment];
        }];
    } else {
        [self postMessage:text attachments:nil];
    }
}

- (void)postMessage:(NSString *)text attachments:(NSString *)attachments {
    long long owner = _ownerId != 0 ? _ownerId : [VKSession shared].userId;
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (owner != 0) [params setObject:[NSString stringWithFormat:@"%lld", owner] forKey:@"owner_id"];
    if (text.length) [params setObject:text forKey:@"message"];
    if (attachments.length) [params setObject:attachments forKey:@"attachments"];
    if (owner < 0) [params setObject:@"1" forKey:@"from_group"];

    [[VKAPI shared] callMethod:@"wall.post" params:params completion:^(id response, NSError *error) {
        [self setSending:NO];
        if (error) {
            [self alert:@"Запись" message:error.localizedDescription ?: @"Не удалось опубликовать запись"];
            return;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:VKWallDidPostNotification object:nil];
        [self closeScreen];
    }];
}

- (void)cancelTapped {
    [self.textView resignFirstResponder];
    [self closeScreen];
}

// Экран открывают и пушем (из профиля), и модально (из сайдбара).
- (void)closeScreen {
    if (self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController.presentingViewController
            dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertView *a = [[UIAlertView alloc] initWithTitle:title message:message
                        delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [a show];
}

@end
