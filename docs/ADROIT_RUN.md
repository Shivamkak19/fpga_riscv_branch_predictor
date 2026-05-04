# Adroit run plan — branch-predictor project, FPGA component removed

This file is the work order for the **`adroit-no-fpga`** branch.
It is written so the next Claude instance running on Princeton's
`adroit-vis.princeton.edu` cluster can execute it end-to-end with
no further questions.

The local laptop session got the project to a fully-working
sim + yosys-relative-synth state but could not reach the FPGA bench
host (network blocker — see `PROGRESS.md` "Session 2 status"). On
adroit there is no FPGA hardware at all, so this branch removes the
FPGA leg of the project entirely and recasts the writeup as a
sim-only design exploration with relative area via yosys synth.

---

## 0. Context: what already works

Everything below has been verified locally and committed to `main`
(merged forward to `adroit-no-fpga` since the branch was cut from
`main` at `6626bd0`):

- 9 predictor variants × 43 RISC-V asm tests → **387/387 pass**
- 9 variants × 4 ubmarks → **36/36 pass**, IPC table is in
  `README.md` and `docs/REPORT.md` §6
- Yosys `synth_xilinx -family xc7` per variant → cell counts in
  `results/yosys_summary.tsv`
- All plots (`results/plots/*.png`) regenerate from those TSVs

Read `PROGRESS.md` for the detailed handoff if you want full
context. Read `docs/REPORT.md` to see the current writeup.

---

## 1. Get on the right branch + check toolchain

```bash
# Clone + branch (or pull if already cloned)
cd ~/ece475
git clone https://github.com/Shivamkak19/fpga_riscv_branch_predictor.git
cd fpga_riscv_branch_predictor
git checkout adroit-no-fpga

# Check what's available
module avail 2>&1 | grep -iE 'verilator|riscv|yosys|gcc|python'
```

You need:
- **`riscv64-unknown-elf-gcc`** (32-bit target: `-march=rv32im_zicsr -mabi=ilp32`)
- **Verilator** ≥ 4.x (5.x preferred)
- **yosys** (any recent version with `synth_xilinx`)
- **Python 3** with `matplotlib`

Princeton's adroit usually has `riscv-gnu-toolchain`, `verilator`,
and `yosys` as modules. Likely names (confirm with `module avail`):

```bash
module load gcc/12 || module load gcc
module load riscv-gnu-toolchain || module load riscv64-elf-gcc || module load riscv
module load verilator
module load yosys                         # if not, build is fine: yosys is just for §3
module load python/3.11 || module load anaconda3
```

If `riscv64-unknown-elf-gcc` is the binary (rather than our local
`riscv64-elf-gcc`), patch the build scripts — see §2 below. You can
also check `~/ece475/lab4/Makefile` for the binary name the course
labs use; if that runs cleanly on adroit, copy its `RISCV_GCC=`
setting into our scripts.

> **Reference**: `~/ece475/lab4` on adroit is the course Lab 4 tree
> (single-issue OoO with ROB). Useful if you need to crib the exact
> module-load incantations or RISC-V toolchain prefix that the
> course staff support — but our project is built on the **`riscvlong`
> single-issue 7-stage in-order** pipeline, NOT lab4's `riscvooo`. Do
> not copy lab4 RTL into our `rtl/` tree.

---

## 2. Patches that may be needed for the adroit toolchain

### 2a. RISC-V gcc binary name

`scripts/build_test.sh` and `scripts/build_ubmark.sh` invoke
`riscv64-elf-gcc`. If adroit uses `riscv64-unknown-elf-gcc`:

```bash
sed -i 's/riscv64-elf-gcc/riscv64-unknown-elf-gcc/g' \
  scripts/build_test.sh scripts/build_ubmark.sh
```

(Also update `scripts/build_test.sh` if `riscv64-elf-objcopy` /
`-objdump` are referenced — check first with `grep riscv64-elf
scripts/*.sh`.)

### 2b. Verilator version

Local was 5.048. Adroit may have older 4.x. If `--language 1364-2005`
or `--x-initial 0` is unrecognized, drop them (older Verilator was
less strict). The lab's Verilog uses `type` as an identifier in
`vc-MemReqMsg.v` — if Verilator complains about this, add
`/* verilator lint_off DECLFILENAME */` style overrides or fall back
to iverilog:

```bash
# fallback if verilator is too old
which iverilog && cat scripts/build_sim.sh | grep -A2 verilator
```

