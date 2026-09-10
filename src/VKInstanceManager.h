#import <Foundation/Foundation.h>

extern NSString *const VKInstancesDidChangeNotification;

@interface VKInstanceManager : NSObject
+ (instancetype)shared;
- (NSArray *)instances;
- (NSArray *)switchTargets;
- (NSString *)nameForHost:(NSString *)host;
- (BOOL)addName:(NSString *)name host:(NSString *)host;
- (void)removeHost:(NSString *)host;
@end
