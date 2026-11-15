#import "QQPCodec.h"
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <errno.h>
#import <fcntl.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>
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
// Video processing uses fixed-size buffers; input sizes are checked for overflow only.
enum { QQPVideoChunk = 48 * 1024 };
static const char QQPVideoMarker[] = "QQENC2\n";

static BOOL QQPVideoFail(NSError **error, NSString *reason) {
    if (error) *error = [NSError errorWithDomain:@"com.ning.qqphoto" code:2
                                        userInfo:@{NSLocalizedDescriptionKey:reason}];
    return NO;
}
static NSString *QQPVideoExtension(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    if ([value hasPrefix:@"."]) value = [value substringFromIndex:1];
    NSString *ext = value.lowercaseString;
    return [@[@"mp4", @"mov", @"m4v"] containsObject:ext] ? ext : nil;
}
static uint32_t QQPBE32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static uint64_t QQPBE64(const uint8_t *p) {
    return ((uint64_t)QQPBE32(p) << 32) | QQPBE32(p+4);
}
static BOOL QQPBrand(const uint8_t *p) {
    static const char *const brands[] = {"isom", "iso2", "iso3", "iso4", "iso5",
        "iso6", "avc1", "mp41", "mp42", "qt  ", "M4V "};
    for (size_t i = 0; i < sizeof(brands)/sizeof(brands[0]); i++)
        if (!memcmp(p, brands[i], 4)) return YES;
    return NO;
}

