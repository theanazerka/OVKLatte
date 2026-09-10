#import "VKHTTP.h"
#import <Security/Security.h>

// Набор вшитых anchor-сертификатов (грузим один раз из Resources/roots/*.der,
// с фолбэком на корень бандла).
static NSArray *VKAnchorCertificates(void) {
    static NSArray *anchors = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *result = [NSMutableArray array];
        NSString *dir = [[NSBundle mainBundle] pathForResource:@"roots" ofType:nil];
        NSArray *files = dir ? [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL] : nil;
        for (NSString *name in files) {
            if (![[name pathExtension] isEqualToString:@"der"]) continue;
            NSData *der = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:name]];
            if (der.length == 0) continue;
            SecCertificateRef cert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der);
            if (cert) [result addObject:(__bridge_transfer id)cert];
        }
        if (result.count == 0) {
            for (NSString *p in [[NSBundle mainBundle] pathsForResourcesOfType:@"der" inDirectory:nil]) {
                NSData *der = [NSData dataWithContentsOfFile:p];
                SecCertificateRef cert = der ? SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der) : NULL;
                if (cert) [result addObject:(__bridge_transfer id)cert];
            }
        }
        anchors = [result copy];
        NSLog(@"[VKHTTP] loaded %lu embedded root CAs", (unsigned long)anchors.count);
    });
    return anchors;
}



#pragma mark - Per-request delegate task

@interface VKHTTPTask : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate> {
    NSMutableData *_buffer;
    NSURLResponse *_response;
    NSURLConnection *_connection;
    NSURLRequest *_initialRequest;
    void (^_completion)(NSData *, NSURLResponse *, NSError *);
    VKHTTPTask *_selfRef;   // держим себя живым до завершения
    NSString *_host;
}
- (void)startWithRequest:(NSURLRequest *)request
              completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
@end

@implementation VKHTTPTask

- (void)startWithRequest:(NSURLRequest *)request
              completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    _completion = [completion copy];
    _initialRequest = request;
    _buffer = [NSMutableData data];
    _host = [[request URL] host];
    _selfRef = self;
    // Так же, как в рабочем клиенте Avito: явное расписание в main run loop.
    _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [_connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [_connection start];
    if (!_connection) {
        [self finish:nil error:[NSError errorWithDomain:@"VKHTTP" code:-1
                               userInfo:@{NSLocalizedDescriptionKey: @"Не удалось создать соединение"}]];
    }
}

- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse {
    if (redirectResponse) {
        if ([_initialRequest.HTTPMethod isEqualToString:@"POST"] && (![[request.URL.scheme lowercaseString] isEqualToString:[_initialRequest.URL.scheme lowercaseString]] || ![[request.URL.host lowercaseString] isEqualToString:[_initialRequest.URL.host lowercaseString]] || ![(request.URL.port ?: @443) isEqual:(_initialRequest.URL.port ?: @443)])) {
            [connection cancel];
            [self finish:nil error:[NSError errorWithDomain:@"VKHTTP" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"Сервер перенаправил запрос на другой адрес. Укажите API-хост инстанса."}]];
            return nil;
        }
        if ([_initialRequest.HTTPMethod isEqualToString:@"POST"]) {
            NSMutableURLRequest *r = [request mutableCopy];
            [r setHTTPMethod:@"POST"];
            [r setHTTPBody:_initialRequest.HTTPBody];
            NSDictionary *headers = _initialRequest.allHTTPHeaderFields;
            for (NSString *h in headers) {
                [r setValue:[headers objectForKey:h] forHTTPHeaderField:h];
            }
            return r;
        }
    }
    return request;
}

- (void)finish:(NSData *)data error:(NSError *)error {
    void (^block)(NSData *, NSURLResponse *, NSError *) = _completion;
    _completion = nil;
    _connection = nil;
    _initialRequest = nil;
    if (block) block(data, _response, error);
    _selfRef = nil;
}

#pragma mark TLS

- (BOOL)connection:(NSURLConnection *)connection
canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)space {
    return YES;
}

- (void)connection:(NSURLConnection *)connection
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    if (space.serverTrust) {
        SecTrustRef trust = space.serverTrust;
        NSArray *anchors = VKAnchorCertificates();
        if (anchors.count > 0) {
            SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)anchors);
            SecTrustSetAnchorCertificatesOnly(trust, false);
        }
        SecTrustResultType result = kSecTrustResultInvalid;
        SecTrustEvaluate(trust, &result);
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:trust]
             forAuthenticationChallenge:challenge];
        return;
    }
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

#pragma mark Data

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _response = response;
    [_buffer setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_buffer appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self finish:_buffer error:nil];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSLog(@"[VKHTTP] fail %@: %@ (%ld)", _host, error.localizedDescription, (long)error.code);
    [self finish:nil error:error];
}

@end

#pragma mark - VKHTTP facade

@implementation VKHTTP

+ (void)sendRequest:(NSURLRequest *)request
         completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    // Готовим запрос как в Avito: без keep-alive (Connection: close устраняет
    // -1005 при переиспользовании соединения на iOS 6), без кэша и кук.
    NSMutableURLRequest *req = [request mutableCopy];
    [req setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [req setHTTPShouldHandleCookies:NO];
    if (![req valueForHTTPHeaderField:@"Connection"]) {
        [req setValue:@"close" forHTTPHeaderField:@"Connection"];
    }
    if (![req valueForHTTPHeaderField:@"User-Agent"]) {
        [req setValue:@"VKClient/4.0.1 (iPhone; iOS 6.1.3; Scale/2.00)" forHTTPHeaderField:@"User-Agent"];
    }
    if (![req valueForHTTPHeaderField:@"Accept"]) {
        [req setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    }
    if (![req valueForHTTPHeaderField:@"Accept-Encoding"]) {
        [req setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
    }

    NSString *host = [[request URL] host];
    if (host.length) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if ([NSURLRequest respondsToSelector:@selector(setAllowsAnyHTTPSCertificate:forHost:)]) {
            [NSURLRequest performSelector:@selector(setAllowsAnyHTTPSCertificate:forHost:)
                               withObject:(id)kCFBooleanTrue
                               withObject:host];
        }
#pragma clang diagnostic pop
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        VKHTTPTask *task = [[VKHTTPTask alloc] init];
        [task startWithRequest:req completion:completion];
    });
}

@end
