#!/usr/bin/env bash
# Build CoreMark for the Shakti single-hart gem5 full-system bare-metal setup.
# ITERATIONS=0 uses CoreMark's automatic ~10-second run calibration.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project=$(cd -- "$repo/../.." && pwd)
out="$repo/coremark.gem5.riscv"
iterations=0
run=validation
cpu_hz=1000000000

usage() {
    cat <<USAGE
Usage: $0 [--iterations N] [--run validation|performance|profile] [--cpu-hz HZ] [--output ELF]

Defaults: validation seeds, automatic iterations (CoreMark targets about 10 seconds), 1 GHz.
USAGE
}
while (($#)); do
    case "$1" in
        --iterations) iterations=${2:?missing iteration count}; shift 2 ;;
        --run) run=${2:?missing run type}; shift 2 ;;
        --cpu-hz) cpu_hz=${2:?missing CPU frequency}; shift 2 ;;
        --output) out=${2:?missing output ELF}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
[[ "$iterations" =~ ^[0-9]+$ ]] || { echo "error: iterations must be a nonnegative integer" >&2; exit 2; }
[[ "$cpu_hz" =~ ^[1-9][0-9]*$ ]] || { echo "error: CPU frequency must be a positive integer in Hz" >&2; exit 2; }
case "$run" in
    validation) run_define=VALIDATION_RUN; data_size=2000 ;;
    performance) run_define=PERFORMANCE_RUN; data_size=2000 ;;
    profile) run_define=PROFILE_RUN; data_size=1200 ;;
    *) echo "error: --run must be validation, performance, or profile" >&2; exit 2 ;;
esac

cc=${RISCV_CC:-riscv64-unknown-elf-gcc}
readelf=${RISCV_READELF:-riscv64-unknown-elf-readelf}
nm=${RISCV_NM:-riscv64-unknown-elf-nm}
for tool in "$cc" "$readelf" "$nm" python3; do
    command -v "$tool" >/dev/null || { echo "error: required tool not found: $tool" >&2; exit 1; }
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/coremark-gem5.XXXXXX")
# Shakti's single-thread C-Class configuration reports a nonzero context ID.
# Force hart 0 in the stock CRT and use the toolchain's actual XLEN macro.
sed -e 's/csrr a0, mhartid/li a0, 0/g' \
    -e 's/#ifdef __riscv64/#if __riscv_xlen == 64/g' \
    "$project/riscv-benchmarks/common/crt.S" > "$build_dir/crt.S"

# The EEMBC barebones formatter expects a board UART. Replace only that output
# hook in a temporary copy with semihosting SYS_WRITEC; upstream files stay intact.
python3 - "$repo/barebones/ee_printf.c" "$build_dir/ee_printf.c" <<'PY'
import re
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text()
helper = r'''
#include <stdint.h>
static inline void coremark_semihost_writec(char ch)
{
    register uintptr_t a0 asm("a0") = 0x03; /* SYS_WRITEC */
    register uintptr_t a1 asm("a1") = (uintptr_t)&ch;
    __asm__ volatile (
        ".option push\n"
        ".option norvc\n"
        "slli zero, zero, 31\n"
        "ebreak\n"
        "srai zero, zero, 7\n"
        ".option pop\n"
        : "+r"(a0) : "r"(a1) : "memory");
}
'''
src = src.replace('#include <stdarg.h>', '#include <stdarg.h>\n' + helper, 1)
pattern = re.compile(r"void\s+uart_send_char\(char c\)\s*\{.*?\n\}", re.S)
src, count = pattern.subn(
    "void\nuart_send_char(char c)\n{\n    coremark_semihost_writec(c);\n}", src, count=1
)
if count != 1:
    raise SystemExit("error: could not replace CoreMark UART hook")
Path(sys.argv[2]).write_text(src)
PY

case_flags=(
    -mcmodel=medany -static -std=gnu99 -O2 -ffast-math -fno-common
    -fno-builtin-printf -fno-tree-loop-distribute-patterns
    -march=rv64imafdc -mabi=lp64d
    -DSTANDALONE=1 -DMAIN_HAS_NOARGC=0 -DMEM_METHOD=MEM_STACK
    "-DTOTAL_DATA_SIZE=$data_size"
    "-D${run_define}=1" "-DITERATIONS=$iterations"
    "-DCOREMARK_CPU_HZ=${cpu_hz}ULL"
    "-DFLAGS_STR=\"-O2 -march=rv64imafdc -mabi=lp64d\""
    "-I$project/riscv-benchmarks/riscv-pk/machine"
    "-I$repo/gem5_port" "-I$repo"
)

objects=()
for unit in core_list_join core_main core_matrix core_state core_util; do
    obj="$build_dir/$unit.o"
    "$cc" "${case_flags[@]}" -c "$repo/$unit.c" -o "$obj"
    objects+=("$obj")
done
for unit in core_portme; do
    obj="$build_dir/$unit.o"
    "$cc" "${case_flags[@]}" -c "$repo/gem5_port/$unit.c" -o "$obj"
    objects+=("$obj")
done
for src in "$build_dir/ee_printf.c" "$repo/barebones/cvt.c" "$repo/gem5_port/coremark_runtime.c"; do
    obj="$build_dir/$(basename "${src%.c}").o"
    "$cc" "${case_flags[@]}" -c "$src" -o "$obj"
    objects+=("$obj")
done
"$cc" "${case_flags[@]}" -D__ASSEMBLY__=1 -c "$build_dir/crt.S" -o "$build_dir/crt.o"

mkdir -p -- "$(dirname -- "$out")"
out=$(realpath -m -- "$out")
(
    cd -- "$build_dir"
    "$cc" -nostdlib -nostartfiles -static -mcmodel=medany \
        -march=rv64imafdc -mabi=lp64d -T "$project/riscv-benchmarks/common/test.ld" \
        -Wl,-e,_start "${objects[@]}" crt.o -lm -lgcc -o "$out"
)
entry=$($readelf -h "$out" | awk '/Entry point address:/ {print $4}')
[[ "$entry" == 0x80000000 ]] || { echo "error: expected ELF entry 0x80000000, got ${entry:-unknown}" >&2; exit 1; }
echo "Built $out"
echo "Entry: $entry"
echo "Run mode: $run; iterations: $iterations; CPU clock: $cpu_hz Hz"
"$nm" "$out" | grep -E ' (_start|_init|main|handle_trap)$'
