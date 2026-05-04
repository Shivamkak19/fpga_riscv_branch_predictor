# Branch-Predictor Design Exploration on `riscvooo`

**ECE 475 Term Project — Spring 2026**
**Authors:** Shivam Kak (sk3686), Wonju Lee (wl2527)

---

## 1. Summary and scope

This project takes Lab 4's single-issue out-of-order RISC-V processor
(`riscvooo`, with reorder buffer and scoreboard) and adds a branch
direction predictor at the front-end. Three direction-predictor
designs are evaluated, plus two stretch goals (JAL prediction and a
Return Address Stack) from the proposal.

The directory layout is byte-equivalent to `l4/lab4/` except for one
new sub-package (`bp/`) and four patched files in `riscvooo/`. All
patches are gated by `` `ifdef BP_ENABLED ``, so the unmodified path
through the build tree is bit-for-bit identical to lab4. The
predictor-aware build is selected by passing `BP_DEFINES` to
`build/Makefile`:

```
make BP_DEFINES="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL -DBP_RAS" riscvooo-sim
```

Cycle and instruction counts come from the **same** `proc.ctrl.num_cycles`
and `proc.ctrl.num_inst` registers `riscvooo-sim.v` reads in lab4 — the
predictor adds only `BP_ENABLED`-gated diagnostic counters, never
modifies the canonical ones. `*-ooo.out` files our build produces for
the baseline diff cleanly against `l4/lab4/build/*-ooo.out`.

### Scope vs proposal

The proposal proposed targeting "the dual-issue in-order superscalar
RISC-V processor we have designed for Lab 3" with a 3-cycle
misprediction penalty. The actual lab tree has:
- a single-issue 7-stage in-order pipeline (`riscvlong`, from Lab 2), and
- a single-issue out-of-order pipeline with reorder buffer (`riscvooo`,
  Lab 4 — the actual Lab 4 deliverable).

This project targets `riscvooo`, the Lab 4 deliverable. The
mispredict penalty is 2 cycles (squash F + D when a conditional
branch is wrong-path), not 3 as the proposal stated for an X0-resolution
dual-issue design. All three predictor algorithms apply unchanged.

The proposal also called for an FPGA synthesis flow (Vivado on a
Nexys-4 DDR / Artix-7). That leg is **deferred** — the lab bench host
became unreachable across the project window — so the area axis is
left as a future-work item; the writeup below covers IPC only.

---

## 2. Baseline pipeline and where mispredictions hurt

`riscvooo`'s pipeline is:

```
P → F → D → X → M → X2 → X3 → W
```

with a 16-entry Reorder Buffer for in-order commit and an 8-entry
Scoreboard for issue-time hazard tracking. The front-end (P → F → D)
is structurally similar to `riscvlong`'s — branches resolve in **X**
via the `branch_cond_*_Xhl` signals comparing `branch_targ_Xhl`
against the current PC. JAL and JALR redirect in **D** with a 1-cycle
penalty.

For a wrong-direction conditional branch, the existing logic raises
`brj_taken_Xhl` and selects `pm_b` on the PC mux, which squashes F + D
and refetches at `branch_targ_Xhl`. **2 cycles of work are wasted per
mispredicted branch.** The baseline has no prediction, so every taken
conditional branch incurs this 2-cycle penalty even when the program
takes the same branch direction every iteration.

The OoO machinery downstream of D — issue, scoreboard, ROB — is
untouched by the predictor. All wrong-path instructions are squashed
in the F+D shadow before they enter issue, so the ROB only ever sees
correct-path instructions. No new ROB-rollback machinery is needed.

The kernel-only static cost shows up most plainly in `ubmark-vvadd`,
a tight `for(i=0; i<size; i++)` loop. Built with `-O3 -funroll-loops`
(matching lab4's `ubmark.mk`), the baseline retires 453 instructions
in 511 cycles inside the `test_stats_on/off` kernel region (IPC 0.886);
of the 10 dynamic conditional branches, 9 are taken — `9 × 2 = 18
cycles` lost to refetch, the predictor's entire opportunity on this
workload. With BHT-2 the predictor cuts that to 4 cycles (2 mispredicts
× 2 cycles), saving 14 cycles → IPC 0.911.

---

## 3. Predictor RTL

All seven predictor source files live in `bp/`. Each one uses a
`` `define BP_*_V `` include guard at the top so re-inclusion is safe.

### 3.1 Pre-decoder (`bp_predecode.v`)

Pure-combinational decoder over the F-stage instruction word:

- `is_branch`, `is_jal`, `is_jalr` from opcode classification
- `is_call = (is_jal || is_jalr) && rd == x1`
- `is_return = is_jalr && rs1 == x1 && rd != x1`
- `br_target  = pc + sign_extend(imm_sb)` for B-type
- `jal_target = pc + sign_extend(imm_uj)` for JAL

Both targets are decodable from F-stage bits alone — no register read
needed, so they fit on the critical fetch path.

### 3.2 1-bit BHT (`bp_bht1.v`)

A 256-entry register array of 1 bit each. Read is combinational,
indexed by `predict_pc[9:2]`. Write happens at end of X on every
resolved conditional branch, indexed by `update_pc[9:2]`. No tagging.

### 3.3 2-bit BHT (`bp_bht2.v`)

256 × 2-bit saturating counters: `00`=strongly NT, `01`=weakly NT,
`10`=weakly T, `11`=strongly T. Predict taken iff bit 1 set. On reset
all entries initialize to `01` (weakly NT).

### 3.4 GShare (`bp_gshare.v`)

256-entry PHT of 2-bit counters indexed by `PC[9:2] XOR GHR[7:0]`. The
GHR is shifted left with the resolved direction on every branch
update at X. Non-speculative GHR (only updated at resolve) — see §6
for why this matters on these benchmarks.

### 3.5 Return Address Stack (`bp_ras.v`)

8-entry × 32-bit LIFO. The pre-decoder classifies the F-stage
instruction as a *call* (JAL or JALR with `rd == x1`) or *return*
(JALR with `rs1 == x1` and `rd != x1`). On a call, F pushes `pc+4`
onto the stack; on a return, F pops the top and uses it as the
predicted target.

### 3.6 Selectable wrapper (`bp_top.v`)

Instantiates exactly one of the four direction predictors based on
the `BP_*` define set at build time:

```verilog
`ifdef BP_STATIC_NT  bp_static_nt  ...
`elsif BP_BHT1       bp_bht1       ...
`elsif BP_GSHARE     bp_gshare     ...
`else                bp_bht2       ... // default
`endif
```

---

## 4. Integration into `riscvooo`

All hooks gated by `` `ifdef BP_ENABLED ``.

### 4.1 F-stage prediction (`riscvooo-CoreCtrl.v`)

`bp_predecode` runs combinationally on `imemresp_queue_mux_out_Fhl`
(the 32-bit instruction word that D will receive next cycle), tagged
with `pc_Fhl` (a new input wired from dpath). The predictor is queried
with the same PC. The F stage fires a redirect through a new
PC-mux input when:

```
pred_redirect_Fhl = pred_branch_active_F  // B-type predicted taken
                 || pred_jal_active_F      // any JAL (BP_PRED_JAL)
                 || ras_predict_F          // JALR-return via RAS (BP_RAS)
```

with target priority RAS > JAL > B-type:

```
pred_target_Fhl = ras_predict_F     ? ras_top_F
                : pred_jal_active_F ? jal_target_F
                :                     br_target_F
```

The PC-mux ordering becomes (highest priority first):

```
pc_mux_sel_Phl =
   brj_taken_Xhl     → pm_b      (mispredict redirect at X — highest priority)
 : brj_taken_Dhl     → pm_j/pm_r (jump redirect at D, JAL/JALR fallback)
 : pred_redirect_Fhl → pm_pred   (F-stage prediction)
 :                     pm_p      (PC + 4)
```

`pm_pred = 3'd4` is a new mux input feeding `pred_target_Fhl` into the
PC register on the next clock edge. The `pc_mux_sel_Phl` signal width
grows from 2 to 3 bits (gated by `` `ifdef BP_ENABLED `` on both the
ctrl-side declaration and the dpath-side mux).

### 4.2 Pipelining the prediction (`riscvooo-CoreCtrl.v`)

A small register chain pipelines `predict_taken_F` and the
`is_jal_F` / `ras_predict_F` flags from F → D → X:

```verilog
reg pred_taken_Dhl_r, pred_taken_Xhl_r;
reg pred_jal_Dhl_r, pred_return_Dhl_r;
always @(posedge clk) begin
  if (reset) {pred_taken_Dhl_r, pred_taken_Xhl_r, pred_jal_Dhl_r, pred_return_Dhl_r} <= 0;
  else begin
    if (!stall_Dhl) begin
      pred_taken_Dhl_r  <= (inst_val_Fhl && is_branch_F) ? predict_taken_F : 1'b0;
      pred_jal_Dhl_r    <= pred_jal_active_F;
      pred_return_Dhl_r <= ras_predict_F;
    end
    if (!stall_Xhl) pred_taken_Xhl_r <= pred_taken_Dhl_r;
  end
end
```

The bit is valid only when the X-stage instruction is itself a B-type
(`br_sel_Xhl != br_none`); the X-stage compare gates on
`bp_resolve_Xhl` so stray "predictions" on non-branches never pollute
the predictor.

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
Correct predictions cost zero cycles, and that is where the IPC
improvement comes from.

The `pm_b` PC-mux input (in dpath) now selects between `branch_targ_Xhl`
and `pc_Xhl + 4` depending on `redirect_to_target_Xhl`:

- Mispredict (predicted T, actual NT): F was redirected to wrong target;
  squash F+D, redirect back to fall-through `pc_Xhl + 4`.
- Mispredict (predicted NT, actual T): F was fetching fall-through;
  squash F+D, redirect to `branch_targ_Xhl`.

### 4.4 Suppressing redundant D-stage redirects

Without prediction, JAL and JALR raise `brj_taken_Dhl` to redirect F
in D (the existing 1-cycle penalty). With JAL prediction at F, this
redirect is redundant — F already started fetching from the right
target. Same for a correct RAS prediction on JALR. The integration
suppresses `brj_taken_Dhl` in those two cases:

```verilog
wire brj_taken_Dhl = raw_brj_taken_Dhl
                   && !suppress_jal_Dhl
                   && !suppress_jalr_ret_Dhl;
```

`suppress_jal_Dhl` checks `is_jal_Dhl_w && pred_jal_Dhl` (under
`BP_PRED_JAL`); `suppress_jalr_ret_Dhl` checks `is_jalr_Dhl_w &&
pred_return_Dhl && pred_target_match_Dhl`, where
`pred_target_match_Dhl` is a 32-bit equality between the
F-stage-pipelined `pred_target` and the actual `jumpreg_targ_Dhl`
computed in dpath at D.

### 4.5 Predictor training

Training is unconditional on every resolved conditional branch:

```verilog
bp_top u_bp (
  .predict_pc       (pc_Fhl),
  .predict_taken    (predict_taken_F),
  .update_en        (bp_resolve_Xhl),
  .update_pc        (pc_Xhl),
  .update_taken     (actual_taken_Xhl),
  .update_mispredict(mispredict_Xhl)
);
```

The 2-bit BHT and GShare both update their counters toward the actual
outcome (saturating at the endpoints). The 1-bit BHT just overwrites
with the actual outcome.

### 4.6 Diagnostic counters (`riscvooo-CoreCtrl.v`, `riscvooo-sim.v`)

The lab4 stats block in CoreCtrl is extended with five new counters
under `` `ifdef BP_ENABLED ``:

```
num_branches      conditional branches resolved in X
num_taken         of those, how many actually taken
num_pred_resolve  predictor weighed in (== num_branches when enabled)
num_pred_correct  prediction matched actual
num_mispredicts   prediction != actual
```

They share the `(stats_en || csr_stats)` gating with `num_cycles` and
`num_inst`, so they reflect the same kernel/whole-program region the
rest of the lab4 stats do. `riscvooo-sim.v` prints them after the
existing four headline lines, also under `` `ifdef BP_ENABLED ``.

---

## 5. Functional verification

All 47 RISC-V assembly tests from the lab4 `tests = …` list pass on
every configuration:

| Variant         | passed | failed | error |
|-----------------|-------:|-------:|------:|
| baseline        |     47 |      0 |     0 |
| bp_static_nt    |     47 |      0 |     0 |
| bp_bht1         |     47 |      0 |     0 |
| bp_bht2         |     47 |      0 |     0 |
| bp_gshare       |     47 |      0 |     0 |
| bp_bht2_jal     |     47 |      0 |     0 |
| bp_gshare_jal   |     47 |      0 |     0 |
| bp_bht2_full    |     47 |      0 |     0 |
| bp_gshare_full  |     47 |      0 |     0 |

This includes every branch test (`riscv-beq`, `riscv-bne`, `riscv-blt`,
`riscv-bge`, `riscv-bltu`, `riscv-bgeu`), every jump test (`riscv-j`,
`riscv-jal`, `riscv-jalr`, `riscv-jr`), the integer/load-store/mul-div
suites, and the four OoO-specific tests (`riscv-ooo-commit`,
`riscv-rob-bypass`, `riscv-waw`, `riscv-long-better-ipc`). The full
per-test log lives at `results/<variant>.asm.log` and per-test
status under `results/<variant>/asm_tests.tsv`.

---

## 6. Performance results: ubmark microbenchmarks

### 6.0 Methodology — alignment with lab4

The repository directory layout matches `l4/lab4` verbatim, with the
predictor added as a new `bp/` subpackage and the integration hooks
applied to `riscvooo/{Core,CoreCtrl,CoreDpath,sim}.v`. The build flow
is also lab4 verbatim plus one knob (`BP_DEFINES`):

```
make BP_DEFINES="-DBP_ENABLED -DBP_BHT2 -DBP_PRED_JAL -DBP_RAS" riscvooo-sim
```

The asm tests (`make check-asm-riscvooo`) and ubmarks
(`make run-bmark-riscvooo`) build and run the way lab4 wired them:
`+verbose=1 +vcd=1 +exe=$<` on the simulator binary, output to
`<bench>-ooo.out`.

The ubmark sources, vmh files, and counter policy match lab4
byte-for-byte:

- **Sources**: `ubmark/ubmark/ubmark-*.{c,dat,h}` are exactly lab4's.
- **Compile flow**: `(cd ubmark && mkdir build && cd build &&
  ../configure --host=riscv32-unknown-elf && make && ../convert)` —
  unchanged from lab4. `riscv32-unknown-elf-gcc` resolves to a
  wrapper for `riscv64-unknown-elf-gcc 15.2.0 -march=rv32im_zicsr
  -mabi=ilp32`. The `convert` script inserts the same hand-encoded
  reset vector at `0x80000` lab4 uses.
- **vmh files**: `ubmark/build/vmh/*.vmh` are byte-identical to
  `l4/lab4/ubmark/build/vmh/*.vmh`.
- **Counters**: `proc.ctrl.num_cycles` / `proc.ctrl.num_inst` (lab4's
  registers, unmodified) gated by `(stats_en || csr_stats)`. Asm-test
  rule passes `+stats=1` → `stats_en=1` → whole-program count. Ubmark
  rule passes `+verbose=1` (no `+stats`) → `stats_en=0`; `csr_stats`
  gates via `test_stats_on(temp)` / `test_stats_off(temp)` (kernel-only
  measurement).

Sanity check — our `results/baseline/*-ooo.out` lines diff cleanly
against `l4/lab4/build/*-ooo.out` for all four ubmarks:

| Benchmark           | num_cycles | num_inst | ipc      |
|---------------------|-----------:|---------:|---------:|
| ubmark-vvadd        |        511 |      453 | 0.886497 |
| ubmark-cmplx-mult   |       2425 |     1723 | 0.710515 |
| ubmark-bin-search   |       1443 |     1017 | 0.704782 |
| ubmark-masked-filter|       7446 |     4931 | 0.662235 |

The build flow + RTL behave bit-for-bit like lab4's reference for the
unmodified core.

### 6.1 IPC by variant (kernel-only, lab4 convention)

| Benchmark           | baseline | static_nt | bht1   | bht2   | gshare |
|---------------------|---------:|----------:|-------:|-------:|-------:|
| ubmark-vvadd        | 0.8865   | 0.8865    | 0.9115 | 0.9115 | 0.8830 |
| ubmark-cmplx-mult   | 0.7105   | 0.7105    | 0.7236 | 0.7236 | 0.7194 |
| ubmark-bin-search   | 0.7048   | 0.7048    | 0.7865 | 0.7952 | 0.7664 |
| ubmark-masked-filter| 0.6622   | 0.6622    | 0.7064 | 0.7153 | 0.7115 |
| **mean**            | **0.741**| **0.741** | **0.782**| **0.786**| **0.770** |

The IPC ceiling is 1.0 (single-issue, single retire per cycle).
Because the cycle counter only runs inside the `test_stats_on/off`
region, the baseline's 0.741 mean reflects the loop kernel only — not
the test setup or verification. The remaining ~26% gap is data hazards
(load-use stalls, multi-cycle muldiv, ROB head waiting on completion)
and branch mispredicts.

`static_nt` is identical to `baseline` because the lab core's existing
behavior is itself "always not-taken" — fetch PC+4 and only correct on
X resolution. Adding our predictor in `static_nt` mode therefore
doesn't change observable IPC. This validates that our integration
adds zero overhead when the predictor signal is constant.

The biggest IPC lifts come from the higher-branch-count workloads:
`bin-search` (0.705 → 0.795 with BHT-2, +12.8%) and `masked-filter`
(0.662 → 0.715, +8.0%). `vvadd` and `cmplx-mult` see smaller relative
lifts because `-O3 -funroll-loops` collapses their inner loops into
nearly straight-line code (only 10 and 27 dynamic conditional branches
in the kernel respectively). The predictor still gets the loop branches
right; there are simply fewer to win on.

GShare is competitive on the bigger benchmarks but consistently worse
than BHT-2 on these workloads. The reason is GHR pollution: for a
single-direction loop branch, the GHR cycles through patterns of
mostly-`1`s, mapping the same PC to different counters depending on
how many other taken branches have just resolved. With more diverse
control flow, GShare's correlation pays off — but on these benchmarks
it never beats BHT-2.

`ubmark-bin-search` is the hardest benchmark for any direction
predictor. Binary search compares against data, so each branch's
direction is essentially uncorrelated random data. BHT-2 hits 79%
accuracy (52 mispredicts in 246 branches), about as well as any
direction predictor can do on this workload without value prediction.

### 6.2 Mispredict rates (kernel only)

| Benchmark           | branches | bht1 misp | bht2 misp | gshare misp |
|---------------------|---------:|----------:|----------:|------------:|
| ubmark-vvadd        |       10 |   2 (20.0%) |   2 (20.0%) |  10 (100.0%) |
| ubmark-cmplx-mult   |       27 |   3 (11.1%) |   3 (11.1%) |  10 ( 37.0%) |
| ubmark-bin-search   |      246 |  59 (24.0%) |  52 (21.1%) |  76 ( 30.9%) |
| ubmark-masked-filter|      668 |  96 (14.4%) |  53  (7.9%) |  71 ( 10.6%) |

A few observations worth calling out:

- **GShare on `vvadd` is 100% wrong** on the kernel's 10 conditional
  branches. The GHR happens to land in a state that maps them all to
  counters the warmup hasn't biased toward "taken" yet. Outside the
  kernel (during init/verification, where the cycle counter is off)
  GShare presumably warms up more, but the lab4 metric only sees the
  kernel.
- **BHT-2 vs BHT-1 split on `masked-filter`**: 53 vs 96 mispredicts.
  This is the one workload where the 2-bit hysteresis pays off — the
  filter's inner branches alternate often enough that 1-bit flips on
  every other iteration but 2-bit holds.

### 6.3 Cycle-level accounting on `ubmark-vvadd`

Worth a closer look because the workload is small enough to reason
about exactly:

- 10 conditional branches in the kernel, 9 actually taken (the
  `-O3 -funroll-loops` build collapses 100 iterations into ~12
  unrolled chunks; only the chunk-back and final fallthrough remain)
- baseline: `9 taken × 2 squash cycles = 18 wasted cycles`
- baseline kernel: 511 cycles for 453 retired insts → IPC 0.8865
- BHT-2: 2 mispredicts × 2 cycles = 4 wasted cycles
- BHT-2 kernel: 497 cycles, IPC 0.9115
- delta: `511 − 497 = 14 cycles saved`, ≈ 78% of the 18-cycle ceiling

The remaining gap from theoretical maximum is from the predictor being
cold at the first loop entry plus a couple of mispredicts in the
chunk-out tail where the unroll factor doesn't divide the iteration
count evenly.

---

## 7. Stretch goals (proposal §RAS, JAL prediction)

### 7.1 JAL prediction at F (`BP_PRED_JAL`)

The pre-decoder already detects JAL and computes `jal_target = pc +
imm_uj`. Under `BP_PRED_JAL`, the F stage redirects on JAL too — same
mechanism as predicted-taken B-types. To avoid the wasted re-redirect
that would otherwise happen at D, the D-stage `brj_taken_Dhl` is
suppressed when the F-stage JAL prediction was the JAL we just decoded.

This saves **1 cycle per JAL** in the program. On `ubmark-bin-search`,
it lifts IPC from 0.795 (`bp_bht2`) to 0.821 (`bp_bht2_jal`) — a +3.3%
gain on the benchmark with the most function calls. On
`ubmark-masked-filter`, 0.715 → 0.739 (+3.4%). On the tighter
benchmarks (vvadd, cmplx-mult) the kernel JAL count is ~0 and the IPC
delta is below 0.1%.

### 7.2 Return Address Stack (`BP_RAS`)

`bp_ras.v` is an 8-entry × 32-bit LIFO. The pre-decoder classifies the
F-stage instruction as a *call* (JAL or JALR with `rd == x1`) or a
*return* (JALR with `rs1 == x1` and `rd != x1`). On a call, F pushes
`pc+4` onto the stack; on a return, F pops the top and uses it as the
predicted target for the JALR.

Detection of "RAS got it right" happens in dpath: a 32-bit register
pipelines `pred_target_Fhl` to D, where it is compared against the
actual `jumpreg_targ_Dhl`. The 1-bit comparison result
(`pred_target_match_Dhl`) feeds back to ctrl, which gates
`brj_taken_Dhl` for JALR-returns.

RAS is correctness-safe by construction: when a return mispredicts
(stack stale, target mismatch), `pred_target_match_Dhl == 0`, the
D-stage redirect is allowed to fire, and the wrong-path instructions
in F+D are squashed. A wrong RAS prediction therefore costs the same
1-cycle penalty as no RAS — but a correct prediction saves that cycle.

Effect on these benchmarks is small: the kernel regions of these
ubmarks have 0–2 JALR returns each (most return-from-main happens
*outside* `test_stats_off`). `bp_bht2_full` and `bp_bht2_jal` produce
the same numbers across all four benchmarks here. On a workload with
deeper recursion or more function calls inside the measured region,
the RAS would matter more — this design exploration shows the
*mechanism* even if the test mix doesn't exercise it heavily.

### 7.3 Final IPC across all variants (4 ubmarks, kernel-only)

| Variant         | vvadd  | cmplx-mult | bin-search | masked-filter | mean   |
|-----------------|-------:|-----------:|-----------:|--------------:|-------:|
| baseline        | 0.8865 |   0.7105   |   0.7048   |    0.6622     | 0.7410 |
| static-NT       | 0.8865 |   0.7105   |   0.7048   |    0.6622     | 0.7410 |
| BHT-1           | 0.9115 |   0.7236   |   0.7865   |    0.7064     | 0.7820 |
| BHT-2           | 0.9115 |   0.7236   |   0.7952   |    0.7153     | 0.7864 |
| GShare          | 0.8830 |   0.7194   |   0.7664   |    0.7115     | 0.7701 |
| BHT-2 + JAL     | 0.9115 |   0.7239   |   0.8215   |    0.7394     | 0.7991 |
| GShare + JAL    | 0.8830 |   0.7197   |   0.7908   |    0.7354     | 0.7822 |
| BHT-2 full      | 0.9115 |   0.7239   |   0.8215   |    0.7394     | 0.7991 |
| GShare full     | 0.8830 |   0.7197   |   0.7908   |    0.7354     | 0.7822 |

"full" = BHT/GShare + JAL prediction + RAS.

The Pareto picture (limited to IPC since the area axis is deferred):

- `baseline = static_nt` validates zero-overhead integration when the
  predictor signal is constant.
- `BHT-1 ≈ BHT-2` everywhere except `masked-filter`, where BHT-2's
  hysteresis cuts the mispredict count almost in half (96 → 53). For
  this workload set BHT-2 is the right base predictor.
- `GShare` is consistently worse than BHT-2 on every benchmark — the
  GHR doesn't help when each loop's branches are uncorrelated with
  recent control flow. On a benchmark with strongly correlated
  branches (e.g. many short conditional bodies inside a tight loop),
  GShare would be expected to overtake; we don't have those.
- `JAL prediction` adds **+1.6% mean IPC** on top of BHT-2, all from
  the two ubmarks (`bin-search` and `masked-filter`) that have JALs
  inside the measured kernel.
- `RAS` is correct and works (we verified by tracing
  `pred_target_match_Dhl`), but the kernels have too few JALR returns
  for it to move IPC measurably.

**BHT-2 + JAL prediction is the winning configuration**, lifting
mean IPC from 0.741 (baseline) to 0.799 (+7.8%).

---

## 8. Open work

- **FPGA implementation deferred.** The proposed Vivado synth and
  on-board IPS measurement on the Nexys-4 DDR are unfinished due to
  lab bench host unreachability (banner-exchange failure on bench
  sshd, no power-cycle access during the project window). Once a
  Vivado bench is available, the same `BP_DEFINES` selection
  mechanism transfers — point Vivado at the same `riscvooo/`,
  `bp/`, `vc/`, `imuldiv/` source tree with the appropriate define
  set, and the integration is identical to what runs in simulation.

- **Wider GShare configurations.** Longer GHR (e.g. 12 or 16 bits)
  combined with a larger PHT could overtake BHT-2 on workloads with
  strong inter-branch correlation. Not promised in the proposal, but
  the parameter knob is there (`-DBP_HIST_BITS=N`,
  `-DBP_INDEX_BITS=N`).

- **A speculative-update GShare.** The current GShare only updates
  the GHR at resolve time (X). Speculatively updating at predict time
  (F) and snapshotting on every branch for rollback on mispredict
  would close a small remaining gap, at the cost of substantially
  more state. For the IPC range these benchmarks exercise the
  non-speculative GHR is sufficient.

---

## 9. Build & run reproducibility

The full pipeline runs on Princeton's `adroit-vis.princeton.edu`
cluster using the same `/home/ECE475/local/encap` toolchain pins lab4
itself uses. Setup, once per shell:

```bash
cd /scratch/network/sk3686/ece475/project/branch_predictor_ooo
source scripts/adroit-env.sh
```

Build the asm-test and ubmark vmh files via lab4's autoconf flow:

```bash
(cd tests  && mkdir -p build && cd build && \
   ../configure --host=riscv32-unknown-elf && make && ../convert)
(cd ubmark && mkdir -p build && cd build && \
   ../configure --host=riscv32-unknown-elf && make && ../convert)
```

After this, `tests/build/vmh/*.vmh` and `ubmark/build/vmh/*.vmh` are
byte-identical to `l4/lab4/{tests,ubmark}/build/vmh/*.vmh`.

Sweep all 9 BP variants (clean rebuild + asm + ubmark per variant,
~90 seconds total):

```bash
./scripts/run_variants.sh
./scripts/plot_results.py
```

Comparing a single output against lab4:

```bash
diff results/baseline/ubmark-vvadd-ooo.out \
     /scratch/network/sk3686/ece475/l4/lab4/build/ubmark-vvadd-ooo.out
```

The only diff is the `riscvooo-sim.v:LINE: $finish` annotation
(lab4 says `:335`, we say `:342` because `riscvooo-sim.v` got 7 lines
longer for the BP_ENABLED diagnostic prints). All four headline
status / num_cycles / num_inst / ipc lines are identical.
