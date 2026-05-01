#!/bin/bash
# run_tests.sh - run all .S tests against a built simulator variant
#
# Usage: run_tests.sh <variant> [test_pattern]
# Output: per-test PASS/FAIL + cycle/IPC summary, written to results/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VARIANT=${1:-baseline}
PATTERN=${2:-"*"}

SIM="$REPO_ROOT/sim/build/$VARIANT/Vsim_top"
TESTS_DIR="$REPO_ROOT/benchmarks/tests/riscv"
BUILD_DIR="$REPO_ROOT/benchmarks/build/$VARIANT"
RESULTS_DIR="$REPO_ROOT/results/$VARIANT"

mkdir -p "$BUILD_DIR" "$RESULTS_DIR"

if [ ! -x "$SIM" ]; then
  echo "ERROR: simulator $SIM not built. Run scripts/build_sim.sh $VARIANT" >&2
  exit 1
fi

SUMMARY="$RESULTS_DIR/asm_tests.tsv"
echo -e "test\tstatus\tcycles\tinst\tipc\tbranches\ttaken\tjumps\tmispredicts" > "$SUMMARY"

PASS=0
FAIL=0
ERROR=0

for src in "$TESTS_DIR"/riscv-${PATTERN}.S; do
  test=$(basename "$src" .S)
  vmh="$BUILD_DIR/$test.vmh"
  log="$RESULTS_DIR/$test.log"

  # Build
  if ! "$REPO_ROOT/scripts/build_test.sh" "$src" "$BUILD_DIR" > "$log.build" 2>&1; then
    echo "ERROR build: $test"
    ERROR=$((ERROR+1))
    continue
  fi

  # Run
  if ! gtimeout 60 "$SIM" +exe="$vmh" +max-cycles=200000 +stats=1 > "$log" 2>&1; then
    rc=$?
    echo "ERROR run rc=$rc: $test"
    ERROR=$((ERROR+1))
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
  : "${status:=UNKNOWN}" "${cycles:=-}" "${inst:=-}" "${ipc:=-}" "${br:=-}" "${taken:=-}" "${jumps:=-}" "${misp:=-}"

  printf "%-30s  %-7s  cyc=%-6s  inst=%-6s  ipc=%-7s  br=%-4s  taken=%-4s  j=%-4s  misp=%s\n" \
         "$test" "$status" "$cycles" "$inst" "$ipc" "$br" "$taken" "$jumps" "$misp"
  echo -e "$test\t$status\t$cycles\t$inst\t$ipc\t$br\t$taken\t$jumps\t$misp" >> "$SUMMARY"

  case "$status" in
    PASSED) PASS=$((PASS+1)) ;;
    FAILED|TIMEOUT) FAIL=$((FAIL+1)) ;;
    *)      ERROR=$((ERROR+1)) ;;
  esac
done

echo ""
echo "=== variant=$VARIANT  pass=$PASS  fail=$FAIL  error=$ERROR ==="
exit $((FAIL + ERROR))
