#!/bin/bash
# build_sim.sh - build a simulator binary for a given variant.
#
# Usage:   build_sim.sh <variant>
# Env:     SIM_TOOL = iverilog (default) | verilator
#
# Output:  $REPO_ROOT/sim/build/<variant>/sim_top.vvp   (iverilog)
#          $REPO_ROOT/sim/build/<variant>/Vsim_top      (verilator >= 5.x)
#
# adroit only has Verilator 4.221, which lacks --timing/--binary, so the
# default backend is iverilog (the testbench uses always #5 clk style
# delays that need the SV scheduler). Set SIM_TOOL=verilator on a host
# with a 5.x verilator if you want the faster C++ backend.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANT=${1:-baseline}
SIM_TOOL=${SIM_TOOL:-iverilog}
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

echo "[build_sim] tool=$SIM_TOOL variant=$VARIANT defines=${DEFINES[*]:-none}"

case "$SIM_TOOL" in
  iverilog)
    # The lab vc/* RTL uses `type` as a port identifier — that's a
    # reserved word under -g2005-sv, so stay on plain IEEE 1364-2005.
    OUT="$OUTDIR/sim_top.vvp"
    iverilog -g2005 -o "$OUT" -s sim_top \
      "${INCS[@]}" "${DEFINES[@]}" \
      "$REPO_ROOT/sim/verilator/sim_top.v"
    echo "[build_sim] ok: $OUT"
    ;;

  verilator)
    WARN_OFF=(
      -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTITOP -Wno-CASEINCOMPLETE
      -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNOPTFLAT -Wno-UNUSEDPARAM
      -Wno-UNUSEDSIGNAL -Wno-UNUSEDGENVAR -Wno-VARHIDDEN -Wno-CASEX
      -Wno-PINMISSING -Wno-IMPLICIT
    )
    DEFARGS=()
    [ ${#DEFINES[@]} -gt 0 ] && DEFARGS=("${DEFINES[@]}")
    verilator --binary --timing --language 1364-2005 --top-module sim_top \
      "${WARN_OFF[@]}" --x-initial 0 \
      --Mdir "$OUTDIR" \
      "${INCS[@]}" ${DEFARGS[@]+"${DEFARGS[@]}"} \
      "$REPO_ROOT/sim/verilator/sim_top.v"
    echo "[build_sim] ok: $OUTDIR/Vsim_top"
    ;;

  *)
    echo "ERROR: unknown SIM_TOOL '$SIM_TOOL' (use iverilog or verilator)" >&2
    exit 1
    ;;
esac
