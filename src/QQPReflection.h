#ifndef QQPReflection_h
#define QQPReflection_h
#include <stdbool.h>
#include "QQPWeakField.h"
// Layout from SwiftShims/Reflection.h; imported by Swift rather than inferred
// from the layout of a native Swift struct or a raw byte buffer.
typedef void (*QQPReflectionNameFree)(const char *);
typedef struct QQPFieldMetadata {
    const char *name;
    QQPReflectionNameFree freeFunc;
    bool isStrong;
    bool isVar;
} QQPFieldMetadata;
#endif
