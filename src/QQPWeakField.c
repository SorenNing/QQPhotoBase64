#include "QQPWeakField.h"
#include <string.h>
#include <limits.h>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

typedef bool (*Reader)(uintptr_t, void *, size_t, void *);
typedef struct { Reader read; void *context; } Input;
static bool Read(Input in, uintptr_t address, void *out, size_t size) {
    return address && size && size<=65536 && address<=UINTPTR_MAX-size &&
           in.read(address,out,size,in.context);
}
static bool Relative(Input in, uintptr_t slot, uintptr_t *out) {
    int32_t offset=0;
    if(!Read(in,slot,&offset,4) || !offset)return false;
    if(offset>0){if(slot>UINTPTR_MAX-(uint32_t)offset)return false;*out=slot+(uint32_t)offset;}
    else {uint64_t distance=(uint64_t)(-(int64_t)offset);if(slot<distance)return false;*out=slot-(uintptr_t)distance;}
    return true;
}
static bool NameEquals(Input in, uintptr_t address, const char *wanted) {
    size_t length=strlen(wanted);if(!length || length>128)return false;
    char buffer[129];return Read(in,address,buffer,length+1) && memcmp(buffer,wanted,length+1)==0;
}
static bool Bytes(Input in, uintptr_t *cursor, const char *text) {
    size_t size=strlen(text);char buffer[16];
    if(size>sizeof(buffer) || !Read(in,*cursor,buffer,size) || memcmp(buffer,text,size))return false;
    *cursor+=size;return true;
}
// A complete, deliberately small grammar, never a search for an Xw suffix:
//   direct nominal class reference Sg Xw NUL
//   direct protocol reference _p Sg Xw NUL
//   direct protocol reference _Xl Sg Xw NUL
// Swift Mangling.rst: symbolic references, Optional, protocol-list and weak.
// Other encodings, substitutions, generics and nested ownership are rejected.
static bool WeakType(Input in, uintptr_t type) {
    if(type>UINTPTR_MAX-32)return false;
    uint8_t tag=0;if(!Read(in,type,&tag,1) || tag!=1)return false;
    uintptr_t nominal=0;if(!Relative(in,type+1,&nominal))return false;
    uint32_t flags=0;if(!Read(in,nominal,&flags,4))return false;
    // ContextDescriptorKind: Class=16, Protocol=3. Version 0 only.
    if(((flags>>8)&255)!=0)return false;
    uint32_t kind=flags&31;uintptr_t cursor=type+5;
    if(kind==3){
        uintptr_t first=cursor;
        if(!Bytes(in,&cursor,"_p")){cursor=first;if(!Bytes(in,&cursor,"_Xl"))return false;}
    } else if(kind!=16)return false;
    if(!Bytes(in,&cursor,"SgXw"))return false;
    uint8_t end=255;return Read(in,cursor,&end,1) && end==0;
}
static bool Probe(Input in, uintptr_t descriptor, const char *name,
                   uint32_t index, uint32_t count) {
    if(!descriptor || descriptor>UINTPTR_MAX-32 || !name || !count || count>4096 || index>=count)return false;
    uint32_t flags=0;
    if(!Read(in,descriptor,&flags,4) || (flags&31)!=16 || ((flags>>8)&255)!=0)return false;
    uintptr_t fields=0;if(!Relative(in,descriptor+16,&fields))return false;
    if(fields>UINTPTR_MAX-16-(uintptr_t)count*12)return false;
    unsigned char header[16];if(!Read(in,fields,header,sizeof(header)))return false;
    uint16_t kind=0,stride=0;uint32_t actual=0;
    memcpy(&kind,header+8,2);memcpy(&stride,header+10,2);memcpy(&actual,header+12,4);
    if(kind!=1 || stride!=12 || actual!=count)return false;
    uint32_t matches=0;uintptr_t selected=0;
    for(uint32_t i=0;i<count;i++){
        uintptr_t record=fields+16+(uintptr_t)i*12,fieldName=0;
        if(!Relative(in,record+8,&fieldName))return false;
        if(!NameEquals(in,fieldName,name))continue;
        uint32_t bits=0;if(!Read(in,record,&bits,4))return false;
        // A mutable stored property only, not artificial/indirect enum storage.
        if(bits!=2 || i!=index || !Relative(in,record+4,&selected))return false;
        matches++;
    }
    return matches==1 && WeakType(in,selected);
}

#ifdef __APPLE__
static bool ProcessRead(uintptr_t address, void *out, size_t size, void *context) {
    (void)context;vm_size_t copied=0;
    kern_return_t result=vm_read_overwrite(mach_task_self(),
        (vm_address_t)address,(vm_size_t)size,
        (vm_address_t)out,&copied);
    return result==KERN_SUCCESS && copied==size;
}
#endif
bool QQPSwiftFieldIsWeak(const void *descriptor,const char *name,uint32_t index,uint32_t count) {
#ifdef __APPLE__
    Input in={ProcessRead,NULL};return Probe(in,(uintptr_t)descriptor,name,index,count);
#else
    (void)descriptor;(void)name;(void)index;(void)count;return false;
#endif
}
#ifdef QQP_WEAK_TEST
bool QQPWeakFieldWithReader(uintptr_t descriptor,const char *name,uint32_t index,
                            uint32_t count,QQPWeakReader reader,void *context) {
    if(!reader)return false;Input in={reader,context};return Probe(in,descriptor,name,index,count);
}
#endif
