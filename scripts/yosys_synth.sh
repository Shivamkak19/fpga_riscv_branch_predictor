#!/bin/bash
# yosys_synth.sh - Run yosys synth_xilinx for one variant and dump cell stats
#
# Usage: yosys_synth.sh <variant>
#
# Output: results/<variant>/yosys_stat.txt with LUT/FF/BRAM counts.
# This is a *rough* estimate — Vivado will produce the authoritative numbers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANT=${1:-baseline}
OUTDIR="$REPO_ROOT/results/$VARIANT"
mkdir -p "$OUTDIR"

case "$VARIANT" in
  baseline)
    RTL_DIRS=("$REPO_ROOT/rtl/baseline/riscvlong" "$REPO_ROOT/rtl/baseline/vc" "$REPO_ROOT/rtl/baseline/imuldiv")
    DEFINES=()
    TOP="riscv_Core"
    SRC="$REPO_ROOT/rtl/baseline/riscvlong/riscvlong-Core.v"
    ;;
  bp_static_nt|bp_bht1|bp_bht2|bp_gshare|bp_bht2_jal|bp_gshare_jal|bp_bht2_full|bp_gshare_full)
    RTL_DIRS=("$REPO_ROOT/rtl/core" "$REPO_ROOT/rtl/bp" "$REPO_ROOT/rtl/baseline/vc" "$REPO_ROOT/rtl/baseline/imuldiv")
    DEFINES=(-DBP_ENABLED)
    case "$VARIANT" in
      bp_static_nt)   DEFINES+=(-DBP_STATIC_NT) ;;
      bp_bht1)        DEFINES+=(-DBP_BHT1)      ;;
      bp_bht2)        DEFINES+=(-DBP_BHT2)      ;;
      bp_gshare)      DEFINES+=(-DBP_GSHARE)    ;;
      bp_bht2_jal)    DEFINES+=(-DBP_BHT2 -DBP_PRED_JAL) ;;
      bp_gshare_jal)  DEFINES+=(-DBP_GSHARE -DBP_PRED_JAL) ;;
      bp_bht2_full)   DEFINES+=(-DBP_BHT2 -DBP_PRED_JAL -DBP_RAS) ;;
      bp_gshare_full) DEFINES+=(-DBP_GSHARE -DBP_PRED_JAL -DBP_RAS) ;;
    esac
    TOP="riscv_Core"
    SRC="$REPO_ROOT/rtl/core/riscvlong-Core.v"
    ;;
  *)
    echo "ERROR: unknown variant '$VARIANT'" >&2
    exit 1
    ;;
esac

INCS=()
for d in "${RTL_DIRS[@]}"; do INCS+=("-I$d"); done

DEF_STRING=""
if [ ${#DEFINES[@]} -gt 0 ]; then
  DEF_STRING="${DEFINES[*]}"
fi

OUTFILE="$OUTDIR/yosys_stat.txt"
SCRIPT="/tmp/yosys_${VARIANT}.ys"

cat > "$SCRIPT" <<EOF
read_verilog -sv -defer ${INCS[*]} ${DEF_STRING} $SRC
hierarchy -check -top $TOP
synth_xilinx -family xc7 -top $TOP
stat -tech xilinx
EOF

echo "[yosys] variant=$VARIANT"
yosys -Q -l "$OUTFILE" -s "$SCRIPT" 2>&1 | tail -3

echo "[yosys] ok: $OUTFILE"
echo "--- cell counts ---"
awk '/Number of cells:/,/^$/' "$OUTFILE" | head -20
