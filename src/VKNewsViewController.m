#import "VKNewsViewController.h"
#import "VKPostCell.h"
#import "VKTheme.h"
#import "VKAPI.h"
#import "OVKAPICompatibility.h"
#import "VKBackend.h"
#import "VKSession.h"
#import "VKSettings.h"
#import "VKPhotoViewController.h"
#import "VKProfileViewController.h"
#import "VKLikes.h"
#import "VKCommentsViewController.h"
#import "VKAudio.h"
#import "VKVideo.h"
#import "VKAudioPlayer.h"
#import "VKAudioPlayerViewController.h"
#import "VKVideoPlayback.h"

@interface VKNewsViewController () <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
    NSInteger _appliedFeedCount;
    VKPost *_pendingRepostPost; // пост для UIAlertView с комментарием
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *posts;
@property (nonatomic, strong) UIRefreshControl *refresh;
@property (nonatomic, strong) VKPost *repostingPost; // пост, для которого открыт ActionSheet репоста
@end

@implementation VKNewsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Новости";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStylePlain];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [VKTheme contentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    // Pull-to-refresh: UIRefreshControl можно добавить прямо в таблицу (iOS 6).
    self.refresh = [[UIRefreshControl alloc] init];
    [self.refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:self.refresh];

    // Настройки ленты (шрифт, фото, количество записей) могут измениться.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange:)
                                                 name:VKSettingsDidChangeNotification
                                               object:nil];

    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)settingsDidChange:(NSNotification *)note {
    // Количество записей влияет на запрос — перезагружаем ленту целиком.
    if ([VKSettings shared].feedCount != _appliedFeedCount && self.posts.count) {
        [self reload];
        return;
    }
    // Остальное (шрифт, показ фото) — только перерисовка.
    [self.tableView reloadData];
}

- (void)reload {
    if (![[VKSession shared] isAuthorized]) {
        self.posts = nil;
        [self.tableView reloadData];
        [self showMessage:@"Войдите с реальным access_token, чтобы загрузить ленту."];
        return;
    }
    [self showMessage:nil];
    if (self.posts.count == 0) [self showLoading:YES];

    // Сколько записей тянуть — из настроек.
    NSInteger count = [VKSettings shared].feedCount;
    _appliedFeedCount = count;

    [[VKAPI shared] callMethod:@"newsfeed.get"
                        params:@{@"filters": @"post",
                                 @"count": [NSString stringWithFormat:@"%d", (int)count]}
                    completion:^(id response, NSError *error) {
        [self showLoading:NO];
        [self.refresh endRefreshing];
        if (error || ![response isKindOfClass:[NSDictionary class]]) {
            if (self.posts.count == 0) {
                NSString *msg = error ? [NSString stringWithFormat:@"%@\n(%@ %d)",
                                         error.localizedDescription, error.domain, (int)error.code]
                                      : @"Не удалось загрузить ленту";
                [self showMessage:msg];
            }
            return;
        }
        self.posts = [self parseFeed:(NSDictionary *)response];
        if (self.posts.count == 0) [self showMessage:@"Лента пуста"];
        [self.tableView reloadData];
    }];
}

