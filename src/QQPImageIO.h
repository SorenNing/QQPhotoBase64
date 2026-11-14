#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^QQPExportCompletion)(NSArray<NSURL *> * _Nullable files, NSError * _Nullable error);
@interface QQPExportTask : NSObject
- (void)cancel;
@end
QQPExportTask *QQPExportImages(NSArray<PHAsset *> *assets, QQPExportCompletion completion);
void QQPDiscardExports(NSArray<NSURL *> * _Nullable files);
void QQPCleanExpiredFiles(void);
void QQPPreviewContainer(NSString *path, UIViewController *presenter);
void QQPShowMessage(UIViewController * _Nullable presenter, NSString *title, NSString * _Nullable message);
NS_ASSUME_NONNULL_END
