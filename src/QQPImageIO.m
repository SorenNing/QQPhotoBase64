#import "QQPImageIO.h"
#import "QQPCodec.h"
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import "QQPRuntime.h"

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

static const void *QQPPreviewBusyKey=&QQPPreviewBusyKey;
static const void *QQPPreviewTokenKey=&QQPPreviewTokenKey;
@interface QQPImagePreview : UIViewController <UIScrollViewDelegate>
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,strong) UIScrollView *zoomView;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,strong) UIButton *closeButton;
@end
@implementation QQPImagePreview
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.blackColor;
    UIScrollView *zoom=[[UIScrollView alloc]initWithFrame:self.view.bounds];
    zoom.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    zoom.delegate=self;zoom.minimumZoomScale=1;zoom.maximumZoomScale=4;
    zoom.showsHorizontalScrollIndicator=NO;zoom.showsVerticalScrollIndicator=NO;
    [self.view addSubview:zoom];self.zoomView=zoom;
    UIImageView *imageView=[[UIImageView alloc]initWithImage:self.image];
    imageView.contentMode=UIViewContentModeScaleAspectFit;
    [zoom addSubview:imageView];self.imageView=imageView;
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    close.accessibilityLabel=@"关闭图片预览";
    [close addTarget:self action:@selector(closePreview:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];self.closeButton=close;
}
- (UIStatusBarStyle)preferredStatusBarStyle {return UIStatusBarStyleLightContent;}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.closeButton.frame=CGRectMake(self.view.safeAreaInsets.left+12,self.view.safeAreaInsets.top+8,56,44);
    if(self.zoomView.zoomScale==1){
        CGSize size=self.image.size;CGSize bounds=self.zoomView.bounds.size;
        if(size.width>0 && size.height>0 && bounds.width>0 && bounds.height>0){
            CGFloat scale=MIN(bounds.width/size.width,bounds.height/size.height);
            self.imageView.frame=CGRectMake(0,0,size.width*scale,size.height*scale);
            self.zoomView.contentSize=self.imageView.bounds.size;
        }
    }
    [self centerImage];[self.view bringSubviewToFront:self.closeButton];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {return self.imageView;}
- (void)scrollViewDidZoom:(UIScrollView *)scrollView {[self centerImage];}
- (void)centerImage {
    CGSize frame=self.zoomView.bounds.size;CGSize content=self.zoomView.contentSize;
    self.zoomView.contentInset=UIEdgeInsetsMake(MAX(0,(frame.height-content.height)/2),
        MAX(0,(frame.width-content.width)/2),MAX(0,(frame.height-content.height)/2),
        MAX(0,(frame.width-content.width)/2));
}
- (void)closePreview:(id)sender {[self dismissViewControllerAnimated:YES completion:nil];}
@end
void QQPPreviewContainer(NSString *path, UIViewController *presenter) {
    if(![path isKindOfClass:NSString.class] || !path.length || !presenter.viewIfLoaded.window || presenter.presentedViewController)return;
    if([objc_getAssociatedObject(presenter,QQPPreviewBusyKey) boolValue])return;
    NSObject *token=[NSObject new];
    objc_setAssociatedObject(presenter,QQPPreviewTokenKey,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(presenter,QQPPreviewBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIViewController *weakPresenter=presenter;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
        NSError *error=nil;
        NSDictionary *attributes=[[NSFileManager defaultManager]attributesOfItemAtPath:path error:&error];
        unsigned long long length=[attributes fileSize];
        NSData *container=nil;
        if(length && length<=32u*1024u*1024u*4u/3u+4096u)
            container=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&error];
        NSData *raw=container?[QQPCodec decodeContainer:container error:&error]:nil;
        if(!raw){dispatch_async(dispatch_get_main_queue(),^{
            UIViewController *host=weakPresenter;
            if(objc_getAssociatedObject(host,QQPPreviewTokenKey)!=token)return;
            objc_setAssociatedObject(host,QQPPreviewBusyKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            QQPShowMessage(host,@"无法解密",error.localizedDescription?:@"请先下载完整的.qqenc文件，或检查文件大小。" );
        });return;}
        CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)raw,
            (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
        CGImageRef thumbnail=source?CGImageSourceCreateThumbnailAtIndex(source,0,
            (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                (id)kCGImageSourceCreateThumbnailWithTransform:@YES,
                (id)kCGImageSourceThumbnailMaxPixelSize:@2048}):NULL;
        if(source)CFRelease(source);
        UIImage *image=thumbnail?[UIImage imageWithCGImage:thumbnail]:nil;
        if(thumbnail)CGImageRelease(thumbnail);
        dispatch_async(dispatch_get_main_queue(),^{
            UIViewController *host=weakPresenter;
            if(objc_getAssociatedObject(host,QQPPreviewTokenKey)!=token)return;
            objc_setAssociatedObject(host,QQPPreviewBusyKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            id model=QQPGetObject(host,@"curFileModel");
            NSString *current=QQPGetObject(model,@"strFilePath");
            if(![current isKindOfClass:NSString.class] || ![current isEqualToString:path] ||
               !host.viewIfLoaded.window || host.presentedViewController)return;
            if(!image){QQPShowMessage(host,@"无法打开",@"图片解码失败，请检查文件是否完整。" );return;}
            QQPImagePreview *preview=[QQPImagePreview new];preview.image=image;
            preview.modalPresentationStyle=UIModalPresentationFullScreen;
            [host presentViewController:preview animated:YES completion:nil];
        });
    }});
}
