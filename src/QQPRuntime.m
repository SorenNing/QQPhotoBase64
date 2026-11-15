#import "QQPRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdlib.h>
#include <string.h>

static const char *QQPSkipQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL QQPObjectEncoding(const char *type) {
    if(!type)return NO;
    if(strcmp(type,"@")==0)return YES;
    size_t length=strlen(type);
    return length>=4 && type[0]=='@' && type[1]=='"' &&
           type[length-1]=='"' && strchr(type+2,'"')==type+length-1;
}
BOOL QQPMethodMatches(Class cls, SEL sel, const char *result, NSArray<NSString *> *arguments) {
    if (!cls) return NO;
    Method method=class_getInstanceMethod(cls,sel);
    if (!method || method_getNumberOfArguments(method)!=arguments.count+2) return NO;
    char *ret=method_copyReturnType(method);
    const char *unqualified=QQPSkipQualifiers(ret);
    BOOL matches=unqualified && (result[0]=='@' && result[1]=='\0' ? QQPObjectEncoding(unqualified) : strcmp(unqualified,result)==0);
    free(ret);
    char *selfType=method_copyArgumentType(method,0),*commandType=method_copyArgumentType(method,1);
    matches=matches && QQPObjectEncoding(QQPSkipQualifiers(selfType)) &&
            QQPSkipQualifiers(commandType) && strcmp(QQPSkipQualifiers(commandType),":")==0;
    free(selfType);free(commandType);
    for (NSUInteger i=0; matches && i<arguments.count; i++) {
        char *type=method_copyArgumentType(method,(unsigned int)i+2);
        const char *plain=QQPSkipQualifiers(type), *expected=arguments[i].UTF8String;
        matches=plain && (expected[0]=='@' && expected[1]=='\0' ? QQPObjectEncoding(plain) : strcmp(plain,expected)==0);
        free(type);
    }
    return matches;
}
id QQPGetObject(id object, NSString *selector) {
    if (!object || !QQPMethodMatches(object_getClass(object),NSSelectorFromString(selector),"@",@[])) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(selector));
}
BOOL QQPClassNamed(id object, NSString *name) {
    Class cls=NSClassFromString(name);
    if (!cls && [name containsString:@"."]) {
        NSArray<NSString *> *p=[name componentsSeparatedByString:@"."];
        if(p.count==2) cls=NSClassFromString([NSString stringWithFormat:@"_TtC%lu%@%lu%@",(unsigned long)p[0].length,p[0],(unsigned long)p[1].length,p[1]]);
    }
    return cls && [object isKindOfClass:cls];
}
UIViewController *QQPOwningController(UIView *view) {
    UIResponder *node=view;
    for (NSUInteger depth=0; node && depth<64; depth++,node=node.nextResponder) if ([node isKindOfClass:UIViewController.class]) return (UIViewController *)node;
    return nil;
}
static NSMutableSet<NSString *> *QQPHookedPairs(void) {
    static NSMutableSet<NSString *> *set;static dispatch_once_t once;
    dispatch_once(&once,^{set=[NSMutableSet set];});return set;
}
static NSString *QQPHookKey(Class cls,SEL selector) {return [NSString stringWithFormat:@"%p/%@",cls,NSStringFromSelector(selector)];}
static BOOL QQPReplace(Class cls, SEL selector, IMP replacement, IMP original) {
    NSString *key=QQPHookKey(cls,selector);
    if([QQPHookedPairs() containsObject:key]){imp_removeBlock(replacement);return NO;}
    Method method=class_getInstanceMethod(cls,selector);
    if (!method || method_getImplementation(method)!=original) { imp_removeBlock(replacement); return NO; }
    if(!class_addMethod(cls,selector,replacement,method_getTypeEncoding(method)))method_setImplementation(class_getInstanceMethod(cls,selector),replacement);
    [QQPHookedPairs() addObject:key];return YES;
}
BOOL QQPHookVoid(Class cls, SEL selector, void (^after)(id)) {
    if (!QQPMethodMatches(cls,selector,"v",@[])) return NO;
    IMP original=class_getMethodImplementation(cls,selector);
    IMP replacement=imp_implementationWithBlock(^(id object){((void(*)(id,SEL))original)(object,selector);after(object);});
    return QQPReplace(cls,selector,replacement,original);
}
BOOL QQPHookAppearance(Class cls,SEL selector,void (^before)(id)) {
    if(!QQPMethodMatches(cls,selector,"v",@[@"B"]) && !QQPMethodMatches(cls,selector,"v",@[@"c"]))return NO;
    IMP original=class_getMethodImplementation(cls,selector);
    IMP replacement=imp_implementationWithBlock(^(id object,BOOL animated){before(object);((void(*)(id,SEL,BOOL))original)(object,selector,animated);});
    return QQPReplace(cls,selector,replacement,original);
}
BOOL QQPHookObjectSetter(Class cls, SEL selector, id (^before)(id,id), void (^after)(id,id,id)) {
    if(!QQPMethodMatches(cls,selector,"v",@[@"@"]))return NO;
    IMP original=class_getMethodImplementation(cls,selector);
    IMP replacement=imp_implementationWithBlock(^(id object,id value){
        id token=before(object,value);
        ((void(*)(id,SEL,id))original)(object,selector,value);
        after(object,value,token);
    });
    return QQPReplace(cls,selector,replacement,original);
}
BOOL QQPHookSend(Class cls, SEL selector, BOOL returnsBool, BOOL (^intercept)(id,id)) {
    BOOL valid=returnsBool ? (QQPMethodMatches(cls,selector,"B",@[@"@"]) || QQPMethodMatches(cls,selector,"c",@[@"@"])) : QQPMethodMatches(cls,selector,"v",@[@"@"]);
    if (!valid) return NO;
    IMP original=class_getMethodImplementation(cls,selector), replacement;
    if (returnsBool) {
        replacement=imp_implementationWithBlock(^BOOL(id object,id argument){
            if(intercept(object,argument))return NO;
            return ((BOOL(*)(id,SEL,id))original)(object,selector,argument);
        });
    } else {
        replacement=imp_implementationWithBlock(^(id object,id argument){
            if(!intercept(object,argument))((void(*)(id,SEL,id))original)(object,selector,argument);
        });
    }
    return QQPReplace(cls,selector,replacement,original);
}
