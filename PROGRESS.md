# PROGRESS — handoff for the next session

**Last updated:** 2026-05-03 (campus session; bench host was
reachable at TCP layer via GP but sshd hung at banner exchange — see
"Session 2 status" below for the diagnosis)

**Working directory:** `/Users/shiva/Desktop/courses/f25/s26/ece475/project/fpga_riscv_branch_predictor`
**GitHub:** https://github.com/Shivamkak19/fpga_riscv_branch_predictor (private)
**Owner:** Shivam Kak (sk3686), partner Wonju Lee (wl2527)
**Course:** ECE 475 / Spring 2026, Princeton

---

## TL;DR

A branch-predictor design exploration for the lab's `riscvlong`
single-issue 7-stage in-order RISC-V pipeline. **Everything that can be
done locally is done.** All RTL is written and committed; full
simulation sweep passes (387/387 asm tests, 36/36 ubmark runs across 9
variants); local yosys synth done for relative cell-count comparison;
report drafted with all sim numbers and Pareto analysis.

**Blocked on:** bench-host sshd is accepting TCP but never sending
its SSH banner (verified from a working GP session on 2026-05-03 —
see "Session 2 status"). Once bench is power-cycled or its sshd
unsticks, the FPGA leg is one command sequence: `deploy → for-loop
synth → scp → parser → plotter`. The parser, plot extension, and
report stubs landed this session, so the only outstanding work is
the actual Vivado batch run + on-board IPS capture.

---

## Environment context the next session needs

### Hardware / network setup
- **FPGA bench host:** `bench@10.50.62.45` (Nexys-4 DDR / Artix-7
  `xc7a100tcsg324-1`), Vivado 2019.1 installed, password from
  `project/fpga_setup.pdf` (`FPGAtest1`). I already pushed an SSH key
  to bench (probably — see "SSH state" below); `~/.ssh/config` has a
  `Host bench` block with `IdentityFile ~/.ssh/id_ed25519_bench`.
- **VPN required:** the Mac being used must be on **Princeton VPN
  specifically** (GlobalProtect / Princeton OIT), not corporate
  Tailscale. The corporate Tailscale (`utun4` → `172.20.x.x`) was up
  during my session and was confused for Princeton VPN — TCP reached
  port 22 via LAN NAT but SSH banner exchange timed out because bench
  saw the connection from a non-Princeton source.
  - Quick check: `ifconfig | grep -B1 "10\."` should show a `utun*`
    interface with a `10.x` or `128.112.x` Princeton address, or
    `netstat -rn | grep "10.50"` should show a route for the lab subnet.

### SSH state
- `~/.ssh/id_ed25519_bench` (private key) and `id_ed25519_bench.pub`
  exist. `ssh-copy-id` was attempted but bench's sshd was hitting
  banner-timeout symptoms during my session, so it's unclear whether
  the key actually got installed in `bench:~/.ssh/authorized_keys`.
  - **First test once VPN is back:** `ssh -o BatchMode=yes bench
    'echo OK; hostname'`. If that fails with "Permission denied",
    re-run `SSHPASS=FPGAtest1 sshpass -e ssh-copy-id -i
    ~/.ssh/id_ed25519_bench.pub bench` (the password is in
    `project/fpga_setup.pdf`).
  - `sshpass` is installed via the homebrew tap
    `hudochenkov/sshpass/sshpass`.

### Local toolchain (already installed via brew)
- `verilator` 5.048
- `riscv64-elf-gcc` 16.1.0 (cross-compiles rv32im_zicsr / ilp32)
- `iverilog` 13.0 (not currently used; verilator is the active sim)
- `yosys` 0.64
- `coreutils` (provides `gtimeout`)
- `matplotlib` (pip)

### Toolchain quirks worth remembering
- Lab's `vc-MemReqMsg.v` and `vc-MemRespMsg.v` use `type` as an
  identifier — verilator must be invoked with `--language 1364-2005`
  to keep `type` un-reserved.
- Verilator with `--timing` deadlocks if `always @(*)` blocks contain
  `$finish` or `#delays`. Our testbench (`sim/verilator/sim_top.v`)
  only uses posedge-clk always blocks for termination.
- Use `--x-initial 0` so uninitialized regs start at 0 (matches FPGA
  flop power-on under reset). Without this, the lab's "two illegal
  instructions in a row → $finish" assertion fires on startup X-state.

