#!/bin/bash
# deploy_to_bench.sh - rsync this repo to the FPGA bench host
#
# Usage: deploy_to_bench.sh
#
# Requires: ssh config alias 'bench' (set up by the README), Princeton VPN.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_DIR=${BENCH_REMOTE:-"~/fpga_riscv_branch_predictor"}

echo "[deploy] rsyncing repo to bench:$REMOTE_DIR"
rsync -avz --delete \
  --exclude='.git/' \
  --exclude='sim/build/' \
  --exclude='benchmarks/build/' \
  --exclude='*.vcd' --exclude='*.fst' --exclude='*.dcp' --exclude='*.bit' \
  --exclude='__pycache__/' --exclude='*.pyc' \
  --exclude='.DS_Store' --exclude='*.bak' --exclude='*.bak2' \
  -e "ssh" \
  "$REPO_ROOT/" "bench:$REMOTE_DIR/"

echo "[deploy] done. To synth on bench:"
echo "  ssh bench"
echo "  cd ~/riscv-fpga/xilinx_proj"
echo "  vivado -mode batch -nojournal -nolog \\"
echo "         -source $REMOTE_DIR/fpga/synth_scripts/synth_variant.tcl \\"
echo "         -tclargs <variant>"
echo ""
echo "Then to fetch results back:"
echo "  scp -r bench:~/results ./fpga_results"