The Verilator version is checked at the top of `scripts/build_sim.sh`.

### 2c. Python matplotlib

```bash
python3 -c 'import matplotlib' 2>&1
# if missing:
pip install --user matplotlib
```

---

## 3. Run the full sweep

```bash
# Sanity: build one variant, run all 43 asm tests
./scripts/build_sim.sh bp_bht2_full
./scripts/run_tests.sh bp_bht2_full       # expect: pass=43 fail=0 error=0

# Full sweep: all 9 variants × (43 asm tests + 4 ubmarks) — ~10 min
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare \
         bp_bht2_jal bp_gshare_jal bp_bht2_full bp_gshare_full; do
  ./scripts/build_sim.sh $v
  ./scripts/run_tests.sh $v
  ./scripts/run_ubmarks.sh $v
done

# Yosys synth (relative cell counts, no FPGA needed) — ~5 min
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare \
         bp_bht2_jal bp_gshare_jal bp_bht2_full bp_gshare_full; do
  ./scripts/yosys_synth.sh $v
done
./scripts/yosys_summary.sh                # → results/yosys_summary.tsv

# Plots
./scripts/plot_results.py                 # default (yosys) mode
./scripts/plot_sweep.py                   # BHT-2 size + GShare heatmap (param sweep,
                                          #   committed TSVs may suffice — re-run only
                                          #   if results/sweep/ TSVs are stale)
```

Confirm against the previously committed results — the asm/ubmark
pass counts and IPC table should be identical to what's in
`README.md`. Yosys cell counts may differ slightly across yosys
versions but the relative ordering should match.

### Optional: Slurm submission for parallel sweep

If the login node is loaded or the user prefers, wrap the variant
sweep in `sbatch`. Each variant build+test is independent and takes
~1-2 min — embarrassingly parallel. Suggested template:

```bash
cat > slurm_sweep.sh <<'EOF'
#!/bin/bash
#SBATCH --array=0-8
#SBATCH --time=00:15:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=2
#SBATCH --output=slurm_%A_%a.log
VARIANTS=(baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare \
          bp_bht2_jal bp_gshare_jal bp_bht2_full bp_gshare_full)
v=${VARIANTS[$SLURM_ARRAY_TASK_ID]}
./scripts/build_sim.sh $v
./scripts/run_tests.sh $v
./scripts/run_ubmarks.sh $v
./scripts/yosys_synth.sh $v
EOF
sbatch slurm_sweep.sh
# wait for all 9 to finish, then:
./scripts/yosys_summary.sh
./scripts/plot_results.py
```

Only worth it if the login node isn't free.

---

## 4. REPORT.md changes — strip the FPGA leg

The current `docs/REPORT.md` has Vivado + on-board IPS subsections
(§7.3 + §7.4) that reference data we will never collect on adroit.
Trim as follows.

### 4a. §1 Summary — add scope-shrink note

