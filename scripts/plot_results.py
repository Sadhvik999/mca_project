#!/usr/bin/env python3
"""Generate publication-quality architectural evaluation plots using Matplotlib.

Plots generated in results/plots/ (both PNG and PDF):
  1. hit_rate_by_config: Hit rate vs cache size (1KB..8KB) and block size (8B..32B).
  2. amat_vs_latency: AMAT vs Backing Memory Latency (5, 10, 20, 50 cycles).
  3. miss_classification_breakdown: Compulsory vs Capacity vs Conflict miss decomposition.
  4. conflict_resolution_amat: Direct-mapped conflict resolution (4 KB vs 8 KB).
"""

import csv
from pathlib import Path
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend
import matplotlib.pyplot as plt
import numpy as np


def setup_style():
    plt.rcParams.update({
        "font.family": "serif",
        "font.size": 10,
        "axes.labelsize": 11,
        "axes.titlesize": 12,
        "xtick.labelsize": 9,
        "ytick.labelsize": 9,
        "legend.fontsize": 9,
        "figure.titlesize": 13,
        "lines.linewidth": 1.8,
        "lines.markersize": 6,
        "grid.alpha": 0.4,
        "grid.linestyle": "--",
    })


def plot_hit_rate_by_config(repo_root: Path, out_dir: Path):
    """Plot hit rate across 12 configurations for all 4 workloads."""
    csv_path = repo_root / "results" / "param_sweeps_amat.csv"
    if not csv_path.is_file():
        print(f"[WARN] {csv_path} not found, skipping hit_rate_by_config")
        return

    data = {}
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = row["trace"]
            cfg = row["config"]
            hr = float(row["hit_rate"]) * 100.0
            data.setdefault(t, {})[cfg] = hr

    configs = [
        "1KB_8B", "1KB_16B", "1KB_32B",
        "2KB_8B", "2KB_16B", "2KB_32B",
        "4KB_8B", "4KB_16B", "4KB_32B",
        "8KB_8B", "8KB_16B", "8KB_32B",
    ]

    fig, ax = plt.subplots(figsize=(10, 4.8))
    x = np.arange(len(configs))
    width = 0.2

    colors = {
        "sequential": "#1f77b4",
        "strided": "#ff7f0e",
        "conflict": "#d62728",
        "random": "#2ca02c",
    }
    labels = {
        "sequential": "Sequential",
        "strided": "Strided",
        "conflict": "Conflict Ping-Pong",
        "random": "Random (Seed 42)",
    }

    for i, trace in enumerate(["sequential", "strided", "conflict", "random"]):
        if trace in data:
            vals = [data[trace].get(cfg, 0.0) for cfg in configs]
            offset = (i - 1.5) * width
            ax.bar(x + offset, vals, width, label=labels[trace], color=colors[trace], alpha=0.9)

    ax.set_ylabel("Hit Rate (%)")
    ax.set_xlabel("Cache Configuration (Capacity_BlockSize)")
    ax.set_title("Cache Hit Rate Across Geometric Configurations (1 KB - 8 KB, 8 B - 32 B)")
    ax.set_xticks(x)
    ax.set_xticklabels(configs, rotation=35, ha="right")
    ax.set_ylim(0, 105)
    ax.grid(True, axis="y")
    ax.legend(loc="upper left", framealpha=0.95)

    plt.tight_layout()
    fig.savefig(out_dir / "hit_rate_by_config.png", dpi=300)
    fig.savefig(out_dir / "hit_rate_by_config.pdf")
    plt.close(fig)
    print("  -> Saved hit_rate_by_config.png/pdf")


