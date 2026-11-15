#import <Foundation/Foundation.h>
#import "QQPCodec.h"
static void Check(BOOL ok,NSString *why){if(!ok){NSLog(@"VIDEO TEST FAILED: %@",why);exit(1);}}
int main(int argc,const char **argv){@autoreleasepool{
    Check(argc==2,@"fixture path");
    NSURL *source=[NSURL fileURLWithPath:@(argv[1])];
    NSURL *dir=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    NSError *error=nil;Check([NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&error],@"create temp");
    NSURL *container=[dir URLByAppendingPathComponent:@"test.qqenc"];
    NSURL *decoded=[dir URLByAppendingPathComponent:@"out.mp4"];
    Check(![QQPCodec isVideoContainerAtURL:source],@"source not marked video container");
    Check([QQPCodec encodeVideoAtURL:source toURL:container extension:@"mp4" error:&error],error.localizedDescription?:@"encode");
    Check([QQPCodec isVideoContainerAtURL:container],@"marker");
    Check([QQPCodec validateVideoContainerAtURL:container error:&error],error.localizedDescription?:@"validate");
    NSString *ext=nil;Check([QQPCodec decodeVideoAtURL:container toURL:decoded extension:&ext error:&error],error.localizedDescription?:@"decode");
    NSData *raw=[NSData dataWithContentsOfURL:source],*again=[NSData dataWithContentsOfURL:decoded];
    Check([raw isEqual:again] && [ext isEqualToString:@"mp4"],@"exact MP4 roundtrip");
    Check(![QQPCodec encodeVideoAtURL:source toURL:container extension:@"mp4" error:&error],@"must not replace existing container");
    NSMutableData *bad=[[NSData dataWithContentsOfURL:container] mutableCopy];
    ((unsigned char *)bad.mutableBytes)[bad.length-4]^=1;
    NSURL *corrupted=[dir URLByAppendingPathComponent:@"corrupt.qqenc"];
    Check([bad writeToURL:corrupted atomically:YES],@"write corrupted");
    Check(![QQPCodec validateVideoContainerAtURL:corrupted error:&error],@"tamper rejected");
    NSURL *partial=[dir URLByAppendingPathComponent:@"partial.qqenc"];
    Check([[bad subdataWithRange:NSMakeRange(0,bad.length-2)] writeToURL:partial atomically:YES],@"write partial");
    Check(![QQPCodec validateVideoContainerAtURL:partial error:&error],@"truncation rejected");
    Check(![QQPCodec encodeVideoAtURL:source toURL:[dir URLByAppendingPathComponent:@"invalid.qqenc"] extension:@"exe" error:&error],@"extension rejected");
    [NSFileManager.defaultManager removeItemAtURL:dir error:NULL];
    puts("{\"video_round_trip\":true,\"video_negative_cases\":4,\"video_memory_mode\":\"streaming\"}");
}return 0;}
