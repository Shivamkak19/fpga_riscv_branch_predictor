# Branch-Predictor Design Exploration on `riscvooo`

ECE 475 Term Project — Spring 2026
Princeton University
Authors: Shivam Kak (sk3686), Wonju Lee (wl2527)

## Overview

This project takes Lab 4's single-issue out-of-order RISC-V processor
(`riscvooo`, with reorder buffer and scoreboard) and adds a branch
direction predictor at the front-end. Three predictor designs of
increasing complexity are evaluated, plus two stretch goals from the
proposal:

1. `bp_static_nt` — always predict not-taken (baseline-equivalent reference)
2. `bp_bht1`     — 256-entry, 1-bit-per-entry Branch History Table
3. `bp_bht2`     — 256-entry, 2-bit saturating-counter BHT
4. `bp_gshare`   — 256-entry GShare with 8-bit Global History Register

Stretch goals (each gated by a separate define, layered on top of any
direction predictor):

- `BP_PRED_JAL` — predict JAL at F using `pc + imm_uj`. Saves the
  1-cycle D-stage redirect per JAL.
- `BP_RAS`      — 8-deep Return Address Stack for JALR returns.

The `bp_bht2_full` and `bp_gshare_full` builds combine direction
prediction + JAL prediction + RAS for the proposal's headline design
points.

## Repo layout

