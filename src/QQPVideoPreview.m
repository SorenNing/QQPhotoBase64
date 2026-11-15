#import "QQPVideoPreview.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

static void *QQPVideoItemContext = &QQPVideoItemContext;

static NSString *QQPVideoClock(NSTimeInterval seconds) {
    long long total = (long long)floor(MAX(0, seconds));
    long long hours = total / 3600;
    long long minutes = (total / 60) % 60;
    long long remainder = total % 60;
    if (hours) return [NSString stringWithFormat:@"%lld:%02lld:%02lld", hours, minutes, remainder];
    return [NSString stringWithFormat:@"%02lld:%02lld", minutes, remainder];
}

@interface QQPVideoPreviewController : UIViewController
@property(nonatomic,strong) NSURL *temporaryDirectory;
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItem *item;
@property(nonatomic,strong) AVPlayerLayer *videoLayer;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UIButton *playButton;
@property(nonatomic,strong) UISlider *scrubber;
@property(nonatomic,strong) UILabel *clockLabel;
@property(nonatomic,strong) UILabel *errorLabel;
@property(nonatomic,strong) UIView *bottomBar;
@property(nonatomic,strong) id timeObserver;
@property(nonatomic,assign) BOOL playWhenReady;
@property(nonatomic,assign) BOOL scrubbing;
@property(nonatomic,assign) BOOL resumeAfterScrub;
@property(nonatomic,assign) BOOL ended;
@property(nonatomic,assign) BOOL cleanedUp;
@property(nonatomic,assign) BOOL visible;
@end

