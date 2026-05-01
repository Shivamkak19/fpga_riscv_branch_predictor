#!/usr/bin/env python3
"""plot_results.py - render IPC/mispredict bar charts from results/*/ubmark.tsv

Outputs results/plots/{ipc.png, mispredict_rate.png, summary.md} from the
per-variant TSVs the run scripts produce. Pure stdlib + matplotlib.

Usage: ./scripts/plot_results.py
"""

import csv
import os
import sys
from pathlib import Path

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    print("matplotlib not installed; pip3 install matplotlib", file=sys.stderr)
    sys.exit(1)

REPO = Path(__file__).resolve().parents[1]
RESULTS = REPO / "results"
OUT = RESULTS / "plots"
OUT.mkdir(parents=True, exist_ok=True)

VARIANTS = ["baseline", "bp_static_nt", "bp_bht1", "bp_bht2", "bp_gshare"]
VARIANT_LABEL = {
    "baseline":    "baseline",
    "bp_static_nt": "static-NT",
    "bp_bht1":     "BHT-1",
    "bp_bht2":     "BHT-2",
    "bp_gshare":   "GShare",
}

def load(variant):
    p = RESULTS / variant / "ubmark.tsv"
    if not p.exists():
        return []
    rows = []
    with open(p) as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            rows.append(row)
    return rows

# Collect: data[bench][variant] = {ipc, mispredicts, branches, cycles}
data = {}
for v in VARIANTS:
    for row in load(v):
        b = row["bench"]
        data.setdefault(b, {})[v] = row

benches = sorted(data.keys())
if not benches:
    print("No ubmark.tsv data found under results/. Run scripts/run_ubmarks.sh first.")
    sys.exit(0)

# --- IPC bar chart ---
fig, ax = plt.subplots(figsize=(10, 5))
xs = list(range(len(benches)))
W = 0.16
for i, v in enumerate(VARIANTS):
    ipcs = [float(data[b][v]["ipc"]) if v in data[b] else 0.0 for b in benches]
    ax.bar([x + W * (i - 2) for x in xs], ipcs, width=W, label=VARIANT_LABEL[v])
ax.set_xticks(xs)
ax.set_xticklabels([b.replace("ubmark-", "") for b in benches])
ax.set_ylabel("IPC")
ax.set_ylim(0, 1.05)
ax.set_title("IPC by predictor variant — ubmark microbenchmarks")
ax.axhline(1.0, color="gray", linewidth=0.5, linestyle="--")
ax.legend(loc="lower right", ncol=5, fontsize=9)
ax.grid(axis="y", linestyle=":", alpha=0.6)
plt.tight_layout()
plt.savefig(OUT / "ipc.png", dpi=130)
plt.close()
print("wrote", OUT / "ipc.png")

# --- Mispredict rate (excluding baseline + static_nt which don't track) ---
fig, ax = plt.subplots(figsize=(10, 5))
predictor_variants = ["bp_bht1", "bp_bht2", "bp_gshare"]
W = 0.25
for i, v in enumerate(predictor_variants):
    rates = []
    for b in benches:
        if v in data[b]:
            br = int(data[b][v]["branches"])
            misp = int(data[b][v]["mispredicts"])
            rates.append(100.0 * misp / br if br else 0.0)
        else:
            rates.append(0.0)
    ax.bar([x + W * (i - 1) for x in xs], rates, width=W, label=VARIANT_LABEL[v])
ax.set_xticks(xs)
ax.set_xticklabels([b.replace("ubmark-", "") for b in benches])
ax.set_ylabel("mispredict rate (%)")
ax.set_title("Branch mispredict rate by predictor — ubmark microbenchmarks")
ax.legend(loc="upper right", fontsize=9)
ax.grid(axis="y", linestyle=":", alpha=0.6)
plt.tight_layout()
plt.savefig(OUT / "mispredict_rate.png", dpi=130)
plt.close()
print("wrote", OUT / "mispredict_rate.png")

