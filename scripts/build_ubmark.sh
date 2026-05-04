#!/bin/bash
# build_ubmark.sh - cross-compile a ubmark .c to .vmh, with our startup
#
# Usage: build_ubmark.sh <ubmark.c> [outdir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC=${1:?usage: build_ubmark.sh <source.c> [outdir]}
OUTDIR=${2:-"$REPO_ROOT/benchmarks/build"}
mkdir -p "$OUTDIR"

BASE=$(basename "$SRC")
NAME="${BASE%.c}"

GCC=${RISCV_GCC:-riscv64-elf-gcc}
OBJDUMP=${RISCV_OBJDUMP:-riscv64-elf-objdump}

# RISCV_MARCH defaults to rv32im — the explicit `_zicsr` suffix is
# rejected by gcc < 11. Override on a newer toolchain if desired.
: "${RISCV_MARCH:=rv32im}"
CFLAGS="-march=${RISCV_MARCH} -mabi=ilp32 -mcmodel=medany -mno-relax \
        -nostdlib -nostartfiles -ffreestanding -fno-builtin -O2 -g \
        -Wno-unused-result"
INCS="-I$REPO_ROOT/benchmarks/ubmark/ubmark"
LDSCRIPT="$REPO_ROOT/benchmarks/linker/ubmark.ld"
STARTUP="$REPO_ROOT/benchmarks/startup/startup.S"

ELF="$OUTDIR/$NAME.elf"
DUMP="$OUTDIR/$NAME.dump"
VMH="$OUTDIR/$NAME.vmh"

echo "[build_ubmark] $SRC -> $VMH"
"$GCC" $CFLAGS $INCS -T "$LDSCRIPT" -o "$ELF" "$STARTUP" "$SRC"
"$OBJDUMP" -EL -sz \
  --section=.xcpthandler --section=.text.init --section=.text \
  --section=.rodata --section=.data --section=.sdata \
  --section=.bss --section=.sbss \
  "$ELF" > "$DUMP"
python3 "$REPO_ROOT/benchmarks/tests/scripts/objdump2vmh.py" "$DUMP" 2>/dev/null > "$VMH"

if ! grep -q "@" "$VMH"; then
  echo "ERROR: $VMH has no addr markers" >&2
  exit 1
fi
echo "[build_ubmark] ok ($(wc -l < "$VMH") lines)"
