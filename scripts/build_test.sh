#!/bin/bash
# build_test.sh - cross-compile a single .S or .c source to .vmh
#
# Usage: build_test.sh <source.S|source.c> [outdir]
# Output: <outdir>/<basename>.vmh (also .elf, .dump kept for debug)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC=${1:?usage: build_test.sh <source> [outdir]}
OUTDIR=${2:-"$REPO_ROOT/benchmarks/build"}
mkdir -p "$OUTDIR"

BASE=$(basename "$SRC")
NAME="${BASE%.*}"
EXT="${BASE##*.}"

GCC=${RISCV_GCC:-riscv64-elf-gcc}
OBJDUMP=${RISCV_OBJDUMP:-riscv64-elf-objdump}

# Default to rv32im_zicsr so the asm tests build under the same -march
# lab4 uses. Older gcc (< 11) doesn't recognize the suffix; in that
# case set RISCV_MARCH=rv32im before invoking.
: "${RISCV_MARCH:=rv32im_zicsr}"
CFLAGS="-march=${RISCV_MARCH} -mabi=ilp32 -nostdlib -nostartfiles -mno-relax -O2"
INCS="-I$REPO_ROOT/benchmarks/tests/riscv -I$REPO_ROOT/benchmarks/ubmark/ubmark"
LDSCRIPT="$REPO_ROOT/benchmarks/tests/scripts/test.ld"

ELF="$OUTDIR/$NAME.elf"
DUMP="$OUTDIR/$NAME.dump"
VMH="$OUTDIR/$NAME.vmh"

echo "[build_test] $SRC -> $VMH"
"$GCC" $CFLAGS $INCS -T "$LDSCRIPT" -o "$ELF" "$SRC"
"$OBJDUMP" -EL -sz \
  --section=.xcpthandler --section=.text --section=.data \
  --section=.sdata --section=.rodata --section=.bss --section=.sbss \
  "$ELF" > "$DUMP"
python3 "$REPO_ROOT/benchmarks/tests/scripts/objdump2vmh.py" "$DUMP" 2>/dev/null > "$VMH"

# Sanity check
if ! grep -q "@" "$VMH"; then
  echo "ERROR: $VMH has no addr markers (objdump may have failed)" >&2
  exit 1
fi
echo "[build_test] ok ($(wc -l < "$VMH") lines)"
