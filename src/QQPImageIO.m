#import "QQPImageIO.h"
#import "QQPCodec.h"
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const NSUInteger QQPImageLimit=32*1024*1024;
static NSURL *QQPWorkRoot(void) {
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"QQPhotoBase64"] isDirectory:YES];
}
@interface QQPExportTask ()
@property(atomic) BOOL cancelled;
@property(atomic,copy) void (^cancelRequest)(void);
@end
@implementation QQPExportTask
- (void)cancel {
    self.cancelled=YES;void (^cancel)(void)=self.cancelRequest;if(cancel)cancel();
}
@end
void QQPDiscardExports(NSArray<NSURL *> *files) {
    NSURL *directory=files.firstObject.URLByDeletingLastPathComponent;
    if(directory && [directory.URLByDeletingLastPathComponent.path isEqual:QQPWorkRoot().path])
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
}
void QQPCleanExpiredFiles(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        NSDate *now=NSDate.date;
        for(NSURL *directory in [NSFileManager.defaultManager contentsOfDirectoryAtURL:QQPWorkRoot() includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:NULL]){
            NSDate *date=nil;[directory getResourceValue:&date forKey:NSURLContentModificationDateKey error:NULL];
            if(date && [now timeIntervalSinceDate:date]>24*3600)[NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
        }
    });
}
static NSError *QQPIOError(NSString *message) {
    return [NSError errorWithDomain:@"com.ning.qqphotobase64" code:2 userInfo:@{NSLocalizedDescriptionKey:message}];
}
void QQPShowMessage(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter.viewIfLoaded.window || presenter.presentedViewController) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:a animated:YES completion:nil];
}
static void QQPFinish(QQPExportCompletion completion, NSArray<NSURL *> *files, NSError *error) {
    dispatch_async(dispatch_get_main_queue(),^{completion(files,error);});
}
static PHAssetResource *QQPStillResource(PHAsset *asset) {
    if(asset.mediaType!=PHAssetMediaTypeImage || (asset.mediaSubtypes&PHAssetMediaSubtypePhotoLive))return nil;
    for(PHAssetResource *resource in [PHAssetResource assetResourcesForAsset:asset])if(resource.type==PHAssetResourceTypePhoto)return resource;
    return nil;
}
static void QQPAbort(NSURL *directory,QQPExportCompletion completion,NSError *error) {
    [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];QQPFinish(completion,nil,error?:QQPIOError(@"已取消，未发送。"));
}
static void QQPExportNext(QQPExportTask *task,NSArray<PHAsset *> *assets,NSUInteger index,NSURL *directory,NSMutableArray<NSURL *> *files,QQPExportCompletion completion) {
    if(task.cancelled){QQPAbort(directory,completion,nil);return;}
    if(index>=assets.count){QQPFinish(completion,[files copy],nil);return;}
    PHAssetResource *resource=QQPStillResource(assets[index]);
    if(!resource){QQPAbort(directory,completion,QQPIOError(@"当前只支持静态图片，视频和实况照片未发送。"));return;}
    NSURL *rawURL=[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"raw-%lu",(unsigned long)index]];
    if(![NSFileManager.defaultManager createFileAtPath:rawURL.path contents:nil attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}]){
        QQPAbort(directory,completion,QQPIOError(@"不能创建临时文件。"));return;
    }
    NSError *openError=nil;NSFileHandle *handle=[NSFileHandle fileHandleForWritingToURL:rawURL error:&openError];
    if(!handle){QQPAbort(directory,completion,openError);return;}
    PHAssetResourceRequestOptions *options=[PHAssetResourceRequestOptions new];options.networkAccessAllowed=YES;
    NSObject *lock=[NSObject new];__block NSUInteger size=0;__block NSError *writeError=nil;
    __block PHAssetResourceDataRequestID request=0;__block BOOL ended=NO;
    task.cancelRequest=^{PHAssetResourceDataRequestID current=0;@synchronized(lock){if(!ended)current=request;}if(current)[PHAssetResourceManager.defaultManager cancelDataRequest:current];};
    PHAssetResourceDataRequestID started=[PHAssetResourceManager.defaultManager requestDataForAssetResource:resource options:options dataReceivedHandler:^(NSData *part){
        PHAssetResourceDataRequestID cancel=0;
        @synchronized(lock){
            if(task.cancelled || writeError)return;
            if(part.length>QQPImageLimit-size)writeError=QQPIOError(@"单张图片超过32MB，已停止处理。");
            else {NSError *error=nil;if(![handle writeData:part error:&error])writeError=error?:QQPIOError(@"写入原图失败。");else size+=part.length;}
            if(writeError)cancel=request;
        }
        if(cancel)[PHAssetResourceManager.defaultManager cancelDataRequest:cancel];
    } completionHandler:^(NSError *error){
        @synchronized(lock){ended=YES;request=0;[handle closeFile];error=writeError?:error;}
        task.cancelRequest=nil;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
            if(task.cancelled){QQPAbort(directory,completion,nil);return;}
            NSError *finalError=error;NSData *raw=finalError?nil:[NSData dataWithContentsOfURL:rawURL options:NSDataReadingMappedIfSafe error:&finalError];
            NSData *container=raw?[QQPCodec encodeImageData:raw error:&finalError]:nil;
            if(task.cancelled){QQPAbort(directory,completion,nil);return;}
            NSURL *output=[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"图片-%02lu.qqenc",(unsigned long)index+1]];
            if(container && ![container writeToURL:output options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&finalError])container=nil;
            [NSFileManager.defaultManager removeItemAtURL:rawURL error:NULL];
            if(!container){QQPAbort(directory,completion,finalError?:QQPIOError(@"图片格式不支持，未发送。"));return;}
            [files addObject:output];QQPExportNext(task,assets,index+1,directory,files,completion);
        }});
    }];
    BOOL cancel=NO;@synchronized(lock){if(!ended){request=started;cancel=task.cancelled||writeError!=nil;}}
    if(cancel)[PHAssetResourceManager.defaultManager cancelDataRequest:started];
}
QQPExportTask *QQPExportImages(NSArray<PHAsset *> *assets,QQPExportCompletion completion) {
    QQPExportTask *task=[QQPExportTask new];
    if(!assets.count || assets.count>9){QQPFinish(completion,nil,QQPIOError(@"请一次选择1至9张静态图片。"));return task;}
    NSURL *directory=[QQPWorkRoot() URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error]){QQPFinish(completion,nil,error);return task;}
    QQPExportNext(task,[assets copy],0,directory,[NSMutableArray array],completion);return task;
}