### Secrets handling
- `project/secrets.txt` (one level up from this repo) contains a
  GitHub PAT. **Never echo it, never commit it.** Use it for `git
  push` via a temp `GIT_ASKPASS` script:
  ```bash
  PAT=$(awk '/^GITHUB PAT/{print $NF}' /Users/shiva/Desktop/courses/f25/s26/ece475/project/secrets.txt)
  ASKPASS=/tmp/git_askpass_$$.sh
  cat > $ASKPASS <<EOF
  #!/bin/sh
  echo "$PAT"
  EOF
  chmod +x $ASKPASS
  trap "rm -f $ASKPASS" EXIT
  GIT_ASKPASS=$ASKPASS GIT_TERMINAL_PROMPT=0 git push
  rm -f $ASKPASS
  ```
- `.gitignore` already excludes `secrets.txt` and `*.pem`.

---

## What's done

### 1. Scope reconciliation
The proposal said "dual-issue in-order superscalar from Lab 3" with
"3-cycle misprediction penalty." Reality:
- Lab 4 is actually about an **OoO single-issue with reorder
  buffer** (riscvooo).
- The FPGA's Vivado project references **`riscvlong`** — a
  single-issue 7-stage in-order pipeline (P→F→D→X→M→X2→X3→W).
- Branches resolve in X with a **2-cycle penalty** (squash F + D).

