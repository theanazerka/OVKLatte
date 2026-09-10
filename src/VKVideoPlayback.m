#import "VKVideoPlayback.h"
#import "VKVideo.h"
#import "VKAPI.h"
#import "VKAudioPlayer.h"
#import "VKSettings.h"
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>

@interface VKVideoWebPlayer : UIViewController
@property (nonatomic, copy) NSString *URLString;
@end
@implementation VKVideoWebPlayer
- (id)initWithURL:(NSString *)URL { if ((self = [super init])) _URLString = [URL copy]; return self; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Видео"; self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)]; self.view.backgroundColor = [UIColor blackColor]; UIWebView *web = [[UIWebView alloc] initWithFrame:self.view.bounds]; web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; web.backgroundColor = [UIColor blackColor]; web.opaque = NO; web.scalesPageToFit = YES; web.allowsInlineMediaPlayback = NO; web.mediaPlaybackRequiresUserAction = NO; [web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.URLString]]]; [self.view addSubview:web]; }
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
@end

@implementation VKVideoPlayback
+ (void)activateSound { [[VKAudioPlayer shared] pause]; AVAudioSession *s = [AVAudioSession sharedInstance]; [s setActive:NO error:nil]; [s setCategory:AVAudioSessionCategoryPlayback error:nil]; [s setActive:YES error:nil]; }
+ (void)presentVideo:(VKVideo *)video from:(UIViewController *)controller {
    NSString *quality = [VKSettings shared].preferredVideoQuality;
    NSString *direct = [quality isEqualToString:@"auto"] ? [video bestDirectVideoURL] : [video videoURLForQuality:quality];
    if (direct.length) {
        [self activateSound];
        MPMoviePlayerViewController *movie = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL URLWithString:direct]];
        movie.moviePlayer.useApplicationAudioSession = NO; movie.moviePlayer.shouldAutoplay = YES; movie.moviePlayer.controlStyle = MPMovieControlStyleFullscreen;
        [controller presentMoviePlayerViewControllerAnimated:movie]; [movie.moviePlayer play];
    } else if (video.playerURL.length) {
        [self activateSound]; VKVideoWebPlayer *web = [[VKVideoWebPlayer alloc] initWithURL:video.playerURL]; [controller presentViewController:[[UINavigationController alloc] initWithRootViewController:web] animated:YES completion:nil];
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Видео недоступно" message:@"Инстанс не передал ссылку для воспроизведения" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}
+ (void)playVideo:(VKVideo *)video from:(UIViewController *)controller {
    if (!video) return;
    if ([video bestDirectVideoURL].length) { [self presentVideo:video from:controller]; return; }
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    NSString *key = [NSString stringWithFormat:@"%lld_%lld%@", video.ownerId, video.videoId, video.accessKey.length ? [NSString stringWithFormat:@"_%@", video.accessKey] : @""];
    [[VKAPI shared] callMethod:@"video.get" params:@{@"videos": key, @"extended": @1} completion:^(id response, NSError *error) {
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
        NSArray *videos = [VKVideo parseVideosResponse:response];
        VKVideo *loaded = videos.count ? [videos objectAtIndex:0] : nil;
        if (loaded) [self presentVideo:loaded from:controller];
        else if (video.playerURL.length) [self presentVideo:video from:controller];
        else [[[UIAlertView alloc] initWithTitle:@"Видео недоступно" message:error.localizedDescription ?: @"Не удалось получить файл видео" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }];
}
@end
