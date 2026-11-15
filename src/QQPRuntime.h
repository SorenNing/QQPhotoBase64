#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

BOOL QQPMethodMatches(Class cls, SEL sel, const char *result, NSArray<NSString *> *arguments);
id QQPGetObject(id object, NSString *selector);
UIViewController *QQPOwningController(UIView *view);
BOOL QQPClassNamed(id object, NSString *name);
BOOL QQPHookVoid(Class cls, SEL selector, void (^after)(id));
BOOL QQPHookAppearance(Class cls, SEL selector, void (^before)(id));
BOOL QQPHookSend(Class cls, SEL selector, BOOL returnsBool, BOOL (^intercept)(id, id));
BOOL QQPHookObjectSetter(Class cls, SEL selector, id (^before)(id, id), void (^after)(id, id, id));
