# FPGA-Based Branch Predictor Design Exploration

ECE 475 Term Project — Spring 2026
Princeton University
Authors: Shivam Kak (sk3686), Wonju Lee (wl2527)

## Overview

This project implements and compares three branch-direction predictors for a
single-issue 7-stage in-order RISC-V pipelined processor (`riscvlong`,
adapted from Lab 2 of ECE 475). Each predictor is integrated into the F
stage with a single combinational lookup, pipelined down to X for
resolution, and trained on every resolved conditional branch. We evaluate:

1. `bp_static_nt`  — always predict not-taken (baseline-equivalent)
2. `bp_bht1`       — 256-entry, 1-bit-per-entry Branch History Table
3. `bp_bht2`       — 256-entry, 2-bit saturating-counter BHT
4. `bp_gshare`     — 256-entry GShare with 8-bit Global History Register

Plus `baseline` (no predictor — the unmodified Lab RTL) for reference.

We measure functional correctness (43 RISC-V assembly tests + 4 ubmark
microbenchmarks) and IPC across all five configurations using a
Verilator-based RTL simulator. FPGA synthesis (Vivado on a Nexys-4 DDR /
Artix-7 xc7a100tcsg324-1) collects LUT/FF utilization, max clock frequency
and critical-path location for the area/performance tradeoff analysis.

## Repo layout

```
rtl/
  baseline/        Unmodified Lab 2 riscvlong RTL (reference)
  core/            Predictor-aware core (modified CoreCtrl + CoreDpath)
  bp/              Predictor modules + pre-decoder, selectable by define
sim/
  verilator/       sim_top.v  - clean Verilator testbench
  build/           Per-variant simulator binaries (gitignored)
benchmarks/
  tests/           43 assembly correctness tests (from lab4)
  ubmark/          4 microbenchmarks (vvadd, cmplx-mult, bin-search, masked-filter)
  startup/         Minimal _start that initializes sp and calls main
  linker/          ubmark.ld - text+data placement
fpga/
  synth_scripts/   Vivado batch tcl for per-variant synth
  constraints/     Nexys-4 DDR XDC (board-default)
  results/         Synth utilization, timing, power reports (per variant)
scripts/
  build_test.sh    Cross-compile a .S asm test to .vmh
  build_ubmark.sh  Cross-compile a .c benchmark to .vmh
  build_sim.sh     Build a verilator simulator for a variant
  run_tests.sh     Sweep asm tests against a built variant
  run_ubmarks.sh   Sweep ubmarks against a built variant
  run_all_variants.sh   Build + run + collect for all 5 variants
  deploy_to_bench.sh    rsync to FPGA bench host
results/
  <variant>/       Per-variant: asm_tests.tsv, ubmark.tsv, per-test logs
  summary.tsv      Aggregated benchmark results
docs/
  REPORT.md        Final report
```

## Toolchain

- **RISC-V cross compiler**: `riscv64-elf-gcc` (Homebrew). We target
  `rv32im_zicsr` / `ilp32` / `medany` / `-mno-relax`.
- **RTL simulator**: Verilator 5.x (`brew install verilator`). The lab's
  testbench was originally VCS-based; our `sim_top.v` is a clean
  rewrite that runs natively under Verilator with `--timing`.
- **FPGA synthesis**: Vivado 2019.1 on the bench host
  (`bench@10.50.62.45`, see `fpga/README.md`).

## Building & running locally

```bash
# 1. Build all 5 variants
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare; do
  ./scripts/build_sim.sh $v
done

# 2. Run all asm tests (correctness) against each variant
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare; do
  ./scripts/run_tests.sh $v
done

# 3. Run ubmarks (performance) against each variant
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare; do
  ./scripts/run_ubmarks.sh $v
done

# Or in one shot:
./scripts/run_all_variants.sh
```

