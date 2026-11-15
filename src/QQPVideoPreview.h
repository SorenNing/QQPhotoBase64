#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Call on the main thread with a local decoded MOV/MP4/M4V file directly inside
// an exclusively owned directory beneath NSTemporaryDirectory()/QQPhotoBase64. On success the
// controller owns and deletes that entire directory after dismissal (or dealloc).
// On nil, ownership stays with the caller. Present the result full-screen.
UIViewController * _Nullable QQPCreateVideoPreview(NSURL *fileURL, NSURL *temporaryDirectory);
NS_ASSUME_NONNULL_END
