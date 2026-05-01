#!/bin/bash
# yosys_summary.sh - aggregate per-variant yosys synth results into a TSV
#
# Output: results/yosys_summary.tsv

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT="$REPO_ROOT/results/yosys_summary.tsv"
echo -e "variant\tcells\tLUTs\tFFs\tRAM32M\tRAMB\test_LCs" > "$OUT"

for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare; do
  log="$REPO_ROOT/results/$v/yosys_stat.txt"
  if [ ! -f "$log" ]; then
    echo "skip $v (no log)"
    continue
  fi
  cells=$(grep -E "^[[:space:]]+[0-9]+ cells$" "$log" | tail -1 | awk '{print $1}' || true)
  fdre=$(grep -E "^[[:space:]]+[0-9]+[[:space:]]+FDRE$" "$log" | tail -1 | awk '{print $1}' || true)
  fdse=$(grep -E "^[[:space:]]+[0-9]+[[:space:]]+FDSE$" "$log" | tail -1 | awk '{print $1}' || true)
  ffs=$(( ${fdre:-0} + ${fdse:-0} ))
  luts=$(grep -E "^[[:space:]]+[0-9]+[[:space:]]+LUT[0-9]+$" "$log" | tail -7 | awk '{sum+=$1} END {print sum}' || true)
  bram=$(grep -E "^[[:space:]]+[0-9]+[[:space:]]+RAMB" "$log" | tail -1 | awk '{print $1}' || true)
  dram=$(grep -E "^[[:space:]]+[0-9]+[[:space:]]+RAM32M$" "$log" | tail -1 | awk '{print $1}' || true)
  lcs=$(grep "Estimated number of LCs:" "$log" | tail -1 | awk '{print $NF}' || true)
  cells=${cells:-"-"}
  luts=${luts:-"-"}
  dram=${dram:-"0"}
  bram=${bram:-"0"}
  lcs=${lcs:-"-"}
  echo -e "$v\t$cells\t$luts\t$ffs\t$dram\t$bram\t$lcs" >> "$OUT"
done

echo "wrote $OUT"
echo ""
column -t -s $'\t' "$OUT"
