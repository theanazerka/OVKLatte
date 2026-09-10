#import "VKSession.h"
#import "VKBackend.h"

static NSString *const kTokenKey = @"vk_access_token";
static NSString *const kMsgTokenKey = @"vk_messages_token";
static NSString *const kUserIdKey = @"vk_user_id";
static NSString *const kUserNameKey = @"vk_user_name";
static NSString *const kUserPhotoKey = @"vk_user_photo";

@implementation VKSession

+ (instancetype)shared {
    static VKSession *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[VKSession alloc] init];
        [s load];
    });
    return s;
}

// Ключи ВК лежат без префикса, OpenVK — с «ovk_», поэтому сессии не мешают друг другу.
- (NSString *)key:(NSString *)base {
    NSString *prefix = [[VKBackend shared] defaultsPrefix];
    return prefix.length ? [prefix stringByAppendingString:base] : base;
}

- (void)load {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *t = [d stringForKey:[self key:kTokenKey]];
    NSString *n = [d stringForKey:[self key:kUserNameKey]];
    NSString *p = [d stringForKey:[self key:kUserPhotoKey]];
    // Пустые строки трактуем как отсутствие значения.
    _accessToken = t.length ? [t copy] : nil;
    NSString *mt = [d stringForKey:[self key:kMsgTokenKey]];
    _messagesToken = mt.length ? [mt copy] : nil;
    _userId = [d doubleForKey:[self key:kUserIdKey]];
    _userName = n.length ? [n copy] : nil;
    _userPhoto = p.length ? [p copy] : nil;
}

- (void)reload {
    _silentToken = nil;
    _silentHash = nil;
    [self load];
}

- (void)save {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:(self.accessToken ?: @"") forKey:[self key:kTokenKey]];
    [d setObject:(self.messagesToken ?: @"") forKey:[self key:kMsgTokenKey]];
    [d setDouble:(double)self.userId forKey:[self key:kUserIdKey]];
    [d setObject:(self.userName ?: @"") forKey:[self key:kUserNameKey]];
    [d setObject:(self.userPhoto ?: @"") forKey:[self key:kUserPhotoKey]];
    [d synchronize];
}

- (void)clear {
    self.accessToken = nil;
    self.messagesToken = nil;
    self.userId = 0;
    self.userName = nil;
    self.userPhoto = nil;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:[self key:kTokenKey]];
    [d removeObjectForKey:[self key:kMsgTokenKey]];
    [d removeObjectForKey:[self key:kUserIdKey]];
    [d removeObjectForKey:[self key:kUserNameKey]];
    [d removeObjectForKey:[self key:kUserPhotoKey]];
    [d synchronize];
}

- (BOOL)isAuthorized {
    return self.accessToken.length > 0;
}

- (BOOL)hasIdentity {
    return [self isAuthorized];
}

@end
