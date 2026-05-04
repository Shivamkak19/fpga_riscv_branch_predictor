#!/bin/bash
#=========================================================================
# run_variants.sh - sweep the 9 BP variants via the lab4 make flow
#=========================================================================
# For each variant: cd build/ ; make clean ; make BP_DEFINES="..."
# check-asm-riscvooo run-bmark-riscvooo. Resulting *-ooo.out files
# get archived under results/<variant>/, identical in name and format
# to l4/lab4/build/*-ooo.out.
#
# Prereqs (run once before the first sweep):
#   source scripts/adroit-env.sh
#   (cd tests   && mkdir -p build && cd build && ../configure --host=riscv32-unknown-elf && make && ../convert)
#   (cd ubmark  && mkdir -p build && cd build && ../configure --host=riscv32-unknown-elf && make && ../convert)
#
# Usage:
#   scripts/run_variants.sh [variant ...]
#   (no args = all 9 variants)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

declare -A VARIANT_DEFS
VARIANT_DEFS=(
  [baseline]=""
  [bp_static_nt]="-DBP_ENABLED -DBP_STATIC_NT"
  [bp_bht1]="-DBP_ENABLED -DBP_BHT1"
  [bp_bht2]="-DBP_ENABLED -DBP_BHT2"
  [bp_two_level]="-DBP_ENABLED -DBP_TWO_LEVEL"
  [bp_bht2_jal]="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL"
  [bp_two_level_jal]="-DBP_ENABLED -DBP_TWO_LEVEL -DBP_PRED_JAL"
  [bp_bht2_full]="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL -DBP_RAS"
  [bp_two_level_full]="-DBP_ENABLED -DBP_TWO_LEVEL -DBP_PRED_JAL -DBP_RAS"
)

# Order matters for the report tables.
ORDER=(baseline bp_static_nt bp_bht1 bp_bht2 bp_two_level \
       bp_bht2_jal bp_two_level_jal bp_bht2_full bp_two_level_full)

if [ $# -gt 0 ]; then
  VARIANTS=("$@")
else
  VARIANTS=("${ORDER[@]}")
fi

cd "$REPO_ROOT/build"

for v in "${VARIANTS[@]}"; do
  if [ -z "${VARIANT_DEFS[$v]+_}" ]; then
    echo "ERROR: unknown variant '$v'" >&2
    exit 1
  fi
  defs="${VARIANT_DEFS[$v]}"

  echo
  echo "========================================================================="
  echo "===== variant=$v"
  echo "===== BP_DEFINES=\"$defs\""
  echo "========================================================================="

  make clean > /dev/null
  make BP_DEFINES="$defs" riscvooo-sim 2>&1 | tail -1

  asm_log="$REPO_ROOT/results/$v.asm.log"
  make BP_DEFINES="$defs" check-asm-riscvooo > "$asm_log" 2>&1
  passed=$(grep -c '\[ PASSED \]' "$asm_log" || true)
  failed=$(grep -c '\[ FAILED \]' "$asm_log" || true)
  echo "  asm:    PASSED=$passed FAILED=$failed (lab4 has 47 ooo_tests targets)"

  bmark_log="$REPO_ROOT/results/$v.bmark.log"
  make BP_DEFINES="$defs" run-bmark-riscvooo > "$bmark_log" 2>&1
  bpassed=$(grep -c '\[ PASSED \]' "$bmark_log" || true)
  bfailed=$(grep -c '\[ FAILED \]' "$bmark_log" || true)
  echo "  ubmark: PASSED=$bpassed FAILED=$bfailed (4 ubmarks)"

  out_dir="$REPO_ROOT/results/$v"
  mkdir -p "$out_dir"
  cp -p *-ooo.out "$out_dir/" 2>/dev/null || true

  # Aggregate TSV for plot_results.py (one row per ubmark). Branch /
  # mispredict columns are populated only for BP variants — riscvooo-sim.v
  # only prints those lines under `ifdef BP_ENABLED.
  ubmark_tsv="$out_dir/ubmark.tsv"
  printf 'bench\tstatus\tcycles\tinst\tipc\tbranches\ttaken\tresolved\tpred_correct\tmispredicts\n' > "$ubmark_tsv"
  for b in ubmark-vvadd ubmark-cmplx-mult ubmark-bin-search ubmark-masked-filter; do
    out_file="$out_dir/${b}-ooo.out"
    [ ! -f "$out_file" ] && continue
    st=$(grep -oE '\*\*\* (PASSED|FAILED)' "$out_file" | head -1 | awk '{print $2}')
    c=$(awk '/^ num_cycles /{print $3; exit}' "$out_file")
    i=$(awk '/^ num_inst   /{print $3; exit}' "$out_file")
    p=$(awk '/^ ipc /{print $3; exit}' "$out_file")
    br=$(awk '/^ branches   /{print $3; exit}' "$out_file")
    tk=$(awk '/^ taken      /{print $3; exit}' "$out_file")
    rs=$(awk '/^ resolved   /{print $3; exit}' "$out_file")
    co=$(awk '/^ correct    /{print $3; exit}' "$out_file")
    mp=$(awk '/^ mispredict /{print $3; exit}' "$out_file")
    : "${st:=UNKNOWN}" "${br:=-}" "${tk:=-}" "${rs:=-}" "${co:=-}" "${mp:=-}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
           "$b" "$st" "$c" "$i" "$p" "$br" "$tk" "$rs" "$co" "$mp" >> "$ubmark_tsv"
    printf '  %-25s cycles=%-6s inst=%-5s ipc=%s  br=%s misp=%s\n' \
           "$b" "$c" "$i" "$p" "$br" "$mp"
  done

  # Asm summary TSV
  asm_tsv="$out_dir/asm_tests.tsv"
  printf 'test\tstatus\n' > "$asm_tsv"
  grep -E '\[ (PASSED|FAILED) \]' "$asm_log" \
    | awk '{ printf "%s\t%s\n", $3, $2 }' \
    | sed 's/-ooo.out//' >> "$asm_tsv" || true
done

echo
echo "Done. Per-variant *-ooo.out files are under results/<variant>/."
