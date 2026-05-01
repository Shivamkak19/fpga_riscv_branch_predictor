#!/bin/bash
# run_all_variants.sh - build sims for all variants and exercise them
# against the asm tests + ubmarks. Aggregates results into results/summary.tsv

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANTS=(baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare)

echo "==> building all variants"
for v in "${VARIANTS[@]}"; do
  "$SCRIPT_DIR/build_sim.sh" "$v" > "$REPO_ROOT/results/build_$v.log" 2>&1
done

echo "==> running asm tests for all variants"
for v in "${VARIANTS[@]}"; do
  echo "    -- $v --"
  "$SCRIPT_DIR/run_tests.sh" "$v" > "$REPO_ROOT/results/$v/asm_run.log" 2>&1 \
    || echo "      (some asm tests failed for $v — see $REPO_ROOT/results/$v/asm_run.log)"
  tail -1 "$REPO_ROOT/results/$v/asm_run.log"
done

echo "==> running ubmarks for all variants"
for v in "${VARIANTS[@]}"; do
  echo "    -- $v --"
  "$SCRIPT_DIR/run_ubmarks.sh" "$v" > "$REPO_ROOT/results/$v/ubmark_run.log" 2>&1
  awk -F'\t' 'NR>1 {printf "      %-25s %s ipc=%s misp=%s\n", $1, $2, $5, $9}' "$REPO_ROOT/results/$v/ubmark.tsv"
done

echo "==> writing summary"
SUMMARY="$REPO_ROOT/results/summary.tsv"
{
  echo -e "variant\tbench\tstatus\tcycles\tinst\tipc\tbranches\ttaken\tmispredicts"
  for v in "${VARIANTS[@]}"; do
    awk -F'\t' -v v="$v" 'NR>1 {print v"\t"$1"\t"$2"\t"$3"\t"$4"\t"$5"\t"$6"\t"$7"\t"$9}' \
      "$REPO_ROOT/results/$v/ubmark.tsv"
  done
} > "$SUMMARY"

echo "==> done. summary: $SUMMARY"
