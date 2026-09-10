#import <UIKit/UIKit.h>
#import <CFNetwork/CFNetwork.h>
#import "VKAppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Принудительно тянем символ из CFNetwork, чтобы фреймворк был загружен
        // уже на старте процесса — иначе MobileSubstrate-фильтр TLSFix
        // (Bundles = com.apple.CFNetwork) может не заинжектиться, и TLS 1.2
        // рукопожатие с api.vk.com обрывается (ошибка -1005).
        CFHTTPMessageRef probe = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, TRUE);
        if (probe) CFRelease(probe);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([VKAppDelegate class]));
    }
}
