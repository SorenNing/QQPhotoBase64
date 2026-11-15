#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// QQENC1 is an encoding container. It provides no secrecy or authenticity.
@interface QQPCodec : NSObject
+ (nullable NSData *)encodeImageData:(NSData *)data error:(NSError **)error;
+ (nullable NSData *)decodeContainer:(NSData *)container error:(NSError **)error;
// QQENC2 is an unauthenticated streaming Base64 video container with fixed-size buffers.
// Destination must not exist; all output is created atomically or removed on failure.
+ (BOOL)encodeVideoAtURL:(NSURL *)source toURL:(NSURL *)destination extension:(NSString *)extension error:(NSError **)error;
+ (BOOL)decodeVideoAtURL:(NSURL *)container toURL:(NSURL *)destination extension:(NSString * _Nullable * _Nullable)extension error:(NSError **)error;
+ (BOOL)validateVideoContainerAtURL:(NSURL *)url error:(NSError **)error;
// Marker probe only; does not authenticate or validate the container contents.
+ (BOOL)isVideoContainerAtURL:(NSURL *)url;
@end
NS_ASSUME_NONNULL_END
