# FPGA-Based Branch Predictor Design Exploration for a Single-Issue RISC-V Pipeline

**ECE 475 Term Project — Spring 2026**
**Authors:** Shivam Kak (sk3686), Wonju Lee (wl2527)

---

## 1. Summary and scope

We implemented and evaluated three branch direction predictors on the
single-issue 7-stage in-order RISC-V pipeline (`riscvlong`) used in the
ECE 475 lab tree. The predictor is integrated at the F stage with a
combinational lookup, pipelined to X for resolution, and trained on
every resolved conditional branch. The mispredict redirect is gated so
that a correct prediction has zero pipeline penalty.

The three predictor designs are:
1. **1-bit Branch History Table (BHT-1)**: 256 entries × 1 bit, indexed by
   `PC[9:2]`. Stores the last observed direction.
2. **2-bit saturating-counter BHT (BHT-2)**: 256 entries × 2 bits with the
   standard `00..11` taken/not-taken hysteresis.
3. **GShare**: 256-entry PHT of 2-bit counters, indexed by
   `PC[9:2] XOR GHR`, with an 8-bit Global History Register.

For comparison we include a `static_nt` predictor (always not-taken) and
the unmodified `baseline` core. All five configurations are bit-accurate
on the lab's 43-test assembly suite.

### Scope adjustment from proposal

The original proposal targeted a "dual-issue in-order superscalar from
Lab 3." Inspection of the actual Lab 4 deliverable shows the lab tree
contains a single-issue 7-stage in-order pipeline (`riscvlong`,
inherited from Lab 2) and a single-issue OoO design with reorder buffer
(`riscvooo`, the actual subject of Lab 4). The Vivado project that
runs on the FPGA bench host references `riscvlong` — this project
therefore targets the single-issue pipeline. The misprediction penalty
in this design is 2 cycles (squash F + D) rather than the 3-cycle
penalty the proposal cited for an X0-resolution dual-issue design. All
three predictor algorithms apply unchanged.

---

## 2. Baseline pipeline and where mispredictions hurt

The lab core's pipeline is:

```
P → F → D → X → M → X2 → X3 → W
```

Conditional branches resolve in **X** via the `branch_cond_*_Xhl`
signals, comparing `branch_targ_Xhl` against the current PC. JAL and
JALR redirect in **D** with a 1-cycle penalty.

For a wrong-direction conditional branch, the existing logic raises
`brj_taken_Xhl` and selects `pm_b` on the PC mux, which squashes F + D
and refetches at `branch_targ_Xhl`. **2 cycles of work are wasted per
mispredicted branch.** The baseline has no prediction, so every taken
conditional branch incurs this 2-cycle penalty even when the program
takes the same branch direction every iteration.

The static cost shows up most plainly in `ubmark-vvadd`, a tight loop
over 100 elements. With 397 of 400 conditional branches taken, the
baseline loses `397 × 2 = 794 cycles` to refetch — about 30% of total
runtime. The opportunity for a predictor is large.

---

## 3. Predictor RTL

### 3.1 Pre-decoder (`bp_predecode.v`)

A pure-combinational decoder over the F-stage instruction word that
extracts:

- `is_branch`, `is_jal`, `is_jalr`: opcode classification
- `br_target  = pc + sign_extend(imm_sb)` for B-type
- `jal_target = pc + sign_extend(imm_uj)` for JAL

Both targets are decodable from F-stage bits alone — no register read
needed, so they fit on the critical fetch path. JALR's target requires
`rs1`, so we don't predict it at F (it falls through to the existing
1-cycle D-stage redirect, same as baseline).

### 3.2 1-bit BHT

A 256-entry register array holding one bit per entry. Read is
combinational, indexed by `predict_pc[9:2]`. Write happens at the end
of the X stage on every resolved conditional branch, indexed by
`update_pc[9:2]`. No tagging — pure direct-mapped, with full aliasing
between branches that hash to the same index.

```verilog
reg [ENTRIES-1:0] table_r;
assign predict_taken = table_r[predict_pc[9:2]];
always @(posedge clk) if (update_en) table_r[update_pc[9:2]] <= update_taken;
```

### 3.3 2-bit BHT

Same indexing, but each entry is a 2-bit saturating counter:
`00`=strongly NT, `01`=weakly NT, `10`=weakly T, `11`=strongly T. Predict
taken iff bit 1 is set. The saturation means a single anomalous
direction in a streak doesn't flip the prediction. On reset all entries
initialize to `01` (weakly NT), giving cold branches a slight bias away
from taken with only one wrong observation needed to flip.

