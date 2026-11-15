#import "QQPChat.h"
#import "QQPRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
@interface QQPChatTarget ()
@property(nonatomic,weak) UIViewController *picker;
@property(nonatomic,weak) id context;
@property(nonatomic,copy) NSString *uin;
@property(nonatomic,copy) NSString *uid;
@property(nonatomic) int chatType;
+ (instancetype)emptyTarget;
@end
@implementation QQPChatTarget
+ (instancetype)emptyTarget { return [[self alloc] initPrivate]; }
- (instancetype)initPrivate { return [super init]; }
@end

static id QQPPickerContext(UIViewController *picker) {
    if(!NSThread.isMainThread || !picker || !picker.viewIfLoaded.window ||
       !(QQPClassNamed(picker,@"NTAIOPhotoMediaPickerController") ||
         QQPClassNamed(picker,@"PhotoPickerViewController")))return nil;
    SEL getter=NSSelectorFromString(@"context");
    Class cls=object_getClass(picker);
    if(!QQPMethodMatches(cls,getter,"@",@[]))return nil;
    @try {
        id context=((id(*)(id,SEL))objc_msgSend)(picker,getter);
        return QQPClassNamed(context,@"AIOChatParameter.AIOChatContext")?context:nil;
    } @catch(__unused NSException *exception) { return nil; }
}
static BOOL QQPReadIdentity(id context, NSString **uin, NSString **uid, int *type) {
    if(!QQPClassNamed(context,@"AIOChatParameter.AIOChatContext") ||
       !QQPMethodMatches(object_getClass(context),NSSelectorFromString(@"chatType"),"i",@[]))return NO;
    @try {
        id u=QQPGetObject(context,@"peerUin"),v=QQPGetObject(context,@"peerUid");
        if(!u)u=@"";if(!v)v=@"";
        if(![u isKindOfClass:NSString.class] || ![v isKindOfClass:NSString.class] ||
           (![u length] && ![v length]) || [u length]>256 || [v length]>256)return NO;
        NSCharacterSet *bad=NSCharacterSet.whitespaceAndNewlineCharacterSet;
        if([u rangeOfCharacterFromSet:bad].location!=NSNotFound ||
           [v rangeOfCharacterFromSet:bad].location!=NSNotFound)return NO;
        *uin=[u copy];*uid=[v copy];
        *type=((int(*)(id,SEL))objc_msgSend)(context,NSSelectorFromString(@"chatType"));
        return YES;
    } @catch(__unused NSException *exception) { return NO; }
}
QQPChatTarget *QQPCaptureChatTarget(UIViewController *picker, NSString **reason) {
    id context=QQPPickerContext(picker);
    NSString *uin=nil,*uid=nil;int type=0;
    if(!context || !QQPReadIdentity(context,&uin,&uid,&type) ||
       QQPPickerContext(picker)!=context){
        if(reason)*reason=@"无法确认相册所属的当前聊天；原图未发送。";
        return nil;
    }
    QQPChatTarget *target=[QQPChatTarget emptyTarget];target.picker=picker;
    target.context=context;target.uin=uin;target.uid=uid;target.chatType=type;
    return target;
}
BOOL QQPChatTargetMatchesPicker(QQPChatTarget *target,UIViewController *picker) {
    if(!NSThread.isMainThread || !target || !picker || target.picker!=picker)return NO;
    id context=QQPPickerContext(picker);
    if(!context || context!=target.context)return NO;
    NSString *uin=nil,*uid=nil;int type=0;
    BOOL matches=QQPReadIdentity(context,&uin,&uid,&type) && type==target.chatType &&
                 [uin isEqualToString:target.uin] && [uid isEqualToString:target.uid];
    return matches && QQPPickerContext(picker)==context;
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
           [seen containsObject:path]) {
            if(reason)*reason=@"编码文件缺失或重复，未提交文件。";
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
