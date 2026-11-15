#ifndef QQPWeakField_h
#define QQPWeakField_h
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// descriptor is returned by Swift's swift_getTypeContextDescriptor through
// a Swift calling-convention declaration. No instance address is accepted.
bool QQPSwiftFieldIsWeak(const void *descriptor, const char *name,
                         uint32_t index, uint32_t count);
#ifdef QQP_WEAK_TEST
// Test reader maps only a caller-owned fixture arena; never process pointers.
typedef bool (*QQPWeakReader)(uintptr_t, void *, size_t, void *);
bool QQPWeakFieldWithReader(uintptr_t descriptor, const char *name,
                            uint32_t index, uint32_t count,
                            QQPWeakReader reader, void *context);
#endif
#ifdef __cplusplus
}
#endif
#endif
