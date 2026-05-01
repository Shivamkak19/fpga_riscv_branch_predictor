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
