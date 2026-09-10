#import <UIKit/UIKit.h>

@class VKAudio, VKVideo;

// Модель одного поста ленты (демо-данные, потом заменим на VK API).
@interface VKPost : NSObject
@property (nonatomic, assign) BOOL likePending;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *timeText;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIImage *avatar;      // плейсхолдер (инициалы)
@property (nonatomic, copy) NSString *avatarURL;    // реальный аватар (photo_100)
@property (nonatomic, assign) NSInteger likes;
@property (nonatomic, assign) NSInteger comments;
@property (nonatomic, assign) NSInteger reposts;
@property (nonatomic, copy) NSString *photoURL;    // прикреплённое фото (если есть)
@property (nonatomic, assign) CGFloat photoAspect; // высота/ширина фото
@property (nonatomic, assign) long long authorId;  // >0 — пользователь, <0 — группа/паблик
@property (nonatomic, assign) long long ownerId;   // владелец стены (для likes/comments)
@property (nonatomic, assign) long long postId;    // id записи на стене
@property (nonatomic, assign) BOOL liked;          // стоит ли мой лайк
@property (nonatomic, assign) BOOL repost;
@property (nonatomic, copy) NSString *originalName;
@property (nonatomic, copy) NSString *originalText;
@property (nonatomic, copy) NSString *originalAvatarURL;
@property (nonatomic, assign) long long originalAuthorId;
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, strong) VKAudio *audioAttachment;
@property (nonatomic, strong) VKVideo *videoAttachment;
@property (nonatomic, assign) NSInteger views;     // число просмотров (0 — не показывать)
@property (nonatomic, assign) CGFloat cachedHeight;
@property (nonatomic, assign) CGFloat cachedTextHeight;
@end

// Ячейка поста в стиле ленты ВКонтакте (iOS 6, вёрстка кодом).
@interface VKPostCell : UITableViewCell
@property (nonatomic, strong) VKPost *post;
// Вызывается при тапе по прикреплённому фото (передаётся текущее изображение).
@property (nonatomic, copy) void (^onPhotoTap)(VKPost *post, UIImage *image);
// Тап по аватару или имени автора — открыть его страницу.
@property (nonatomic, copy) void (^onAuthorTap)(VKPost *post);
@property (nonatomic, copy) void (^onOriginalAuthorTap)(VKPost *post);
// Тап по лайку, комментариям и репосту.
@property (nonatomic, copy) void (^onLikeTap)(VKPost *post);
@property (nonatomic, copy) void (^onCommentTap)(VKPost *post);
@property (nonatomic, copy) void (^onRepostTap)(VKPost *post);
@property (nonatomic, copy) void (^onAudioTap)(VKPost *post);
@property (nonatomic, copy) void (^onVideoTap)(VKPost *post);
// Перерисовать счётчики футера (после лайка) без полной перезагрузки ячейки.
- (void)refreshCounters;
+ (CGFloat)heightForPost:(VKPost *)post width:(CGFloat)width;
@end