// A bounded forward-only MP4 box scanner. It skips media payloads, but requires
// a recognized ftyp, moov/trak/mdia/hdlr(vide), and mdat in the correct hierarchy.
typedef struct {
    uint64_t size, offset, parentEnd[4], itemEnd, seenBoxes, inspectStart;
    uint8_t header[16], word[4];
    unsigned depth, headerUsed, headerNeed, wordUsed, inspectHeader;
    uint32_t inspectType;
    BOOL ftyp, brand, moov, mdat, video;
} QQPVideoScan;
static BOOL QQPVideoBox(QQPVideoScan *s) {
    uint64_t start = s->offset - s->headerUsed;
    uint64_t length = QQPBE32(s->header), parent = s->parentEnd[s->depth];
    uint32_t type = QQPBE32(s->header+4);
    if (length == 1) length = QQPBE64(s->header+8);
    else if (length == 0) {
        if (type != 0x6d646174) return NO; // Only a final mdat may extend to EOF.
        length = parent - start;
    }
    if (s->seenBoxes == UINT64_MAX || start > parent || length < s->headerNeed || length > parent - start) return NO;
    s->seenBoxes++;
    uint64_t end = start + length;
    if (!start && (type != 0x66747970 || s->headerNeed != 8 || length < 16 || length > 4096 || (length & 3))) return NO;
    if (s->depth == 0 && type == 0x6d6f6f76) s->moov = YES;
    if (s->depth == 0 && type == 0x6d646174) s->mdat = YES;
    if (!start) { s->ftyp = YES; s->inspectType = type; s->itemEnd = end; s->wordUsed = 0; s->inspectStart = start; s->inspectHeader = s->headerNeed; }
    else if (s->depth == 3 && type == 0x68646c72 && length >= s->headerNeed+12) {
        s->inspectType = type; s->itemEnd = end; s->wordUsed = 0; s->inspectStart = start; s->inspectHeader = s->headerNeed;
    } else if (s->depth == 0 && type == 0x6d6f6f76 && s->depth < 3) {
        s->parentEnd[++s->depth] = end;
    } else if (s->depth == 1 && type == 0x7472616b) {
        s->parentEnd[++s->depth] = end;
    } else if (s->depth == 2 && type == 0x6d646961) {
        s->parentEnd[++s->depth] = end;
    } else { s->itemEnd = end; }
    s->headerUsed = s->headerNeed = 0;
    return YES;
}
static BOOL QQPVideoScanFeed(QQPVideoScan *s, const uint8_t *bytes, size_t count) {
    size_t pos = 0;
    while (pos < count) {
        if (s->offset >= s->size) return NO;
        if (s->inspectType) {
            uint64_t start = s->offset, remaining = s->itemEnd - start;
            size_t take = (size_t)MIN((uint64_t)(count-pos), remaining);
            for (size_t i = 0; i < take; i++) {
                uint64_t index = start + i;
                if (s->inspectType == 0x66747970 && index >= 8) {
                    s->word[s->wordUsed++] = bytes[pos+i];
                    if (s->wordUsed == 4) {
                        if (index == 11 || index >= 19) s->brand |= QQPBrand(s->word);
                        s->wordUsed = 0;
                    }
                } else if (s->inspectType == 0x68646c72 && index >= s->inspectStart+s->inspectHeader+8 && index < s->inspectStart+s->inspectHeader+12) {
                    s->word[s->wordUsed++] = bytes[pos+i];
                    if (s->wordUsed == 4) {
                        s->video |= !memcmp(s->word, "vide", 4);
                        s->wordUsed = 0;
                    }
                }
            }
            pos += take; s->offset += take;
            if (s->offset == s->itemEnd) { s->inspectType = 0; s->itemEnd = 0; }
            continue;
        }
        if (s->itemEnd > s->offset) {
            size_t take = (size_t)MIN((uint64_t)(count-pos), s->itemEnd-s->offset);
            pos += take; s->offset += take;
            if (s->offset == s->itemEnd) s->itemEnd = 0;
            continue;
        }
        while (s->depth && s->offset == s->parentEnd[s->depth]) s->depth--;
        if (s->offset >= s->parentEnd[s->depth]) return NO;
        if (!s->headerNeed) s->headerNeed = 8;
        size_t take = MIN(count-pos, (size_t)(s->headerNeed-s->headerUsed));
        if (take > s->parentEnd[s->depth] - s->offset) return NO;
        memcpy(s->header+s->headerUsed, bytes+pos, take);
        s->headerUsed += (unsigned)take; s->offset += take; pos += take;
        if (s->headerUsed == 8 && QQPBE32(s->header) == 1) s->headerNeed = 16;
        if (s->headerUsed == s->headerNeed && !QQPVideoBox(s)) return NO;
    }
    return YES;
}
static BOOL QQPVideoScanDone(QQPVideoScan *s) {
    return s->offset == s->size && !s->headerUsed && !s->inspectType &&
        (!s->itemEnd || s->itemEnd == s->size) && s->ftyp && s->brand &&
        s->moov && s->mdat && s->video;
}
static BOOL QQPReadExact(int fd, void *bytes, size_t count) {
    uint8_t *p = bytes;
    while (count) {
        ssize_t n = read(fd, p, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n; count -= (size_t)n;
    }
    return YES;
}
static BOOL QQPWriteExact(int fd, const void *bytes, size_t count) {
    const uint8_t *p = bytes;
    while (count) {
        ssize_t n = write(fd, p, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n; count -= (size_t)n;
    }
    return YES;
}
static int QQPOpenVideo(NSURL *url, uint64_t *length) {
    if (!url.isFileURL) return -1;
    int fd = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    struct stat st;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0) {
        close(fd); return -1;
    }
    *length = (uint64_t)st.st_size;
    return fd;
}
static int QQPTempVideo(NSURL *destination, char **temporary) {
    if (!destination.isFileURL || !destination.lastPathComponent.length ||
        [destination.lastPathComponent isEqualToString:@"."] ||
        [destination.lastPathComponent isEqualToString:@".."] ||
        [destination.path hasSuffix:@"/"]) return -1;
    NSString *name = [destination.path stringByAppendingString:@".qqp-XXXXXX"];
    *temporary = strdup(name.fileSystemRepresentation);
    if (!*temporary) return -1;
    int fd = mkstemp(*temporary);
    if (fd < 0) { free(*temporary); *temporary = NULL; }
    return fd;
}
static void QQPCloseTemp(int fd, char *temporary) {
    if (fd >= 0) close(fd);
    if (temporary) { unlink(temporary); free(temporary); }
}
static BOOL QQPPublishVideo(int fd, char *temporary, NSURL *destination) {
    return fsync(fd) == 0 && link(temporary, destination.fileSystemRepresentation) == 0;
}
static NSString *QQPVideoDigest(const unsigned char *hash) {
    NSMutableString *s = [NSMutableString stringWithCapacity:64];
    for (NSUInteger i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", hash[i]];
    return s;
}
static BOOL QQPVideoHex(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length != 64) return NO;
    for (NSUInteger i=0; i<text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO;
    }
    return YES;
}
static BOOL QQPScanOriginal(int input, uint64_t size, unsigned char *hash) {
    QQPVideoScan scan={0}; scan.size=size; scan.parentEnd[0]=size;
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    uint8_t buffer[QQPVideoChunk];
    for (uint64_t left=size; left;) {
        size_t n = (size_t)MIN(left, (uint64_t)sizeof(buffer));
        if (!QQPReadExact(input, buffer, n) || !QQPVideoScanFeed(&scan, buffer, n)) return NO;
        CC_SHA256_Update(&ctx, buffer, (CC_LONG)n);
        left -= n;
    }
    struct stat st;
    if (!QQPVideoScanDone(&scan) || fstat(input, &st) || st.st_size != (off_t)size ||
        lseek(input, 0, SEEK_SET) != 0) return NO;
    CC_SHA256_Final(hash, &ctx);
    return YES;
}
static BOOL QQPVideoHeader(int fd, uint64_t fileLength, uint64_t *size,
                           NSString **digest, NSString **ext) {
    const size_t markerLength = sizeof(QQPVideoMarker)-1;
    if (fileLength < markerLength+2) return NO;
    uint8_t marker[sizeof(QQPVideoMarker)-1];
    if (!QQPReadExact(fd, marker, sizeof(marker)) || memcmp(marker, QQPVideoMarker, sizeof(marker))) return NO;
    uint8_t header[512];
    size_t length = 0;
    for (;;) {
        if (length >= sizeof(header) || markerLength+length >= fileLength ||
            !QQPReadExact(fd, header+length, 1)) return NO;
        if (header[length++] == '\n') break;
    }
    NSData *json = [NSData dataWithBytes:header length:length-1];
    id value = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *d = value;
    if (d.count != 5 || ![d[@"magic"] isEqual:@"QQENC2"] ||
        ![d[@"algorithm"] isEqual:@"base64"] ||
        ![d[@"extension"] isKindOfClass:NSString.class] ||
        ![QQPVideoExtension(d[@"extension"]) isEqual:d[@"extension"]] ||
        !QQPVideoHex(d[@"sha256"]) || ![d[@"size"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)d[@"size"]) == CFBooleanGetTypeID()) return NO;
    NSNumber *number = d[@"size"];
    uint64_t raw = number.unsignedLongLongValue;
    if (!raw || raw > INT64_MAX ||
        ![number.stringValue isEqualToString:[NSString stringWithFormat:@"%llu", (unsigned long long)raw]]) return NO;
    uint64_t groups = raw/3 + (raw%3 != 0);
    uint64_t base = markerLength + length;
    if (groups > (INT64_MAX-base)/4 || fileLength != base+groups*4) return NO;
    *size = raw; *digest = d[@"sha256"]; *ext = d[@"extension"];
    return YES;
}
static int QQPBase64Value(uint8_t c) {
    if (c >= 'A' && c <= 'Z') return c-'A';
    if (c >= 'a' && c <= 'z') return c-'a'+26;
    if (c >= '0' && c <= '9') return c-'0'+52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}
static BOOL QQPEncodeVideoBytes(int input, int output, uint64_t size,
                                const unsigned char *expected) {
    uint8_t raw[QQPVideoChunk], text[4*(QQPVideoChunk/3)];
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    for (uint64_t left = size; left;) {
        size_t n = (size_t)MIN(left, (uint64_t)sizeof(raw));
        if (!QQPReadExact(input, raw, n)) return NO;
        CC_SHA256_Update(&ctx, raw, (CC_LONG)n);
        size_t used = 0;
        for (size_t i=0; i<n; i+=3) {
            uint32_t a=raw[i], b=i+1<n?raw[i+1]:0, c=i+2<n?raw[i+2]:0;
            text[used++] = alphabet[a>>2];
            text[used++] = alphabet[((a&3)<<4)|(b>>4)];
            text[used++] = i+1<n?alphabet[((b&15)<<2)|(c>>6)]:'=';
            text[used++] = i+2<n?alphabet[c&63]:'=';
        }
        if (!QQPWriteExact(output, text, used)) return NO;
        left -= n;
    }
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(hash, &ctx);
    struct stat st;
    return !memcmp(hash, expected, sizeof(hash)) && !fstat(input, &st) &&
           S_ISREG(st.st_mode) && st.st_size == (off_t)size;
}
static BOOL QQPProcessVideo(NSURL *container, NSURL *destination,
                            NSString * _Nullable * _Nullable resultExtension,
                            NSError **error) {
    uint64_t fileLength=0;
    int in=QQPOpenVideo(container, &fileLength), out=-1;
    char *temporary=NULL;
    BOOL success=NO;
    if (in < 0) return QQPVideoFail(error, @"视频容器不可读");
    @try {
      do {
        uint64_t size=0;
        NSString *digest=nil, *ext=nil;
        if (!QQPVideoHeader(in, fileLength, &size, &digest, &ext)) {
            QQPVideoFail(error, @"QQENC2 视频头部或长度无效"); break;
        }
        if (destination) {
            out = QQPTempVideo(destination, &temporary);
            if (out < 0) { QQPVideoFail(error, @"无法创建目标文件（路径或磁盘空间无效）"); break; }
        }
        QQPVideoScan scan={0}; scan.size=size; scan.parentEnd[0]=size;
        CC_SHA256_CTX ctx;
        CC_SHA256_Init(&ctx);
        uint8_t encoded[QQPVideoChunk], decoded[QQPVideoChunk*3/4];
        uint64_t textRemaining = fileLength - (uint64_t)lseek(in, 0, SEEK_CUR);
        uint64_t rawRemaining = size;
        BOOL valid=YES;
        while (textRemaining && valid) {
            size_t n = (size_t)MIN(textRemaining, (uint64_t)sizeof(encoded));
            if (!QQPReadExact(in, encoded, n)) { valid=NO; break; }
            size_t used=0;
            for (size_t i=0; i<n; i+=4) {
                int a=QQPBase64Value(encoded[i]), b=QQPBase64Value(encoded[i+1]);
                int c=QQPBase64Value(encoded[i+2]), d=QQPBase64Value(encoded[i+3]);
                if (a<0 || b<0 || (encoded[i+2]!='=' && c<0) ||
                    (encoded[i+3]!='=' && d<0) || (encoded[i+2]=='=' && encoded[i+3]!='=')) { valid=NO; break; }
                size_t bytes = encoded[i+2]=='='?1:(encoded[i+3]=='='?2:3);
                if (bytes > rawRemaining || (bytes<3 && (textRemaining != n || i+4 != n)) ||
                    (bytes==1 && (b&15)) || (bytes==2 && (c&3))) { valid=NO; break; }
                decoded[used++] = (uint8_t)((a<<2)|(b>>4));
                if (bytes>1) decoded[used++] = (uint8_t)((b<<4)|(c>>2));
                if (bytes>2) decoded[used++] = (uint8_t)((c<<6)|d);
                rawRemaining -= bytes;
            }
            if (valid && used) {
                CC_SHA256_Update(&ctx, decoded, (CC_LONG)used);
                valid = QQPVideoScanFeed(&scan, decoded, used) &&
                        (out<0 || QQPWriteExact(out, decoded, used));
            }
            textRemaining -= n;
        }
        unsigned char hash[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(hash, &ctx);
        if (!valid || rawRemaining || !QQPVideoScanDone(&scan) ||
            ![QQPVideoDigest(hash) isEqual:digest]) {
            QQPVideoFail(error, @"视频损坏、视频轨无效或读写失败（请检查磁盘空间）"); break;
        }
        struct stat st;
        if (fstat(in, &st) || st.st_size != (off_t)fileLength ||
            (out>=0 && !QQPPublishVideo(out, temporary, destination))) {
            QQPVideoFail(error, @"文件在处理期间发生变化，或无法写入目标文件"); break;
        }
        if (resultExtension) *resultExtension = ext;
        success=YES;
      } while (NO);
    } @finally {
        close(in);
        QQPCloseTemp(out, temporary);
    }
    return success;
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
+ (BOOL)isVideoContainerAtURL:(NSURL *)url {
    uint64_t size=0;int fd=QQPOpenVideo(url,&size);
    if(fd<0)return NO;
    char marker[sizeof(QQPVideoMarker)-1];
    BOOL ok=size>=sizeof(marker) && QQPReadExact(fd,marker,sizeof(marker)) &&
        memcmp(marker,QQPVideoMarker,sizeof(marker))==0;
    close(fd);return ok;
}
+ (BOOL)encodeVideoAtURL:(NSURL *)source toURL:(NSURL *)destination
             extension:(NSString *)extension error:(NSError **)error {
    NSString *ext=QQPVideoExtension(extension);uint64_t size=0;
    if(!ext)return QQPVideoFail(error,@"仅支持 MP4、MOV、M4V 视频。");
    int input=QQPOpenVideo(source,&size);
    if(input<0)return QQPVideoFail(error,@"无法读取原视频文件。");
    if(size>INT64_MAX){close(input);return QQPVideoFail(error,@"当前设备无法表示此视频长度。");}
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if(!QQPScanOriginal(input,size,digest)){close(input);return QQPVideoFail(error,@"不是完整的受支持视频。");}
    NSDictionary *header=@{@"magic":@"QQENC2",@"algorithm":@"base64",
                           @"extension":ext,@"size":@(size),@"sha256":QQPVideoDigest(digest)};
    NSData *json=[NSJSONSerialization dataWithJSONObject:header options:NSJSONWritingSortedKeys error:error];
    if(!json || json.length>511){close(input);return QQPVideoFail(error,@"视频容器头无效。");}
    char *temporary=NULL;int output=QQPTempVideo(destination,&temporary);
    if(output<0){close(input);return QQPVideoFail(error,@"无法创建输出视频容器。");}
    const uint8_t newline='\n';BOOL ok=QQPWriteExact(output,QQPVideoMarker,sizeof(QQPVideoMarker)-1) &&
         QQPWriteExact(output,json.bytes,json.length) && QQPWriteExact(output,&newline,1) &&
         QQPEncodeVideoBytes(input,output,size,digest);
    close(input);
    if(ok)ok=QQPPublishVideo(output,temporary,destination);
    QQPCloseTemp(output,temporary);
    return ok?YES:QQPVideoFail(error,@"编码视频失败，可能是文件变化或设备空间不足。");
}
+ (BOOL)decodeVideoAtURL:(NSURL *)container toURL:(NSURL *)destination
              extension:(NSString * _Nullable * _Nullable)extension error:(NSError **)error {
    return QQPProcessVideo(container,destination,extension,error);
}
+ (BOOL)validateVideoContainerAtURL:(NSURL *)url error:(NSError **)error {
    return QQPProcessVideo(url,nil,NULL,error);
}
@end