#import <QuickLook/QuickLook.h>
#import <objc/runtime.h>

@interface QQPPreviewSession : NSObject <QLPreviewControllerDataSource,QLPreviewControllerDelegate>
@property(nonatomic,strong) NSURL *fileURL;
@property(nonatomic,strong) NSURL *directory;
@end
@implementation QQPPreviewSession
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller{return 1;}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index{return self.fileURL;}
- (void)previewControllerDidDismiss:(QLPreviewController *)controller{[[NSFileManager defaultManager]removeItemAtURL:self.directory error:nil];}
- (void)dealloc{if(_directory)[[NSFileManager defaultManager]removeItemAtURL:_directory error:nil];}
@end
static const void *QQPPreviewKey=&QQPPreviewKey;
void QQPPreviewContainer(NSString *path, UIViewController *presenter) {
    if(![path isKindOfClass:NSString.class] || !path.length || !presenter.viewIfLoaded.window || presenter.presentedViewController)return;
    __weak UIViewController *weakPresenter=presenter;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        NSError *error=nil;
        NSDictionary *attributes=[[NSFileManager defaultManager]attributesOfItemAtPath:path error:&error];
        unsigned long long length=[attributes fileSize];
        NSData *container=nil;
        if(length && length<=32u*1024u*1024u*4u/3u+4096u)container=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
        NSData *raw=container?[QQPCodec decodeContainer:container error:&error]:nil;
        if(!raw){dispatch_async(dispatch_get_main_queue(),^{QQPShowMessage(weakPresenter,@"无法解密",error.localizedDescription?:@"请先下载完整的.qqenc文件，或检查文件大小。" );});return;}
        CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)raw,NULL);
        NSString *uti=source?(__bridge NSString *)CGImageSourceGetType(source):nil;
        NSString *ext=uti?[UTType typeWithIdentifier:uti].preferredFilenameExtension:nil;
        if(source)CFRelease(source);
        if(!ext.length)ext=@"img";
        NSURL *dir=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"QQPhotoBase64/decoded-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
        [[NSFileManager defaultManager]createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error];
        NSURL *file=[dir URLByAppendingPathComponent:[@"原图" stringByAppendingPathExtension:ext]];
        BOOL written=[raw writeToURL:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error];
        dispatch_async(dispatch_get_main_queue(),^{
            UIViewController *host=weakPresenter;
            if(!written || !host.viewIfLoaded.window || host.presentedViewController){[[NSFileManager defaultManager]removeItemAtURL:dir error:nil];if(!written)QQPShowMessage(host,@"无法打开",error.localizedDescription);return;}
            QQPPreviewSession *session=[QQPPreviewSession new];session.fileURL=file;session.directory=dir;
            QLPreviewController *preview=[QLPreviewController new];preview.dataSource=session;preview.delegate=session;
            objc_setAssociatedObject(preview,QQPPreviewKey,session,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [host presentViewController:preview animated:YES completion:nil];
        });
    }});
}
