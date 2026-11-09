#include <stdint.h>

static inline uintptr_t
semihost_call(uintptr_t operation, uintptr_t args)
{
    register uintptr_t a0 asm("a0") = operation;
    register uintptr_t a1 asm("a1") = args;
    __asm__ volatile(
        ".option push\n"
        ".option norvc\n"
        "slli zero, zero, 31\n"
        "ebreak\n"
        "srai zero, zero, 7\n"
        ".option pop\n"
        : "+r"(a0) : "r"(a1) : "memory");
    return a0;
}

static void
semihost_write0(const char *text)
{
    semihost_call(0x04, (uintptr_t)text); /* SYS_WRITE0 */
}

__attribute__((noreturn)) static void
sim_exit(uintptr_t code)
{
    uint64_t args[2] = { 0x20026, (uint32_t)code };
    semihost_call(0x20, (uintptr_t)args); /* SYS_EXIT_EXTENDED */
    for (;;) __asm__ volatile("nop");
}

extern int main(int argc, char **argv);

int
get_nharts(void)
{
    return 1;
}

__attribute__((noreturn)) void
tohost_exit(uintptr_t code)
{
    sim_exit(code);
}

uintptr_t
handle_trap(uintptr_t cause, uintptr_t epc, uintptr_t regs[32])
{
    (void)epc;
    (void)regs;
    semihost_write0("CoreMark: unexpected trap\n");
    sim_exit(0x100 | cause);
}

void
_init(int cid, int nc)
{
    (void)cid;
    (void)nc;
    int result = main(0, 0);
    semihost_write0("CoreMark: main returned; check CRC validation above.\n");
    sim_exit((uintptr_t)result);
}