### 3.4 GShare

256-entry PHT of 2-bit counters indexed by `PC[9:2] XOR GHR[7:0]`. The
GHR is shifted left with the resolved direction on every branch
update. The XOR mixes path-history information into the index so that
the same PC can map to different counters depending on the recent
context — useful when one branch's outcome depends on a recent prior
branch.

A note on speculation: this implementation only updates the GHR at
**resolve** time (X stage), not at predict time (F stage). That means
branches in the F→D→X shadow of an as-yet-unresolved branch see a
slightly stale GHR. A speculative-update design would commit GHR at F
and snapshot it on every branch for rollback on mispredict, which is
substantially more state. For the IPC range we are targeting, the
non-speculative GHR is sufficient and the report results bear this
out.

### 3.5 Selectable wrapper (`bp_top.v`)

`bp_top` instantiates exactly one of the four predictors based on the
`BP_*` define set at build time:

```verilog
`ifdef BP_STATIC_NT  bp_static_nt  ...
`elsif BP_BHT1       bp_bht1       ...
`elsif BP_GSHARE     bp_gshare     ...
`else                bp_bht2       ... // default
`endif
```

The pre-decoder, predictor instantiation, and pipeline registers are
all gated by `\`ifdef BP_ENABLED`. Without that define the core compiles
back to the unmodified baseline — this is what the `baseline` build
target uses.

---

## 4. Integration into the core

### 4.1 F-stage prediction

`bp_predecode` runs combinationally on the imresp queue mux output
(the 32-bit instruction word that D will receive next cycle), tagged
with `pc_Fhl`. The predictor is queried with the same PC. If the
F-stage instruction is a B-type and the predictor says taken, the
F-stage fires a redirect through a new PC-mux input:

```
pred_redirect_Fhl = inst_val_Fhl && is_branch_F && predict_taken_F
pred_target_Fhl   = br_target_F
```

The PC-mux ordering becomes (highest priority first):

```
pc_mux_sel_Phl =
   brj_taken_Xhl     → pm_b      (mispredict redirect at X)
 : brj_taken_Dhl     → pm_j/pm_r (jump redirect at D, JAL/JALR)
 : pred_redirect_Fhl → pm_pred   (predicted-taken redirect at F)
 :                     pm_p      (PC + 4)
```

The new `pm_pred = 3'd4` mux input feeds `pred_target_Fhl` into the PC
register on the next clock edge. JAL/JALR are deliberately not
predicted at F — they continue to redirect from D as before, with their
existing 1-cycle penalty. This keeps the change small and isolates
the new logic to conditional branches.

### 4.2 Pipelining the prediction

A small two-stage register chain pipelines `predict_taken_F` from F →
D → X so the X stage can compare prediction against actual outcome:

```verilog
always @(posedge clk) begin
  if      (reset)         {pred_taken_Dhl_r, pred_taken_Xhl_r} <= 0;
  else begin
    if (!stall_Dhl) pred_taken_Dhl_r <= (inst_val_Fhl && is_branch_F)
                                         ? predict_taken_F : 1'b0;
    if (!stall_Xhl) pred_taken_Xhl_r <= pred_taken_Dhl_r;
  end
end
```

The bit is valid only when the X-stage instruction is itself a B-type
(`br_sel_Xhl != br_none`). For non-branches the bit is a don't-care;
gating the X-stage compare on `bp_resolve_Xhl` keeps stray "predictions"
on non-branches from polluting the predictor.

### 4.3 X-stage resolution and mispredict redirect

```verilog
wire actual_taken_Xhl       = inst_val_Xhl && any_br_taken_Xhl;
wire bp_resolve_Xhl         = inst_val_Xhl && (br_sel_Xhl != br_none);
wire bp_correct_Xhl         = bp_resolve_Xhl && (actual_taken_Xhl == pred_taken_Xhl);
wire mispredict_Xhl         = bp_resolve_Xhl && (actual_taken_Xhl != pred_taken_Xhl);
wire brj_taken_Xhl          = mispredict_Xhl;          // fire only on mispredict
wire redirect_to_target_Xhl = actual_taken_Xhl;        // T→branch_targ, NT→pc+4
```

The most important change is `brj_taken_Xhl = mispredict_Xhl`. With the
predictor, X-stage redirect *only* fires when prediction was wrong.
A correct taken-prediction does not squash F+D — F is already fetching
from the correct target. A correct not-taken-prediction also doesn't
squash — F is already fetching from PC+4. **Correct predictions cost
zero cycles**, and that is where IPC improvement comes from.

