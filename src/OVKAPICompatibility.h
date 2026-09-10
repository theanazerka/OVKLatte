#import <Foundation/Foundation.h>

// Normalize nullable and legacy fields at the API boundary, before UIKit models.
@interface OVKAPICompatibility : NSObject
+ (NSString *)postText:(NSDictionary *)post;
+ (id)normalizeResponse:(id)value;
+ (NSError *)errorFromEnvelope:(NSDictionary *)envelope;
+ (NSDictionary *)parameters:(NSDictionary *)parameters forMethod:(NSString *)method userId:(long long)userId;
@end
