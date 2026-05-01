#=========================================================================
# Top-level Makefile for the branch predictor project
#=========================================================================
# Convenience wrappers around scripts/. Most heavy lifting lives in shell
# scripts so the Makefile stays as a thin entry point.

VARIANTS := baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare

.PHONY: help all sim asm ubmark plots fpga-deploy clean

help:
	@echo "Targets:"
	@echo "  make sim          Build verilator binaries for all variants"
	@echo "  make asm          Run RISC-V asm test suite for each variant"
	@echo "  make ubmark       Run ubmark microbenchmarks for each variant"
	@echo "  make all          sim + asm + ubmark + plots (full local sweep)"
	@echo "  make plots        Render IPC and mispredict-rate charts"
	@echo "  make fpga-deploy  rsync repo to bench (requires Princeton VPN)"
	@echo "  make clean        Remove sim builds and per-test logs"

sim:
	@for v in $(VARIANTS); do \
	  ./scripts/build_sim.sh $$v ; \
	done

asm: sim
	@for v in $(VARIANTS); do \
	  echo "=== asm tests: $$v ===" ; \
	  ./scripts/run_tests.sh $$v ; \
	done

ubmark: sim
	@for v in $(VARIANTS); do \
	  echo "=== ubmark: $$v ===" ; \
	  ./scripts/run_ubmarks.sh $$v ; \
	done

plots:
	@./scripts/plot_results.py

all: sim asm ubmark plots
	@echo ""
	@echo "==> all sweeps complete. summary at results/plots/summary.md"

fpga-deploy:
	@./scripts/deploy_to_bench.sh

clean:
	rm -rf sim/build benchmarks/build
	rm -f results/*/riscv-*.log results/*/riscv-*.log.build
	rm -f results/*/ubmark-*.log results/*/ubmark-*.log.build
	rm -f results/build_*.log results/*_run.log
