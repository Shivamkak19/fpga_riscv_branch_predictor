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

# Match lab4 ubmark CFLAGS (-O3 -funroll-loops) so cycle/inst counts
# are directly comparable to l4/lab4/build/ubmark-*-long.out. Older gcc
# (< 11) rejects the explicit `_zicsr` suffix on -march; the
# `adroit-env.sh` wrapper points us at a newer gcc that accepts it.
: "${RISCV_MARCH:=rv32im_zicsr}"
: "${RISCV_OPT:=-O3 -funroll-loops}"
CFLAGS="-march=${RISCV_MARCH} -mabi=ilp32 -mcmodel=medany -mno-relax \
        -nostdlib -nostartfiles -ffreestanding -fno-builtin -g \
        -Wno-unused-result ${RISCV_OPT}"
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
