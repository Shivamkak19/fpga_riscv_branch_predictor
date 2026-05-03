#!/usr/bin/env python3
"""parse_vivado_reports.py — collect Vivado per-variant reports into a TSV.

Reads ./fpga_results/<variant>/{utilization.rpt, timing_summary.rpt, power.rpt}
(the directory layout `scp -r bench:~/results ./fpga_results` produces) and
writes results/vivado_summary.tsv with one row per variant.

Columns:
  variant, slice_luts, lut_logic, lut_mem, slice_regs, bram_tile, dsp,
  target_period_ns, wns_ns, fmax_mhz, total_power_w

Run:  ./scripts/parse_vivado_reports.py [--input fpga_results] [--output results/vivado_summary.tsv]
"""

import argparse
import csv
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
VARIANTS = ["baseline", "bp_static_nt", "bp_bht1", "bp_bht2", "bp_gshare",
            "bp_bht2_jal", "bp_gshare_jal", "bp_bht2_full", "bp_gshare_full"]

UTIL_KEYS = {
    "slice_luts":  re.compile(r"^\|\s*(?:Slice|CLB)\s+LUTs\*?\s*\|\s*(\d+)\s*\|"),
    "lut_logic":   re.compile(r"^\|\s*LUT as Logic\s*\|\s*(\d+)\s*\|"),
    "lut_mem":     re.compile(r"^\|\s*LUT as Memory\s*\|\s*(\d+)\s*\|"),
    "slice_regs":  re.compile(r"^\|\s*(?:Slice|CLB)\s+Registers\s*\|\s*(\d+)\s*\|"),
    "bram_tile":   re.compile(r"^\|\s*Block RAM Tile\s*\|\s*(\d+(?:\.\d+)?)\s*\|"),
    "dsp":         re.compile(r"^\|\s*DSPs\s*\|\s*(\d+)\s*\|"),
}

CLOCK_ROW = re.compile(
    r"^\s*\S+\s+\{[^}]+\}\s+([\d.]+)\s+([\d.]+)\s*$"
)
WNS_HEADER = re.compile(r"^\s*\|?\s*WNS\(ns\)\s+TNS\(ns\)")
WNS_NUM = re.compile(r"^\s*\|?\s*(-?\d+\.\d+)\s+(-?\d+\.\d+)")
POWER_TOTAL = re.compile(
    r"^\|\s*Total On-Chip Power\s*\(W\)\s*\|\s*(\d+\.\d+)\s*\|"
)


def parse_utilization(path: Path) -> dict:
    out = {k: "" for k in UTIL_KEYS}
    if not path.exists():
        return out
    text = path.read_text(errors="replace")
    for line in text.splitlines():
        for key, pat in UTIL_KEYS.items():
            if out[key]:
                continue
            m = pat.match(line)
            if m:
                out[key] = m.group(1)
    return out


def parse_timing(path: Path) -> dict:
    out = {"target_period_ns": "", "wns_ns": "", "fmax_mhz": ""}
    if not path.exists():
        return out
    lines = path.read_text(errors="replace").splitlines()

    # Clock period — first row matching the "name {wave} period freq" shape
    # under a "Clock Summary" section.
    in_clock_summary = False
    for line in lines:
        if "Clock Summary" in line:
            in_clock_summary = True
            continue
        if in_clock_summary:
            m = CLOCK_ROW.match(line)
            if m:
                out["target_period_ns"] = m.group(1)
                break
            if line.strip().startswith("---") or not line.strip():
                continue
            if "----" not in line and line.strip() and "Clock" not in line and "Period" not in line and "Waveform" not in line:
                # Some Vivado versions: "clk_pin_p   {0.000 5.000}    10.000     100.000"
                toks = line.split()
                if len(toks) >= 4:
                    try:
                        float(toks[-2])
                        out["target_period_ns"] = toks[-2]
                        break
                    except ValueError:
                        pass

    # WNS — first numeric row after "WNS(ns) TNS(ns) ..." header
    for i, line in enumerate(lines):
        if WNS_HEADER.match(line):
            for j in range(i + 1, min(i + 6, len(lines))):
                m = WNS_NUM.match(lines[j])
                if m:
                    out["wns_ns"] = m.group(1)
                    break
            if out["wns_ns"]:
                break

    if out["target_period_ns"] and out["wns_ns"]:
        try:
            period = float(out["target_period_ns"])
            wns = float(out["wns_ns"])
            achieved = period - wns
            if achieved > 0:
                out["fmax_mhz"] = f"{1000.0 / achieved:.2f}"
        except ValueError:
            pass

    return out


def parse_power(path: Path) -> dict:
    out = {"total_power_w": ""}
    if not path.exists():
        return out
    for line in path.read_text(errors="replace").splitlines():
        m = POWER_TOTAL.match(line)
        if m:
            out["total_power_w"] = m.group(1)
            break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default=str(REPO / "fpga_results"),
                    help="dir holding <variant>/ subdirs of Vivado .rpt files")
    ap.add_argument("--output", default=str(REPO / "results" / "vivado_summary.tsv"))
    args = ap.parse_args()

    in_root = Path(args.input)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    cols = ["variant", "slice_luts", "lut_logic", "lut_mem", "slice_regs",
            "bram_tile", "dsp", "target_period_ns", "wns_ns", "fmax_mhz",
            "total_power_w"]

    rows = []
    for v in VARIANTS:
        vdir = in_root / v
        if not vdir.is_dir():
            print(f"skip {v} — no directory at {vdir}", file=sys.stderr)
            continue
        row = {"variant": v}
        row.update(parse_utilization(vdir / "utilization.rpt"))
        row.update(parse_timing(vdir / "timing_summary.rpt"))
        row.update(parse_power(vdir / "power.rpt"))
        for c in cols:
            row.setdefault(c, "")
        rows.append(row)

    if not rows:
        print(f"no variants found under {in_root}", file=sys.stderr)
        sys.exit(1)

    with open(out_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, delimiter="\t")
        w.writeheader()
        w.writerows(rows)

    print(f"wrote {out_path}")
    widths = [max(len(str(r.get(c, ""))) for r in [{"variant": "variant"}] + rows) for c in cols]
    widths = [max(w_, len(c)) for w_, c in zip(widths, cols)]
    print("  " + "  ".join(c.ljust(w_) for c, w_ in zip(cols, widths)))
    for r in rows:
        print("  " + "  ".join(str(r.get(c, "")).ljust(w_) for c, w_ in zip(cols, widths)))


if __name__ == "__main__":
    main()
