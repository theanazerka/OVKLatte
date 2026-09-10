#import "VKVideo.h"

static NSString *VKVideoFormatDuration(NSInteger seconds) {
    if (seconds <= 0) return @"0:00";
    NSInteger h = seconds / 3600;
    NSInteger m = (seconds % 3600) / 60;
    NSInteger s = seconds % 60;
    if (h > 0) {
        return [NSString stringWithFormat:@"%d:%02d:%02d", (int)h, (int)m, (int)s];
    }
    return [NSString stringWithFormat:@"%d:%02d", (int)m, (int)s];
}

static NSString *VKVideoPlural(NSInteger n, NSString *one, NSString *few, NSString *many) {
    NSInteger a = ABS(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return many;
    if (b == 1) return one;
    if (b > 1 && b < 5) return few;
    return many;
}

static NSString *VKVideoFormatViews(NSInteger n) {
    if (n < 0) n = 0;
    if (n >= 1000000) {
        return [NSString stringWithFormat:@"%.1fM просмотров", n / 1000000.0];
    }
    if (n >= 10000) {
        return [NSString stringWithFormat:@"%dK просмотров", (int)(n / 1000)];
    }
    if (n >= 1000) {
        return [NSString stringWithFormat:@"%.1fK просмотров", n / 1000.0];
    }
    return [NSString stringWithFormat:@"%d %@", (int)n, VKVideoPlural(n, @"просмотр", @"просмотра", @"просмотров")];
}

static NSString *VKVideoFormatDate(NSTimeInterval ts) {
    if (ts <= 0) return @"";
    NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - ts;
    if (diff < 60) return @"только что";
    if (diff < 3600) {
        int m = (int)(diff / 60);
        return [NSString stringWithFormat:@"%d %@ назад", m, VKVideoPlural(m, @"минуту", @"минуты", @"минут")];
    }
    if (diff < 86400) {
        int h = (int)(diff / 3600);
        return [NSString stringWithFormat:@"%d %@ назад", h, VKVideoPlural(h, @"час", @"часа", @"часов")];
    }
    if (diff < 86400 * 30) {
        int d = (int)(diff / 86400);
        return [NSString stringWithFormat:@"%d %@ назад", d, VKVideoPlural(d, @"день", @"дня", @"дней")];
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
    df.dateFormat = @"d MMM yyyy";
    return [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:ts]];
}

@implementation VKVideo

+ (instancetype)videoFromDictionary:(NSDictionary *)dict
                           profiles:(NSDictionary *)profiles
                             groups:(NSDictionary *)groups {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    VKVideo *v = [[VKVideo alloc] init];
    id rawId = [dict objectForKey:@"id"] ?: [dict objectForKey:@"vid"];
    v.videoId = [rawId respondsToSelector:@selector(longLongValue)] ? [rawId longLongValue] : 0;

    id rawOwner = [dict objectForKey:@"owner_id"];
    v.ownerId = [rawOwner respondsToSelector:@selector(longLongValue)] ? [rawOwner longLongValue] : 0;

    v.title = [dict objectForKey:@"title"] ?: @"";
    v.videoDescription = [dict objectForKey:@"description"] ?: @"";
    v.duration = [[dict objectForKey:@"duration"] integerValue];
    v.durationString = VKVideoFormatDuration(v.duration);

    // Превью видео: перебираем форматы от высокого к низкому
    NSString *photo = [dict objectForKey:@"photo_640"] ?: [dict objectForKey:@"photo_800"];
    if (!photo) photo = [dict objectForKey:@"photo_320"];
    if (!photo) photo = [dict objectForKey:@"photo_130"];

    // Если фото в массиве image (VK API 5.131+)
    if (!photo) {
        NSArray *images = [dict objectForKey:@"image"];
        if ([images isKindOfClass:[NSArray class]] && images.count > 0) {
            NSDictionary *bestImg = nil;
            NSInteger bestW = 0;
            for (NSDictionary *img in images) {
                NSInteger w = [[img objectForKey:@"width"] integerValue];
                if (w > bestW) {
                    bestW = w;
                    bestImg = img;
                }
            }
            if (bestImg) photo = [bestImg objectForKey:@"url"];
        }
    }

    // Если фото в массиве first_frame
    if (!photo) {
        photo = [dict objectForKey:@"first_frame_640"] ?: [dict objectForKey:@"first_frame_320"] ?: [dict objectForKey:@"first_frame_130"];
    }
    v.photoURL = photo ?: @"";

    id rawDate = [dict objectForKey:@"date"] ?: [dict objectForKey:@"adding_date"];
    v.date = [rawDate respondsToSelector:@selector(doubleValue)] ? [rawDate doubleValue] : 0;
    v.timeString = VKVideoFormatDate(v.date);

    v.views = [[dict objectForKey:@"views"] integerValue];
    v.viewsString = VKVideoFormatViews(v.views);

    id comments = [dict objectForKey:@"comments"];
    if ([comments isKindOfClass:[NSDictionary class]]) {
        v.commentsCount = [[comments objectForKey:@"count"] integerValue];
    } else {
        v.commentsCount = [comments integerValue];
    }

    id likes = [dict objectForKey:@"likes"];
    if ([likes isKindOfClass:[NSDictionary class]]) {
        v.likesCount = [[likes objectForKey:@"count"] integerValue];
        v.liked = [[likes objectForKey:@"user_likes"] integerValue] != 0;
    } else {
        v.likesCount = 0;
        v.liked = NO;
    }

    v.canComment = [[dict objectForKey:@"can_comment"] integerValue] != 0;
    v.canLike = [[dict objectForKey:@"can_like"] integerValue] != 0;
    v.playerURL = [dict objectForKey:@"player"] ?: @"";
    v.files = [dict objectForKey:@"files"];
    v.accessKey = [dict objectForKey:@"access_key"] ?: @"";

    // Автор видео (из profiles или groups)
    NSString *key = [NSString stringWithFormat:@"%lld", v.ownerId];
    if (v.ownerId < 0) {
        // Сообщество
        NSDictionary *g = [groups objectForKey:key] ?: [groups objectForKey:[NSString stringWithFormat:@"%lld", -v.ownerId]];
        if (g) {
            v.authorName = [g objectForKey:@"name"] ?: @"";
            v.authorPhotoURL = [g objectForKey:@"photo_100"] ?: [g objectForKey:@"photo_50"];
        }
    } else if (v.ownerId > 0) {
        // Пользователь
        NSDictionary *p = [profiles objectForKey:key];
        if (p) {
            v.authorName = [NSString stringWithFormat:@"%@ %@",
                            [p objectForKey:@"first_name"] ?: @"",
                            [p objectForKey:@"last_name"] ?: @""];
            v.authorPhotoURL = [p objectForKey:@"photo_100"] ?: [p objectForKey:@"photo_50"];
        }
    }

    if (!v.authorName.length) {
        v.authorName = (v.ownerId < 0) ? @"Сообщество" : @"Пользователь";
    }

    return v;
}

+ (NSArray *)parseVideosResponse:(id)response {
    if (!response) return @[];

    NSArray *rawItems = nil;
    NSMutableDictionary *profiles = [NSMutableDictionary dictionary];
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];

    if ([response isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)response;
        rawItems = [dict objectForKey:@"items"];
        if (!rawItems) rawItems = [dict objectForKey:@"videos"];

        for (NSDictionary *p in [dict objectForKey:@"profiles"]) {
            id uid = [p objectForKey:@"id"] ?: [p objectForKey:@"uid"];
            if (uid) [profiles setObject:p forKey:[NSString stringWithFormat:@"%@", uid]];
        }
        for (NSDictionary *g in [dict objectForKey:@"groups"]) {
            id gid = [g objectForKey:@"id"] ?: [g objectForKey:@"gid"];
            if (gid) {
                [groups setObject:g forKey:[NSString stringWithFormat:@"%@", gid]];
                [groups setObject:g forKey:[NSString stringWithFormat:@"-%@", gid]];
            }
        }
    } else if ([response isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)response;
        if (arr.count > 0 && [[arr objectAtIndex:0] isKindOfClass:[NSNumber class]]) {
            // Формат старого API: [count, item1, item2, ...]
            NSRange range = NSMakeRange(1, arr.count - 1);
            rawItems = [arr subarrayWithRange:range];
        } else {
            rawItems = arr;
        }
    }

    if (![rawItems isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:rawItems.count];
    for (id item in rawItems) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        VKVideo *v = [self videoFromDictionary:item profiles:profiles groups:groups];
        if (v && v.videoId != 0) {
            [result addObject:v];
        }
    }
    return result;
}

