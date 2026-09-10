#import "VKAudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

NSString *const VKAudioPlayerTrackDidChangeNotification = @"VKAudioPlayerTrackDidChangeNotification";
NSString *const VKAudioPlayerStateDidChangeNotification = @"VKAudioPlayerStateDidChangeNotification";
NSString *const VKAudioPlayerProgressDidChangeNotification = @"VKAudioPlayerProgressDidChangeNotification";

@interface VKAudioPlayer () {
    id _timeObserver;
    BOOL _isObservingStatus;
}
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) NSArray *playlist;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) VKAudio *currentAudio;
@property (nonatomic, assign) VKAudioPlaybackState state;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) CGFloat progress;
@end

@implementation VKAudioPlayer

+ (instancetype)shared {
    static VKAudioPlayer *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[VKAudioPlayer alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) {
        _playlist = @[];
        _currentIndex = -1;
        _state = VKAudioStateStopped;
        _repeatMode = VKAudioRepeatOff;
        _shuffle = NO;

        [self setupAudioSession];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(itemDidFinishPlaying:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(itemFailedToPlay:)
                                                     name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self removeTimeObserver];
    [self removeStatusObserver];
}

- (void)setupAudioSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [session setCategory:AVAudioSessionCategoryPlayback error:&err];
    [session setActive:YES error:&err];

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
}

#pragma mark - Playback Controls

- (void)playAudio:(VKAudio *)audio inPlaylist:(NSArray *)playlist {
    if (!audio) return;
    NSArray *list = (playlist.count > 0) ? playlist : @[audio];
    NSInteger idx = [list indexOfObject:audio];
    if (idx == NSNotFound) {
        // Попробуем найти по audioId
        for (NSInteger i = 0; i < (NSInteger)list.count; i++) {
            VKAudio *item = [list objectAtIndex:i];
            if (item.audioId == audio.audioId) {
                idx = i;
                break;
            }
        }
    }
    if (idx == NSNotFound) idx = 0;
    [self playAudioAtIndex:idx inPlaylist:list];
}

- (void)playAudioAtIndex:(NSInteger)index inPlaylist:(NSArray *)playlist {
    if (playlist.count == 0 || index < 0 || index >= (NSInteger)playlist.count) return;

    self.playlist = [playlist copy];
    self.currentIndex = index;
    self.currentAudio = [playlist objectAtIndex:index];

    [self loadAndPlayCurrentAudio];
}

- (void)loadAndPlayCurrentAudio {
    if (!self.currentAudio || self.currentAudio.url.length == 0) {
        self.state = VKAudioStateError;
        [self postStateChange];
        return;
    }

    NSURL *url = [NSURL URLWithString:self.currentAudio.url];
    if (!url) {
        self.state = VKAudioStateError;
        [self postStateChange];
        return;
    }

    [self removeTimeObserver];
    [self removeStatusObserver];

    self.state = VKAudioStateBuffering;
    self.currentTime = 0;
    self.duration = self.currentAudio.duration;
    self.progress = 0;



    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:item];
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
    }

    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    _isObservingStatus = YES;

    [self setupTimeObserver];
    [self.player play];
    [self updateNowPlayingInfo];
    [self postTrackChange]; [self postStateChange];
}

- (void)setupTimeObserver {
    __weak typeof(self) weakSelf = self;
    CMTime interval = CMTimeMake(1, 4); // 4 раза в секунду
    _timeObserver = [self.player addPeriodicTimeObserverForInterval:interval
                                                              queue:dispatch_get_main_queue()
                                                         usingBlock:^(CMTime time) {
        [weakSelf timeDidUpdate:time];
    }];
}

- (void)removeTimeObserver {
    if (_timeObserver && self.player) {
        [self.player removeTimeObserver:_timeObserver];
        _timeObserver = nil;
    }
}

- (void)removeStatusObserver {
    if (_isObservingStatus && self.player.currentItem) {
        @try {
            [self.player.currentItem removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *e) {}
        _isObservingStatus = NO;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self observeValueForKeyPath:keyPath ofObject:object change:change context:context]; });
        return;
    }
    if (object != self.player.currentItem) return;
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusReadyToPlay) {
            self.state = VKAudioStatePlaying;
            if (CMTIME_IS_NUMERIC(item.duration) && isfinite(CMTimeGetSeconds(item.duration)) && item.duration.value > 0) {
                self.duration = CMTimeGetSeconds(item.duration);
            }
            [self.player play];
            [self postStateChange];
            [self updateNowPlayingInfo];
        } else if (item.status == AVPlayerItemStatusFailed) {
            self.state = VKAudioStateError;
            [self postStateChange];
        }
    }
}

- (void)timeDidUpdate:(CMTime)time {
    if (!CMTIME_IS_VALID(time)) return;
    double seconds = CMTimeGetSeconds(time);
    if (!isfinite(seconds)) return;
    self.currentTime = seconds;
    if (self.duration > 0) {
        self.progress = self.currentTime / self.duration;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:VKAudioPlayerProgressDidChangeNotification object:self];
}

