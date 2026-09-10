#import <Foundation/Foundation.h>

@interface VKVideo : NSObject

@property (nonatomic, assign) long long videoId;
@property (nonatomic, assign) long long ownerId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *videoDescription;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, copy) NSString *durationString;
@property (nonatomic, copy) NSString *photoURL;
@property (nonatomic, assign) NSTimeInterval date;
@property (nonatomic, copy) NSString *timeString;
@property (nonatomic, assign) NSInteger views;
@property (nonatomic, copy) NSString *viewsString;
@property (nonatomic, assign) NSInteger commentsCount;
@property (nonatomic, assign) NSInteger likesCount;
@property (nonatomic, assign) BOOL liked;
@property (nonatomic, assign) BOOL canComment;
@property (nonatomic, assign) BOOL canLike;
@property (nonatomic, copy) NSString *playerURL;
@property (nonatomic, strong) NSDictionary *files; // mp4_240, mp4_360, mp4_480, mp4_720, mp4_1080
@property (nonatomic, copy) NSString *accessKey;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *authorPhotoURL;

+ (instancetype)videoFromDictionary:(NSDictionary *)dict
                           profiles:(NSDictionary *)profiles
                             groups:(NSDictionary *)groups;

+ (NSArray *)parseVideosResponse:(id)response;

// Лучшая прямая ссылка на видеопоток (начиная с 720p/480p/360p/240p)
- (NSString *)bestDirectVideoURL;
- (NSArray *)availableQualities; // Массив строк (@"720p", @"480p", ...)
- (NSString *)videoURLForQuality:(NSString *)quality;

@end
