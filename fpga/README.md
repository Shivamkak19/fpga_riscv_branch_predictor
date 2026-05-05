# FPGA synthesis infrastructure

These scripts implement the synthesis flow described in §4 of
`docs/report.tex` ("FPGA synthesis infrastructure"). They were
authored against the parallel `riscvlong` port on this repo's `fpga`
branch and bundled here so the submission zip is self-contained.

Two flows are included:

- **Vivado** (`fpga/synth_scripts/synth_variant.tcl`,
  `scripts/parse_vivado_reports.py`) — batch synth + impl + bitstream
  on a Nexys-4 DDR / `xc7a100tcsg324-1` Artix-7 part driven by Vivado
  2019.1 on the lab bench, then parses the per-variant utilization,
  timing, and power reports into `results/vivado_summary.tsv`. The
  bench host became unreachable across the project window, so no
  end-to-end Vivado runs were executed; the script is committed for
  reference and reproducibility.

- **yosys** (`scripts/yosys_synth.sh`, `scripts/yosys_summary.sh`,
  `results/yosys_summary.tsv`) — relative-area sweep with
  `yosys 0.64`'s `synth_xilinx -family xc7` front-end, used as a
  cell-count proxy. Numbers in Table 4 of the report come from this
  flow.

## Directory-layout note

Both flows reference the `riscvlong` RTL tree from the `fpga` branch
(`rtl/baseline/riscvlong/`, `rtl/core/`, `rtl/bp/`). Those paths do
not exist on `main`, which carries the `riscvooo` integration
(`riscvooo/`, `bp/` at top level). To re-run the synthesis flow,
check out the `fpga` branch:

```
git checkout fpga
./scripts/yosys_synth.sh bp_bht2
./scripts/yosys_summary.sh
```

The predictor RTL and define set (`BP_ENABLED`, `BP_BHT1`, `BP_BHT2`,
`BP_GSHARE` (= `BP_TWO_LEVEL` on `main`), `BP_PRED_JAL`, `BP_RAS`)
are identical between the two cores; re-targeting Vivado at
`riscvooo` is described at the end of report §4.

## Variant naming

The `fpga`-branch scripts use `bp_gshare` for the two-level
PC⊕GHR-indexed predictor; `main`'s simulation flow renames this to
`bp_two_level` for clarity. The synthesis numbers in
`results/yosys_summary.tsv` and Table 4 of the report use the
original `bp_gshare` labels, since that is the name the synthesis
flow was actually run under.
