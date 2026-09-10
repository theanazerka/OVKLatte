#import "VKAPI.h"
#import "VKSession.h"
#import "VKBackend.h"
#import "VKHTTP.h"
#import "OVKAPICompatibility.h"

NSString *const VKAPIVersion = @"5.131";

@implementation VKAPI

+ (instancetype)shared {
    static VKAPI *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VKAPI alloc] init]; });
    return s;
}

// Процентное экранирование значения параметра (iOS 6 API).
- (NSString *)escape:(NSString *)s {
    if (![s isKindOfClass:[NSString class]]) {
        s = [NSString stringWithFormat:@"%@", s];
    }
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
        NULL, (CFStringRef)s, NULL, CFSTR(":/?#[]@!$&'()*+,;=%"),
        kCFStringEncodingUTF8));
}

- (void)callMethod:(NSString *)method
            params:(NSDictionary *)params
        completion:(VKAPICompletion)completion {
    [self callMethod:method params:params retriesLeft:1 completion:completion];
}

- (void)callMethod:(NSString *)method
            params:(NSDictionary *)params
       retriesLeft:(NSInteger)retriesLeft
        completion:(VKAPICompletion)completion {

    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:[OVKAPICompatibility parameters:params forMethod:method userId:[VKSession shared].userId]];
    VKBackend *backend = [VKBackend shared];
    NSString *token = [VKSession shared].accessToken;
    NSString *requestHost = [backend.ovkHost copy];
    if (token.length) [all setObject:token forKey:@"access_token"];
    [all setObject:[backend apiVersion] forKey:@"v"];
    if (![all objectForKey:@"lang"]) [all setObject:@"ru" forKey:@"lang"];

    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in all) {
        NSString *val = [self escape:[all objectForKey:key]];
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, val]];
    }
    NSString *query = [pairs componentsJoinedByString:@"&"];
    NSString *urlStr = [NSString stringWithFormat:@"%@%@", [backend methodBase], method];
    NSURL *url = [NSURL URLWithString:urlStr];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20.0;
    req.HTTPMethod = @"POST";
    req.HTTPBody = [query dataUsingEncoding:NSUTF8StringEncoding];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"OpenVKiOS6/1.0" forHTTPHeaderField:@"User-Agent"];

    void (^finish)(id, NSError *) = ^(id response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![requestHost isEqualToString:[VKBackend shared].ovkHost] || ![(token ?: @"") isEqualToString:([VKSession shared].accessToken ?: @"")]) return;
            if (completion) completion(response, error);
        });
    };

    [VKHTTP sendRequest:req completion:^(NSData *data, NSURLResponse *resp, NSError *connErr) {
        if (connErr) {
            // Транзиентные сетевые ошибки — одна повторная попытка.
            BOOL transient = [connErr.domain isEqualToString:NSURLErrorDomain] &&
                (connErr.code == NSURLErrorNetworkConnectionLost ||
                 connErr.code == NSURLErrorTimedOut ||
                 connErr.code == NSURLErrorCannotConnectToHost ||
                 connErr.code == NSURLErrorNotConnectedToInternet);
            BOOL readOnly = [method rangeOfString:@".get"].location != NSNotFound || [method hasSuffix:@".search"];
            if (transient && readOnly && retriesLeft > 0) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (![requestHost isEqualToString:[VKBackend shared].ovkHost] || ![(token ?: @"") isEqualToString:([VKSession shared].accessToken ?: @"")]) return;
                    [self callMethod:method params:params retriesLeft:retriesLeft - 1 completion:completion];
                });
                return;
            }
            finish(nil, connErr);
            return;
        }
        if (!data) {
            finish(nil, [NSError errorWithDomain:@"VKAPI" code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Пустой ответ"}]);
            return;
        }
        NSError *jsonErr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![json isKindOfClass:[NSDictionary class]]) {
            finish(nil, jsonErr ?: [NSError errorWithDomain:@"VKAPI" code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"Некорректный JSON"}]);
            return;
        }
        NSDictionary *dict = (NSDictionary *)json;
        NSError *apiError = [OVKAPICompatibility errorFromEnvelope:dict];
        if (apiError) { finish(nil, apiError); return; }
        id response = [OVKAPICompatibility normalizeResponse:[dict objectForKey:@"response"]];
        if (!response) {
            finish(nil, [NSError errorWithDomain:@"OpenVKAPI" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"Сервер не вернул результат метода"}]);
            return;
        }
        finish(response, nil);
    }];
}

@end
