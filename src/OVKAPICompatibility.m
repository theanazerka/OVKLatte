#import "OVKAPICompatibility.h"

@implementation OVKAPICompatibility
+ (NSString *)postText:(NSDictionary *)post {
    NSMutableArray *parts = [NSMutableArray array];
    id text = [post objectForKey:@"text"];
    if ([text isKindOfClass:[NSString class]] && [text length]) [parts addObject:text];
    NSArray *copies = [post objectForKey:@"copy_history"];
    if ([copies isKindOfClass:[NSArray class]]) {
        for (id copy in copies) if ([copy isKindOfClass:[NSDictionary class]]) {
            NSString *quoted = [self postText:copy];
            [parts addObject:[NSString stringWithFormat:@"Репост: %@", quoted.length ? quoted : @"запись"]];
        }
    }
    NSArray *attachments = [post objectForKey:@"attachments"];
    if ([attachments isKindOfClass:[NSArray class]]) for (id attachment in attachments) {
        if (![attachment isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [attachment objectForKey:@"type"];
        if (![type isKindOfClass:[NSString class]] || [type isEqualToString:@"photo"]) continue;
        NSDictionary *body = [attachment objectForKey:type];
        NSString *title = [body isKindOfClass:[NSDictionary class]] ? ([body objectForKey:@"title"] ?: [body objectForKey:@"question"]) : nil;
        if (![title isKindOfClass:[NSString class]]) title = @"";
        NSString *label = [@{@"video": @"Видео", @"audio": @"Аудиозапись", @"doc": @"Документ", @"poll": @"Опрос", @"note": @"Заметка", @"link": @"Ссылка"} objectForKey:type] ?: @"Вложение";
        [parts addObject:title.length ? [NSString stringWithFormat:@"%@: %@", label, title] : label];
    }
    return [parts componentsJoinedByString:@"\n\n"];
}
+ (id)normalizeResponse:(id)value {
    if (!value || value == [NSNull null]) return nil;
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray array];
        for (id item in value) {
            id normalized = [self normalizeResponse:item];
            if (normalized) [array addObject:normalized];
        }
        return array;
    }
    if (![value isKindOfClass:[NSDictionary class]]) return value;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString *key in value) {
        id normalized = [self normalizeResponse:[value objectForKey:key]];
        if (normalized) [dict setObject:normalized forKey:key];
    }
    // OpenVK newsfeed.get hydrates wall objects with id, not VK's post_id.
    if ([[dict objectForKey:@"type"] isEqual:@"post"] && ![dict objectForKey:@"post_id"] && [dict objectForKey:@"id"])
        [dict setObject:[dict objectForKey:@"id"] forKey:@"post_id"];
    if (![dict objectForKey:@"url"] && [[dict objectForKey:@"src"] isKindOfClass:[NSString class]])
        [dict setObject:[dict objectForKey:@"src"] forKey:@"url"];
    if (![dict objectForKey:@"text"] && [[dict objectForKey:@"body"] isKindOfClass:[NSString class]])
        [dict setObject:[dict objectForKey:@"body"] forKey:@"text"];
    // An unencoded video has files: [] instead of an object.
    if ([dict objectForKey:@"files"] && ![[dict objectForKey:@"files"] isKindOfClass:[NSDictionary class]])
        [dict setObject:@{} forKey:@"files"];
    return dict;
}
+ (NSError *)errorFromEnvelope:(NSDictionary *)envelope {
    id detail = [envelope objectForKey:@"error"];
    if (![detail isKindOfClass:[NSDictionary class]]) detail = envelope;
    id code = [detail objectForKey:@"error_code"];
    id message = [detail objectForKey:@"error_msg"] ?: [detail objectForKey:@"error_description"];
    BOOL failed = [code respondsToSelector:@selector(integerValue)] || [envelope objectForKey:@"error"] != nil;
    if (!failed) return nil;
    if (![message isKindOfClass:[NSString class]]) message = @"Ошибка OpenVK API";
    return [NSError errorWithDomain:@"OpenVKAPI" code:([code respondsToSelector:@selector(integerValue)] ? [code integerValue] : -1)
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}
+ (NSDictionary *)parameters:(NSDictionary *)parameters forMethod:(NSString *)method userId:(long long)userId {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:parameters ?: @{}];
    if ([method isEqualToString:@"groups.isMember"] && ![result objectForKey:@"user_id"])
        [result setObject:@(userId) forKey:@"user_id"];
    if ([method hasPrefix:@"newsfeed."] && ![result objectForKey:@"fields"])
        [result setObject:@"photo_100,photo_50,screen_name,online" forKey:@"fields"];
    return result;
}
@end
