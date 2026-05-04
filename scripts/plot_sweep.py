#!/usr/bin/env python3
"""plot_sweep.py - render BHT-2 size sweep + GShare (idx, hist) sweep charts
   from results/sweep/sweep.tsv

Outputs results/sweep/{bht2_size.png, gshare_heatmap.png, sweep_summary.md}.
"""

import csv
import sys
from pathlib import Path
from collections import defaultdict

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
except ImportError:
    print("missing matplotlib/numpy", file=sys.stderr)
    sys.exit(1)

REPO = Path(__file__).resolve().parents[1]
TSV  = REPO / "results" / "sweep" / "sweep.tsv"
OUT  = REPO / "results" / "sweep"

if not TSV.exists():
    print(f"no {TSV}; run scripts/sweep_predictor_size.sh first")
    sys.exit(1)

rows = []
with open(TSV) as f:
    for r in csv.DictReader(f, delimiter="\t"):
        try:
            r["index_bits"] = int(r["index_bits"])
            r["hist_bits"]  = int(r["hist_bits"]) if r["hist_bits"] not in ("-", "") else None
            r["mispredicts"] = int(r["mispredicts"]) if r["mispredicts"] != "-" else None
            r["branches"]   = int(r["branches"]) if r["branches"] != "-" else None
            r["ipc"]        = float(r["ipc"]) if r["ipc"] != "-" else None
            rows.append(r)
        except (ValueError, KeyError):
            pass

# --- BHT-2 size sweep: mispredict rate vs index_bits, one curve per bench ---
bht2 = defaultdict(dict)  # bht2[bench][idx] = misprate%
for r in rows:
    if r["predictor"] != "bht2":
        continue
    if r["mispredicts"] is None or r["branches"] is None or r["branches"] == 0:
        continue
    misp_pct = 100.0 * r["mispredicts"] / r["branches"]
    bht2[r["bench"]][r["index_bits"]] = misp_pct

if bht2:
    fig, ax = plt.subplots(figsize=(8, 5))
    for bench, m in sorted(bht2.items()):
        xs = sorted(m.keys())
        ys = [m[x] for x in xs]
        ax.plot(xs, ys, marker="o", label=bench.replace("ubmark-", ""))
    ax.set_xlabel("INDEX_BITS  (entries = 2**INDEX_BITS)")
    ax.set_ylabel("mispredict rate (%)")
    ax.set_title("BHT-2 mispredict rate vs table size")
    ax.set_xticks(sorted({r["index_bits"] for r in rows if r["predictor"] == "bht2"}))
    ax.grid(linestyle=":", alpha=0.6)
    ax.legend()
    plt.tight_layout()
    plt.savefig(OUT / "bht2_size.png", dpi=130)
    plt.close()
    print("wrote", OUT / "bht2_size.png")

# --- GShare heatmap: mean mispredict rate over benchmarks, by (idx, hist) ---
gshare_data = defaultdict(list)  # gshare_data[(idx,hist)] = [misprate_per_bench]
gshare_idx_set, gshare_hist_set = set(), set()
for r in rows:
    if r["predictor"] != "gshare" or r["hist_bits"] is None:
        continue
    if r["mispredicts"] is None or r["branches"] in (None, 0):
        continue
    rate = 100.0 * r["mispredicts"] / r["branches"]
    gshare_data[(r["index_bits"], r["hist_bits"])].append(rate)
    gshare_idx_set.add(r["index_bits"])
    gshare_hist_set.add(r["hist_bits"])

if gshare_data:
    idxs  = sorted(gshare_idx_set)
    hists = sorted(gshare_hist_set)
    Z = np.zeros((len(hists), len(idxs)))
    for i, hb in enumerate(hists):
        for j, ib in enumerate(idxs):
            v = gshare_data.get((ib, hb), [])
            Z[i, j] = sum(v) / len(v) if v else float("nan")

    fig, ax = plt.subplots(figsize=(7, 5))
    im = ax.imshow(Z, cmap="viridis", aspect="auto")
    ax.set_xticks(range(len(idxs)))
    ax.set_xticklabels(idxs)
    ax.set_yticks(range(len(hists)))
    ax.set_yticklabels(hists)
    ax.set_xlabel("INDEX_BITS")
    ax.set_ylabel("HIST_BITS")
    ax.set_title("GShare mean mispredict rate (%) — averaged over 4 ubmarks")
    for i in range(len(hists)):
        for j in range(len(idxs)):
            v = Z[i, j]
            if v == v:  # not nan
                ax.text(j, i, f"{v:.1f}", ha="center", va="center",
                        color="white" if v > Z[~np.isnan(Z)].mean() else "black",
                        fontsize=10)
    fig.colorbar(im, ax=ax, label="mispredict rate (%)")
    plt.tight_layout()
    plt.savefig(OUT / "gshare_heatmap.png", dpi=130)
    plt.close()
    print("wrote", OUT / "gshare_heatmap.png")

# --- summary.md ---
with open(OUT / "sweep_summary.md", "w") as f:
    f.write("# Predictor parameter sweep\n\n")
    f.write("## BHT-2 mispredict rate (%) vs table size\n\n")
    if bht2:
        idxs = sorted({r["index_bits"] for r in rows if r["predictor"] == "bht2"})
        f.write("| benchmark | " + " | ".join(f"idx={i}" for i in idxs) + " |\n")
        f.write("|---|" + "---:|" * len(idxs) + "\n")
        for bench, m in sorted(bht2.items()):
            cells = [f"{m.get(i, float('nan')):.2f}" if m.get(i) is not None else "-" for i in idxs]
            f.write(f"| {bench} | " + " | ".join(cells) + " |\n")
    f.write("\n## GShare mispredict rate (%) — mean over 4 ubmarks\n\n")
    if gshare_data:
        f.write("| HIST_BITS \\ INDEX_BITS | " + " | ".join(str(i) for i in idxs) + " |\n")
        f.write("|---|" + "---:|" * len(idxs) + "\n")
        for hb in hists:
            cells = []
            for ib in idxs:
                v = gshare_data.get((ib, hb), [])
                cells.append(f"{(sum(v)/len(v)):.2f}" if v else "-")
            f.write(f"| hist={hb} | " + " | ".join(cells) + " |\n")
print("wrote", OUT / "sweep_summary.md")