# --- summary.md ---
with open(OUT / "summary.md", "w") as f:
    f.write("# Predictor benchmark summary\n\n")
    f.write("## IPC\n\n")
    f.write("| benchmark | " + " | ".join(VARIANT_LABEL[v] for v in VARIANTS) + " |\n")
    f.write("|---" + "|---:" * len(VARIANTS) + "|\n")
    for b in benches:
        cells = []
        for v in VARIANTS:
            if v in data[b]:
                cells.append(f"{float(data[b][v]['ipc']):.4f}")
            else:
                cells.append("-")
        f.write(f"| {b} | " + " | ".join(cells) + " |\n")
    f.write("\n## Mispredict rate (%)\n\n")
    f.write("| benchmark | branches | " + " | ".join(VARIANT_LABEL[v] for v in predictor_variants) + " |\n")
    f.write("|---|---:|" + "---:|" * len(predictor_variants) + "\n")
    for b in benches:
        br = int(data[b].get("bp_bht2", data[b].get("bp_bht1", {})).get("branches", 0))
        cells = [str(br)]
        for v in predictor_variants:
            if v in data[b]:
                br = int(data[b][v]["branches"])
                misp = int(data[b][v]["mispredicts"])
                cells.append(f"{100.0 * misp / br:.2f}" if br else "-")
            else:
                cells.append("-")
        f.write(f"| {b} | " + " | ".join(cells) + " |\n")
print("wrote", OUT / "summary.md")

# --- Synth comparison: yosys cell counts per variant ---
synth_tsv = RESULTS / "yosys_summary.tsv"
if synth_tsv.exists():
    with open(synth_tsv) as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    if rows:
        labels = [VARIANT_LABEL.get(r["variant"], r["variant"]) for r in rows]
        cells = [int(r["cells"]) if r["cells"].isdigit() else 0 for r in rows]
        luts  = [int(r["LUTs"])  if r["LUTs"].isdigit()  else 0 for r in rows]
        ffs   = [int(r["FFs"])   if r["FFs"].isdigit()   else 0 for r in rows]

        fig, axes = plt.subplots(1, 3, figsize=(13, 4))
        for ax, vals, title, color in [
            (axes[0], cells, "Total cells",       "tab:blue"),
            (axes[1], luts,  "LUTs (sum LUT1-6)", "tab:green"),
            (axes[2], ffs,   "FFs (FDRE+FDSE)",   "tab:red"),
        ]:
            ax.bar(labels, vals, color=color)
            ax.set_title(title)
            ax.tick_params(axis="x", labelrotation=20)
            ax.grid(axis="y", linestyle=":", alpha=0.6)
            for i, vv in enumerate(vals):
                ax.text(i, vv, f"{vv}", ha="center", va="bottom", fontsize=8)
        fig.suptitle("yosys synth_xilinx (xc7) cell counts by variant — relative comparison", fontsize=11)
        plt.tight_layout()
        plt.savefig(OUT / "synth_area.png", dpi=130)
        plt.close()
        print("wrote", OUT / "synth_area.png")

        # IPC vs area scatter
        # Use mean IPC across the 4 ubmarks for each variant
        mean_ipc = {}
        for v in VARIANTS:
            xs_ = [float(data[b][v]["ipc"]) for b in benches if v in data[b]]
            mean_ipc[v] = sum(xs_) / len(xs_) if xs_ else 0
        fig, ax = plt.subplots(figsize=(8, 5))
        for r, lbl, color in zip(
                rows, labels,
                ["tab:gray", "tab:orange", "tab:blue", "tab:red", "tab:purple"]):
            v = r["variant"]
            mip = mean_ipc.get(v, 0)
            cl = int(r["cells"]) if r["cells"].isdigit() else 0
            ax.scatter(cl, mip, s=120, color=color, edgecolor="black", zorder=3)
            ax.annotate(lbl, (cl, mip), xytext=(8, 5), textcoords="offset points")
        ax.set_xlabel("yosys cell count (relative area)")
        ax.set_ylabel("mean IPC across 4 ubmarks")
        ax.set_title("Performance vs area: IPC per cell")
        ax.grid(linestyle=":", alpha=0.5)
        ax.set_ylim(0.65, 1.0)
        plt.tight_layout()
        plt.savefig(OUT / "ipc_vs_area.png", dpi=130)
        plt.close()
        print("wrote", OUT / "ipc_vs_area.png")