@implementation QQPVideoPreviewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.videoLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view.layer addSublayer:self.videoLayer];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    close.layer.cornerRadius = 22;
    close.accessibilityLabel = @"关闭视频预览";
    [close addTarget:self action:@selector(closePreview:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    self.closeButton = close;

    UIView *bar = [UIView new];
    bar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    [self.view addSubview:bar];
    self.bottomBar = bar;

    UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
    play.tintColor = UIColor.whiteColor;
    [play addTarget:self action:@selector(togglePlayback:) forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:play];
    self.playButton = play;

    UISlider *scrubber = [UISlider new];
    scrubber.minimumValue = 0;
    scrubber.maximumValue = 1;
    scrubber.enabled = NO;
    scrubber.minimumTrackTintColor = UIColor.systemBlueColor;
    scrubber.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.45];
    [scrubber addTarget:self action:@selector(beginScrubbing:) forControlEvents:UIControlEventTouchDown];
    [scrubber addTarget:self action:@selector(scrubbingChanged:) forControlEvents:UIControlEventValueChanged];
    [scrubber addTarget:self action:@selector(endScrubbing:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [bar addSubview:scrubber];
    self.scrubber = scrubber;

    UILabel *clock = [UILabel new];
    clock.textColor = UIColor.whiteColor;
    clock.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    clock.text = @"00:00 / --:--";
    clock.isAccessibilityElement = YES;
    [bar addSubview:clock];
    self.clockLabel = clock;

    UILabel *error = [UILabel new];
    error.text = @"视频无法播放，请检查文件是否完整。";
    error.textColor = UIColor.whiteColor;
    error.textAlignment = NSTextAlignmentCenter;
    error.numberOfLines = 0;
    error.font = [UIFont systemFontOfSize:16];
    error.hidden = YES;
    [self.view addSubview:error];
    self.errorLabel = error;
    [self updatePlayButton];

    [self.item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew context:QQPVideoItemContext];
    [self.item addObserver:self forKeyPath:@"duration" options:NSKeyValueObservingOptionInitial|NSKeyValueObservingOptionNew context:QQPVideoItemContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFailPlayback:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        [weakSelf updateTimeline];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.videoLayer.frame = self.view.bounds;
    [CATransaction commit];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    self.closeButton.frame = CGRectMake(safe.left + 12, safe.top + 8, 44, 44);
    self.bottomBar.frame = CGRectMake(0, CGRectGetHeight(bounds) - safe.bottom - 82, CGRectGetWidth(bounds), 82 + safe.bottom);
    CGFloat width = CGRectGetWidth(bounds);
    self.playButton.frame = CGRectMake(safe.left + 12, 4, 48, 48);
    self.scrubber.frame = CGRectMake(safe.left + 72, 6, MAX(0, width - safe.left - safe.right - 84), 44);
    self.clockLabel.frame = CGRectMake(safe.left + 20, 52, MAX(0, width - safe.left - safe.right - 32), 22);
    self.errorLabel.frame = CGRectInset(CGRectMake(0, 0, width, CGRectGetHeight(bounds)), 24, 90);
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (BOOL)shouldAutorotate { return YES; }

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.visible = YES;
    if (self.playWhenReady && self.item.status == AVPlayerItemStatusReadyToPlay &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
        [self.player play];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
    self.playWhenReady = NO;
    [self.player pause];
    [self updatePlayButton];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || !self.presentingViewController) [self finishPreview];
}

- (void)updatePlayButton {
    BOOL playing = self.playWhenReady && !self.ended;
    [self.playButton setImage:[UIImage systemImageNamed:playing ? @"pause.fill" : @"play.fill"] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = playing ? @"暂停视频" : @"播放视频";
    self.playButton.enabled = self.item.status == AVPlayerItemStatusReadyToPlay && self.errorLabel.hidden;
}

- (NSTimeInterval)videoDuration {
    CMTime duration = self.item.duration;
    if (!CMTIME_IS_NUMERIC(duration)) return 0;
    NSTimeInterval seconds = CMTimeGetSeconds(duration);
    return isfinite(seconds) && seconds > 0 ? seconds : 0;
}

- (void)updateTimeline {
    if (self.cleanedUp || self.ended) return;
    NSTimeInterval duration = [self videoDuration];
    NSTimeInterval position = CMTimeGetSeconds(self.player.currentTime);
    if (!isfinite(position) || position < 0) position = 0;
    self.scrubber.enabled = duration > 0 && self.item.status == AVPlayerItemStatusReadyToPlay && self.errorLabel.hidden;
    if (!self.scrubbing) self.scrubber.value = duration > 0 ? (float)MIN(1, position / duration) : 0;
    NSTimeInterval shown = self.scrubbing ? self.scrubber.value * duration : position;
    self.clockLabel.text = [NSString stringWithFormat:@"%@ / %@", QQPVideoClock(shown),
                            duration > 0 ? QQPVideoClock(duration) : @"--:--"];
}

- (void)showPlaybackFailure {
    if (self.cleanedUp) return;
    self.playWhenReady = NO;
    [self.player pause];
    self.errorLabel.hidden = NO;
    self.scrubber.enabled = NO;
    self.playButton.enabled = NO;
    [self updatePlayButton];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (context != QQPVideoItemContext || object != self.item) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cleanedUp) return;
        if (self.item.status == AVPlayerItemStatusFailed) [self showPlaybackFailure];
        else {
            [self updateTimeline];
            [self updatePlayButton];
            if ([keyPath isEqualToString:@"status"] && self.item.status == AVPlayerItemStatusReadyToPlay &&
                self.playWhenReady && self.visible &&
                UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
                [self.player play];
        }
    });
}

- (void)togglePlayback:(id)sender {
    if (self.item.status != AVPlayerItemStatusReadyToPlay || !self.errorLabel.hidden) return;
    if (self.playWhenReady) {
        self.playWhenReady = NO;
        [self.player pause];
    } else {
        self.playWhenReady = YES;
        if (self.ended) {
            self.ended = NO;
            [self.player seekToTime:kCMTimeZero completionHandler:^(BOOL completed) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completed && self.playWhenReady && self.visible &&
                        UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
                        [self.player play];
                });
            }];
        } else if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
            [self.player play];
        }
    }
    [self updatePlayButton];
}

- (void)beginScrubbing:(UISlider *)sender {
    self.scrubbing = YES;
    self.resumeAfterScrub = self.playWhenReady;
    [self.player pause];
}

