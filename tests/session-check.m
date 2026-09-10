#import <Foundation/Foundation.h>
#import "VKBackend.h"
#import "VKSession.h"
int main(void) {
    @autoreleasepool {
        VKBackend *b = [VKBackend shared];
        VKSession *s = [VKSession shared];
        b.ovkHost = @"https://alpha.example/";
        [s clear]; s.accessToken = @"fixture-alpha"; s.userId = 11; [s save];
        b.ovkHost = @"beta.example";
        [s clear];
        NSCAssert(!s.isAuthorized && s.userId == 0, @"Session leaked between instances");
        s.accessToken = @"fixture-beta"; [s save];
        b.ovkHost = @"https://ALPHA.example/";
        NSCAssert([s.accessToken isEqualToString:@"fixture-alpha"] && s.userId == 11, @"Session not restored");
        NSCAssert([[b methodBase] isEqualToString:@"https://alpha.example/method/"], @"Invalid base URL");
        NSString *url = [b tokenURLWithUsername:@"a+b@example.org" password:@"x&y=z" code:@"123456"];
        NSCAssert([url rangeOfString:@"a%2Bb%40example.org"].location != NSNotFound, @"Login escaping");
        NSCAssert([url rangeOfString:@"x%26y%3Dz"].location != NSNotFound, @"Password escaping");
        [s clear]; b.ovkHost = @"beta.example"; [s clear];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"vk_ovk_host"];
        puts("PASS: instance isolation, session restoration, URL normalization, credential encoding");
    }
}