Per-test results are written to `results/<variant>/`. The aggregated
benchmark CSV is `results/summary.tsv`. See `docs/REPORT.md` for the
analysis.

## FPGA flow

The FPGA build runs on the lab bench host (Nexys-4 DDR + xc7a100tcsg324-1
Artix-7). The Vivado project lives at `~/riscv-fpga/xilinx_proj/` on the
bench host and references RTL under `~/ece475-lab4/`. To synth a variant
end-to-end:

```bash
# from the laptop, after connecting to Princeton VPN:
./scripts/deploy_to_bench.sh                          # rsync this repo to bench

# on the bench host:
ssh bench
cd ~/riscv-fpga/xilinx_proj
vivado -mode batch -nojournal -nolog \
       -source ~/fpga_riscv_branch_predictor/fpga/synth_scripts/synth_variant.tcl \
       -tclargs bp_bht2

# back on the laptop:
scp -r bench:~/results ./fpga_results
```

`synth_variant.tcl` overlays our predictor RTL into the lab tree, sets the
appropriate `BP_*` verilog defines, runs synth and impl, generates the
bitstream, and exports utilization + timing reports. Run it once per
variant.

## Headline results (RTL simulation)

All 43 assembly tests pass on all 5 variants — the predictor integration
preserves architectural correctness in every configuration.

ubmark IPC (higher is better):

| Benchmark           | baseline | static_nt | bht1   | bht2   | gshare |
|---------------------|---------:|----------:|-------:|-------:|-------:|
| ubmark-vvadd        | 0.699    | 0.699     | 0.991  | 0.991  | 0.966  |
| ubmark-cmplx-mult   | 0.747    | 0.747     | 0.912  | 0.912  | 0.902  |
| ubmark-bin-search   | 0.715    | 0.715     | 0.813  | 0.821  | 0.780  |
| ubmark-masked-filter| 0.682    | 0.682     | 0.924  | 0.922  | 0.922  |

Mispredict count (lower is better):

| Benchmark           | bht1 | bht2 | gshare | total branches |
|---------------------|-----:|-----:|-------:|---------------:|
| ubmark-vvadd        |    7 |    7 |     31 |            400 |
| ubmark-cmplx-mult   |    6 |    6 |     25 |            600 |
| ubmark-bin-search   |   64 |   57 |     94 |            276 |
| ubmark-masked-filter|   72 |   82 |     85 |           1868 |

See `docs/REPORT.md` for analysis, FPGA area/Fmax tradeoffs, and the
two-dimensional performance/area discussion.

## Scope clarification

The original proposal described the base processor as the "dual-issue
in-order superscalar from Lab 3." The actual lab tree contains a
single-issue 7-stage in-order pipeline (`riscvlong`, derived from Lab 2)
and an out-of-order single-issue ROB design (`riscvooo`, Lab 4). The
FPGA's Vivado project references `riscvlong` — so this project targets the
single-issue 7-stage pipeline. The misprediction penalty is 2 cycles
(squash F + D when a conditional branch is wrong-path), not 3 as the
proposal stated for an X0-resolution dual-issue design. All three
predictor algorithms still apply unchanged.

## Notes on simulator setup

The original `riscvlong-sim.v` was written for Synopsys VCS and a few
small adjustments were needed for Verilator + `riscv64-elf-gcc`:

- The `vc-MemReqMsg.v` / `vc-MemRespMsg.v` use `type` as an identifier;
  we set `--language 1364-2005` to keep `type` un-reserved.
- We pass `--x-initial 0` so uninitialized regs come up at 0 (matches
  FPGA flop power-on behavior under reset).
- Our testbench (`sim/verilator/sim_top.v`) avoids `always @(*)`
  blocks containing `$finish`/`#delay`, which deadlock the timing
  scheduler. All termination logic lives in a single posedge-clk block.
- Reset is held for 50 simulated ns to ensure the bubble-bit chain
  fully propagates through the pipeline before instructions begin
  retiring.
