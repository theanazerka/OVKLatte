#import "VKBackend.h"
#import "VKSession.h"
#import "VKSettings.h"

NSString *const VKBackendDidChangeNotification = @"VKBackendDidChangeNotification";
NSString *const VKRequestLoginNotification = @"VKRequestLoginNotification";
NSString *const VKBackendDefaultOVKHost = @"api.openvk.org";

static NSString *const kHostKey = @"vk_ovk_host";

// Процентное экранирование значения параметра (iOS 6 API).
static NSString *VKBackendEscape(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return @"";
    return (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
        NULL, (CFStringRef)s, NULL, CFSTR(":/?#[]@!$&'()*+,;=%"), kCFStringEncodingUTF8));
}

@implementation VKBackend

+ (instancetype)shared {
    static VKBackend *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VKBackend alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *h = [d stringForKey:kHostKey];
        _ovkHost = h.length ? [h copy] : [VKBackendDefaultOVKHost copy];
    }
    return self;
}

// Принимаем и «openvk.su», и «https://openvk.su/» — приводим к чистому хосту.
- (void)setOvkHost:(NSString *)ovkHost {
    NSString *h = [ovkHost stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([h hasPrefix:@"https://"]) h = [h substringFromIndex:8];
    else if ([h hasPrefix:@"http://"]) h = [h substringFromIndex:7];
    while ([h hasSuffix:@"/"]) h = [h substringToIndex:h.length - 1];
    if (!h.length) h = VKBackendDefaultOVKHost;
    h = [h lowercaseString];
    if ([_ovkHost isEqualToString:h]) return;
    [[VKSession shared] save];
    _ovkHost = [h copy];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:_ovkHost forKey:kHostKey];
    [[VKSession shared] reload];
    [d synchronize];
}

- (BOOL)isOVK {
    return YES;
}

- (NSString *)methodBase {
    return [NSString stringWithFormat:@"https://%@/method/", self.ovkHost];
}

// OpenVK повторяет API ВК, поэтому версию отправляем ту же.
- (NSString *)apiVersion {
    return @"5.131";
}

- (NSString *)displayName {
    return @"OpenVK Latte";
}

- (NSString *)defaultsPrefix {
    return [NSString stringWithFormat:@"openvk_%@_", self.ovkHost];
}

- (NSString *)tokenURLWithUsername:(NSString *)username
                          password:(NSString *)password
                              code:(NSString *)code {
    NSMutableString *s = [NSMutableString stringWithFormat:
        @"https://%@/token?grant_type=password&username=%@&password=%@&client_name=%@",
        self.ovkHost, VKBackendEscape(username), VKBackendEscape(password),
        VKBackendEscape([VKSettings shared].postAsAndroid ? @"Latte for Android" : @"Latte for Apple")];
    if (code.length) [s appendFormat:@"&code=%@", VKBackendEscape(code)];
    return s;
}

- (NSString *)webHost {
    return [self.ovkHost isEqualToString:VKBackendDefaultOVKHost] ? @"openvk.org" : self.ovkHost;
}

@end
