#import "QQPChat.h"
#import "QQPRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
static const void *QQPBindingKey=&QQPBindingKey;
static const void *QQPDisabledKey=&QQPDisabledKey;
static BOOL QQPCaptureIsDisabled(id picker) {
    return objc_getAssociatedObject(picker,QQPDisabledKey)!=nil;
}
@interface QQPChatBinding : NSObject
@property(nonatomic,weak) id owner;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL assigning;
@end
@implementation QQPChatBinding
@end
@interface QQPChatTarget ()
@property(nonatomic,weak) UIViewController *picker;
@property(nonatomic,weak) id owner;
@property(nonatomic,weak) id context;
@property(nonatomic,strong) QQPChatBinding *binding;
@property(nonatomic) NSUInteger generation;
@property(nonatomic,copy) NSString *uin;
@property(nonatomic,copy) NSString *uid;
@property(nonatomic) int chatType;
+ (instancetype)emptyTarget;
@end
@implementation QQPChatTarget
+ (instancetype)emptyTarget { return [[self alloc] initPrivate]; }
- (instancetype)initPrivate { return [super init]; }
@end

static id QQPBoundContext(id owner) {
    if(!owner || ![owner isKindOfClass:NSObject.class])return nil;
    if(QQPClassNamed(owner,@"AIOChatParameter.AIOChatContext"))return owner;
    if(!NSThread.isMainThread || !QQPClassNamed(owner,@"NTBaseAIO.NTAIOChatBaseViewController"))return nil;
    Class inspector=NSClassFromString(@"QQPContextInspector");
    SEL read=NSSelectorFromString(@"contextForOwner:");
    if(!QQPMethodMatches(object_getClass(inspector),read,"@",@[@"@"]))return nil;
    @try {
        id value=((id(*)(id,SEL,id))objc_msgSend)(inspector,read,owner);
        return QQPClassNamed(value,@"AIOChatParameter.AIOChatContext")?value:nil;
    } @catch(__unused NSException *exception) { return nil; }
}
static BOOL QQPReadIdentity(id context, NSString **uin, NSString **uid, int *type) {
    if(!QQPClassNamed(context,@"AIOChatParameter.AIOChatContext") ||
       !QQPMethodMatches(object_getClass(context),NSSelectorFromString(@"chatType"),"i",@[]))return NO;
    @try {
        id u=QQPGetObject(context,@"peerUin"),v=QQPGetObject(context,@"peerUid");
        if(![u isKindOfClass:NSString.class] || ![v isKindOfClass:NSString.class] ||
           ![u length] || ![v length] || [u length]>256 || [v length]>256)return NO;
        NSCharacterSet *bad=NSCharacterSet.whitespaceAndNewlineCharacterSet;
        if([u rangeOfCharacterFromSet:bad].location!=NSNotFound ||
           [v rangeOfCharacterFromSet:bad].location!=NSNotFound)return NO;
        *uin=[u copy];*uid=[v copy];
        *type=((int(*)(id,SEL))objc_msgSend)(context,NSSelectorFromString(@"chatType"));
        return YES;
    } @catch(__unused NSException *exception) { return NO; }
}
static QQPChatBinding *QQPBinding(UIViewController *picker) {
    return objc_getAssociatedObject(picker,QQPBindingKey);
}
static id QQPVerifiedPickerOwner(UIViewController *picker, QQPChatBinding *binding) {
    if(QQPCaptureIsDisabled(picker) || !NSThread.isMainThread || !picker ||
       !binding || binding.assigning || QQPBinding(picker)!=binding)return nil;
    // Verify what this picker actually stores, not only its setter argument.
    // Prefer an exact object getter. Swift-only weak fields use the bridge's
    // ownership-checked, single-field runtime load; never a guessed ivar cast.
    @try {
        id actual=nil;SEL getter=NSSelectorFromString(@"context");
        if(class_getInstanceMethod(object_getClass(picker),getter)) {
            if(!QQPMethodMatches(object_getClass(picker),getter,"@",@[]))return nil;
            actual=QQPGetObject(picker,@"context");
        } else {
            Class inspector=NSClassFromString(@"QQPContextInspector");
            SEL read=NSSelectorFromString(@"ownerForPicker:");
            if(!QQPMethodMatches(object_getClass(inspector),read,"@",@[@"@"]))return nil;
            actual=((id(*)(id,SEL,id))objc_msgSend)(inspector,read,picker);
        }
        id expected=binding.owner;
        BOOL allowed=actual &&
            ([actual isKindOfClass:NSClassFromString(@"AIOChatParameter.AIOChatContext")] ||
             [actual isKindOfClass:NSClassFromString(@"NTBaseAIO.NTAIOChatBaseViewController")]);
        return allowed && actual==expected && !QQPCaptureIsDisabled(picker) &&
            QQPBinding(picker)==binding && !binding.assigning && binding.owner==actual?actual:nil;
    } @catch(__unused NSException *exception) { return nil; }
}
void QQPInstallChatCapture(void) {
    Class cls=NSClassFromString(@"NTAIOPhotoMediaPickerController");
    QQPHookObjectSetter(cls,NSSelectorFromString(@"setContext:"),
        ^id(id picker,__unused id owner){
            if(!NSThread.isMainThread){
                objc_setAssociatedObject(picker,QQPDisabledKey,@YES,OBJC_ASSOCIATION_RETAIN);
                return nil;
            }
            if(QQPCaptureIsDisabled(picker))return nil;
            // A fresh identity per invocation also protects against setter reentry.
            QQPChatBinding *binding=[QQPChatBinding new];binding.assigning=YES;
            objc_setAssociatedObject(picker,QQPBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return binding;
        },^(id picker,id owner,id token){
            if(!NSThread.isMainThread || !token || QQPBinding(picker)!=token)return;
            QQPChatBinding *binding=token;binding.owner=owner;binding.assigning=NO;
        });
}
QQPChatTarget *QQPCaptureChatTarget(UIViewController *picker, NSString **reason) {
    if(!NSThread.isMainThread || !picker){if(reason)*reason=@"当前相册状态已失效，请返回聊天重新选图。";return nil;}
    QQPChatBinding *binding=QQPBinding(picker);id owner=QQPVerifiedPickerOwner(picker,binding);
    id context=QQPBoundContext(owner);NSString *uin=nil,*uid=nil;int type=0;
    if(!binding || binding.assigning || !owner || !QQPReadIdentity(context,&uin,&uid,&type)){
        if(reason)*reason=@"无法确认这个相册所属的聊天，请返回当前聊天重新打开相册；原图未发送。";
        return nil;
    }
    if(QQPCaptureIsDisabled(picker) || QQPBinding(picker)!=binding ||
       binding.assigning || binding.owner!=owner){
        if(reason)*reason=@"读取聊天期间会话发生变化，未发送。";
        return nil;
    }
    QQPChatTarget *target=[QQPChatTarget emptyTarget];target.picker=picker;
    target.owner=owner;target.context=context;target.binding=binding;
    target.generation=binding.generation;target.uin=uin;target.uid=uid;target.chatType=type;
    return target;
}
BOOL QQPChatTargetMatchesPicker(QQPChatTarget *target,UIViewController *picker) {
    if(!NSThread.isMainThread || !picker || target.picker!=picker)return NO;
    QQPChatBinding *binding=objc_getAssociatedObject(picker,QQPBindingKey);
    id owner=QQPVerifiedPickerOwner(picker,binding),context=QQPBoundContext(owner);
    if(!binding || binding!=target.binding || binding.assigning || binding.generation!=target.generation ||
       !owner || owner!=target.owner || !context || context!=target.context)return NO;
    NSString *uin=nil,*uid=nil;int type=0;
    BOOL matches=QQPReadIdentity(context,&uin,&uid,&type) && type==target.chatType &&
                 [uin isEqualToString:target.uin] && [uid isEqualToString:target.uid];
    return matches && !QQPCaptureIsDisabled(picker) && QQPBinding(picker)==binding &&
           !binding.assigning && binding.owner==owner && binding.generation==target.generation;
}
BOOL QQPSendFilesToChat(NSArray<NSURL *> *files, QQPChatTarget *target,
                        UIViewController *picker, NSUInteger *submitted,
                        NSString **reason) {
    if(submitted)*submitted=0;
    if(!NSThread.isMainThread || !files.count || files.count>9 ||
       !QQPChatTargetMatchesPicker(target,picker)) {
        if(reason)*reason=@"相册所属聊天已变化或失效，请重新选图；原图未发送。";
        return NO;
    }
    Class managerClass=NSClassFromString(@"AIFileManager");
    SEL shared=NSSelectorFromString(@"sharedInstance");
    SEL send=NSSelectorFromString(@"sendFileWithPath:uin:uid:chatType:");
    if(!QQPMethodMatches(object_getClass(managerClass),shared,"@",@[]) ||
       !QQPMethodMatches(managerClass,send,"v",@[@"@",@"@",@"@",@"i"])) {
        if(reason)*reason=@"当前QQ的聊天文件发送接口不匹配，原图未发送。";
        return NO;
    }
    // Validate the entire batch before the first irreversible hand-off.
    NSMutableArray<NSString *> *paths=[NSMutableArray arrayWithCapacity:files.count];
    NSMutableSet<NSString *> *seen=[NSMutableSet set];
    for(NSURL *file in files) {
        if(![file isKindOfClass:NSURL.class] || !file.isFileURL ||
           ![file.pathExtension.lowercaseString isEqualToString:@"qqenc"]) {
            if(reason)*reason=@"编码文件格式不匹配，未提交文件。";
            return NO;
        }
        NSString *path=file.path.stringByStandardizingPath;
        NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        if(![attributes[NSFileType] isEqual:NSFileTypeRegular] || !attributes.fileSize ||
           attributes.fileSize>32ull*1024ull*1024ull*4ull/3ull+4096ull || [seen containsObject:path]) {
            if(reason)*reason=@"编码文件缺失、过大或重复，未提交文件。";
            return NO;
        }
        [seen addObject:path];[paths addObject:path];
    }
    NSUInteger count=0;
    @try {
        id manager=((id(*)(id,SEL))objc_msgSend)(managerClass,shared);
        if(![manager isKindOfClass:managerClass] ||
           !QQPMethodMatches(object_getClass(manager),send,"v",@[@"@",@"@",@"@",@"i"])) {
            if(reason)*reason=@"QQ文件发送服务不可用，未提交文件。";
            return NO;
        }
        for(NSString *path in paths) {
            if(!QQPChatTargetMatchesPicker(target,picker)) {
                if(reason)*reason=@"聊天状态已变化，剩余文件未提交。";
                return NO;
            }
            // Count attempted calls conservatively: an exception can follow a side effect.
            count++;if(submitted)*submitted=count;
            ((void(*)(id,SEL,id,id,id,int))objc_msgSend)(manager,send,path,target.uin,target.uid,target.chatType);
        }
    } @catch(__unused NSException *exception) {
        if(reason)*reason=@"QQ处理文件时发生异常，请先检查聊天记录再决定是否重试。";
        return NO;
    }
    return YES;
}
