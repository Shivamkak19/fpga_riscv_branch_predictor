#!/bin/bash
# run_ubmarks.sh - build & run all ubmark benchmarks against a variant
# Usage: run_ubmarks.sh <variant>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANT=${1:-baseline}
SIM="$REPO_ROOT/sim/build/$VARIANT/Vsim_top"
BUILD_DIR="$REPO_ROOT/benchmarks/build/$VARIANT"
RESULTS_DIR="$REPO_ROOT/results/$VARIANT"
mkdir -p "$BUILD_DIR" "$RESULTS_DIR"

if [ ! -x "$SIM" ]; then
  echo "ERROR: simulator $SIM not built." >&2
  exit 1
fi

SUMMARY="$RESULTS_DIR/ubmark.tsv"
echo -e "bench\tstatus\tcycles\tinst\tipc\tbranches\ttaken\tjumps\tmispredicts\tpred_correct" > "$SUMMARY"

cd "$REPO_ROOT/benchmarks/ubmark/ubmark"
for src in ubmark-vvadd.c ubmark-cmplx-mult.c ubmark-bin-search.c ubmark-masked-filter.c; do
  name="${src%.c}"
  vmh="$BUILD_DIR/$name.vmh"
  log="$RESULTS_DIR/$name.log"

  if ! "$REPO_ROOT/scripts/build_ubmark.sh" "$src" "$BUILD_DIR" > "$log.build" 2>&1; then
    echo "ERROR build: $name"
    continue
  fi

  if ! gtimeout 120 "$SIM" +exe="$vmh" +max-cycles=2000000 +stats=1 > "$log" 2>&1; then
    echo "ERROR run: $name (rc=$?)"
    continue
  fi

  status=$(grep -E "\*\*\* (PASSED|FAILED|TIMEOUT) \*\*\*" "$log" | head -1 | awk '{print $2}')
  cycles=$(awk '/^ cycles  /{print $3; exit}' "$log")
  inst=$(awk '/^ retired_inst /{print $3; exit}' "$log")
  ipc=$(awk '/^ ipc /{print $3; exit}' "$log")
  br=$(awk '/^ branches /{print $3; exit}' "$log")
  taken=$(awk '/^ taken_branches /{print $3; exit}' "$log")
  jumps=$(awk '/^ jumps /{print $3; exit}' "$log")
  misp=$(awk '/^ mispredicts /{print $3; exit}' "$log")
  pcor=$(awk '/^ pred_correct /{print $3; exit}' "$log")
  : "${status:=UNKNOWN}" "${cycles:=-}" "${inst:=-}" "${ipc:=-}" "${br:=-}" "${taken:=-}" "${jumps:=-}" "${misp:=-}" "${pcor:=-}"

  printf "%-25s  %-7s  cyc=%-7s  inst=%-6s  ipc=%-7s  br=%-4s  taken=%-4s  j=%-3s  misp=%-4s  pcor=%s\n" \
         "$name" "$status" "$cycles" "$inst" "$ipc" "$br" "$taken" "$jumps" "$misp" "$pcor"
  echo -e "$name\t$status\t$cycles\t$inst\t$ipc\t$br\t$taken\t$jumps\t$misp\t$pcor" >> "$SUMMARY"
done
