#import "VKImageLoader.h"
#import "VKHTTP.h"
#import "VKSettings.h"

@interface VKImageLoader ()
@property (nonatomic, strong) NSCache *cache;
@property (nonatomic, strong) NSMutableDictionary *byteSizes;
@property (nonatomic, strong) NSMutableDictionary *pending;
- (void)downloadURL:(NSString *)urlString URL:(NSURL *)url;
- (void)finishURL:(NSString *)urlString image:(UIImage *)image;
@end

@implementation VKImageLoader

+ (instancetype)shared {
    static VKImageLoader *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VKImageLoader alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        _cache = [[NSCache alloc] init];
        _cache.countLimit = 600;
        _cache.totalCostLimit = 36 * 1024 * 1024;
        _byteSizes = [[NSMutableDictionary alloc] init];
        _pending = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSString *)diskPathForURL:(NSString *)urlString {
    NSMutableString *name = [urlString mutableCopy];
    for (NSString *bad in @[@"/", @":", @"?", @"&", @"=", @"#"]) {
        [name replaceOccurrencesOfString:bad withString:@"_" options:0 range:NSMakeRange(0, name.length)];
    }
    if (name.length > 180) name = [[name substringToIndex:180] mutableCopy];
    NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *dir = [cache stringByAppendingPathComponent:@"OpenVKLatteImages"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir stringByAppendingPathComponent:name];
}

- (UIImage *)cachedImageForURL:(NSString *)urlString {
    if (!urlString.length) return nil;
    return [self.cache objectForKey:urlString];
}

- (void)setCachedImage:(UIImage *)image forURL:(NSString *)urlString {
    if (!urlString.length || !image) return;
    [self.cache setObject:image forKey:urlString cost:(NSUInteger)[self bytesForImage:image]];
    [self.byteSizes setObject:[NSNumber numberWithUnsignedLongLong:[self bytesForImage:image]]
                       forKey:urlString];
}

- (void)loadURL:(NSString *)urlString completion:(void (^)(UIImage *))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self loadURL:urlString completion:completion]; });
        return;
    }
    if (!urlString.length) { if (completion) completion(nil); return; }

    UIImage *cached = [self.cache objectForKey:urlString];
    if (cached) { if (completion) completion(cached); return; }

    NSMutableArray *waiters = [self.pending objectForKey:urlString];
    if (waiters) {
        if (completion) [waiters addObject:[completion copy]];
        return;
    }
    waiters = [NSMutableArray array];
    if (completion) [waiters addObject:[completion copy]];
    [self.pending setObject:waiters forKey:urlString];

    NSString *diskPath = [self diskPathForURL:urlString];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSData *onDisk = [NSData dataWithContentsOfFile:diskPath];
        UIImage *diskImage = onDisk.length ? [UIImage imageWithData:onDisk] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (diskImage) { [self setCachedImage:diskImage forURL:urlString]; [self finishURL:urlString image:diskImage]; return; }
            if (![VKSettings shared].loadImages) { [self finishURL:urlString image:nil]; return; }
            NSURL *url = [NSURL URLWithString:urlString];
            if (!url) { [self finishURL:urlString image:nil]; return; }
            [self downloadURL:urlString URL:url];
        });
    });
}

- (void)downloadURL:(NSString *)urlString URL:(NSURL *)url {
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:20.0];
    [VKHTTP sendRequest:req completion:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (!data.length) { [self finishURL:urlString image:nil]; return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            UIImage *img = nil;
            @autoreleasepool {
                img = [UIImage imageWithData:data];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (img) {
                    [self setCachedImage:img forURL:urlString];
                    [data writeToFile:[self diskPathForURL:urlString] atomically:YES];
                }
                [self finishURL:urlString image:img];
            });
        });
    }];
}

- (void)finishURL:(NSString *)urlString image:(UIImage *)image {
    NSArray *blocks = [[self.pending objectForKey:urlString] copy];
    [self.pending removeObjectForKey:urlString];
    for (void (^block)(UIImage *) in blocks) block(image);
}

#pragma mark - Кэш

- (unsigned long long)bytesForImage:(UIImage *)image {
    CGFloat scale = image.scale > 0.0 ? image.scale : 1.0;
    return (unsigned long long)(image.size.width * scale * image.size.height * scale * 4.0);
}

- (void)pruneByteSizes {
    for (NSString *key in [self.byteSizes allKeys]) {
        if (![self.cache objectForKey:key]) [self.byteSizes removeObjectForKey:key];
    }
}

- (NSUInteger)cachedImageCount {
    [self pruneByteSizes];
    return self.byteSizes.count;
}

- (unsigned long long)cachedImageBytes {
    [self pruneByteSizes];
    unsigned long long total = 0;
    for (NSNumber *n in [self.byteSizes allValues]) total += [n unsignedLongLongValue];
    return total;
}

- (void)clearCache {
    [self.cache removeAllObjects];
    [self.byteSizes removeAllObjects];
    NSString *cache = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *dir = [cache stringByAppendingPathComponent:@"OpenVKLatteImages"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
}

@end