def plot_amat_vs_latency(repo_root: Path, out_dir: Path):
    """Plot AMAT vs Memory Latency for default 4KB_16B cache."""
    csv_path = repo_root / "results" / "amat_table.csv"
    if not csv_path.is_file():
        print(f"[WARN] {csv_path} not found, skipping amat_vs_latency")
        return

    data = {}
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = row["trace"]
            lat = int(row["mem_latency"])
            amat = float(row["amat_cycles"])
            data.setdefault(t, {})[lat] = amat

    latencies = [5, 10, 20, 50]
    fig, ax = plt.subplots(figsize=(7, 4.5))

    styles = {
        "sequential": ("#1f77b4", "o-", "Sequential (Miss Rate = 25.0%)"),
        "strided": ("#ff7f0e", "s-", "Strided (Miss Rate = 100.0%)"),
        "conflict": ("#d62728", "^-", "Conflict (Miss Rate = 100.0%, 25% Dirty)"),
        "random": ("#2ca02c", "d-", "Random (Miss Rate = 81.0%, 17% Dirty)"),
    }

    for trace in ["sequential", "strided", "conflict", "random"]:
        if trace in data:
            y = [data[trace][lat] for lat in latencies]
            color, fmt, label = styles[trace]
            ax.plot(latencies, y, fmt, color=color, label=label)

    ax.set_xlabel("Backing Memory Latency (Cycles)")
    ax.set_ylabel("Average Memory Access Time (Cycles / Access)")
    ax.set_title("AMAT vs Memory Latency Sensitivity (Default 4 KB, 16-Byte Blocks)")
    ax.set_xticks(latencies)
    ax.grid(True)
    ax.legend(loc="upper left", framealpha=0.95)

    plt.tight_layout()
    fig.savefig(out_dir / "amat_vs_latency.png", dpi=300)
    fig.savefig(out_dir / "amat_vs_latency.pdf")
    plt.close(fig)
    print("  -> Saved amat_vs_latency.png/pdf")


def plot_miss_classification_breakdown(repo_root: Path, out_dir: Path):
    """Stacked bar plot of Compulsory vs Capacity vs Conflict misses for 4KB vs 8KB."""
    csv_path = repo_root / "results" / "miss_classification.csv"
    if not csv_path.is_file():
        print(f"[WARN] {csv_path} not found, skipping miss_classification_breakdown")
        return

    # Extract 4KB_16B and 8KB_16B rows
    configs = ["4KB_16B", "8KB_16B"]
    traces = ["sequential", "strided", "conflict", "random"]
    rows = {}
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            if r["config"] in configs and r["trace"] in traces:
                rows[(r["trace"], r["config"])] = {
                    "compulsory": int(r["compulsory_misses"]),
                    "capacity": int(r["capacity_misses"]),
                    "conflict": int(r["conflict_misses"]),
                    "total": int(r["misses"]),
                }

    fig, ax = plt.subplots(figsize=(8.5, 4.8))

    bar_labels = []
    comp_vals = []
    cap_vals = []
    conf_vals = []

    for t in traces:
        for cfg in configs:
            key = (t, cfg)
            d = rows.get(key, {"compulsory": 0, "capacity": 0, "conflict": 0})
            bar_labels.append(f"{t[:4].capitalize()}.\n{cfg}")
            comp_vals.append(d["compulsory"])
            cap_vals.append(d["capacity"])
            conf_vals.append(d["conflict"])

    x = np.arange(len(bar_labels))
    width = 0.55

    p1 = ax.bar(x, comp_vals, width, label="Compulsory (Cold)", color="#2b5c8f")
    p2 = ax.bar(x, cap_vals, width, bottom=comp_vals, label="Capacity", color="#d95f02")
    bottom_conf = np.array(comp_vals) + np.array(cap_vals)
    p3 = ax.bar(x, conf_vals, width, bottom=bottom_conf, label="Conflict", color="#e7298a")

    ax.set_ylabel("Number of Misses (out of 1,024 accesses)")
    ax.set_title("Miss Decomposition: Compulsory vs Capacity vs Conflict Misses (16 B Blocks)")
    ax.set_xticks(x)
    ax.set_xticklabels(bar_labels)
    ax.set_ylim(0, 1150)
    ax.grid(True, axis="y")
    ax.legend(loc="upper right", framealpha=0.95)

    # Annotate total misses above bars
    for i in range(len(bar_labels)):
        total = comp_vals[i] + cap_vals[i] + conf_vals[i]
        ax.annotate(str(total), (x[i], total + 15), ha="center", fontsize=8, fontweight="bold")

    plt.tight_layout()
    fig.savefig(out_dir / "miss_classification_breakdown.png", dpi=300)
    fig.savefig(out_dir / "miss_classification_breakdown.pdf")
    plt.close(fig)
    print("  -> Saved miss_classification_breakdown.png/pdf")