- (NSString *)bestDirectVideoURL {
    if (![self.files isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *order = @[@"mp4_720", @"mp4_480", @"mp4_360", @"mp4_240", @"mp4_1080", @"hls"];
    for (NSString *key in order) {
        NSString *url = [self.files objectForKey:key];
        if ([url isKindOfClass:[NSString class]] && url.length > 0) {
            return url;
        }
    }
    return nil;
}

- (NSArray *)availableQualities {
    if (![self.files isKindOfClass:[NSDictionary class]]) return @[];
    NSMutableArray *res = [NSMutableArray array];
    NSArray *keys = @[@"mp4_1080", @"mp4_720", @"mp4_480", @"mp4_360", @"mp4_240"];
    for (NSString *k in keys) {
        NSString *url = [self.files objectForKey:k];
        if ([url isKindOfClass:[NSString class]] && url.length > 0) {
            NSString *label = [k stringByReplacingOccurrencesOfString:@"mp4_" withString:@""];
            [res addObject:[NSString stringWithFormat:@"%@p", label]];
        }
    }
    return res;
}

- (NSString *)videoURLForQuality:(NSString *)quality {
    if (![self.files isKindOfClass:[NSDictionary class]]) return nil;
    NSString *cleanKey = [quality stringByReplacingOccurrencesOfString:@"p" withString:@""];
    NSString *key = [NSString stringWithFormat:@"mp4_%@", cleanKey];
    return [self.files objectForKey:key] ?: [self bestDirectVideoURL];
}

@end
