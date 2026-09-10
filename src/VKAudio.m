#import "VKAudio.h"

static NSString *VKAudioFormatDuration(NSInteger seconds) {
    if (seconds <= 0) return @"0:00";
    NSInteger h = seconds / 3600;
    NSInteger m = (seconds % 3600) / 60;
    NSInteger s = seconds % 60;
    if (h > 0) {
        return [NSString stringWithFormat:@"%d:%02d:%02d", (int)h, (int)m, (int)s];
    }
    return [NSString stringWithFormat:@"%d:%02d", (int)m, (int)s];
}

@implementation VKAudio

+ (instancetype)audioFromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;

    VKAudio *a = [[VKAudio alloc] init];
    id rawId = [dict objectForKey:@"id"] ?: [dict objectForKey:@"aid"];
    a.audioId = [rawId respondsToSelector:@selector(longLongValue)] ? [rawId longLongValue] : 0;

    id rawOwner = [dict objectForKey:@"owner_id"];
    a.ownerId = [rawOwner respondsToSelector:@selector(longLongValue)] ? [rawOwner longLongValue] : 0;

    a.artist = [dict objectForKey:@"artist"] ?: @"Неизвестный исполнитель";
    a.title = [dict objectForKey:@"title"] ?: @"Без названия";
    a.duration = [[dict objectForKey:@"duration"] integerValue];
    a.durationString = VKAudioFormatDuration(a.duration);
    id rawURL = [dict objectForKey:@"url"];
    a.url = [rawURL isKindOfClass:[NSString class]] ? rawURL : @"";

    id rawLyrics = [dict objectForKey:@"lyrics_id"];
    a.lyricsId = [rawLyrics respondsToSelector:@selector(longLongValue)] ? [rawLyrics longLongValue] : 0;

    id rawAlbum = [dict objectForKey:@"album_id"];
    a.albumId = [rawAlbum respondsToSelector:@selector(longLongValue)] ? [rawAlbum longLongValue] : 0;

    a.genreId = [[dict objectForKey:@"genre_id"] integerValue];

    id rawDate = [dict objectForKey:@"date"];
    a.date = [rawDate respondsToSelector:@selector(doubleValue)] ? [rawDate doubleValue] : 0;

    a.accessKey = [dict objectForKey:@"access_key"] ?: @"";
    NSDictionary *album = [dict objectForKey:@"album"];
    NSString *cover = [dict objectForKey:@"cover_url"] ?: [dict objectForKey:@"cover"];
    if (![cover isKindOfClass:[NSString class]]) cover = nil;
    if (!cover.length && [album isKindOfClass:[NSDictionary class]]) {
        cover = [album objectForKey:@"thumb_src"] ?: [album objectForKey:@"cover_url"] ?: [album objectForKey:@"thumb_url"];
        if (![cover isKindOfClass:[NSString class]]) cover = nil;
    }
    a.artworkURL = cover ?: @"";
    a.isAdded = NO;

    return a;
}

+ (NSArray *)parseAudioResponse:(id)response {
    if (!response) return @[];

    NSArray *rawItems = nil;

    if ([response isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)response;
        rawItems = [dict objectForKey:@"items"];
        if (!rawItems) rawItems = [dict objectForKey:@"audios"];
    } else if ([response isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)response;
        if (arr.count > 0 && [[arr objectAtIndex:0] isKindOfClass:[NSNumber class]]) {
            // Старый формат API: [count, item1, item2, ...]
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
        VKAudio *a = [self audioFromDictionary:item];
        if (a && a.audioId != 0) {
            [result addObject:a];
        }
    }
    return result;
}

@end
