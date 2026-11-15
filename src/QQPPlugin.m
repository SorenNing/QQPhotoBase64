#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "QQPRuntime.h"
#import "QQPImageIO.h"
#import "QQPChat.h"
#import "QQPCodec.h"

static const void *QQPSessionKey=&QQPSessionKey;
static const void *QQPControlKey=&QQPControlKey;
static const void *QQPDecodeKey=&QQPDecodeKey;

@interface QQPSession : NSObject
@property(nonatomic) BOOL selected;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL submitted;
@property(nonatomic,weak) UIViewController *picker;
@property(nonatomic,strong) NSArray<NSURL *> *exports;
@property(nonatomic,strong) QQPExportTask *task;
@property(nonatomic) NSUInteger generation;
@end
@implementation QQPSession
@end
@interface QQPEncryptButton : UIButton
@property(nonatomic,weak) QQPSession *session;
@end
@implementation QQPEncryptButton
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        [self setTitle:@"加密" forState:UIControlStateNormal];self.titleLabel.font=[UIFont systemFontOfSize:13];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateSelected];
        [self setTitleColor:[UIColor.whiteColor colorWithAlphaComponent:0.55] forState:UIControlStateDisabled];
        UIImageSymbolConfiguration *config=[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightRegular];
        [self setImage:[UIImage systemImageNamed:@"circle" withConfiguration:config] forState:UIControlStateNormal];
        [self setImage:[UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:config] forState:UIControlStateSelected];
        self.imageView.contentMode=UIViewContentModeScaleAspectFit;
        self.titleLabel.textAlignment=NSTextAlignmentLeft;self.tintColor=UIColor.whiteColor;
        [self addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
        self.accessibilityLabel=@"加密，Base64图片或视频文件";
    }return self;
}
- (CGRect)imageRectForContentRect:(CGRect)rect {
    return CGRectMake(CGRectGetMinX(rect),CGRectGetMidY(rect)-8,16,16);
}
- (CGRect)titleRectForContentRect:(CGRect)rect {
    return CGRectMake(CGRectGetMinX(rect)+21,CGRectGetMinY(rect),MAX(0,CGRectGetWidth(rect)-21),CGRectGetHeight(rect));
}
- (void)toggle:(id)sender {
    if(!self.session || self.session.busy || self.session.submitted)return;
    self.session.selected=!self.session.selected;
    self.selected=self.session.selected;
    self.accessibilityValue=self.selected?@"已勾选":@"未勾选";
}
@end
static UIViewController *QQPFindPickerFromController(UIViewController *owner) {
    NSMutableArray<UIViewController *> *queue=[NSMutableArray array];if(owner)[queue addObject:owner];
    NSHashTable *seen=[NSHashTable weakObjectsHashTable];UIViewController *fallback=nil;
    for(NSUInteger i=0;i<queue.count && i<24;i++){
        UIViewController *vc=queue[i];if([seen containsObject:vc])continue;[seen addObject:vc];
        if(QQPClassNamed(vc,@"PhotoPickerViewController") || QQPClassNamed(vc,@"QQMultiImagePickerController"))return vc;
        if(QQPClassNamed(vc,@"QQImageTableViewController"))fallback=vc;
        if(vc.parentViewController)[queue addObject:vc.parentViewController];
        if(vc.navigationController)[queue addObject:vc.navigationController];
        if(vc.presentingViewController)[queue addObject:vc.presentingViewController];
    }return fallback;
}
static QQPSession *QQPSessionForBar(UIView *bar) {
    UIViewController *picker=QQPFindPickerFromController(QQPOwningController(bar));if(!picker)return nil;
    QQPSession *s=objc_getAssociatedObject(picker,QQPSessionKey);
    if(!s){s=[QQPSession new];s.picker=picker;objc_setAssociatedObject(picker,QQPSessionKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return s;
}
static void QQPCollectViews(UIView *root,NSMutableArray<UIView *> *views) {
    if(!root)return;[views addObject:root];
    for(NSUInteger i=0;i<views.count && i<384;i++){
        for(UIView *child in [views[i].subviews copy]){if(views.count>=384)return;[views addObject:child];}
    }
}
static NSArray<PHAsset *> *QQPSelectedMedia(QQPSession *s) {
    UIViewController *picker=s.picker;id objects=QQPGetObject(picker,@"selectedList");
    if(![objects isKindOfClass:NSArray.class]){
        NSMutableArray<UIView *> *views=[NSMutableArray array];QQPCollectViews(picker.viewIfLoaded,views);
        for(UIView *view in views)if(QQPClassNamed(view,@"QQAlbumPicker.GalleryView")){
            id vm=QQPGetObject(view,@"viewModel");id model=QQPGetObject(vm,@"selectionModel");
            objects=QQPGetObject(model,@"selectedAssets");if([objects isKindOfClass:NSArray.class])break;
        }
    }
    if(![objects isKindOfClass:NSArray.class] || ![objects count] || [objects count]>9)return nil;
    NSMutableArray<PHAsset *> *result=[NSMutableArray array];
    for(id object in [objects copy]){
        id ph=[object isKindOfClass:PHAsset.class]?object:QQPGetObject(object,@"underlyingObject");
        if(!ph)ph=QQPGetObject(object,@"phAsset");
        if(![ph isKindOfClass:PHAsset.class])return nil;
        PHAsset *photo=(PHAsset *)ph;
        if(photo.mediaType!=PHAssetMediaTypeVideo &&
           (photo.mediaType!=PHAssetMediaTypeImage || (photo.mediaSubtypes&PHAssetMediaSubtypePhotoLive)))return nil;
        [result addObject:photo];
    }
    return [result copy];
}
static UIView *QQPOriginalButton(UIView *bar) {
    NSMutableArray<UIView *> *views=[NSMutableArray array];QQPCollectViews(bar,views);
    for(UIView *v in views){
        if(QQPClassNamed(v,@"PhotoOperatorView.PhotoMediaPickerOriginButton"))return v;
        if([v isKindOfClass:UIButton.class] && [((UIButton *)v).currentTitle containsString:@"原图"])return v;
    }return nil;
}
static void QQPLayoutBar(UIView *bar) {
    QQPSession *session=QQPSessionForBar(bar);QQPEncryptButton *button=objc_getAssociatedObject(bar,QQPControlKey);
    UIView *origin=QQPOriginalButton(bar);
    if(!session || !origin || origin.hidden || CGRectGetWidth(bar.bounds)<180){button.hidden=YES;return;}
    if(!button){button=[[QQPEncryptButton alloc]initWithFrame:CGRectMake(0,0,72,36)];objc_setAssociatedObject(bar,QQPControlKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[bar addSubview:button];}
    button.session=session;button.selected=session.selected;button.enabled=!session.busy && !session.submitted;
    CGRect anchor=[origin convertRect:origin.bounds toView:bar];
    CGFloat width=72,x=CGRectGetMaxX(anchor)+6,y=CGRectGetMidY(anchor)-18;
    CGRect target=CGRectMake(x,y,width,36);
    BOOL fits=CGRectGetMaxX(target)<=CGRectGetWidth(bar.bounds)-4 && y>=0 && CGRectGetMaxY(target)<=CGRectGetHeight(bar.bounds);
    if(fits)for(UIView *v in bar.subviews){
        if(v==button || v==origin || v.hidden || v.alpha<0.01 || ![v isKindOfClass:UIControl.class])continue;
        if(CGRectIntersectsRect(v.frame,CGRectInset(target,2,2))){fits=NO;break;}
    }
    if(!fits){x=CGRectGetMinX(anchor)-width-6;target=CGRectMake(x,y,width,36);fits=x>=4 && CGRectGetMaxX(target)<=CGRectGetWidth(bar.bounds)-4 && y>=0 && CGRectGetMaxY(target)<=CGRectGetHeight(bar.bounds);
        if(fits)for(UIView *v in bar.subviews){if(v==button||v==origin||v.hidden||![v isKindOfClass:UIControl.class])continue;if(CGRectIntersectsRect(v.frame,CGRectInset(target,2,2))){fits=NO;break;}}
    }
    button.hidden=!fits;button.frame=target;
}

static BOOL QQPValidExports(NSArray<NSURL *> *files) {
    if(!files.count || files.count>9)return NO;
    for(NSURL *file in files){
        @autoreleasepool {
            if(![file isKindOfClass:NSURL.class] || !file.isFileURL ||
               ![file.pathExtension.lowercaseString isEqualToString:@"qqenc"])return NO;
            NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
            unsigned long long length=[attrs fileSize];
            if(![attrs[NSFileType] isEqual:NSFileTypeRegular] || !length)return NO;
            if([QQPCodec isVideoContainerAtURL:file]){
                if(![QQPCodec validateVideoContainerAtURL:file error:nil])return NO;
            }else{
                if(length>32ull*1024ull*1024ull*4ull/3ull+4096ull)return NO;
                NSData *data=[NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe error:nil];
                if(!data || ![QQPCodec decodeContainer:data error:nil])return NO;
            }
        }
    }
    return YES;
}
static void QQPOfferEncryptedShare(UIViewController *host, QQPSession *session,
                                   NSArray<NSURL *> *files, NSString *reason) {
    if(!host.viewIfLoaded.window || host.presentedViewController || !QQPValidExports(files)){
        QQPDiscardExports(files);session.busy=NO;
        return;
    }
    session.exports=files;session.busy=NO;session.submitted=YES;
    UIAlertController *notice=[UIAlertController alertControllerWithTitle:@"无法确认当前聊天直发"
        message:reason.length?reason:@"QQ直发接口不可用。可手动分享仅已编码的 .qqenc 文件，或取消；不会发送原图。"
        preferredStyle:UIAlertControllerStyleAlert];
    [notice addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIViewController *weakHost=host;
    __weak UIAlertController *weakNotice=notice;
    [notice addAction:[UIAlertAction actionWithTitle:@"分享编码文件" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action){
            UIViewController *presenter=weakHost;
            UIAlertController *alert=weakNotice;
            void (^showShare)(void)=^{
                if(!presenter.viewIfLoaded.window || presenter.presentedViewController)return;
                UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:files applicationActivities:nil];
                [presenter presentViewController:share animated:YES completion:nil];
            };
            if(presenter.presentedViewController==alert)
                [alert dismissViewControllerAnimated:YES completion:showShare];
            else showShare();
        }]];
    [host presentViewController:notice animated:YES completion:nil];
}

static void QQPReturnToChat(QQPSession *session) {
    UIViewController *picker=session.picker;
    if(!picker || !picker.viewIfLoaded.window || picker.presentedViewController)return;
    SEL dismiss=NSSelectorFromString(@"dismissVC");
    if(QQPClassNamed(picker,@"NTAIOPhotoMediaPickerController") &&
       QQPMethodMatches(object_getClass(picker),dismiss,"v",@[])){
        ((void(*)(id,SEL))objc_msgSend)(picker,dismiss);
        return;
    }
    UIViewController *modal=picker;
    for(NSUInteger i=0;i<8 && modal;i++,modal=modal.parentViewController){
        if(modal.presentingViewController && modal.viewIfLoaded.window){
            [modal dismissViewControllerAnimated:YES completion:nil];return;
        }
    }
    UINavigationController *nav=picker.navigationController;
    NSArray<UIViewController *> *stack=nav.viewControllers;
    if(stack.count>=2 && stack.lastObject==picker && nav.viewIfLoaded.window &&
       QQPClassNamed(stack[stack.count-2],@"NTAIOChat.NTAIOChatViewController"))
        [nav popViewControllerAnimated:YES];
}
// File submission uses the recipient captured from this picker.
static BOOL QQPInterceptSend(UIView *bar) {
    QQPSession *s=QQPSessionForBar(bar);if(!s.selected)return NO;
    if(s.busy)return YES;
    UIViewController *presenter=QQPOwningController(bar);
    if(s.submitted)return YES;
    NSString *reason=nil;QQPChatTarget *target=QQPCaptureChatTarget(s.picker,&reason);
    NSArray<PHAsset *> *assets=QQPSelectedMedia(s);
    if(!assets.count){QQPShowMessage(presenter,@"未发送",@"请在相册选择1至9项图片或视频；实况照片及不支持的资源不会发送。" );return YES;}
    s.busy=YES;[bar setNeedsLayout];__weak UIView *weakBar=bar;__weak UIViewController *weakPresenter=presenter;
    NSUInteger generation=++s.generation;
    s.task=QQPExportMedia(assets,^(NSArray<NSURL *> *files,NSError *error){
        if(generation!=s.generation){QQPDiscardExports(files);return;}
        s.task=nil;UIViewController *host=weakPresenter;
        if(!host.viewIfLoaded.window || host.presentedViewController){s.busy=NO;[weakBar setNeedsLayout];QQPDiscardExports(files);return;}
        if(!files.count){s.busy=NO;[weakBar setNeedsLayout];QQPShowMessage(host,@"未发送",error.localizedDescription?:@"图片处理失败。" );return;}
        if(!target){
            QQPOfferEncryptedShare(host,s,files,reason);
            [weakBar setNeedsLayout];
            return;
        }
        NSString *failure=nil;NSUInteger submitted=0;
        BOOL complete=QQPSendFilesToChat(files,target,s.picker,&submitted,&failure);
        if(!complete && submitted==0){
            QQPOfferEncryptedShare(host,s,files,failure);
            [weakBar setNeedsLayout];
            return;
        }
        s.busy=NO;s.submitted=submitted>0;
        if(submitted)s.exports=files;else QQPDiscardExports(files);
        [weakBar setNeedsLayout];
        if(complete && submitted==files.count)QQPReturnToChat(s);
        else QQPShowMessage(host,@"提交中断，请检查聊天",failure?:@"QQ处理文件异常；请检查聊天记录，不要重复发送。" );
    });return YES;
}

static NSString *QQPContainerPath(UIViewController *controller) {
    id model=QQPGetObject(controller,@"curFileModel");
    id path=QQPGetObject(model,@"strFilePath");
    return [path isKindOfClass:NSString.class]?path:nil;
}
static BOOL QQPIsContainerPage(UIViewController *controller) {
    id model=QQPGetObject(controller,@"curFileModel");
    id filename=QQPGetObject(model,@"strFileName");
    NSString *path=QQPContainerPath(controller);
    return ([filename isKindOfClass:NSString.class] && [[filename pathExtension].lowercaseString isEqualToString:@"qqenc"]) || [path.pathExtension.lowercaseString isEqualToString:@"qqenc"];
}
@interface QQPDecodeButton : UIButton
@property(nonatomic,weak) UIViewController *host;
@end
@implementation QQPDecodeButton
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        [self setTitle:@"解密" forState:UIControlStateNormal];
        self.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        self.backgroundColor=UIColor.systemBlueColor;self.layer.cornerRadius=20;
        [self addTarget:self action:@selector(openContainer:) forControlEvents:UIControlEventTouchUpInside];
    }return self;
}
- (void)openContainer:(id)sender {
    UIViewController *host=self.host;
    if(!QQPIsContainerPage(host))return;
    NSString *path=QQPContainerPath(host);
    if(!path.length){QQPShowMessage(host,@"请先下载",@"请使用QQ下载完整的.qqenc文件，再点解密。" );return;}
    QQPPreviewContainer(path,host);
}
@end
static CGRect QQPOpenWithOtherAppFrame(UIView *root) {
    NSMutableArray<UIView *> *views=[NSMutableArray array];QQPCollectViews(root,views);
    for(UIView *view in views){
        if(view.hidden || view.alpha<0.01)continue;
        NSString *text=nil;
        if([view isKindOfClass:UIButton.class])text=((UIButton *)view).currentTitle;
        else if([view isKindOfClass:UILabel.class])text=((UILabel *)view).text;
        if(![text containsString:@"用其他应用打开"] && ![view.accessibilityLabel containsString:@"用其他应用打开"])continue;
        UIView *anchor=view;
        for(UIView *parent=view.superview;parent && parent!=root;parent=parent.superview){
            if(parent.hidden || parent.alpha<0.01)break;
            if([parent isKindOfClass:UIControl.class] ||
               (CGRectGetWidth(parent.bounds)>=CGRectGetWidth(root.bounds)*0.5 &&
                CGRectGetHeight(parent.bounds)>=36 && CGRectGetHeight(parent.bounds)<=110)){
                anchor=parent;break;
            }
        }
        CGRect frame=[anchor convertRect:anchor.bounds toView:root];
        if(CGRectGetMinY(frame)>CGRectGetHeight(root.bounds)*0.5 &&
           CGRectGetMaxY(frame)<=CGRectGetHeight(root.bounds)+2 &&
           CGRectGetWidth(frame)>=40 && CGRectGetHeight(frame)>10){
            if(anchor==view && [view isKindOfClass:UILabel.class])frame.origin.y-=22;
            return frame;
        }
    }
    return CGRectNull;
}
static void QQPLayoutFilePage(UIViewController *controller) {
    QQPDecodeButton *button=objc_getAssociatedObject(controller,QQPDecodeKey);
    if(!QQPIsContainerPage(controller)){button.hidden=YES;return;}
    CGRect native=QQPOpenWithOtherAppFrame(controller.view);
    if(CGRectIsNull(native)){button.hidden=YES;return;}
    UIEdgeInsets safe=controller.view.safeAreaInsets;
    CGFloat width=104,height=44;
    CGFloat x=CGRectGetMidX(native)-width/2,y=CGRectGetMinY(native)-height-28;
    if(x<safe.left+12 || x+width>CGRectGetWidth(controller.view.bounds)-safe.right-12 ||
       y<safe.top+12 || y+height>=CGRectGetMinY(native)){button.hidden=YES;return;}
    if(!button){button=[[QQPDecodeButton alloc]initWithFrame:CGRectZero];button.host=controller;objc_setAssociatedObject(controller,QQPDecodeKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);[controller.view addSubview:button];}
    button.frame=CGRectMake(x,y,width,height);button.layer.cornerRadius=height/2;
    button.hidden=NO;[controller.view bringSubviewToFront:button];
}
static void QQPCancelLeaving(id object) {
    UIViewController *vc=object;UIViewController *picker=QQPFindPickerFromController(vc);
    QQPSession *s=picker?objc_getAssociatedObject(picker,QQPSessionKey):nil;
    if(!s.busy)return;
    ++s.generation;[s.task cancel];s.task=nil;s.busy=NO;
}
static void QQPInstallHooks(void) {
    static BOOL installed=NO;if(installed)return;installed=YES;
    NSArray<NSString *> *barNames=@[@"QQImagePickerBottomBar",@"PhotoOperatorView.QQPhotoOperatorView",@"_TtC17PhotoOperatorView19QQPhotoOperatorView"];
    NSMutableSet *seen=[NSMutableSet set];
    for(NSString *name in barNames){
        Class cls=NSClassFromString(name);if(!cls || [seen containsObject:cls])continue;[seen addObject:cls];
        SEL send=NSSelectorFromString([name isEqualToString:@"QQImagePickerBottomBar"]?@"onSendButtonClick:":@"sendButtonClick:");
        BOOL boolReturn=[name isEqualToString:@"QQImagePickerBottomBar"];
        if(QQPHookSend(cls,send,boolReturn,^BOOL(id object,id arg){return QQPInterceptSend(object);})){QQPHookVoid(cls,@selector(layoutSubviews),^(id object){QQPLayoutBar(object);});}
    }
    for(NSString *name in @[@"QQImageTableViewController",@"PhotoPickerViewController",@"QQMultiImagePickerController",@"PhotoPreviewController"])
        QQPHookAppearance(NSClassFromString(name),@selector(viewWillDisappear:),^(id object){QQPCancelLeaving(object);});
    QQPCleanExpiredFiles();
    Class file=NSClassFromString(@"NTFAViewController");
    QQPHookVoid(file,@selector(viewDidLayoutSubviews),^(id object){QQPLayoutFilePage(object);});
}
__attribute__((constructor)) static void QQPInitialize(void) {
    if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.mqq"])return;
    dispatch_async(dispatch_get_main_queue(),^{QQPInstallHooks();});
}
