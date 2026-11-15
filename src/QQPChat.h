#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface QQPChatTarget : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
void QQPInstallChatCapture(void);
QQPChatTarget * _Nullable QQPCaptureChatTarget(UIViewController *picker, NSString * _Nullable * _Nullable reason);
BOOL QQPChatTargetMatchesPicker(QQPChatTarget *target, UIViewController *picker);
// Reports local hand-off only: the private QQ API returns void, not a delivery receipt.
BOOL QQPSendFilesToChat(NSArray<NSURL *> *files, QQPChatTarget *target,
                        UIViewController *picker, NSUInteger *submitted,
                        NSString * _Nullable * _Nullable reason);
NS_ASSUME_NONNULL_END