// Строим словарь автор -> (имя, аватар) из profiles/groups и мапим посты.
- (NSArray *)parseFeed:(NSDictionary *)response {
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    NSMutableDictionary *photos = [NSMutableDictionary dictionary];

    for (NSDictionary *p in [response objectForKey:@"profiles"]) {
        long long uid = [[p objectForKey:@"id"] longLongValue];
        NSString *key = [NSString stringWithFormat:@"%lld", uid];
        [names setObject:[NSString stringWithFormat:@"%@ %@",
                          [p objectForKey:@"first_name"] ?: @"",
                          [p objectForKey:@"last_name"] ?: @""] forKey:key];
        if ([p objectForKey:@"photo_100"]) [photos setObject:[p objectForKey:@"photo_100"] forKey:key];
    }
    for (NSDictionary *g in [response objectForKey:@"groups"]) {
        long long gid = [[g objectForKey:@"id"] longLongValue];
        NSString *key = [NSString stringWithFormat:@"%lld", -gid]; // группы = отрицательный source_id
        [names setObject:([g objectForKey:@"name"] ?: @"") forKey:key];
        if ([g objectForKey:@"photo_100"]) [photos setObject:[g objectForKey:@"photo_100"] forKey:key];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in [response objectForKey:@"items"]) {
        if (![[item objectForKey:@"type"] isEqualToString:@"post"]) continue;
        NSString *text = [OVKAPICompatibility postText:item];
        if (![text isKindOfClass:[NSString class]]) text = @"";

        // Первые вложения каждого поддерживаемого типа.
        NSString *photoURL = nil; CGFloat aspect = 0.0;
        VKAudio *audioAttachment = nil;
        VKVideo *videoAttachment = nil;
        for (NSDictionary *att in [item objectForKey:@"attachments"]) {
            NSString *type = [att objectForKey:@"type"];
            if ([type isEqualToString:@"audio"] && !audioAttachment) {
                audioAttachment = [VKAudio audioFromDictionary:[att objectForKey:@"audio"]];
                continue;
            }
            if ([type isEqualToString:@"video"] && !videoAttachment) {
                videoAttachment = [VKVideo videoFromDictionary:[att objectForKey:@"video"] profiles:@{} groups:@{}];
                continue;
            }
            if (![type isEqualToString:@"photo"] || photoURL.length) continue;
            NSArray *sizes = [[att objectForKey:@"photo"] objectForKey:@"sizes"];
            NSDictionary *best = nil;
            for (NSDictionary *s in sizes) {
                NSString *t = [s objectForKey:@"type"];
                // предпочитаем 'x' (~604px), иначе 'm'/'y'
                if ([t isEqualToString:@"x"]) { best = s; break; }
                if (!best && ([t isEqualToString:@"y"] || [t isEqualToString:@"m"])) best = s;
            }
            if (best) {
                photoURL = [best objectForKey:@"url"];
                CGFloat w = [[best objectForKey:@"width"] floatValue];
                CGFloat h = [[best objectForKey:@"height"] floatValue];
                if (w > 0.0 && h > 0.0) aspect = h / w;
            }
        }

        // Пропускаем только записи без текста и без поддерживаемых вложений.
        if (text.length == 0 && !photoURL && !audioAttachment && !videoAttachment) continue;

        VKPost *post = [[VKPost alloc] init];
        // source_id: >0 — пользователь, <0 — паблик, который выложил запись.
        id source = [item objectForKey:@"source_id"];
        long long sourceId = [source respondsToSelector:@selector(longLongValue)]
            ? [source longLongValue] : 0;
        NSString *key = [NSString stringWithFormat:@"%lld", sourceId];
        post.authorId = [[item objectForKey:@"from_id"] longLongValue] ?: sourceId;
        key = [NSString stringWithFormat:@"%lld", post.authorId];
        post.authorName = [names objectForKey:key] ?: @"Запись";
        post.avatarURL = [photos objectForKey:key];
        post.text = text;
        post.photoURL = photoURL;
        post.photoAspect = aspect;
        post.audioAttachment = audioAttachment;
        post.videoAttachment = videoAttachment;
        post.timeText = [self relativeTime:[[item objectForKey:@"date"] doubleValue]];
        post.likes = [[[item objectForKey:@"likes"] objectForKey:@"count"] integerValue];
        post.comments = [[[item objectForKey:@"comments"] objectForKey:@"count"] integerValue];
        post.reposts = [[[item objectForKey:@"reposts"] objectForKey:@"count"] integerValue];
        // Запись в ленте живёт на стене source_id и имеет собственный post_id —
        // этого хватает и для лайков, и для комментариев.
        post.ownerId = sourceId;
        post.postId = [[item objectForKey:@"post_id"] longLongValue];
        post.repost = ([[item objectForKey:@"copy_history"] isKindOfClass:[NSArray class]] && [[item objectForKey:@"copy_history"] count] > 0) ||
                       ([[item objectForKey:@"repost_history"] isKindOfClass:[NSArray class]] && [[item objectForKey:@"repost_history"] count] > 0);
        NSArray *history = [item objectForKey:@"copy_history"];
        if (![history isKindOfClass:[NSArray class]] || !history.count) history = [item objectForKey:@"repost_history"];
        NSDictionary *original = [history isKindOfClass:[NSArray class]] && history.count && [[history objectAtIndex:0] isKindOfClass:[NSDictionary class]] ? [history objectAtIndex:0] : nil;
        if (original) {
            long long author = [[original objectForKey:@"from_id"] longLongValue];
            if (!author) author = [[original objectForKey:@"owner_id"] longLongValue];
            NSString *key = [NSString stringWithFormat:@"%lld", author];
            post.originalName = [names objectForKey:key] ?: [NSString stringWithFormat:author < 0 ? @"Сообщество %lld" : @"Пользователь %lld", llabs(author)];
            post.originalAvatarURL = [photos objectForKey:key];
            post.originalAuthorId = author; // сохраняем ID для открытия профиля по тапу
            post.originalText = [OVKAPICompatibility postText:original];
            for (NSDictionary *attachment in [original objectForKey:@"attachments"]) {
                NSString *type = [attachment objectForKey:@"type"];
                if ([type isEqualToString:@"audio"] && !post.audioAttachment) {
                    post.audioAttachment = [VKAudio audioFromDictionary:[attachment objectForKey:@"audio"]];
                } else if ([type isEqualToString:@"video"] && !post.videoAttachment) {
                    post.videoAttachment = [VKVideo videoFromDictionary:[attachment objectForKey:@"video"] profiles:@{} groups:@{}];
                }
            }
            if (!post.photoURL.length) for (NSDictionary *attachment in [original objectForKey:@"attachments"]) {
                NSDictionary *photo = [attachment objectForKey:@"photo"];
                if (![photo isKindOfClass:[NSDictionary class]]) continue;
                NSString *url = [photo objectForKey:@"photo_604"] ?: [photo objectForKey:@"photo_130"];
                CGFloat ratio = 1;
                for (NSDictionary *size in [photo objectForKey:@"sizes"]) {
                    NSString *candidate = [size objectForKey:@"url"] ?: [size objectForKey:@"src"];
                    if ([candidate isKindOfClass:[NSString class]]) {
                        url = candidate;
                        CGFloat width = [[size objectForKey:@"width"] doubleValue];
                        if (width > 0) ratio = [[size objectForKey:@"height"] doubleValue] / width;
                    }
                }
                if ([url isKindOfClass:[NSString class]] && url.length) { post.photoURL = url; post.photoAspect = ratio > 0 ? ratio : 1; break; }
            }

            NSMutableDictionary *own = [item mutableCopy];
            [own removeObjectForKey:@"copy_history"]; [own removeObjectForKey:@"repost_history"];
            post.text = [OVKAPICompatibility postText:own];
        }

        post.liked = [[[item objectForKey:@"likes"] objectForKey:@"user_likes"] integerValue] != 0;
        post.views = [[[item objectForKey:@"views"] objectForKey:@"count"] integerValue];

        NSString *initials = post.authorName.length ? [[post.authorName substringToIndex:1] uppercaseString] : @"?";
        post.avatar = [VKTheme avatarWithInitials:initials size:40.0 background:[VKTheme navBarColor]];
        [result addObject:post];
    }
    return result;
}