- (void)play {
    if (self.currentAudio) {
        if (self.player && self.player.currentItem) {
            [self.player play];
            self.state = VKAudioStatePlaying;
            [self postStateChange];
            [self updateNowPlayingInfo];
        } else {
            [self loadAndPlayCurrentAudio];
        }
    }
}

- (void)pause {
    if (self.player) {
        [self.player pause];
        self.state = VKAudioStatePaused;
        [self postStateChange];
        [self updateNowPlayingInfo];
    }
}

- (void)stop {
    [self.player pause];
    [self removeTimeObserver];
    [self removeStatusObserver];
    self.state = VKAudioStateStopped;
    self.currentAudio = nil;
    self.playlist = @[];
    self.currentIndex = -1;
    self.currentTime = 0;
    self.progress = 0;

    [self updateNowPlayingInfo];
    [self postTrackChange];
    [self postStateChange];
}

- (void)togglePlayPause {
    if (self.isPlaying) {
        [self pause];
    } else {
        [self play];
    }
}

- (BOOL)isPlaying {
    return (self.state == VKAudioStatePlaying || self.state == VKAudioStateBuffering);
}

- (BOOL)isPlayingAudio:(VKAudio *)audio {
    if (!audio || !self.currentAudio) return NO;
    return (self.currentAudio.audioId == audio.audioId && self.isPlaying);
}

- (void)next {
    if (self.playlist.count == 0) return;

    if (self.shuffle && self.playlist.count > 1) {
        NSInteger randIdx = arc4random_uniform((u_int32_t)self.playlist.count);
        if (randIdx == self.currentIndex) {
            randIdx = (randIdx + 1) % self.playlist.count;
        }
        [self playAudioAtIndex:randIdx inPlaylist:self.playlist];
        return;
    }

    NSInteger nextIdx = self.currentIndex + 1;
    if (nextIdx >= (NSInteger)self.playlist.count) {
        if (self.repeatMode == VKAudioRepeatAll) {
            nextIdx = 0;
        } else {
            self.state = VKAudioStateStopped;
            self.currentAudio = nil;
            self.playlist = @[];
            self.currentIndex = -1;
            [self postTrackChange];
            [self postStateChange];
            return;
        }
    }
    [self playAudioAtIndex:nextIdx inPlaylist:self.playlist];
}

- (void)previous {
    if (self.playlist.count == 0) return;

    // Если прошло больше 3 секунд трека — возвращаем в начало
    if (self.currentTime > 3.0) {
        [self seekToTime:0];
        return;
    }

    NSInteger prevIdx = self.currentIndex - 1;
    if (prevIdx < 0) {
        if (self.repeatMode == VKAudioRepeatAll) {
            prevIdx = self.playlist.count - 1;
        } else {
            prevIdx = 0;
        }
    }
    [self playAudioAtIndex:prevIdx inPlaylist:self.playlist];
}

- (void)seekToTime:(NSTimeInterval)time {
    if (!self.player || !self.player.currentItem) return;
    if (!isfinite(time) || self.player.currentItem.status != AVPlayerItemStatusReadyToPlay) return;
    time = MAX(0, MIN(time, self.duration));
    CMTime target = CMTimeMakeWithSeconds(time, 600);
    [self.player seekToTime:target];
}

- (void)seekToProgress:(CGFloat)progress {
    if (self.duration > 0) {
        [self seekToTime:self.duration * progress];
    }
}

#pragma mark - Playback Notifications

- (void)itemDidFinishPlaying:(NSNotification *)note {
    if (note.object != self.player.currentItem) return;

    if (self.repeatMode == VKAudioRepeatOne) {
        [self seekToTime:0];
        [self play];
    } else {
        [self next];
    }
}

- (void)itemFailedToPlay:(NSNotification *)note {
    if (note.object != self.player.currentItem) return;
    self.state = VKAudioStateError;
    [self postStateChange];
}

#pragma mark - Lockscreen Now Playing Info

- (void)updateNowPlayingInfo {
    if (!self.currentAudio) {
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        return;
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject:(self.currentAudio.title ?: @"Без названия") forKey:MPMediaItemPropertyTitle];
    [info setObject:(self.currentAudio.artist ?: @"Неизвестный исполнитель") forKey:MPMediaItemPropertyArtist];
    [info setObject:[NSNumber numberWithDouble:self.duration] forKey:MPMediaItemPropertyPlaybackDuration];
    [info setObject:[NSNumber numberWithDouble:self.currentTime] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
    [info setObject:[NSNumber numberWithFloat:(self.isPlaying ? 1.0 : 0.0)] forKey:MPNowPlayingInfoPropertyPlaybackRate];

    // Ставим иконку аудио ВК в качестве обложки на экране блокировки
    UIImage *art = [UIImage imageNamed:@"placeholder_audio@2x"] ?: [UIImage imageNamed:@"audio_preview_placeholder"];
    if (art) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithImage:art];
        [info setObject:artwork forKey:MPMediaItemPropertyArtwork];
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

#pragma mark - Helper posts

- (void)postTrackChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:VKAudioPlayerTrackDidChangeNotification object:self];
}

- (void)postStateChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:VKAudioPlayerStateDidChangeNotification object:self];
}

@end