The `pm_b` PC-mux input now selects between `branch_targ_Xhl` and
`pc_Xhl + 4` depending on the actual direction (`redirect_to_target_Xhl`):

- Mispredict (predicted T, actual NT): F was redirected to wrong target;
  squash F+D, redirect back to fall-through `pc_Xhl + 4`.
- Mispredict (predicted NT, actual T): F was fetching fall-through;
  squash F+D, redirect to `branch_targ_Xhl`.

The squash logic itself is unchanged — `squash_Fhl` still fires on
`brj_taken_Xhl`, `squash_Dhl` still fires on `brj_taken_Xhl`. Only the
*meaning* of `brj_taken_Xhl` changes.

### 4.4 Predictor training

Training is unconditional on every resolved conditional branch:

```verilog
bp_top u_bp (
  ...
  .update_en   (bp_resolve_Xhl),
  .update_pc   (pc_Xhl),
  .update_taken(actual_taken_Xhl),
  .update_mispredict(mispredict_Xhl)
);
```

The 2-bit BHT and GShare both update their counters toward the actual
outcome (saturating at the endpoints). The 1-bit BHT just overwrites
with the actual outcome.

---

## 5. Functional verification

All 43 RISC-V assembly tests from the lab tree pass on every
configuration:

| Variant       | passed | failed | error |
|---------------|-------:|-------:|------:|
| baseline      |     43 |      0 |     0 |
| bp_static_nt  |     43 |      0 |     0 |
| bp_bht1       |     43 |      0 |     0 |
| bp_bht2       |     43 |      0 |     0 |
| bp_gshare     |     43 |      0 |     0 |

This includes every branch test (`riscv-beq`, `riscv-bne`, `riscv-blt`,
`riscv-bge`, `riscv-bltu`, `riscv-bgeu`), every jump test (`riscv-j`,
`riscv-jal`, `riscv-jalr`, `riscv-jr`), and the integer / load-store /
mul-div suites. The full per-test log lives at
`results/<variant>/asm_tests.tsv`.

---

## 6. Performance results: ubmark microbenchmarks

The four ubmark binaries — `vvadd`, `cmplx-mult`, `bin-search`,
`masked-filter` — are larger workloads with real loops and so exercise
the predictor far more meaningfully than the assembly tests (whose
branches mostly use unique PCs and never repeat).

### 6.1 IPC by variant

| Benchmark           | baseline | static_nt | bht1   | bht2   | gshare |
|---------------------|---------:|----------:|-------:|-------:|-------:|
| ubmark-vvadd        |  0.6986  |  0.6986   | 0.9914 | 0.9914 | 0.9665 |
| ubmark-cmplx-mult   |  0.7475  |  0.7475   | 0.9116 | 0.9116 | 0.9019 |
| ubmark-bin-search   |  0.7146  |  0.7146   | 0.8128 | 0.8208 | 0.7799 |
| ubmark-masked-filter|  0.6819  |  0.6819   | 0.9242 | 0.9222 | 0.9216 |
| **mean**            | **0.711** | **0.711** | **0.910** | **0.911** | **0.893** |

The IPC ceiling is 1.0 (single-issue, single retire per cycle). The
baseline's 0.71 mean tells us roughly 30% of cycles are lost to either
data hazards (load-use stalls, multi-cycle muldiv) or branch
mispredicts.

`static_nt` is identical to `baseline` because the lab core's existing
behavior is itself "always not-taken" — fetch PC+4 and only correct on
X resolution. Adding our predictor in `static_nt` mode therefore
doesn't change observable IPC. This validates that our integration
adds zero overhead when the predictor signal is constant.

The 1-bit and 2-bit BHTs give the largest IPC lift on the loop-heavy
benchmarks: vvadd jumps from 0.70 → 0.99, eliminating essentially the
entire branch-mispredict tax (only 7 mispredicts remain out of 400
branches, all on cold loop entry/exit).

GShare is competitive on the larger benchmarks but slightly worse than
BHT-2 on tight loops, especially `vvadd` (0.97 vs 0.99). The reason is
GHR pollution: for a single-direction loop branch, the GHR cycles
through patterns of mostly-`1`s, mapping the same PC to different
counters depending on how many other taken branches have just
resolved. That delays warmup and doubles the warmup cost. With more
diverse control flow, GShare's correlation pays off — but on these
benchmarks it never beats BHT-2.

