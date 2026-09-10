#import "VKUploader.h"
#import "VKAPI.h"
#import "VKHTTP.h"
#import "VKSession.h"
#import "OVKAPICompatibility.h"

static NSError *VKUploadError(NSString *msg) {
    return [NSError errorWithDomain:@"VKUpload" code:-1
        userInfo:[NSDictionary dictionaryWithObject:(msg ?: @"Не удалось загрузить файл")
                                            forKey:NSLocalizedDescriptionKey]];
}

// Ужимаем до 1280 px по длинной стороне для быстрой загрузки
static UIImage *VKShrink(UIImage *image) {
    CGFloat w = image.size.width, h = image.size.height;
    CGFloat longest = MAX(w, h);
    if (longest <= 1280.0 || longest <= 0.0) return image;
    CGFloat k = 1280.0 / longest;
    CGSize size = CGSizeMake(floorf(w * k), floorf(h * k));
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [image drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

static NSString *VKUploadStr(id v) {
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v respondsToSelector:@selector(stringValue)]) return [v stringValue];
    return nil;
}

@implementation VKUploader

+ (void)uploadWallPhoto:(UIImage *)image
                ownerId:(long long)ownerId
             completion:(VKUploadCompletion)completion {
    if (!image) { completion(nil, VKUploadError(@"Нет фотографии")); return; }
    long long uid = ownerId != 0 ? ownerId : [VKSession shared].userId;

    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (uid < 0) [params setObject:@(-uid) forKey:@"group_id"];

    [[VKAPI shared] callMethod:@"photos.getWallUploadServer" params:params
                    completion:^(id response, NSError *error) {
        NSString *url = [response isKindOfClass:[NSDictionary class]]
            ? VKUploadStr([response objectForKey:@"upload_url"]) : nil;
        if (!url.length) {
            completion(nil, error ?: VKUploadError(@"Сервер загрузки недоступен"));
            return;
        }
        NSData *jpeg = UIImageJPEGRepresentation(VKShrink(image), 0.85);
        [self postFile:jpeg fileName:@"photo.jpg" mimeType:@"image/jpeg" fieldName:@"photo" toURL:url completion:^(NSDictionary *result, NSError *err) {
            if (!result) { completion(nil, err); return; }
            [self saveWallPhoto:result userId:uid completion:completion];
        }];
    }];
}

+ (void)postFile:(NSData *)fileData
        fileName:(NSString *)fileName
        mimeType:(NSString *)mimeType
       fieldName:(NSString *)fieldName
           toURL:(NSString *)urlStr
      completion:(void (^)(NSDictionary *result, NSError *error))completion {
    if (!fileData.length) { completion(nil, VKUploadError(@"Нет данных файла")); return; }
    if (!fileName.length) fileName = @"file.jpg";
    if (!mimeType.length) mimeType = @"image/jpeg";
    if (!fieldName.length) fieldName = @"file";

    NSString *boundary = @"----VKiOS6BoundaryUpload7MA4";
    NSMutableData *body = [NSMutableData data];

    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", fieldName, fileName] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n\r\n", mimeType] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:fileData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    NSURL *uploadURL = [NSURL URLWithString:urlStr];
    if (!uploadURL.host.length || ![uploadURL.scheme isEqualToString:@"https"]) {
        completion(nil, VKUploadError(@"Некорректный HTTPS-адрес загрузки")); return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:uploadURL];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"%d", (int)body.length] forHTTPHeaderField:@"Content-Length"];
    [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [req setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    [req setValue:@"OpenVKiOS6/1.1" forHTTPHeaderField:@"User-Agent"];
    [req setHTTPBody:body];
    [req setTimeoutInterval:90.0];

    [VKHTTP sendRequest:req completion:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }

        if (!data.length) {
            completion(nil, VKUploadError(@"Сервер загрузки не вернул ответ"));
            return;
        }

        NSString *rawStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!rawStr) rawStr = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!rawStr) rawStr = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];

        id json = nil;
        if (data) json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];

        if (!json && rawStr.length) {
            NSRange start = [rawStr rangeOfString:@"{"];
            NSRange end = [rawStr rangeOfString:@"}" options:NSBackwardsSearch];
            if (start.location != NSNotFound && end.location != NSNotFound && end.location > start.location) {
                NSString *jsonSub = [rawStr substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
                NSData *subData = [jsonSub dataUsingEncoding:NSUTF8StringEncoding];
                json = [NSJSONSerialization JSONObjectWithData:subData options:0 error:NULL];
            }
        }

        if ([json isKindOfClass:[NSDictionary class]]) {
            NSError *serverError = [OVKAPICompatibility errorFromEnvelope:json];
            if (serverError) {
                completion(nil, serverError);
                return;
            }
            completion((NSDictionary *)json, nil);
            return;
        }

        NSString *snippet = rawStr.length > 80 ? [rawStr substringToIndex:80] : (rawStr ?: @"пустой ответ");
        completion(nil, VKUploadError([NSString stringWithFormat:@"Некорректный ответ: %@", snippet]));
    }];
}

+ (void)saveWallPhoto:(NSDictionary *)uploaded
               userId:(long long)uid
           completion:(VKUploadCompletion)completion {
    NSMutableDictionary *save = [NSMutableDictionary dictionary];
    NSArray *keys = [NSArray arrayWithObjects:@"server", @"photo", @"hash", nil];
    for (NSString *k in keys) {
        NSString *v = VKUploadStr([uploaded objectForKey:k]);
        if (v) [save setObject:v forKey:k];
    }
    if (uid < 0) [save setObject:@(-uid) forKey:@"group_id"];

    [[VKAPI shared] callMethod:@"photos.saveWallPhoto" params:save
                    completion:^(id response, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *photo = nil;
        if ([response isKindOfClass:[NSArray class]] && [response count]) {
            photo = [response objectAtIndex:0];
        } else if ([response isKindOfClass:[NSDictionary class]]) {
            NSArray *inner = [response objectForKey:@"response"];
            if ([inner isKindOfClass:[NSArray class]] && inner.count > 0) photo = [inner objectAtIndex:0];
            else photo = response;
        }
        if (![photo isKindOfClass:[NSDictionary class]]) {
            completion(nil, VKUploadError(@"Не удалось сохранить фото"));
            return;
        }
        long long pid = [(VKUploadStr([photo objectForKey:@"id"])
                          ?: VKUploadStr([photo objectForKey:@"pid"]) ?: @"0") longLongValue];
        long long owner = [(VKUploadStr([photo objectForKey:@"owner_id"]) ?: @"0") longLongValue];
        if (owner == 0) owner = uid;
        if (pid == 0) { completion(nil, VKUploadError(@"Неверный ID сохраненного фото")); return; }
        completion([NSString stringWithFormat:@"photo%lld_%lld", owner, pid], nil);
    }];
}

+ (void)uploadMessagesPhoto:(UIImage *)image
                     peerId:(long long)peerId
                 completion:(VKUploadCompletion)completion {
    if (!image) { completion(nil, VKUploadError(@"Нет фотографии")); return; }
    // OpenVK messages.send accepts photo attachments; document upload API is a stub.
    [self uploadWallPhoto:image ownerId:[VKSession shared].userId completion:completion];
}

@end
