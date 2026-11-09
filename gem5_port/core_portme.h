#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stddef.h>
#include <stdint.h>

#define HAS_FLOAT 1
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define MAIN_HAS_NOARGC 0
#define MAIN_HAS_NORETURN 0
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STACK
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#define MEM_LOCATION "gem5 bare-metal RAM"
#define COMPILER_VERSION "RISC-V GCC " __VERSION__
#define COMPILER_FLAGS FLAGS_STR

#ifndef COREMARK_CPU_HZ
#define COREMARK_CPU_HZ 1000000000ULL
#endif

/* CoreMark's ee_ptr_int must be wide enough to hold an RV64 pointer. */
typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef double ee_f32;
typedef uint8_t ee_u8;
typedef uint32_t ee_u32;
typedef uintptr_t ee_ptr_int;
typedef size_t ee_size_t;

#define align_mem(x) \
    (void *)(4 + (((ee_ptr_int)(x) - 1) & ~(ee_ptr_int)3))

typedef uint64_t CORETIMETYPE;
typedef uint64_t CORE_TICKS;

#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif

#ifndef ITERATIONS
#define ITERATIONS 0
#endif

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int ee_printf(const char *fmt, ...);

#endif
