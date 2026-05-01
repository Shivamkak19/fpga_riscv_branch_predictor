#!/bin/bash
# build_sim.sh - build a verilator simulator binary for a given variant
#
# Usage: build_sim.sh <variant>
#   <variant> ∈ { baseline | bp_static_nt | bp_bht1 | bp_bht2 | bp_gshare }
#
# Output: build/sim_<variant>/Vsim_top

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANT=${1:-baseline}
OUTDIR="$REPO_ROOT/sim/build/$VARIANT"
mkdir -p "$OUTDIR"

DEFINES=()
case "$VARIANT" in
  baseline)
    RTL_DIRS=(
      "$REPO_ROOT/rtl/baseline/riscvlong"
      "$REPO_ROOT/rtl/baseline/vc"
      "$REPO_ROOT/rtl/baseline/imuldiv"
    )
    ;;
  bp_static_nt|bp_bht1|bp_bht2|bp_gshare|bp_bht2_jal|bp_gshare_jal|bp_bht2_full|bp_gshare_full)
    RTL_DIRS=(
      "$REPO_ROOT/rtl/core"
      "$REPO_ROOT/rtl/bp"
      "$REPO_ROOT/rtl/baseline/vc"
      "$REPO_ROOT/rtl/baseline/imuldiv"
    )
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
    ;;
  *)
    echo "ERROR: unknown variant '$VARIANT'" >&2
    exit 1
    ;;
esac

INCS=()
for d in "${RTL_DIRS[@]}"; do INCS+=("-I$d"); done

WARN_OFF=(
  -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTITOP -Wno-CASEINCOMPLETE
  -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNOPTFLAT -Wno-UNUSEDPARAM
  -Wno-UNUSEDSIGNAL -Wno-UNUSEDGENVAR -Wno-VARHIDDEN -Wno-CASEX
  -Wno-PINMISSING -Wno-IMPLICIT
)

echo "[build_sim] variant=$VARIANT defines=${DEFINES[*]:-none}"
DEFARGS=()
[ ${#DEFINES[@]} -gt 0 ] && DEFARGS=("${DEFINES[@]}")
verilator --binary --timing --language 1364-2005 --top-module sim_top \
  "${WARN_OFF[@]}" --x-initial 0 \
  --Mdir "$OUTDIR" \
  "${INCS[@]}" ${DEFARGS[@]+"${DEFARGS[@]}"} \
  "$REPO_ROOT/sim/verilator/sim_top.v"

echo "[build_sim] ok: $OUTDIR/Vsim_top"
