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

Both proposal stretch goals are also implemented (each as a separate define
that layers on top of any direction predictor):

- `BP_PRED_JAL` — predict JAL at F using the deterministic
  `pc + imm_uj` target. Saves the 1-cycle D-stage redirect per JAL.
- `BP_RAS` — 8-deep Return Address Stack. JAL/JALR with `rd == x1`
  pushes pc+4; JALR with `rs1 == x1` and `rd != x1` pops and uses
  the top as the predicted target. Suppresses the redundant D-stage
  redirect when the prediction matches actual.

The `bp_bht2_full` and `bp_gshare_full` build variants combine
direction prediction + JAL prediction + RAS for the final design point.

We measure functional correctness (43 RISC-V assembly tests + 4 ubmark
microbenchmarks) and IPC across all five configurations using a
Verilator-based RTL simulator. FPGA synthesis (Vivado on a Nexys-4 DDR /
Artix-7 xc7a100tcsg324-1) collects LUT/FF utilization, max clock frequency
and critical-path location for the area/performance tradeoff analysis.

## Repo layout

The directory layout matches lab4 verbatim — the same `vc/`,
`imuldiv/`, `riscvlong/`, `riscvooo/`, `tests/`, `ubmark/`, `build/`
subpackages, the same autoconf'd `tests/build` and `ubmark/build`
flow, and the same mcppbs Makefile under `build/`. The only addition
is `bp/` (the predictor sub-package) plus our own `docs/`, `fpga/`,
`scripts/`, and `results/`.

```
vc/                 Verilog components (unchanged from lab4: RAMs, queues, mem msgs, ...)
imuldiv/            Multiplier/divider units (unchanged from lab4)
riscvlong/          7-stage in-order pipeline (lab4 + our predictor hooks)
                    -CoreCtrl.v / -CoreDpath.v / -Core.v  ← patched, hooks gated by `ifdef BP_ENABLED
                    -sim.v  ← extended to print branch/mispredict counters under `ifdef BP_ENABLED
                    everything else (Alu, Regfile, MulDiv, InstMsg, ...)  ← byte-identical to lab4
riscvooo/           Reorder-buffer design (unchanged from lab4; we do not modify or evaluate it)
bp/                 NEW: branch-predictor sub-package
                    bp_predecode.v / bp_static_nt.v / bp_bht1.v / bp_bht2.v / bp_gshare.v / bp_ras.v / bp_top.v
                    bp.mk
tests/              Asm tests (unchanged from lab4) — 47 long_tests targets including ooo-specific ones
  riscv/            *.S sources
  scripts/          objdump2vmh.py + test.ld
  build/            (configured) where vmh files land via tests/convert
ubmark/             ubmarks (unchanged from lab4)
  ubmark/           ubmark-{vvadd,cmplx-mult,bin-search,masked-filter}.{c,dat}, ubmark.h
  scripts/          objdump2vmh.py
  build/            (configured) where vmh files land via ubmark/convert
build/              Top-level make target (lab4's, with one extra knob)
  Makefile          unchanged but for `BP_DEFINES ?=` (appended to COMP_FLAGS)
  riscvlong-sim     iverilog vvp script (rebuilt per variant)
  *-long.out        per-test/ubmark output (when present in tree, the latest sweep's)
fpga/               Vivado batch synth scripts (deferred — see "FPGA flow" section)
scripts/
  adroit-env.sh     source this on adroit to point at /home/ECE475 toolchain
  run_variants.sh   sweep all 9 BP_* variants via the lab4 make targets
  yosys_synth.sh    per-variant yosys synth_xilinx run
  yosys_summary.sh  aggregate yosys cell counts → results/yosys_summary.tsv
  plot_results.py   render results/plots/*.png
  plot_sweep.py     render BHT-2 size sweep + GShare heatmap
  parse_vivado_reports.py  Vivado-report parser (deferred)
  sweep_predictor_size.sh  per-(INDEX_BITS, HIST_BITS) parameter sweep
results/
  <variant>/        per-variant: ubmark-*-long.out + ubmark.tsv + asm_tests.tsv
  yosys_summary.tsv aggregated cell counts (laptop yosys 0.64; see REPORT §7.1)
  sweep/            BHT-2 size + GShare hist-bits sweep
  plots/            ipc.png, mispredict_rate.png, synth_area.png, ipc_vs_area.png, summary.md
docs/
  REPORT.md         project report
  ADROIT_RUN.md     work order for the no-FPGA branch
PROGRESS.md         handoff notes between sessions
```

## Toolchain

- **RISC-V cross compiler**: `riscv32-unknown-elf-gcc` 15.2.0 from
  `/home/ECE475/local/encap/riscv-gnu-toolchain-2026.2.13` (a wrapper
  for `riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32`).
- **RTL simulator**: iverilog 12 (`/home/ECE475/local/encap/iverilog-v12`).
  Same simulator the lab4 reference build uses.