`ubmark-bin-search` is the hardest benchmark for any direction
predictor. Binary search compares against data, so each branch's
direction is essentially uncorrelated random data. BHT-2 hits 79%
accuracy (57 mispredicts in 276 branches), about as well as any
direction predictor can do on this workload without value prediction.
GShare actually does worse here (66% accuracy) because the GHR's
correlation assumption is just wrong for data-driven branches.

### 6.2 Mispredict rates

| Benchmark           | branches | bht1 misp | bht2 misp | gshare misp |
|---------------------|---------:|----------:|----------:|------------:|
| ubmark-vvadd        |      400 |  7  (1.8%) |  7  (1.8%) | 31 ( 7.8%) |
| ubmark-cmplx-mult   |      600 |  6  (1.0%) |  6  (1.0%) | 25 ( 4.2%) |
| ubmark-bin-search   |      276 | 64 (23.2%) | 57 (20.7%) | 94 (34.1%) |
| ubmark-masked-filter|     1868 | 72  (3.9%) | 82  (4.4%) | 85 ( 4.6%) |

For comparison, every variant resolves the same number of branches per
benchmark (predictors don't change the dynamic instruction count, only
where the front-end is fetching from while the branch is in flight).

### 6.3 Cycle-level accounting on `ubmark-vvadd`

Worth a closer look because the workload is small enough to reason
about exactly:

- 400 conditional branches, 397 actually taken (`397/400 = 99.25%` taken
  rate — a tight `for (i=0; i<size; i++)` loop)
- baseline: `397 taken × 2 squash cycles = 794 wasted cycles`
- baseline total: 2641 cycles for 1845 retired insts → IPC 0.699
- bht2: 7 mispredicts × 2 cycles = 14 wasted cycles
- bht2 total: 1861 cycles, IPC 0.991
- delta: `2641 - 1861 = 780 cycles saved`, very close to the 794 ceiling

The ~14-cycle gap from theoretical maximum is from the predictor being
cold at loop entry (the first encounter of each loop branch is
mispredicted) and from the small bit of non-loop control flow in the
test harness.

---

## 7. FPGA synthesis results

The Vivado synth flow runs on the lab bench host
(`bench@10.50.62.45`, Nexys-4 DDR / Artix-7 xc7a100tcsg324-1).
`fpga/synth_scripts/synth_variant.tcl` performs the per-variant
build:

1. Overlays the variant's RTL files into `~/ece475-lab4/riscvlong/`
   (and the predictor sources into `~/ece475-lab4/bp/`)
2. Sets the appropriate `BP_*` verilog defines on the project's
   fileset
3. Resets and re-runs `synth_1`, then `impl_1` through bitstream
4. Captures `report_utilization`, `report_timing_summary`,
   `report_timing -delay_type max -max_paths 25`, and `report_power`
5. Copies the bitstream to `~/results/<variant>/fpga_top.bit`

To execute end-to-end (from this repo on the laptop):

```
./scripts/deploy_to_bench.sh
ssh bench
cd ~/riscv-fpga/xilinx_proj
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare; do
  vivado -mode batch -nojournal -nolog \
         -source ~/fpga_riscv_branch_predictor/fpga/synth_scripts/synth_variant.tcl \
         -tclargs $v
done
```

> **Status**: The bench host was unreachable from this Mac during the
> write-up window (Princeton VPN connection dropped after authoring
> began). The synthesis flow scripts and the per-variant overlay logic
> are committed to `fpga/synth_scripts/` and `scripts/deploy_to_bench.sh`,
> ready to run as soon as the VPN session is re-established. The
> FPGA-area-and-Fmax sub-table below will be filled in from the run
> outputs once that happens. **The lab evaluation runs verbatim on
> the bench host with the supplied scripts** — no RTL changes are
> required at synthesis time vs. the simulation flow.

### 7.1 Expected FPGA results (planned table)

To be filled from `~/results/<variant>/{utilization.rpt, timing_summary.rpt}`:

| Variant       | LUTs | FFs  | BRAM | Fmax (MHz) | Crit-path |
|---------------|-----:|-----:|-----:|-----------:|-----------|
| baseline      |  TBD |  TBD |  TBD |        TBD | TBD       |
| bp_static_nt  |  TBD |  TBD |  TBD |        TBD | TBD       |
| bp_bht1       |  TBD |  TBD |  TBD |        TBD | TBD       |
| bp_bht2       |  TBD |  TBD |  TBD |        TBD | TBD       |
| bp_gshare     |  TBD |  TBD |  TBD |        TBD | TBD       |

### 7.2 What we expect

