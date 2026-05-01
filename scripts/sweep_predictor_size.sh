#!/bin/bash
# sweep_predictor_size.sh - sweep INDEX_BITS (and for GShare, HIST_BITS)
# and run all 4 ubmarks for each configuration.
#
# Usage: sweep_predictor_size.sh
# Output: results/sweep/sweep.tsv  +  build dirs under sim/build/sweep_*

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SWEEP_DIR="$REPO_ROOT/results/sweep"
mkdir -p "$SWEEP_DIR"
TSV="$SWEEP_DIR/sweep.tsv"
echo -e "predictor\tindex_bits\thist_bits\tbench\tcycles\tinst\tipc\tbranches\tmispredicts" > "$TSV"

# Build a verilator binary with custom defines
build_one() {
  local tag=$1; shift
  local outdir="$REPO_ROOT/sim/build/sweep_$tag"
  mkdir -p "$outdir"

  local includes=(
    "-I$REPO_ROOT/rtl/core" "-I$REPO_ROOT/rtl/bp"
    "-I$REPO_ROOT/rtl/baseline/vc" "-I$REPO_ROOT/rtl/baseline/imuldiv"
  )
  local warns=(
    -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MULTITOP -Wno-CASEINCOMPLETE
    -Wno-MULTIDRIVEN -Wno-LATCH -Wno-UNOPTFLAT -Wno-UNUSEDPARAM
    -Wno-UNUSEDSIGNAL -Wno-UNUSEDGENVAR -Wno-VARHIDDEN -Wno-CASEX
    -Wno-PINMISSING -Wno-IMPLICIT -Wno-SELRANGE
  )
  echo "[sweep] build $tag with $@"
  verilator --binary --timing --language 1364-2005 --top-module sim_top \
    "${warns[@]}" --x-initial 0 \
    --Mdir "$outdir" \
    "${includes[@]}" "$@" \
    "$REPO_ROOT/sim/verilator/sim_top.v" > "$SWEEP_DIR/build_$tag.log" 2>&1
  if [ ! -x "$outdir/Vsim_top" ]; then
    echo "[sweep] BUILD FAILED for $tag (see $SWEEP_DIR/build_$tag.log)"
    return 1
  fi
}

run_one() {
  local tag=$1; local pred=$2; local idx=$3; local hist=$4
  local sim="$REPO_ROOT/sim/build/sweep_$tag/Vsim_top"
  for src in ubmark-vvadd.c ubmark-cmplx-mult.c ubmark-bin-search.c ubmark-masked-filter.c; do
    name="${src%.c}"
    vmh="$REPO_ROOT/benchmarks/build/sweep/$name.vmh"
    if [ ! -f "$vmh" ]; then
      mkdir -p "$REPO_ROOT/benchmarks/build/sweep"
      "$REPO_ROOT/scripts/build_ubmark.sh" \
        "$REPO_ROOT/benchmarks/ubmark/ubmark/$src" \
        "$REPO_ROOT/benchmarks/build/sweep" > /dev/null 2>&1
    fi
    log="$REPO_ROOT/results/sweep/run_${tag}_${name}.log"
    gtimeout 120 "$sim" +exe="$vmh" +max-cycles=2000000 +stats=1 > "$log" 2>&1 || true
    cycles=$(awk '/^ cycles  /{print $3; exit}' "$log")
    inst=$(awk '/^ retired_inst /{print $3; exit}' "$log")
    ipc=$(awk '/^ ipc /{print $3; exit}' "$log")
    br=$(awk '/^ branches /{print $3; exit}' "$log")
    misp=$(awk '/^ mispredicts /{print $3; exit}' "$log")
    : "${cycles:=-}" "${inst:=-}" "${ipc:=-}" "${br:=-}" "${misp:=-}"
    echo -e "$pred\t$idx\t$hist\t$name\t$cycles\t$inst\t$ipc\t$br\t$misp" >> "$TSV"
    printf "  %-22s %s ipc=%s misp=%s\n" "$name" "[$pred idx=$idx hist=$hist]" "$ipc" "$misp"
  done
}

# Sweep BHT-2 over table sizes
for idx in 5 6 7 8 9 10; do
  tag="bht2_idx${idx}"
  echo "==> $tag"
  build_one "$tag" -DBP_ENABLED -DBP_BHT2 -DBP_INDEX_BITS=$idx
  if [ $? -eq 0 ]; then
    run_one "$tag" "bht2" "$idx" "-"
  fi
done

# Sweep GShare over (INDEX_BITS, HIST_BITS)
for idx in 6 8 10; do
  for hist in 4 8 12; do
    tag="gshare_idx${idx}_hist${hist}"
    echo "==> $tag"
    build_one "$tag" -DBP_ENABLED -DBP_GSHARE -DBP_INDEX_BITS=$idx -DBP_HIST_BITS=$hist
    if [ $? -eq 0 ]; then
      run_one "$tag" "gshare" "$idx" "$hist"
    fi
  done
done

echo ""
echo "==> sweep complete: $TSV"