def plot_conflict_resolution_amat(repo_root: Path, out_dir: Path):
    """Detailed visual comparison of conflict ping-pong resolution at 8 KB."""
    csv_path = repo_root / "results" / "param_sweeps_amat.csv"
    if not csv_path.is_file():
        print(f"[WARN] {csv_path} not found, skipping conflict_resolution_amat")
        return

    cs_data = {}
    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            if r["trace"] == "conflict" and r["config"].endswith("_16B"):
                cfg = r["config"]
                cs_data[cfg] = {
                    "hits": int(r["hits"]),
                    "misses": int(r["misses"]),
                    "cycles": int(r["cycles"]),
                    "amat": float(r["amat_cycles"]),
                }

    cfgs = ["1KB_16B", "2KB_16B", "4KB_16B", "8KB_16B"]
    hits = [cs_data[c]["hits"] for c in cfgs]
    cycles = [cs_data[c]["cycles"] for c in cfgs]
    amats = [cs_data[c]["amat"] for c in cfgs]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.5, 4.2))

    # Subplot 1: Hit count & Total cycles
    x = np.arange(len(cfgs))
    w = 0.35
    ax1.bar(x - w/2, hits, w, label="Hits (out of 1024)", color="#2ca02c")
    ax1_twin = ax1.twinx()
    ax1_twin.bar(x + w/2, cycles, w, label="Total Cycles", color="#d62728", alpha=0.8)

    ax1.set_xticks(x)
    ax1.set_xticklabels(cfgs)
    ax1.set_ylabel("Hit Count", color="#2ca02c")
    ax1_twin.set_ylabel("Total Cycles", color="#d62728")
    ax1.set_title("Conflict Ping-Pong: Hits vs Total Cycles")
    ax1.grid(True, axis="y")

    # Subplot 2: AMAT transition
    ax2.plot(cfgs, amats, "o-", color="#8c564b", linewidth=2.2, markersize=8)
    for i, txt in enumerate(amats):
        ax2.annotate(f"{txt:.2f} cyc", (cfgs[i], txt + 0.6), ha="center", fontsize=9, fontweight="bold")
    ax2.set_ylabel("AMAT (Cycles / Access)")
    ax2.set_title("Conflict Ping-Pong: AMAT Elimination at 8 KB")
    ax2.set_ylim(0, 19)
    ax2.grid(True)

    plt.tight_layout()
    fig.savefig(out_dir / "conflict_resolution_amat.png", dpi=300)
    fig.savefig(out_dir / "conflict_resolution_amat.pdf")
    plt.close(fig)
    print("  -> Saved conflict_resolution_amat.png/pdf")


def main():
    repo_root = Path(__file__).resolve().parent.parent
    out_dir = repo_root / "results" / "plots"
    out_dir.mkdir(parents=True, exist_ok=True)

    setup_style()
    print(f"Generating plots in {out_dir}...")
    plot_hit_rate_by_config(repo_root, out_dir)
    plot_amat_vs_latency(repo_root, out_dir)
    plot_miss_classification_breakdown(repo_root, out_dir)
    plot_conflict_resolution_amat(repo_root, out_dir)
    print("[SUCCESS] All plots generated successfully!")


if __name__ == "__main__":
    main()