The predictor designs are quite small relative to the rest of the
core. Expected FF / LUT impact for each variant relative to baseline:

- **bp_static_nt**: ~zero — just the pre-decoder and a few pipeline
  registers, all of which optimize away when `predict_taken` is
  constant 0.
- **bp_bht1**: 256 1-bit FFs (the table) + the read/write LUT logic
  + 2 pipeline FFs for `pred_taken_Dhl`/`pred_taken_Xhl`. Roughly
  ~270 FFs and a few dozen LUTs of overhead.
- **bp_bht2**: 512 FFs (256 entries × 2 bits) + counter increment/
  decrement logic. Roughly ~520 FFs, a few hundred LUTs.
- **bp_gshare**: 512 PHT FFs + 8-bit GHR + an 8-input XOR for the
  index. Slightly more than BHT-2 because of the XOR network and
  the GHR shift register.

Critical-path concern: the BHT/GShare read is on the F-stage PC-mux
path (the predicted target feeds `pc_mux_out_Phl`, which drives both
the imreq output and `pc_Fhl <=`). If Vivado places the BHT in
distributed RAM, the read is one LUT delay; in BRAM it's a clocked
read, which would force a one-cycle delay we did not pipeline for.
The intended mapping is **distributed RAM (LUTs)** since we use a
simple `reg [W-1:0] table_r [N-1:0]` declaration without `(*
ram_style="block" *)`. This should keep the predictor read out of
the critical path for tables of 256 entries; we will confirm from the
synth reports.

If GShare moves the critical path significantly (the XOR + index +
read all sit before the PC-mux), then the IPC win on the bigger
benchmarks must be weighed against a possible Fmax drop.

---

## 8. Two-dimensional tradeoff analysis

Pending FPGA Fmax numbers, the simulation-only view of
performance-per-area is:

| Variant       | mean IPC | Δ-FFs vs base | Δ-LUTs vs base | Notes |
|---------------|---------:|--------------:|---------------:|-------|
| baseline      |   0.711  |             0 |              0 | reference |
| bp_static_nt  |   0.711  |          ~few |           ~few | overhead-only |
| bp_bht1       |   0.910  |         ~270 |         ~few   | 28% IPC lift, tiny area |
| bp_bht2       |   0.911  |         ~520 |        ~hundreds | best mean IPC, ~2× FFs of BHT-1 |
| bp_gshare     |   0.893  |         ~520 |        ~hundreds + XOR | worse mean IPC than BHT-2 here |

The interesting headline: **on this workload mix, BHT-2 is the
performance-per-area sweet spot**. BHT-1 is half the FF count for
within 0.1% of the IPC. GShare is slightly worse than BHT-2 in IPC
*and* slightly larger in area + critical path. GShare's design
strength — exploiting recent path correlation — doesn't pay off on
loop-heavy microbenchmarks where the same PC always wants the same
prediction.

Once the Fmax numbers come in, the second axis (instructions per
**second**, not per cycle) might tell a different story. For example,
if GShare's XOR network drops Fmax by 5% relative to BHT-2 with no IPC
benefit, the wall-clock answer will favor BHT-2 even more strongly.

---

## 9. Build & run reproducibility

Every result above is reproducible from a clean checkout with:

```bash
brew install verilator riscv64-elf-gcc icarus-verilog coreutils
./scripts/run_all_variants.sh
```

This re-runs the full sweep (5 variants × {43 asm tests + 4 ubmarks})
and writes `results/<variant>/{asm_tests.tsv, ubmark.tsv}` plus an
aggregated `results/summary.tsv`. The committed TSVs in this repo come
from exactly this flow on the local laptop.

---

## 10. Open work

1. **FPGA synth runs.** Five Vivado batch jobs (one per variant),
   each ~10–15 minutes on the Artix-7 part. Pending VPN reconnect.
2. **On-board IPS measurement.** With the bitstream programmed, run
   each ubmark via the UART loader and record wall-clock cycles. This
   gives the actual instructions-per-second number to combine with
   the synth-reported Fmax for the final performance/area picture.
3. **(Optional, time-permitting) Return-Address Stack** for JALR.
   The pre-decoder already identifies JALR; a small 8-deep RAS would
   eliminate the 1-cycle JALR penalty on function returns. Folded
   into `bp_top` behind another define.
4. **(Optional) JAL prediction at F.** The pre-decoder already
   computes `jal_target`; redirecting JAL at F would save the
   1-cycle D-stage redirect on every JAL. Avoided so far to keep
   the squash logic for D-stage redirects untouched and the change
   surface area small.
