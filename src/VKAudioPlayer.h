#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "VKAudio.h"

typedef enum {
    VKAudioRepeatOff = 0,
    VKAudioRepeatOne,
    VKAudioRepeatAll
} VKAudioRepeatMode;

typedef enum {
    VKAudioStateStopped = 0,
    VKAudioStateBuffering,
    VKAudioStatePlaying,
    VKAudioStatePaused,
    VKAudioStateError
} VKAudioPlaybackState;

extern NSString *const VKAudioPlayerTrackDidChangeNotification;
extern NSString *const VKAudioPlayerStateDidChangeNotification;
extern NSString *const VKAudioPlayerProgressDidChangeNotification;

@interface VKAudioPlayer : NSObject

+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray *playlist;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, strong, readonly) VKAudio *currentAudio;
@property (nonatomic, assign, readonly) BOOL isPlaying;
@property (nonatomic, assign, readonly) VKAudioPlaybackState state;
@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) NSTimeInterval duration;
@property (nonatomic, assign, readonly) CGFloat progress; // 0.0 .. 1.0

@property (nonatomic, assign) BOOL shuffle;
@property (nonatomic, assign) VKAudioRepeatMode repeatMode;

- (void)playAudio:(VKAudio *)audio inPlaylist:(NSArray *)playlist;
- (void)playAudioAtIndex:(NSInteger)index inPlaylist:(NSArray *)playlist;
- (void)play;
- (void)pause;
- (void)stop;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)seekToTime:(NSTimeInterval)time;
- (void)seekToProgress:(CGFloat)progress;

// Проверка, играет ли сейчас конкретный трек
- (BOOL)isPlayingAudio:(VKAudio *)audio;

@end
