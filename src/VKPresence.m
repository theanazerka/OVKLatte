#import "VKPresence.h"

static NSString *VKPresencePlural(NSInteger n, NSString *one, NSString *few, NSString *many) {
    NSInteger a = ABS(n) % 100, b = a % 10;
    if (a > 10 && a < 20) return many;
    if (b == 1) return one;
    if (b > 1 && b < 5) return few;
    return many;
}

@implementation VKPresence

+ (NSString *)textForOnline:(BOOL)online
                     mobile:(BOOL)mobile
                   lastSeen:(NSTimeInterval)lastSeen
                     female:(BOOL)female {
    if (online) return mobile ? @"в сети (моб.)" : @"в сети";
    if (lastSeen <= 0.0) return @"";

    NSString *verb = female ? @"заходила" : @"заходил";
    NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - lastSeen;
    if (diff < 60.0) return [NSString stringWithFormat:@"%@ только что", verb];
    if (diff < 3600.0) {
        int m = (int)(diff / 60.0);
        return [NSString stringWithFormat:@"%@ %d %@ назад", verb, m,
                VKPresencePlural(m, @"минуту", @"минуты", @"минут")];
    }
    if (diff < 86400.0) {
        int h = (int)(diff / 3600.0);
        return [NSString stringWithFormat:@"%@ %d %@ назад", verb, h,
                VKPresencePlural(h, @"час", @"часа", @"часов")];
    }
    int d = (int)(diff / 86400.0);
    if (d <= 30) {
        return [NSString stringWithFormat:@"%@ %d %@ назад", verb, d,
                VKPresencePlural(d, @"день", @"дня", @"дней")];
    }
    // Давно — показываем дату, как в оригинальном клиенте.
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"ru_RU"];
    df.dateFormat = @"d MMMM";
    NSString *date = [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:lastSeen]];
    return [NSString stringWithFormat:@"%@ %@", verb, date];
}

+ (UIImage *)dotForOnline:(BOOL)online mobile:(BOOL)mobile {
    if (!online) return nil;
    UIImage *dot = [UIImage imageNamed:(mobile ? @"online_mobile" : @"Online")];
    return dot ?: [UIImage imageNamed:@"Online"];
}

@end
