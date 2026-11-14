#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// QQENC1 is an encoding container. It provides no secrecy or authenticity.
@interface QQPCodec : NSObject
+ (nullable NSData *)encodeImageData:(NSData *)data error:(NSError **)error;
+ (nullable NSData *)decodeContainer:(NSData *)container error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
