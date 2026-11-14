#import "QQPCodec.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
static const NSUInteger QQPMax = 32 * 1024 * 1024;
static NSString *QQPHash(NSData *data) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, h);
    NSMutableString *s = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i=0; i<sizeof(h); i++) [s appendFormat:@"%02x", h[i]];
    return s;
}
static NSData *QQPFail(NSError **e, NSString *message) {
    if (e) *e=[NSError errorWithDomain:@"com.ning.qqphoto" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
    return nil;
}
static BOOL QQPImage(NSData *data) {
    CGImageSourceRef src=CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if(!src)return NO;
    NSString *type=(__bridge NSString *)CGImageSourceGetType(src);
    BOOL allowed=[@[@"public.jpeg",@"public.png",@"public.heic",@"public.heif"] containsObject:type];
    NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src,0,NULL));
    unsigned long long w=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongLongValue];
    unsigned long long h=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongLongValue];
    BOOL valid=allowed && CGImageSourceGetCount(src)==1 && w && h && w<=16384 && h<=16384 && w*h<=50000000 && CGImageSourceGetStatus(src)==kCGImageStatusComplete;
    if(valid){
        NSDictionary *opts=@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@64,(__bridge NSString *)kCGImageSourceShouldCache:@NO};
        CGImageRef thumb=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)opts);
        valid=thumb!=NULL;if(thumb)CGImageRelease(thumb);
    }
    CFRelease(src);
    return valid;
}
@implementation QQPCodec
+ (NSData *)encodeImageData:(NSData *)data error:(NSError **)error {
    if (!data.length || data.length>QQPMax || !QQPImage(data)) return QQPFail(error,@"图片无效或超过32MB");
    NSDictionary *obj=@{@"magic":@"QQENC1",@"algorithm":@"base64",@"size":@(data.length),@"sha256":QQPHash(data),@"data":[data base64EncodedStringWithOptions:0]};
    return [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingSortedKeys|NSJSONWritingWithoutEscapingSlashes error:error];
}
+ (NSData *)decodeContainer:(NSData *)container error:(NSError **)error {
    if (!container.length || container.length>QQPMax*4/3+4096) return QQPFail(error,@"文件大小无效");
    id obj=[NSJSONSerialization JSONObjectWithData:container options:0 error:error];
    if (![obj isKindOfClass:NSDictionary.class]) return QQPFail(error,@"无效的QQENC1文件");
    NSDictionary *d=obj;
    if (![d[@"magic"] isEqual:@"QQENC1"] || ![d[@"algorithm"] isEqual:@"base64"] || ![d[@"data"] isKindOfClass:NSString.class] || ![d[@"size"] isKindOfClass:NSNumber.class] || ![d[@"sha256"] isKindOfClass:NSString.class]) return QQPFail(error,@"文件格式不支持");
    double declared=[d[@"size"] doubleValue];
    NSUInteger size=[d[@"size"] unsignedIntegerValue];
    NSString *text=d[@"data"], *hash=d[@"sha256"];
    if(declared!=size || !size || size>QQPMax || text.length!=4*((size+2)/3) || hash.length!=64 || [hash rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location!=NSNotFound)return QQPFail(error,@"长度或校验字段无效");
    NSData *raw=[[NSData alloc] initWithBase64EncodedString:text options:0];
    if (!raw.length || raw.length>QQPMax || raw.length!=[d[@"size"] unsignedLongLongValue] || ![QQPHash(raw) isEqual:d[@"sha256"]] || ![[raw base64EncodedStringWithOptions:0] isEqual:d[@"data"]] || !QQPImage(raw)) return QQPFail(error,@"文件损坏或不是有效图片");
    return raw;
}
@end