- (NSString *)relativeTime:(NSTimeInterval)ts {
    if (ts <= 0) return @"";
    NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - ts;
    if (diff < 60) return @"только что";
    if (diff < 3600) return [NSString stringWithFormat:@"%d мин назад", (int)(diff / 60)];
    if (diff < 86400) return [NSString stringWithFormat:@"%d ч назад", (int)(diff / 3600)];
    return [NSString stringWithFormat:@"%d дн назад", (int)(diff / 86400)];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.posts.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    VKPost *p = [self.posts objectAtIndex:indexPath.row];
    return [VKPostCell heightForPost:p width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"VKPostCell";
    VKPostCell *cell = [tableView dequeueReusableCellWithIdentifier:ident];
    if (!cell) {
        cell = [[VKPostCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];
    }
    cell.post = [self.posts objectAtIndex:indexPath.row];
    __weak VKNewsViewController *weakSelf = self;
    cell.onPhotoTap = ^(VKPost *post, UIImage *image) {
        VKPhotoViewController *viewer = [[VKPhotoViewController alloc] initWithImage:image url:post.photoURL];
        viewer.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        [weakSelf presentViewController:viewer animated:YES completion:nil];
    };
    // Тап по аватару или имени — страница автора записи (паблика или человека).
    cell.onAuthorTap = ^(VKPost *post) {
        VKProfileViewController *page = [[VKProfileViewController alloc]
            initWithUserId:post.authorId name:post.authorName];
        [weakSelf.navigationController pushViewController:page animated:YES];
    };
    // Тап по имени/аватару оригинального автора в блоке репоста — открыть его страницу.
    cell.onOriginalAuthorTap = ^(VKPost *post) {
        if (!post.originalAuthorId) return;
        VKProfileViewController *page = [[VKProfileViewController alloc]
            initWithUserId:post.originalAuthorId name:post.originalName];
        [weakSelf.navigationController pushViewController:page animated:YES];
    };
    // Лайк: счётчик правим сразу, ячейку перерисовываем без reloadData.
    __weak VKPostCell *weakCell = cell;
    cell.onLikeTap = ^(VKPost *post) {
        [VKLikes togglePost:post changed:^{
            if (weakCell.post == post) [weakCell refreshCounters];
        }];
    };
    cell.onCommentTap = ^(VKPost *post) {
        VKCommentsViewController *comments = [[VKCommentsViewController alloc]
            initWithOwnerId:post.ownerId postId:post.postId];
        [weakSelf.navigationController pushViewController:comments animated:YES];
    };
    cell.onRepostTap = ^(VKPost *post) {
        [weakSelf showRepostSheetForPost:post];
    };
    cell.onAudioTap = ^(VKPost *post) {
        VKAudio *audio = post.audioAttachment;
        if (!audio) return;
        [[VKAudioPlayer shared] playAudio:audio inPlaylist:@[audio]];
        [[VKAudioPlayerViewController sharedController] presentFromViewController:weakSelf];
    };
    cell.onVideoTap = ^(VKPost *post) {
        if (!post.videoAttachment) return;
        [VKVideoPlayback playVideo:post.videoAttachment from:weakSelf];
    };
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// ---------- Репост ----------

- (void)showRepostSheetForPost:(VKPost *)post {
    self.repostingPost = post;
    UIActionSheet *sheet = [[UIActionSheet alloc]
        initWithTitle:@"Поделиться записью"
             delegate:self
    cancelButtonTitle:@"Отмена"
destructiveButtonTitle:nil
    otherButtonTitles:@"На мою стену", @"На стену с комментарием", nil];
    [sheet showInView:self.view];
}

// UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex || !self.repostingPost) {
        self.repostingPost = nil;
        return;
    }
    VKPost *post = self.repostingPost;
    self.repostingPost = nil;

    if (buttonIndex == 1) {
        // «На стену с комментарием» — показываем UIAlertView с текстовым полем.
        // iOS 6: UIAlertView delegate нужен отдельный объект, т.к. блоков нет.
        _pendingRepostPost = post;
        UIAlertView *alert = [[UIAlertView alloc]
            initWithTitle:@"Комментарий к репосту"
                  message:nil
                 delegate:self
        cancelButtonTitle:@"Отмена"
        otherButtonTitles:@"Репостнуть", nil];
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        [[alert textFieldAtIndex:0] setPlaceholder:@"Ваш комментарий…"];
        alert.tag = 42; // маркер — это alertView репоста
        [alert show];
        return;
    }

    // buttonIndex == 0: репост на мою стену без комментария
    [self doRepostPost:post message:@""];
}

- (void)doRepostPost:(VKPost *)post message:(NSString *)message {
    // wall.repost: object = wall{ownerId}_{postId}
    NSString *object = [NSString stringWithFormat:@"wall%lld_%lld", post.ownerId, post.postId];
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:object forKey:@"object"];
    if (message.length) [params setObject:message forKey:@"message"];

    // Показываем HUD-заглушку через NavigationBar title пока грузится
    NSString *savedTitle = self.title;
    self.title = @"Репостим…";

    [[VKAPI shared] callMethod:@"wall.repost"
                        params:params
                    completion:^(id response, NSError *error) {
        self.title = savedTitle;
        if (error) {
            UIAlertView *err = [[UIAlertView alloc]
                initWithTitle:@"Ошибка репоста"
                      message:error.localizedDescription
                     delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
            [err show];
        } else {
            // Обновим счётчик репостов в посте
            post.reposts += 1;
            // Найдём ячейку и перерисуем
            NSUInteger idx = [self.posts indexOfObject:post];
            if (idx != NSNotFound) {
                NSIndexPath *ip = [NSIndexPath indexPathForRow:idx inSection:0];
                VKPostCell *cell = (VKPostCell *)[self.tableView cellForRowAtIndexPath:ip];
                if (cell) [cell refreshCounters];
            }
            UIAlertView *ok = [[UIAlertView alloc]
                initWithTitle:@"Готово!"
                      message:@"Запись добавлена на вашу стену."
                     delegate:nil
            cancelButtonTitle:@"OK"
            otherButtonTitles:nil];
            [ok show];
        }
    }];
}

// UIAlertViewDelegate — для UIAlertView с комментарием к репосту (tag == 42)
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != 42) return;
    if (buttonIndex == alertView.cancelButtonIndex || !_pendingRepostPost) {
        _pendingRepostPost = nil;
        return;
    }
    NSString *message = [[alertView textFieldAtIndex:0] text] ?: @"";
    VKPost *post = _pendingRepostPost;
    _pendingRepostPost = nil;
    [self doRepostPost:post message:message];
}

@end