We pivoted to `riscvlong` (matches the FPGA + matches what's installed).
The report's §1 "Scope adjustment from proposal" has the explanation.

### 2. RTL — predictor modules
All under `rtl/bp/`:

- `bp_predecode.v` — pure combinational F-stage decoder. Extracts
  opcode, rs1, rd, imm_sb (B-type), imm_uj (J-type). Outputs
  `is_branch / is_jal / is_jalr / is_call / is_return` and
  `br_target / jal_target`.
- `bp_static_nt.v` — always predict not-taken (baseline-equivalent
  reference, just exercises the integration path).
- `bp_bht1.v` — 256 × 1-bit direction-only BHT, indexed by `PC[9:2]`.
- `bp_bht2.v` — 256 × 2-bit saturating-counter BHT, init `01`.
- `bp_gshare.v` — 256 × 2-bit PHT indexed by `PC[9:2] XOR GHR[7:0]`,
  GHR shifts in actual outcome on every resolved branch (not
  speculative — see §3.4 of REPORT for why).
- `bp_ras.v` — 8-deep × 32-bit Return Address Stack. Push on call
  (JAL/JALR with `rd==x1`); pop on return (JALR with `rs1==x1`,
  `rd!=x1`). Combinational top-of-stack output for F-stage redirect.
- `bp_top.v` — selectable wrapper. Picks BHT/GShare based on
  `BP_*` defines. Default if none specified is BHT-2.

### 3. RTL — predictor integration into core
Modified files under `rtl/core/` (copies of lab RTL, gated by `\`ifdef
BP_ENABLED`):

- `riscvlong-CoreCtrl.v` — pre-decoder + predictor instantiated in F;
  `pred_taken` pipelined F→D→X; X-stage compares prediction vs actual
  and computes `mispredict_Xhl`; `brj_taken_Xhl` redefined to fire
  ONLY on mispredict (was firing on every taken branch); X-redirect
  target gated by `redirect_to_target_Xhl` which selects between
  `branch_targ_Xhl` (actual taken) and `pc_Xhl + 4` (actual NT).
- `riscvlong-CoreDpath.v` — PC mux extended with new input `pm_pred =
  3'd4` driven by `pred_target_Fhl` from ctrl; pipelines
  `pred_target_Fhl → pred_target_Dhl_r` and exposes the comparison
  `pred_target_match_Dhl` back to ctrl (used by RAS to suppress
  redundant D-stage redirects).
- `riscvlong-Core.v` — wires all the new ctrl ↔ dpath signals.

The integration logic is in `rtl/core/riscvlong-CoreCtrl.v` lines
~165–250 (search for `BP_ENABLED`). PC mux priority:

```
brj_taken_Xhl     ? pm_b   : (mispredict redirect at X — highest priority)
brj_taken_Dhl     ? pc_mux_sel_Dhl  : (D-redirect for JAL/JALR — fallthrough)
pred_redirect_Fhl ? pm_pred:         (F-stage prediction)
                    pm_p             (PC + 4)
```

### 4. Stretch goals (proposal §RAS, JAL prediction)
Both implemented behind separate defines that layer on top of any
direction predictor:

- `BP_PRED_JAL` — predict JAL at F (always taken, target deterministic).
  Pipelines a `pred_was_jal_Dhl` bit and **suppresses the redundant
  D-stage redirect** when the JAL was already redirected at F. Saves
  1 cycle per JAL.
- `BP_RAS` — uses `bp_ras.v`. Pre-decoder identifies calls/returns;
  push happens at F on calls, pop happens at F on returns. Suppression
  of redundant D-redirect is gated by `pred_target_match_Dhl` from
  dpath (a 32-bit equality check between F's predicted target and
  D's actual `jumpreg_targ_Dhl`).

### 5. Build / run infrastructure
All under `scripts/`:

- `build_test.sh <source.S>` — cross-compiles a single asm test to
  `.vmh`. Uses `riscv64-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -mno-relax`.
- `build_ubmark.sh <source.c>` — cross-compiles a ubmark `.c` with
  the local `benchmarks/startup/startup.S` and
  `benchmarks/linker/ubmark.ld`. Startup sets `sp = 0x100000-16`,
  zeroes `gp`, calls `main`, signals PASS via `csrw 21, 1` if main
  returns.
- `build_sim.sh <variant>` — verilator binary build per variant.
  Variants: `baseline`, `bp_static_nt`, `bp_bht1`, `bp_bht2`,
  `bp_gshare`, `bp_bht2_jal`, `bp_gshare_jal`, `bp_bht2_full`,
  `bp_gshare_full`. Output: `sim/build/<variant>/Vsim_top`.
- `run_tests.sh <variant>` — sweeps all 43 RISC-V asm tests against
  the variant; writes `results/<variant>/asm_tests.tsv`.
- `run_ubmarks.sh <variant>` — runs all 4 ubmarks; writes
  `results/<variant>/ubmark.tsv`.
- `run_all_variants.sh` — convenience wrapper, builds + runs all 5
  base variants and aggregates.
- `sweep_predictor_size.sh` — sweep BHT-2 over INDEX_BITS={5..10}
  and GShare over (INDEX_BITS, HIST_BITS) ∈ {6,8,10} × {4,8,12}.
- `yosys_synth.sh <variant>` — yosys `synth_xilinx -family xc7` for
  the variant; outputs a (gitignored) per-variant log.
- `yosys_summary.sh` — aggregates per-variant yosys output to
  `results/yosys_summary.tsv`.
- `plot_results.py` — renders IPC, mispredict-rate, synth-area, and
  IPC-vs-area plots from the TSVs.
- `plot_sweep.py` — renders BHT-2 size sweep + GShare heatmap.
- `deploy_to_bench.sh` — rsyncs this repo to bench. **Needs VPN.**

`Makefile` provides high-level targets: `make sim`, `make asm`,
`make ubmark`, `make plots`, `make all`, `make fpga-deploy`,
`make clean`.

### 6. Verilator testbench
`sim/verilator/sim_top.v` — clean rewrite of the lab's `riscvlong-sim.v`.
Drives `riscv_Core` against `vc_TestDualPortRandDelayMem` (1 MB, 0
delay). Loads program from `+exe=<path>.vmh`, terminates on
`csr_status != 0`, prints stats summary. Tracks: cycles, retired
instructions, branches, taken branches, jumps, mispredicts (when
predictor enabled), pred_correct.

Key gotchas baked into this file:
- `reset_mem` and `reset_proc` are explicitly initialized to 1 (not
  X) to avoid spurious illegal-instruction asserts at startup.
- All termination logic lives in one `always @(posedge clk)` block —
  `always @(*)` blocks with `$finish`/`#delays` deadlock the timing
  scheduler.
- `exe_filename` is 4096 bits wide (was 1024) to fit deep absolute
  paths.

### 7. Results — RTL simulation
**387 / 387 asm tests pass (9 variants × 43 tests).**
**36 / 36 ubmarks pass (9 variants × 4 ubmarks).**

Mean IPC across the 4 ubmarks (vvadd, cmplx-mult, bin-search,
masked-filter):

| Variant         | Mean IPC |
|-----------------|---------:|
| baseline        | 0.711    |
| static-NT       | 0.711    |
| BHT-1           | 0.910    |
| BHT-2           | 0.912    |
| GShare          | 0.893    |
| BHT-2 + JAL     | 0.918    |
| GShare + JAL    | 0.898    |
| BHT-2 full      | **0.918** |
| GShare full     | 0.898    |

Notable findings:
- Predictors lift `vvadd` from 0.699 → 0.991 (+42%) — biggest single
  win, due to its 397/400 taken loop branches.
- GShare loses to BHT-2 on this workload mix because the loops are
  tight and uncorrelated; longer history just causes aliasing. Heatmap
  at `results/sweep/gshare_heatmap.png` shows shorter history (4 bits)
  consistently beats longer history.
- BHT-2 size doesn't matter past 32 entries — `results/sweep/bht2_size.png`
  is essentially flat from idx=5 to idx=10.
- JAL prediction adds +0.7% mean IPC, dominated by `bin-search` (43
  JAL function calls → 41 cycles saved → +2.9% on that benchmark).
- RAS on these benchmarks adds only 1 cycle on `masked-filter`. The
  ubmarks have 1–3 JALR returns each — RAS is correct and works,
  the workload just doesn't exercise it heavily.

### 8. Results — yosys synth (local, relative comparison)
`results/yosys_summary.tsv`:

| Variant         | cells  | LUTs   | FFs   |
|-----------------|-------:|-------:|------:|
| baseline        | 31,737 | 16,512 |   874 |
| bp_static_nt    | 32,686 | 16,847 |   940 |
| bp_bht1         | 33,472 | 17,370 | 1,196 |
| bp_bht2         | 33,849 | 17,450 | 1,452 |
| bp_gshare       | 35,024 | 18,026 | 1,460 |
| bp_bht2_jal     | 33,886 | 17,477 | 1,453 |
| bp_gshare_jal   | 35,071 | 18,056 | 1,461 |
| bp_bht2_full    | 34,240 | 17,608 | 1,714 |
| bp_gshare_full  | 35,389 | 18,171 | 1,722 |

Predictor adds 5–11% to total cells. JAL prediction is essentially
free in area (~30 cells). RAS adds ~260 FFs (the 8×32-bit stack)
plus the 32-bit pipelined comparator in dpath. Per-variant yosys
logs are gitignored — only this aggregated TSV is committed.

### 9. Plots
- `results/plots/ipc.png` — IPC bar chart, all 9 variants × 4 ubmarks.
- `results/plots/mispredict_rate.png` — per-predictor mispredict rate.
- `results/plots/synth_area.png` — three-panel cell/LUT/FF
  comparison.
- `results/plots/ipc_vs_area.png` — Pareto scatter (mean IPC vs total
  cells).
- `results/sweep/bht2_size.png` — BHT-2 size sweep, mispredict rate vs
  INDEX_BITS.
- `results/sweep/gshare_heatmap.png` — GShare (idx, hist) heatmap.

### 10. Report
`docs/REPORT.md` — full draft with:
- §1 Summary + scope adjustment
- §2 Baseline pipeline
- §3 Predictor RTL details
- §4 Integration design
- §5 Functional verification (all 43 asm tests)
- §6 ubmark IPC + mispredict rates
- §7 FPGA synth (yosys section filled, **Vivado section §7.3 marked
  TBD pending VPN**)
- §8 Two-dimensional tradeoff analysis
- §9 Build & run reproducibility
- §10 Stretch goals (JAL, RAS) + final 9-variant tables + Pareto
- §11 Open work

### 11. Git history
6 commits on `main`, all pushed:

```
ffd2b46 README: update headline numbers + describe stretch-goal variants
5138d78 RAS for JALR returns + complete 9-variant evaluation
41de45e Parameter sweep + JAL-prediction stretch goal
653c272 Add yosys local synth + IPC-vs-area chart, expand REPORT FPGA section
7a07672 Add result plots and plotting helper
0b4a048 Add detailed REPORT with simulation results and FPGA flow plan
f0875b6 Initial commit: branch predictor design exploration for riscvlong
```

---

## Session 2 status (2026-05-03)

### What got done this session
- **Verified local toolchain**: full clean rebuild + 43-test asm
  sweep on `bp_bht2_full` → 43/0/0. Toolchain is fine.
- **Wrote `scripts/parse_vivado_reports.py`** — reads
  `fpga_results/<variant>/{utilization.rpt,timing_summary.rpt,power.rpt}`,
  extracts Slice LUTs / Slice Regs / BRAM tile / DSP / target period /
  WNS / power, computes Fmax = 1000 / (period − WNS), writes
  `results/vivado_summary.tsv`. Validated end-to-end against a
  hand-built Vivado-format fixture: regex tolerates both
  `WNS(ns) ...` and `| WNS(ns) ...` forms (Vivado switches between
  boxed and unboxed table styles across sections); fixture parsed to
  4231 LUTs / 1452 regs / 12 BRAM / 4 DSP / Fmax 130.63 MHz / 0.234 W.
- **Extended `scripts/plot_results.py`** with `--source {yosys,vivado}`.
  Vivado mode reads the new TSV and re-renders `synth_area.png` (Slice
  LUTs / Slice Regs / BRAM tile panels), `ipc_vs_area.png` (against
  Slice LUTs), plus two new charts: `fmax.png` (per-variant achieved
  MHz bar chart) and `mips_vs_area.png` (the Fmax-corrected Pareto —
  mean_IPC × Fmax plotted against Slice LUTs, which is the only
  honest "performance per area" view). Yosys mode unchanged.
- **REPORT.md rewrites:** §7.3 was "to be filled" — replaced with a
  9-row utilization+timing+power table skeleton, named the parser/
  plot pipeline explicitly, fixed the duplicate §7.1/§7.2 numbering
  bug (those were renumbered to §7.3.1 / §7.3.2). Added new §7.4
  "On-board IPS measurement" with full methodology, the formula
  `IPS = retired_inst × Fmax_MHz × 1e6 / cycles`, and a 36-row TBD
  table (9 variants × 4 ubmarks).

### What we learned about the network situation
- **GlobalProtect IS the `utun4 / 172.20.x.x` interface** — Princeton's
  GP gateway hands out addresses in `172.20.x.x` private space.
  Earlier sessions (and the start of this one) misread that as
  Anthropic Tailscale. There is no Tailscale running on this Mac
  (no `tailscaled` process, no launchd entry — only PaloAlto's
  `pangps` and `pangpa` daemons).
- **Princeton OIT eduroam alone does NOT route to the `10.50.62.x`
  lab subnet.** Even on campus, you still need GP up. Confirmed by
  watching the route to `10.50.62.45` flip from "no route" to
  "via utun4" the moment GP connected.
- **Bench-side sshd is the current blocker.** With GP up, TCP to
  port 22 succeeds in <1 sec (`nc -zv` reports "succeeded"), and
  other ports actively `refused` (RST) — proving the host is up and
  the GP routing is correct. But sshd accepts the TCP connection
  and then **never sends its banner**: `ssh -vvv` gets to "Connection
  established / Local version string SSH-2.0-OpenSSH_9.4" then dies
  at "Connection timed out during banner exchange" 15 seconds later.
  Manual `nc 10.50.62.45 22` reads zero bytes over 5 seconds. A 30-
  second pause before retry didn't unstick it.
- **Most likely cause:** the cluster of failed `ssh-copy-id`
  attempts during the first session triggered fail2ban or sshd's
  `MaxStartups` to silently drop subsequent connections from this
  source. Less likely: sshd has a stuck child blocking accepts.
  Either way, the fix is **a power-cycle of bench** (physical lab
  visit, ~2 min) or **wait it out** (10 min for default fail2ban,
  potentially much longer if the lab tuned the ban window up).

### Recovery sequence (once bench is unstuck)

```bash
cd /Users/shiva/Desktop/courses/f25/s26/ece475/project/fpga_riscv_branch_predictor

# 1. Confirm bench answers
ssh -o ConnectTimeout=10 -o BatchMode=yes bench 'echo OK; hostname'

# 2. Push repo + run all 9 Vivado synths (~1h unattended on bench)
./scripts/deploy_to_bench.sh
ssh bench 'cd ~/riscv-fpga/xilinx_proj && \
  for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare \
           bp_bht2_jal bp_gshare_jal bp_bht2_full bp_gshare_full; do \
    vivado -mode batch -nojournal -nolog \
      -source ~/fpga_riscv_branch_predictor/fpga/synth_scripts/synth_variant.tcl \
      -tclargs $v ; \
  done'

# 3. Pull reports, parse, plot
scp -r bench:~/results ./fpga_results
./scripts/parse_vivado_reports.py            # → results/vivado_summary.tsv
./scripts/plot_results.py --source vivado    # → synth_area / fmax / mips_vs_area / ipc_vs_area

# 4. On-board IPS capture (interactive, ~30 min via VNC):
ssh -L 5905:localhost:5905 bench   # then VNC client → localhost:5905
# In Vivado HW Manager, program each variant's fpga_top.bit and read
# cycle counts via UART per ubmark. Numbers go into REPORT §7.4.
```

---

## What's left

### A. Vivado synth on bench (~1 hour, all 9 variants)
**Blocker:** bench sshd hung — see Session 2 status above.

The script that drives this is `fpga/synth_scripts/synth_variant.tcl`.
For each variant it (1) overlays the variant's RTL into the lab tree on
bench (`~/ece475-lab4/riscvlong/` plus a new `~/ece475-lab4/bp/`),
(2) sets the appropriate `BP_*` verilog defines on the project's
fileset, (3) resets and re-runs synth+impl through bitstream,
(4) exports `report_utilization`, `report_timing_summary`,
`report_timing -delay_type max -max_paths 25`, `report_power` to
`~/results/<variant>/` on bench.

Run sequence (from this Mac, with VPN up):

```bash
./scripts/deploy_to_bench.sh                    # rsync repo to bench

ssh bench
cd ~/riscv-fpga/xilinx_proj
for v in baseline bp_static_nt bp_bht1 bp_bht2 bp_gshare \
         bp_bht2_jal bp_gshare_jal bp_bht2_full bp_gshare_full; do
  echo "=== $v ==="
  vivado -mode batch -nojournal -nolog \
         -source ~/fpga_riscv_branch_predictor/fpga/synth_scripts/synth_variant.tcl \
         -tclargs $v
done
exit

scp -r bench:~/results ./fpga_results            # fetch reports
```

That gives, per variant: `utilization.rpt`, `timing_summary.rpt`,
`timing_paths.rpt`, `power.rpt`, plus the bitstream `fpga_top.bit`.

**TODO after that:**
- ~~Parse the Vivado utilization + timing reports into a TSV~~ —
  **done in session 2**: `scripts/parse_vivado_reports.py`.
- ~~Update the IPC-vs-area scatter to use Vivado cell counts instead
  of yosys~~ — **done in session 2**: `scripts/plot_results.py
  --source vivado` plots LUT-based area + adds `fmax.png` and
  `mips_vs_area.png` (the Fmax-corrected Pareto).
- Fill in the table in `docs/REPORT.md` §7.3.1 from
  `results/vivado_summary.tsv` (table skeleton already in place).
- Update REPORT §8 if the Vivado Fmax data changes the performance-
  per-area conclusion (currently BHT-2 full wins; could shift if
  GShare's XOR network drops Fmax noticeably).

### B. On-board IPS measurement (~30 minutes)
**Blocker:** same as §A; also needs Vivado bitstreams from §A.

Once each variant's `fpga_top.bit` is in `fpga_results/<variant>/`:
1. Open VNC tunnel: `ssh -L 5905:localhost:5905 bench`, then VNC to
   `localhost:5905` (password also `FPGAtest1`).
2. In Vivado on the bench host, open the project, program the device
   with each variant's bitstream.
3. Use the lab's serial terminal to load each ubmark `.vmh` and
   record the wall-clock cycle count returned via UART.
4. Combine: actual IPS = (instructions retired) × (Vivado-reported
   Fmax) ÷ (cycles measured on board).
5. Compare actual IPS to the simulation-projected IPS — should match.
6. Record numbers in REPORT §7.4 (subsection + 36-row TBD table
   already in place from session 2 — just fill the cells).

### C. Final report polish
Once §A and §B are filled in:
- Fill `docs/REPORT.md` §7.3.1 (utilization+Fmax+power table) and
  §7.4 (on-board IPS table) from the TSVs.
- Update §8 Pareto picture if the Vivado Fmax data shifts the
  performance-per-area conclusion.
- ~~Add a §7.4 "On-board IPS measurement" subsection~~ — **done in
  session 2** (just needs filling).
- ~~Re-render `ipc_vs_area.png` against Vivado utilization~~ —
  **done in session 2**: `plot_results.py --source vivado`.
- Optional: a brief discussion of how the lab/test mix limits what
  GShare can show (correlated benchmarks would change the picture).

### D. Potential follow-ups (not in proposal, would be extras)
- A wider GShare config that *should* beat BHT-2: longer histories
  combined with a tournament selector, or a hashed second-level
  predictor. Not promised; only worth doing if there's time.
- Wire the predictor stats (mispredict count, branches resolved) out
  to a CSR or memory-mapped reg so on-board runs can read them
  directly via UART, rather than relying on the simulation match.

---

## Files of interest

```
PROGRESS.md                            ← this file
README.md                              project overview, headline numbers
Makefile                               make sim / asm / ubmark / plots / all
docs/REPORT.md                         final report (Vivado §7.3 is TBD)

rtl/baseline/                          unmodified lab RTL (reference)
rtl/core/                              modified core (predictor-aware,
                                       gated by `ifdef BP_ENABLED)
  riscvlong-Core.v                     wires ctrl ↔ dpath
  riscvlong-CoreCtrl.v                 predictor instantiation,
                                       F-stage redirect logic, X-stage
                                       resolve / mispredict
  riscvlong-CoreDpath.v                pm_pred mux, pred_target pipeline,
                                       pred_target_match_Dhl comparator

rtl/bp/                                predictor library
  bp_predecode.v                       F-stage opcode/imm pre-decode
  bp_static_nt.v                       always-NT (baseline-equivalent)
  bp_bht1.v                            1-bit BHT
  bp_bht2.v                            2-bit BHT
  bp_gshare.v                          GShare (param: HIST_BITS)
  bp_ras.v                             8-deep Return Address Stack
  bp_top.v                             selectable wrapper

sim/verilator/sim_top.v                clean Verilator testbench

scripts/                               (see §5 above)
fpga/synth_scripts/synth_variant.tcl   Vivado batch synth (per variant)

results/                               committed: TSVs + plots + asm/ubmark
                                       summaries
results/sweep/                         BHT-2 size + GShare param sweep
results/yosys_summary.tsv              yosys per-variant cell counts
results/plots/                         all rendered charts
results/<variant>/asm_tests.tsv        per-test status + cycle counts
results/<variant>/ubmark.tsv           per-ubmark IPC / mispredict
```

---

## Quick reproducibility check

To verify everything still works on the next session:

```bash
cd /Users/shiva/Desktop/courses/f25/s26/ece475/project/fpga_riscv_branch_predictor

# Sanity: do one build + one asm test pass on the most-loaded variant
./scripts/build_sim.sh bp_bht2_full
./scripts/run_tests.sh bp_bht2_full   # expect "pass=43 fail=0 error=0"

# Then full sweep (takes ~10 minutes)
./scripts/run_all_variants.sh          # builds and runs 5 base variants
for v in bp_bht2_jal bp_gshare_jal bp_bht2_full bp_gshare_full; do
  ./scripts/build_sim.sh $v
  ./scripts/run_tests.sh $v
  ./scripts/run_ubmarks.sh $v
done

./scripts/yosys_summary.sh             # confirms results/yosys_summary.tsv
./scripts/plot_results.py              # regenerates results/plots/*.png
```

If any of those fail, the most likely cause is a missing tool — see
"Local toolchain" above; everything was installed via brew.

---

## Useful one-liners

```bash
# Compare best predictor to baseline on each ubmark
diff <(awk -F'\t' '$1!="bench"' results/baseline/ubmark.tsv) \
     <(awk -F'\t' '$1!="bench"' results/bp_bht2_full/ubmark.tsv)

# Total LUT/FF overhead of the predictor + RAS
awk 'NR>1 && /full/ {bht_full=$2; bht_full_luts=$3; bht_full_ffs=$4}
     NR>1 && /baseline/ {base=$2; base_luts=$3; base_ffs=$4}
     END {print "Δ-cells", bht_full-base, "Δ-LUTs", bht_full_luts-base_luts, "Δ-FFs", bht_full_ffs-base_ffs}' \
     results/yosys_summary.tsv

# Re-test SSH
ssh -o ConnectTimeout=10 -o BatchMode=yes bench 'echo OK; hostname'
```