The directory layout is **lab4 verbatim** with one new sub-package
(`bp/`) and minimal hooks in four `riscvooo/` files (all gated by
`` `ifdef BP_ENABLED `` so the lab4 path is byte-equivalent without
the predictor defines).

```
vc/                Verilog components (unchanged from lab4)
imuldiv/           Multiplier/divider units (unchanged from lab4)
riscvooo/          Single-issue OoO core (lab4 + 4 patched files)
  riscvooo-Core.v          ← wires bp signals between ctrl ↔ dpath
  riscvooo-CoreCtrl.v      ← bp_top instantiate, F-redirect, X-resolve, counters
  riscvooo-CoreDpath.v     ← pm_pred mux + pred_target pipeline
  riscvooo-sim.v           ← prints branch/misp lines under `ifdef BP_ENABLED
  everything else (Alu, Regfile, MulDiv, Scoreboard, ROB, InstMsg) ← byte-identical to lab4
bp/                NEW — branch-predictor sub-package
  bp_predecode.v   F-stage opcode/imm pre-decode
  bp_static_nt.v   always-NT (baseline-equivalent)
  bp_bht1.v        1-bit BHT
  bp_bht2.v        2-bit saturating-counter BHT
  bp_gshare.v      GShare with 2-bit counters + GHR
  bp_ras.v         8-entry Return Address Stack
  bp_top.v         selectable wrapper (picks one predictor by `BP_*` define)
  bp.mk
tests/             Asm tests (unchanged from lab4)
ubmark/            ubmarks (unchanged from lab4)
build/Makefile     lab4 + one extra knob: `BP_DEFINES ?=` (appended to COMP_FLAGS)
scripts/
  adroit-env.sh    source to set up /home/ECE475 toolchain on adroit
  run_variants.sh  sweep all 9 BP_* variants via lab4 make targets
  plot_results.py  render results/plots/*.png from per-variant TSVs
  plot_sweep.py    parameter sweep plotter (BHT-2 size + GShare heatmap)
results/
  <variant>/       per-variant ubmark-*-ooo.out + ubmark.tsv + asm_tests.tsv
  plots/           ipc.png, mispredict_rate.png, summary.md
docs/REPORT.md     project report
```

## Toolchain

- **RISC-V cross compiler**: `riscv32-unknown-elf-gcc` 15.2.0 from
  `/home/ECE475/local/encap/riscv-gnu-toolchain-2026.2.13` (a wrapper
  for `riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32`).
- **RTL simulator**: iverilog 12 (`/home/ECE475/local/encap/iverilog-v12`).
  Same simulator the lab4 reference build uses.

`scripts/adroit-env.sh` puts both on `PATH`. Source it once per shell.

## Build & run (lab4 commands verbatim, plus one knob)

```bash
source scripts/adroit-env.sh

# One-time: build the asm-test and ubmark vmh files via lab4's autoconf flow.
(cd tests  && mkdir -p build && cd build && \
   ../configure --host=riscv32-unknown-elf && make && ../convert)
(cd ubmark && mkdir -p build && cd build && \
   ../configure --host=riscv32-unknown-elf && make && ../convert)

# Baseline (unmodified lab4 riscvooo)
cd build
make riscvooo-sim
make check-asm-riscvooo            # 47/47 PASSED expected
make run-bmark-riscvooo            # emits ubmark-*-ooo.out

# Predictor variant
make clean
make BP_DEFINES="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL -DBP_RAS" \
     riscvooo-sim check-asm-riscvooo run-bmark-riscvooo
```

Sweep all 9 variants and aggregate per-variant `*-ooo.out` + TSVs
under `results/<variant>/`:

```bash
./scripts/run_variants.sh         # ~90 seconds
./scripts/plot_results.py         # render PNGs from results/<variant>/ubmark.tsv
```

## Headline results (RTL simulation, kernel-only per lab4 convention)

All 47 asm tests pass on every variant (`make check-asm-riscvooo`
reports `[ PASSED ]` × 47). All 4 ubmarks pass on every variant. The
`*-ooo.out` files this project produces are byte-identical to
`l4/lab4/build/*-ooo.out` for the **baseline** build (same toolchain,
same flags, same testbench, same vmh).

ubmark IPC (kernel-only, gated by `csr_stats` per lab4 convention):

| Benchmark           | baseline | static_nt | bht1   | bht2   | gshare |
|---------------------|---------:|----------:|-------:|-------:|-------:|
| ubmark-vvadd        | 0.8865   | 0.8865    | 0.9115 | 0.9115 | 0.8830 |
| ubmark-cmplx-mult   | 0.7105   | 0.7105    | 0.7236 | 0.7236 | 0.7194 |
| ubmark-bin-search   | 0.7048   | 0.7048    | 0.7865 | 0.7952 | 0.7664 |
| ubmark-masked-filter| 0.6622   | 0.6622    | 0.7064 | 0.7153 | 0.7115 |
| **mean**            | **0.741**| **0.741** | **0.782**| **0.786**| **0.770** |

With both proposal stretch goals enabled (JAL prediction + RAS):

| Benchmark           | bht2_full | gshare_full |
|---------------------|----------:|------------:|
| ubmark-vvadd        | 0.9115    | 0.8830      |
| ubmark-cmplx-mult   | 0.7239    | 0.7197      |
| ubmark-bin-search   | 0.8215    | 0.7908      |
| ubmark-masked-filter| 0.7394    | 0.7354      |
| **mean**            | **0.799** | **0.782**   |

**Sanity check vs lab4 reference** — our `results/baseline/*-ooo.out`
status / num_cycles / num_inst / ipc lines diff cleanly against
`l4/lab4/build/*-ooo.out` for all 4 ubmarks:

| Benchmark           | num_cycles | num_inst | ipc     |
|---------------------|-----------:|---------:|--------:|
| ubmark-vvadd        |        511 |      453 | 0.886497 |
| ubmark-cmplx-mult   |       2425 |     1723 | 0.710515 |
| ubmark-bin-search   |       1443 |     1017 | 0.704782 |
| ubmark-masked-filter|       7446 |     4931 | 0.662235 |

Identical numbers across all four. The build flow + RTL behave
exactly as lab4's reference for the baseline, and the predictor
variants build on top with `BP_DEFINES`.

The biggest IPC lifts come from the higher-branch-count workloads:
`bin-search` (0.705 → 0.795 with BHT-2, +12.8%) and `masked-filter`
(0.662 → 0.715, +8.0%). `vvadd` and `cmplx-mult` see smaller
*relative* lifts because `-O3 -funroll-loops` collapses their inner
loops into nearly straight-line code (only 10 and 27 dynamic
conditional branches in the kernel, respectively). With the JAL
stretch goal on, `bin-search` jumps further (0.795 → 0.822, +3.4%)
and `masked-filter` lifts to 0.739, taking BHT-2 + JAL to 0.799
mean IPC across the four ubmarks.

See `docs/REPORT.md` for the integration design, methodology, and
analysis.
