#import <Foundation/Foundation.h>
#import "QQPCodec.h"

static void Require(BOOL value,NSString *message){if(!value){NSLog(@"FAIL: %@",message);exit(1);}}
static NSData *Modify(NSData *container,NSString *key,id value){NSMutableDictionary *d=[[NSJSONSerialization JSONObjectWithData:container options:NSJSONReadingMutableContainers error:nil] mutableCopy];d[key]=value;return [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];}
int main(int argc,char **argv){@autoreleasepool{
    Require(argc==2,@"fixture argument");
    NSData *raw=[NSData dataWithContentsOfFile:@(argv[1])];Require(raw.length>0,@"fixture read");
    NSError *error=nil;NSData *encoded=[QQPCodec encodeImageData:raw error:&error];Require(encoded!=nil,error.localizedDescription);
    NSData *decoded=[QQPCodec decodeContainer:encoded error:&error];Require([decoded isEqualToData:raw],@"exact round trip");
    NSDictionary *obj=[NSJSONSerialization JSONObjectWithData:encoded options:0 error:nil];
    Require([obj[@"sha256"] isEqual:@"4367da457752561dd42b09931010b6c34bd2a84eb9f2d1c659dc7b0719091cd2"],@"independent fixture SHA256");
    NSArray *bad=@[Modify(encoded,@"magic",@"wrong"),Modify(encoded,@"size",@0),Modify(encoded,@"size",@(-1)),Modify(encoded,@"size",@0.5),Modify(encoded,@"size",@YES),Modify(encoded,@"sha256",@"bad"),Modify(encoded,@"sha256",[@"0" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]),Modify(encoded,@"algorithm",@"aes"),Modify(encoded,@"data",[obj[@"data"] stringByAppendingString:@"\n"]),Modify(encoded,@"data",@7),Modify(encoded,@"size",NSNull.null),[@"[]" dataUsingEncoding:NSUTF8StringEncoding],[@"null" dataUsingEncoding:NSUTF8StringEncoding],[encoded subdataWithRange:NSMakeRange(0,encoded.length-1)]];
    for(NSData *candidate in bad)Require([QQPCodec decodeContainer:candidate error:&error]==nil,@"malformed container rejected");
    Require([QQPCodec encodeImageData:[@"not an image" dataUsingEncoding:NSUTF8StringEncoding] error:&error]==nil,@"non-image rejected");
    Require([QQPCodec encodeImageData:[NSMutableData dataWithLength:32u*1024u*1024u+1] error:&error]==nil,@"oversized input rejected");
    NSMutableString *invalid=[obj[@"data"] mutableCopy];[invalid replaceCharactersInRange:NSMakeRange(0,1) withString:@"!"];
    Require([QQPCodec decodeContainer:Modify(encoded,@"data",invalid) error:&error]==nil,@"invalid Base64 alphabet");
    Require([QQPCodec decodeContainer:Modify(encoded,@"sha256",[@"g" stringByPaddingToLength:64 withString:@"g" startingAtIndex:0]) error:&error]==nil,@"non-hex digest");
    Require([QQPCodec decodeContainer:[NSMutableData dataWithLength:32u*1024u*1024u*4/3+4097] error:&error]==nil,@"oversized container");
    NSData *boundary=[NSData dataWithContentsOfFile:[@(argv[1]).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"boundary.png"]];
    Require(boundary.length==32u*1024u*1024u,@"exact limit fixture");
    NSData *large=[QQPCodec encodeImageData:boundary error:&error];Require(large!=nil,error.localizedDescription);
    Require(large.length<=32u*1024u*1024u*4/3+4096,@"maximum container fits decode limit");
    Require([[QQPCodec decodeContainer:large error:&error] isEqualToData:boundary],@"exact limit byte round trip");
    NSMutableString *noncanonical=[[@"/" stringByPaddingToLength:44739243 withString:@"/" startingAtIndex:0] mutableCopy];[noncanonical appendString:@"="];
    Require([QQPCodec decodeContainer:Modify(large,@"data",noncanonical) error:&error]==nil,@"noncanonical Base64 padding");
    NSDictionary *result=@{@"round_trip":@YES,@"boundary_round_trip":@YES,@"negative_cases":@(bad.count+6),@"raw_bytes":@(raw.length),@"container_bytes":@(encoded.length),@"boundary_raw_bytes":@(boundary.length),@"boundary_container_bytes":@(large.length)};
    NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];puts([[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
}return 0;}
