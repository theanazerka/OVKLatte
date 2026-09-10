#import "VKInstanceManager.h"
#import "VKBackend.h"

NSString *const VKInstancesDidChangeNotification = @"VKInstancesDidChangeNotification";
static NSString *const kInstancesKey = @"openvk_saved_instances";

@implementation VKInstanceManager
+ (instancetype)shared { static id s; static dispatch_once_t once; dispatch_once(&once, ^{ s = [self new]; }); return s; }
- (NSArray *)instances { NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kInstancesKey]; return [a isKindOfClass:[NSArray class]] ? a : @[]; }
- (NSString *)cleanHost:(NSString *)host {
    NSString *h = [[host ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([h hasPrefix:@"https://"]) h = [h substringFromIndex:8];
    if ([h hasPrefix:@"http://"]) h = [h substringFromIndex:7];
    while ([h hasSuffix:@"/"]) h = [h substringToIndex:h.length - 1];
    return h;
}
- (NSString *)nameForHost:(NSString *)host {
    NSString *h = [self cleanHost:host];
    if ([h isEqualToString:VKBackendDefaultOVKHost]) return @"OpenVK";
    for (NSDictionary *d in [self instances]) if ([[d objectForKey:@"host"] isEqualToString:h]) return [d objectForKey:@"name"] ?: h;
    return h;
}
- (NSArray *)switchTargets {
    NSMutableArray *a = [NSMutableArray arrayWithObject:@{@"name": @"OpenVK", @"host": VKBackendDefaultOVKHost}];
    [a addObjectsFromArray:[self instances]];
    NSString *current = [VKBackend shared].ovkHost;
    NSIndexSet *same = [a indexesOfObjectsPassingTest:^BOOL(NSDictionary *d, NSUInteger idx, BOOL *stop) { return [[d objectForKey:@"host"] isEqualToString:current]; }];
    [a removeObjectsAtIndexes:same];
    return a;
}
- (BOOL)addName:(NSString *)name host:(NSString *)host {
    NSString *h = [self cleanHost:host];
    if (!h.length || [h isEqualToString:VKBackendDefaultOVKHost]) return NO;
    NSMutableArray *a = [[self instances] mutableCopy];
    NSUInteger found = [a indexOfObjectPassingTest:^BOOL(NSDictionary *d, NSUInteger idx, BOOL *stop) { return [[d objectForKey:@"host"] isEqualToString:h]; }];
    NSDictionary *entry = @{@"name": name.length ? name : h, @"host": h};
    if (found != NSNotFound) [a replaceObjectAtIndex:found withObject:entry];
    else if (a.count < 5) [a addObject:entry]; else return NO;
    [[NSUserDefaults standardUserDefaults] setObject:a forKey:kInstancesKey]; [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:VKInstancesDidChangeNotification object:nil]; return YES;
}
- (void)removeHost:(NSString *)host {
    NSString *h = [self cleanHost:host]; NSMutableArray *a = [[self instances] mutableCopy];
    NSIndexSet *matches = [a indexesOfObjectsPassingTest:^BOOL(NSDictionary *d, NSUInteger idx, BOOL *stop) { return [[d objectForKey:@"host"] isEqualToString:h]; }];
    [a removeObjectsAtIndexes:matches]; [[NSUserDefaults standardUserDefaults] setObject:a forKey:kInstancesKey]; [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:VKInstancesDidChangeNotification object:nil];
}
@end
