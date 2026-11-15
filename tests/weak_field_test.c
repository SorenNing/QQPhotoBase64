#include "QQPWeakField.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static unsigned char arena[4096];
static unsigned reads;
static const uintptr_t base=0x10000;
static bool reader(uintptr_t address,void *out,size_t size,void *context) {
    (void)context;reads++;
    if(address<base || size>sizeof(arena) || address-base>sizeof(arena)-size)return false;
    memcpy(out,arena+address-base,size);return true;
}
static void u16(size_t at,uint16_t x){memcpy(arena+at,&x,2);}
static void u32(size_t at,uint32_t x){memcpy(arena+at,&x,4);}
static void rel(size_t slot,size_t target){int32_t x=(int32_t)target-(int32_t)slot;memcpy(arena+slot,&x,4);}
static void fixture(unsigned kind,const char *suffix) {
    memset(arena,0,sizeof(arena));reads=0;
    u32(0,16);rel(16,128);
    u16(136,1);u16(138,12);u32(140,1);
    u32(144,2);rel(148,400);rel(152,350);
    strcpy((char *)arena+350,"context");
    arena[400]=1;rel(401,600);strcpy((char *)arena+405,suffix);
    u32(600,kind);
}
static bool probe(uint32_t index,uint32_t count){return QQPWeakFieldWithReader(base,"context",index,count,reader,NULL);}
static void require(bool value){assert(value);}
int main(void) {
    unsigned cases=0;
    fixture(16,"SgXw");require(probe(0,1));cases++;
    // Relative reference payload includes embedded zero bytes: not strlen text.
    require(arena[402]==0 && arena[403]==0 && arena[404]==0);cases++;
    fixture(3,"_pSgXw");require(probe(0,1));cases++;
    fixture(3,"_XlSgXw");require(probe(0,1));cases++;
    const char *bad[]={"SgXo","SgXu","Sg","SgXwXo","SgXwSg","SgXwXw",
        "XwSg","SgXwgarbage","yXwG","SgXoXw","_pSgXw","SgXw_"};
    for(size_t i=0;i<sizeof(bad)/sizeof(*bad);i++){fixture(16,bad[i]);require(!probe(0,1));cases++;}
    fixture(16,"SgXw");arena[400]=2;require(!probe(0,1));cases++;
    fixture(17,"SgXw");require(!probe(0,1));cases++;
    fixture(16,"SgXw");u32(600,16|0x100);require(!probe(0,1));cases++;
    fixture(16,"SgXw");u16(136,0);require(!probe(0,1));cases++;
    fixture(16,"SgXw");u16(138,16);require(!probe(0,1));cases++;
    fixture(16,"SgXw");u32(140,2);require(!probe(0,1));cases++;
    fixture(16,"SgXw");u32(144,0);require(!probe(0,1));cases++;
    fixture(16,"SgXw");strcpy((char *)arena+350,"else");require(!probe(0,1));cases++;
    fixture(16,"SgXw");require(!probe(1,1));require(!probe(0,4097));cases+=2;
    fixture(16,"SgXw");rel(148,4090);require(!probe(0,1));cases++;
    fixture(16,"SgXw");rel(401,20000);require(!probe(0,1));cases++;
    fixture(16,"SgXw");u32(140,2);u32(156,2);rel(160,400);rel(164,350);require(!probe(0,2));cases++;
    fixture(16,"SgXw");u32(140,2);strcpy((char *)arena+370,"other");rel(152,370);
    u32(156,2);rel(160,400);rel(164,350);require(probe(1,2));require(!probe(0,2));cases+=2;
    // Invalid input must be rejected without a raw memory dereference.
    require(!QQPWeakFieldWithReader(UINTPTR_MAX,"context",0,1,reader,NULL));cases++;
    require(!QQPWeakFieldWithReader(1,"context",0,1,reader,NULL));cases++;
    require(!QQPWeakFieldWithReader(base,NULL,0,1,reader,NULL));cases++;
    printf("{\"passed\":true,\"cases\":%u,\"scope\":\"production C metadata decoder, fixture memory only\"}\n",cases);
    return 0;
}
