#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "QQPRuntime.h"
#import "QQPImageIO.h"

// Only a selector declaration: no QQ classes are linked or reimplemented.
@interface NSObject (QQPModelInitialization)
- (instancetype)initWithLocalFile:(id)path;
@end

static const void *QQPForwardModelKey=&QQPForwardModelKey;
static BOOL QQPForwardFile(NSURL *file,UIViewController *presenter) {
    Class modelClass=NSClassFromString(@"FAModel"), utilClass=NSClassFromString(@"FAModelUtility");
    SEL init=NSSelectorFromString(@"initWithLocalFile:"), forward=NSSelectorFromString(@"forwardFileToFriend:fromViewController:delegate:");
    if(!QQPMethodMatches(modelClass,init,"@",@[@"@"]) || !QQPMethodMatches(object_getClass(utilClass),forward,"v",@[@"@",@"@",@"@"]))return NO;
    NSDictionary *attrs=[[NSFileManager defaultManager]attributesOfItemAtPath:file.path error:nil];
    if(![attrs fileSize])return NO;
    id model=[[modelClass alloc] initWithLocalFile:file.path];
    NSString *actual=QQPGetObject(model,@"strFilePath");
    if(![actual isKindOfClass:NSString.class] || ![actual.stringByStandardizingPath isEqualToString:file.path.stringByStandardizingPath])return NO;
    objc_setAssociatedObject(presenter,QQPForwardModelKey,model,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(utilClass,forward,model,presenter,nil);
    return YES;
}
@interface QQPFilesController : UITableViewController
@property(nonatomic,strong) NSArray<NSURL *> *files;
@end
@implementation QQPFilesController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"已编码的图片";
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close:)];
    self.tableView.tableHeaderView=({UILabel *l=[[UILabel alloc]initWithFrame:CGRectMake(16,0,300,76)];l.numberOfLines=0;l.textAlignment=NSTextAlignmentCenter;l.font=[UIFont systemFontOfSize:13];l.text=@"点一张图片，使用QQ原生界面确认收件人。\nBase64不提供保密性。";l;});
}
- (NSInteger)tableView:(UITableView *)view numberOfRowsInSection:(NSInteger)section{return self.files.count;}
- (UITableViewCell *)tableView:(UITableView *)view cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[view dequeueReusableCellWithIdentifier:@"File"]?:[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"File"];
    NSURL *file=self.files[path.row];cell.textLabel.text=file.lastPathComponent;cell.detailTextLabel.text=@"QQENC1 · 点此转发文件";cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)view didSelectRowAtIndexPath:(NSIndexPath *)path {
    [view deselectRowAtIndexPath:path animated:YES];
    if(!QQPForwardFile(self.files[path.row],self))QQPShowMessage(self,@"未发送",@"当前QQ的文件转发接口不匹配，普通图片不会发送。" );
}
- (void)close:(id)sender{[self dismissViewControllerAnimated:YES completion:nil];}
@end
BOOL QQPShareFiles(NSArray<NSURL *> *files,UIViewController *presenter) {
    if(!files.count || !presenter.viewIfLoaded.window || presenter.presentedViewController)return NO;
    if(files.count==1)return QQPForwardFile(files.firstObject,presenter);
    QQPFilesController *list=[QQPFilesController new];list.files=files;
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:list];
    [presenter presentViewController:navigation animated:YES completion:nil];return YES;
}
