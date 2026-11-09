#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#elif PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
#else
volatile ee_s32 seed1_volatile = 8;
volatile ee_s32 seed2_volatile = 8;
volatile ee_s32 seed3_volatile = 8;
#endif

volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

static inline CORETIMETYPE
read_cycle_counter(void)
{
    CORETIMETYPE value;
    __asm__ volatile("rdcycle %0" : "=r"(value));
    return value;
}

void
start_time(void)
{
    /* The CRT and gem5 config both start the CPU at 1 GHz by default. */
    extern CORETIMETYPE coremark_start_ticks;
    coremark_start_ticks = read_cycle_counter();
}

void
stop_time(void)
{
    extern CORETIMETYPE coremark_stop_ticks;
    coremark_stop_ticks = read_cycle_counter();
}

CORE_TICKS
get_time(void)
{
    extern CORETIMETYPE coremark_start_ticks;
    extern CORETIMETYPE coremark_stop_ticks;
    return coremark_stop_ticks - coremark_start_ticks;
}

secs_ret
time_in_secs(CORE_TICKS ticks)
{
    return (secs_ret)ticks / (secs_ret)COREMARK_CPU_HZ;
}

CORETIMETYPE coremark_start_ticks;
CORETIMETYPE coremark_stop_ticks;

void
portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(void *) || sizeof(ee_u32) != 4) {
        ee_printf("CoreMark port type-size check failed\n");
    }
    p->portable_id = 1;
}

void
portable_fini(core_portable *p)
{
    p->portable_id = 0;
}
