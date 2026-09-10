#import <Foundation/Foundation.h>

typedef enum { VKBackendOVK = 1 } VKBackendKind;
extern NSString *const VKBackendDidChangeNotification;
extern NSString *const VKRequestLoginNotification;
extern NSString *const VKBackendDefaultOVKHost;

@interface VKBackend : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *ovkHost;
- (BOOL)isOVK;
- (NSString *)methodBase;
- (NSString *)apiVersion;
- (NSString *)displayName;
- (NSString *)defaultsPrefix;
- (NSString *)webHost;
- (NSString *)tokenURLWithUsername:(NSString *)username password:(NSString *)password code:(NSString *)code;
@end