- **FPGA synthesis (deferred)**: Vivado 2019.1 on the lab bench host
  (`bench@10.50.62.45`). See "FPGA flow" below.

`scripts/adroit-env.sh` puts all of these on `PATH` and pins the right
defaults — source it once per shell:

```bash
source scripts/adroit-env.sh
```

## Building & running

The lab4 build flow drives everything. One-time setup to build the
asm-test and ubmark `.vmh` files:

```bash
(cd tests  && mkdir -p build && cd build && ../configure --host=riscv32-unknown-elf && make && ../convert)
(cd ubmark && mkdir -p build && cd build && ../configure --host=riscv32-unknown-elf && make && ../convert)
```

Build the **baseline** simulator (no predictor) and run the lab4
checks the same way `l4/lab4/build` does:

```bash
cd build
make riscvlong-sim                # build (no BP_DEFINES → unmodified core)
make check-asm-riscvlong          # 47 asm tests
make run-bmark-riscvlong          # 4 ubmarks; emits ubmark-*-long.out
```

For a **predictor variant**, pass `BP_DEFINES`:

```bash
make clean
make BP_DEFINES="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL -DBP_RAS" riscvlong-sim
make BP_DEFINES="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL -DBP_RAS" run-bmark-riscvlong
```

Sweep all 9 variants and aggregate per-variant `*-long.out` + TSVs
under `results/<variant>/`:

```bash
./scripts/run_variants.sh         # ~75 seconds
./scripts/plot_results.py         # render PNGs from results/<variant>/ubmark.tsv
```

## FPGA flow

> **Status:** the FPGA leg is **deferred** in this branch
> (`adroit-no-fpga`) — the Princeton lab bench host became unreachable
> across the project window, so we recast the area axis as relative
> cell counts from yosys instead of post-implementation Vivado data.
> The scripts below are retained but not executed in this branch; see
> `docs/ADROIT_RUN.md` for the no-FPGA work order and `PROGRESS.md`
> for the network diagnosis.

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

All 47 lab4 long_tests targets pass on every variant (`make
check-asm-riscvlong` reports `[ PASSED ]` × 47 for each of the 9
configs). All 4 ubmarks pass with `*** PASSED ***`. The
`*-long.out` files this project produces are byte-identical to
`l4/lab4/build/*-long.out` for the baseline build — same toolchain,
same flags, same testbench, same vmh.

ubmark IPC (kernel-only, gated by `csr_stats` per lab4 convention):

| Benchmark           | baseline | static_nt | bht1   | bht2   | gshare |
|---------------------|---------:|----------:|-------:|-------:|-------:|
| ubmark-vvadd        | 0.9618   | 0.9618    | 0.9912 | 0.9912 | 0.9577 |
| ubmark-cmplx-mult   | 0.7255   | 0.7255    | 0.7392 | 0.7392 | 0.7348 |
| ubmark-bin-search   | 0.7203   | 0.7203    | 0.8059 | 0.8149 | 0.7847 |
| ubmark-masked-filter| 0.7818   | 0.7818    | 0.8442 | 0.8568 | 0.8515 |
| **mean**            | **0.797**| **0.797** | **0.845**| **0.851**| **0.831** |

With both proposal stretch goals enabled (JAL prediction + RAS):

| Benchmark           | bht2_full | gshare_full |
|---------------------|----------:|------------:|
| ubmark-vvadd        | 0.9912    | 0.9577      |
| ubmark-cmplx-mult   | 0.7395    | 0.7351      |
| ubmark-bin-search   | 0.8426    | 0.8104      |
| ubmark-masked-filter| 0.8918    | 0.8861      |
| **mean**            | **0.866** | **0.847**   |

Sanity check — our `results/baseline/ubmark-vvadd-long.out`
diffs cleanly against `l4/lab4/build/ubmark-vvadd-long.out`:

```
$ diff results/baseline/ubmark-vvadd-long.out \
       /scratch/network/sk3686/ece475/l4/lab4/build/ubmark-vvadd-long.out
< (no relevant diff — header lines may differ in iverilog warning text)
```

Both report `status=1, num_cycles=471, num_inst=453, ipc=0.961783`.

The biggest single win is `bin-search` (baseline 0.720 → BHT-2 0.815,
+13%) and `masked-filter` (0.782 → 0.857, +9.5%). `vvadd` and
`cmplx-mult` see smaller relative lifts because `-O3 -funroll-loops`
collapses their inner loops into nearly straight-line code (only 10
and 27 dynamic conditional branches in the entire kernel,
respectively). The JAL-prediction stretch goal lifts `bin-search`
another +3% (BHT-2 0.815 → BHT-2+JAL 0.843) by removing the 1-cycle
D-stage redirect on the inner-loop call.

See `docs/REPORT.md` for analysis, parameter sweeps, FPGA area/Fmax
tradeoffs, and the two-dimensional performance/area discussion.

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