Append a paragraph to §1 (after the existing "Scope adjustment from
proposal" subsection) that says:

> **Further scope adjustment (post-proposal):** the project's
> proposed FPGA leg (Vivado synthesis on the lab bench host +
> on-board IPS measurement on the Nexys-4 DDR) was cut after the
> bench host became unreachable across the project window. The
> writeup below recasts the area axis as **relative cell counts from
> yosys `synth_xilinx -family xc7`** (Artix-7 cell library, no
> place-and-route, no Fmax). Performance is reported as IPC only;
> the proposal's "instructions per second" tradeoff narrative is
> reframed as "IPC at known relative area." All RTL, all simulation
> infrastructure, and the per-variant yosys flow run unchanged.

### 4b. §7 — retitle and trim

Current title: `## 7. FPGA synthesis results`
Change to:    `## 7. Synthesis results — yosys (relative area)`

Inside §7:
- **Keep** §7.1 (Yosys synth_xilinx — relative cell counts) and
  §7.2 (Performance per area) as-is.
- **Delete** §7.3 (Vivado synth on-bench) entirely — that whole
  subsection including §7.3.1 and §7.3.2.
- **Delete** §7.4 (On-board IPS measurement) entirely.

### 4c. §8 — close the Fmax speculation

Current §8 final paragraph speculates about Fmax shifting the
performance/area picture. Replace it with:

> Without Vivado place-and-route data we can't translate IPC to
> wall-clock IPS — that conversion was the proposal's headline
> deliverable but is unrecoverable from the simulation flow alone.
> The honest claim this writeup can defend is **IPC vs relative
> cell area**, where BHT-2 (with both stretch goals) is the Pareto
> winner among the 9 design points evaluated.

### 4d. §11 Open work — replace FPGA items

Delete the existing §11 items "Vivado synth on the bench host" and
"On-board IPS measurement". Replace with one bullet:

> - **FPGA implementation deferred.** The proposed Vivado synth and
>   on-board IPS measurement on the Nexys-4 DDR are unfinished due
>   to lab bench host unreachability. The synthesis flow scripts
>   (`fpga/synth_scripts/synth_variant.tcl`,
>   `scripts/parse_vivado_reports.py`,
>   `scripts/plot_results.py --source vivado`) remain in the
>   repository and are runnable end-to-end as soon as a
>   suitably-configured Vivado bench is available. See `PROGRESS.md`
>   "Session 2 status" for the full network diagnosis.

### 4e. README.md — same edit, condensed

In `README.md`, in the "Headline results" or "FPGA flow" section,
add a one-line note: "FPGA flow scripts retained but not executed
in this branch; see `docs/ADROIT_RUN.md`."

---

## 5. What NOT to do

- **Do not delete `fpga/`, `scripts/parse_vivado_reports.py`, or the
  `--source vivado` mode of `plot_results.py`.** They're harmless
  on adroit (just unused), and keeping them lets the FPGA leg
  resume cleanly if someone gets bench access later.
- **Do not change anything under `rtl/`.** The predictor RTL is
  frozen and verified.
- **Do not copy lab4 (`riscvooo`) RTL into our tree.** Our project is
  built on `riscvlong` (single-issue 7-stage in-order). The lab4
  tree is reference only.
- **Do not regenerate the asm-test or ubmark numbers as "new"
  results.** They were captured locally and the sims are
  deterministic — adroit reproduction is a sanity check, not a
  primary data source. If adroit's numbers differ from the committed
  TSVs, investigate the cause (toolchain version skew, Verilator
  version difference) before overwriting.

---

## 6. Definition of done

- [ ] All 9 variants build on adroit with no warnings
- [ ] 387/387 asm tests pass + 36/36 ubmarks pass (matches local)
- [ ] `results/yosys_summary.tsv` regenerated on adroit; relative
      ordering of cell counts matches the committed TSV
- [ ] All plots in `results/plots/*.png` regenerated cleanly
- [ ] `docs/REPORT.md` edits in §4 above applied; no remaining
      `TBD` cells; no remaining references to Vivado data we don't
      have
- [ ] `README.md` headline numbers + FPGA-flow note updated
- [ ] Branch `adroit-no-fpga` committed + pushed
- [ ] PR or note left for sk3686 with a one-line summary of any
      adroit-toolchain-specific patches that were needed (so the
      eventual merge into `main` is auditable)

---

## 7. If something doesn't work

- **`riscv64-unknown-elf-gcc: not found`** — `module avail riscv` and
  use whatever name shows up. If nothing shows up, ECE 475 staff
  may have a project-local toolchain at `/scratch/ece475/...` or
  `~/ece475/toolchain/`; check `~/ece475/lab4/Makefile` for the
  exact path the course uses.
- **Verilator deadlock during `--timing`** — local symptom was that
  `always @(*)` blocks containing `$finish`/`#delay` deadlocked the
  scheduler. Our testbench (`sim/verilator/sim_top.v`) avoids this,
  but if adroit's Verilator is older it may behave differently.
  Drop `--timing` and use the iverilog fallback if needed.
- **Asm test fails on adroit but not locally** — likely a toolchain
  difference. Compare disassembly: `riscv64-unknown-elf-objdump -d
  benchmarks/build/<test>/<test>.elf` and check for unexpected
  instructions (e.g., compressed `c.*` if `-march` doesn't include
  `c`). Our scripts pass `-march=rv32im_zicsr -mabi=ilp32 -mno-relax`
  — keep these.
- **Yosys synth fails on a variant** — `synth_xilinx -family xc7`
  expects predictor RTL to elaborate cleanly. If yosys version is
  ≤ 0.30, parameter overrides may need explicit `chparam` instead of
  defparam. Per-variant yosys logs go to `results/<variant>/yosys_stat.txt`.

---

That's it. Once §3 sweeps pass and §4 REPORT edits are applied,
the project is "done" in the no-FPGA scope. Commit, push, open a
PR from `adroit-no-fpga` → `main` for sk3686 to review.
