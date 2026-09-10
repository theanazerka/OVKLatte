#import <Foundation/Foundation.h>

@interface VKAudio : NSObject

@property (nonatomic, assign) long long audioId;
@property (nonatomic, assign) long long ownerId;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, copy) NSString *durationString;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) long long lyricsId;
@property (nonatomic, assign) long long albumId;
@property (nonatomic, assign) NSInteger genreId;
@property (nonatomic, assign) NSTimeInterval date;
@property (nonatomic, copy) NSString *accessKey;
@property (nonatomic, copy) NSString *artworkURL;
@property (nonatomic, assign) BOOL isAdded;

+ (instancetype)audioFromDictionary:(NSDictionary *)dict;
+ (NSArray *)parseAudioResponse:(id)response;

@end