- (void)scrubbingChanged:(UISlider *)sender { [self updateTimeline]; }

- (void)endScrubbing:(UISlider *)sender {
    if (!self.scrubbing) return;
    BOOL shouldResume = self.resumeAfterScrub;
    self.scrubbing = NO;
    self.ended = NO;
    NSTimeInterval duration = [self videoDuration];
    if (!duration) return;
    [self.player seekToTime:CMTimeMakeWithSeconds(duration * sender.value, 600)
         toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL completed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completed && !self.cleanedUp && shouldResume && self.playWhenReady && self.visible &&
                UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
                [self.player play];
            [self updateTimeline];
        });
    }];
    [self updateTimeline];
}

- (void)didReachEnd:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cleanedUp) return;
        self.playWhenReady = NO;
        [self.player pause];
        self.scrubber.value = 1;
        NSTimeInterval duration = [self videoDuration];
        self.clockLabel.text = [NSString stringWithFormat:@"%@ / %@", QQPVideoClock(duration), QQPVideoClock(duration)];
        [self updatePlayButton];
        self.ended = YES;
    });
}

- (void)didFailPlayback:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self showPlaybackFailure]; });
}

- (void)didEnterBackground:(NSNotification *)notification {
    self.playWhenReady = NO;
    [self.player pause];
    [self updatePlayButton];
}

- (void)closePreview:(id)sender {
    self.playWhenReady = NO;
    [self.player pause];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)finishPreview {
    if (self.cleanedUp) return;
    self.cleanedUp = YES;
    self.playWhenReady = NO;
    [self.player pause];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
        [self.item removeObserver:self forKeyPath:@"status" context:QQPVideoItemContext];
        [self.item removeObserver:self forKeyPath:@"duration" context:QQPVideoItemContext];
    }
    self.videoLayer.player = nil;
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.item = nil;
    self.player = nil;
    NSURL *directory = self.temporaryDirectory;
    self.temporaryDirectory = nil;
    if (directory) [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
}

- (void)dealloc { [self finishPreview]; }
@end

UIViewController *QQPCreateVideoPreview(NSURL *fileURL, NSURL *temporaryDirectory) {
    if (!NSThread.isMainThread || ![fileURL isKindOfClass:NSURL.class] ||
        ![temporaryDirectory isKindOfClass:NSURL.class] || !fileURL.isFileURL ||
        !temporaryDirectory.isFileURL) return nil;
    NSURL *root = [[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                    URLByAppendingPathComponent:@"QQPhotoBase64" isDirectory:YES]
                   URLByStandardizingPath].URLByResolvingSymlinksInPath;
    NSURL *directory = temporaryDirectory.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    NSURL *file = fileURL.URLByStandardizingPath.URLByResolvingSymlinksInPath;
    if (![directory.URLByDeletingLastPathComponent.path isEqualToString:root.path] ||
        ![file.URLByDeletingLastPathComponent.path isEqualToString:directory.path] ||
        ![@[@"mov", @"mp4", @"m4v"] containsObject:file.pathExtension.lowercaseString]) return nil;
    NSDictionary *dirAttrs = [NSFileManager.defaultManager attributesOfItemAtPath:directory.path error:NULL];
    NSDictionary *fileAttrs = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:NULL];
    if (![dirAttrs[NSFileType] isEqualToString:NSFileTypeDirectory] ||
        ![fileAttrs[NSFileType] isEqualToString:NSFileTypeRegular] ||
        [fileAttrs[NSFileSize] unsignedLongLongValue] == 0) return nil;
    QQPVideoPreviewController *preview = [QQPVideoPreviewController new];
    preview.item = [AVPlayerItem playerItemWithURL:file];
    preview.player = [AVPlayer playerWithPlayerItem:preview.item];
    preview.temporaryDirectory = directory;
    preview.playWhenReady = YES;
    preview.modalPresentationStyle = UIModalPresentationFullScreen;
    return preview;
}
