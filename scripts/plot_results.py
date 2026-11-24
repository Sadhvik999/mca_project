#!/usr/bin/env python3
"""Generate publication-quality architectural evaluation plots using Matplotlib.

Read the measured and classified CSVs in results/. Write PNG and PDF figures
to results/plots/. Pass --directed-vcd to render the testbench waveforms.
"""

import argparse
import csv
from pathlib import Path
import matplotlib
matplotlib.use("Agg")  # Non-interactive backend
import matplotlib.pyplot as plt
import numpy as np

from run_sweep import DEFAULT_BLOCK_SIZES, DEFAULT_CACHE_SIZES, format_config

TRACE_STYLES = {
    "sequential": ("#2166ac", "o-", "Sequential"),
    "strided": ("#b35806", "s--", "Strided"),
    "conflict": ("#b2182b", "^:", "Conflict ping-pong"),
    "random": ("#007651", "D-.", "Random (seed 42)"),
}


def save_figure(fig, out_dir, name):
    fig.savefig(out_dir / f"{name}.png", dpi=300)
    fig.savefig(out_dir / f"{name}.pdf", metadata={"CreationDate": None})
    plt.close(fig)
    print(f"  -> Saved {name}.png/pdf")


def read_rows(path, *key_fields):
    with path.open(newline="", encoding="utf-8") as infile:
        return {
            tuple(row[field] for field in key_fields): row
            for row in csv.DictReader(infile)
        }


def plot_hit_rate_slice(results_dir, out_dir, *, name, field, values, xlabel, title):
    rows = read_rows(results_dir / f"sweep_{name}.csv", "trace", field)
    fig, ax = plt.subplots(figsize=(6.2, 3.4), layout="constrained")
    for trace, (color, style, label) in TRACE_STYLES.items():
        rates = [100 * float(rows[trace, str(value)]["hit_rate"]) for value in values]
        ax.plot(values, rates, style, color=color, label=label, markerfacecolor="none")
    ax.set(xlabel=xlabel, ylabel="Hit rate (%)", title=title, xticks=values, ylim=(-4, 104))
    ax.grid(True)
    ax.legend(loc="upper center", ncol=2, bbox_to_anchor=(0.5, -0.22), frameon=False)
    save_figure(fig, out_dir, f"hit_rate_vs_{name}")


def plot_amat_by_config(results_dir, out_dir):
    rows = read_rows(results_dir / "param_sweeps_amat.csv", "trace", "config")
    fig, axes = plt.subplots(2, 2, figsize=(7.5, 5.7), layout="constrained")
    maximum = max(float(row["amat_cycles"]) for row in rows.values())
    for trace, ax in zip(TRACE_STYLES, axes.flat):
        values = [
            [float(rows[trace, format_config(cache, block)]["amat_cycles"])
             for block in DEFAULT_BLOCK_SIZES]
            for cache in DEFAULT_CACHE_SIZES
        ]
        image = ax.imshow(values, cmap="Blues", vmin=0, vmax=maximum, aspect="auto")
        for (row, col), value in np.ndenumerate(values):
            ax.text(col, row, f"{value:.2f}", ha="center", va="center",
                    color="white" if value > 0.6 * maximum else "#14212d")
        ax.set(title=TRACE_STYLES[trace][2],
               xticks=range(len(DEFAULT_BLOCK_SIZES)), xticklabels=DEFAULT_BLOCK_SIZES,
               yticks=range(len(DEFAULT_CACHE_SIZES)),
               yticklabels=[size // 1024 for size in DEFAULT_CACHE_SIZES])
    fig.supxlabel("Block size (B)")
    fig.supylabel("Cache size (KiB)")
    fig.colorbar(image, ax=axes, label="AMAT (cycles/access)")
    save_figure(fig, out_dir, "amat_by_config")


def verify_miss_classification(results_dir):
    measured = read_rows(results_dir / "sweep_all_traces.csv", "trace", "config")
    classified = read_rows(results_dir / "miss_classification.csv", "trace", "config")
    for key, row in measured.items():
        model = classified[key]
        if any(row[field] != model[field] for field in ("accesses", "hits", "misses")):
            raise ValueError(f"{key}: 3Cs model disagrees with measured RTL counters")
        if sum(int(model[f"{kind}_misses"]) for kind in ("compulsory", "capacity", "conflict")) != int(row["misses"]):
            raise ValueError(f"{key}: 3Cs counts do not add up to measured misses")


def directed_events(path, selected):
    """Read selected hierarchy paths from the Icarus directed testbench VCD."""
    scopes, codes, events = [], {}, {signal: [] for signal in selected.values()}
    with path.open(encoding="ascii") as infile:
        for raw in infile:
            parts = raw.split()
            if not parts:
                continue
            if parts[0] == "$scope":
                scopes.append(parts[2])
            elif parts[0] == "$upscope":
                scopes.pop()
            elif parts[0] == "$var":
                signal = selected.get(".".join([*scopes, parts[4]]))
                if signal is not None:
                    codes[parts[3]] = signal
            elif parts[0] == "$timescale":
                # The Icarus dump inherits 1 ps precision from the RTL and TB.
                if next(infile).strip() != "1ps":
                    raise ValueError("expected Icarus VCD timescale of 1 ps")
            elif parts[0] == "$enddefinitions":
                break
        if set(codes.values()) != set(events):
            raise ValueError(f"missing directed testbench signals in {path}")

        time_ns = 0
        for raw in infile:
            line = raw.strip()
            if line.startswith("#"):
                time_ns = int(line[1:]) / 1000
            elif line and line[0] in "b01xXzZ":
                if line[0] == "b":
                    bits, code = line[1:].split()
                else:
                    bits, code = line[0], line[1:]
                if code in codes:
                    value = None if set(bits.lower()) & {"x", "z"} else int(bits, 2)
                    events[codes[code]].append((time_ns, value))
    return events


def plot_directed_waveforms(path, out_dir):
    names = ("req", "miss", "hit", "dirty_evict", "mem_req", "mem_we", "mem_ready", "ready")
    selected = {f"tb_directed.{name}": name for name in ("req", "miss", "hit", "dirty_evict", "ready")}
    selected.update({f"tb_directed.dut.{name}": name for name in ("mem_req", "mem_we", "mem_ready")})
    selected["tb_directed.test_case_id"] = "case"
    events = directed_events(path, selected)
    case_starts = {case: time for time, case in events["case"]}
    dirty_start = case_starts[7]
    dirty_completion = next(time for time, value in events["ready"] if time > dirty_start and value == 1)
    windows = (
        (case_starts[1], case_starts[3], "TC-01 / TC-02  |  Cold read followed by a hit"),
        (dirty_start, min(case_starts[8], dirty_completion + 10),
         "TC-07  |  Dirty write-back followed by refill (first request)"),
    )
    fig, axes = plt.subplots(2, 1, figsize=(8.2, 5.3), layout="constrained")
    for ax, (start, end, title) in zip(axes, windows):
        for lane, name in enumerate(reversed(names)):
            series = events[name]
            previous = [value for time, value in series if time <= start][-1]
            window = [(start, previous), *((t, v) for t, v in series if start < t <= end)]
            window.append((end, window[-1][1]))
            ax.step([time for time, _ in window],
                    [lane + 0.65 * value for _, value in window], where="post",
                    color="#2166ac" if name.startswith("mem_") else "#7f2704", linewidth=1.15)
        ax.set(title=title, xlim=(start, end), ylim=(-0.2, len(names)),
               yticks=np.arange(len(names)) + 0.32, yticklabels=names[::-1],
               xlabel="Simulation time (ns)")
        ax.grid(True, axis="x")
    save_figure(fig, out_dir, "directed_waveforms")


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
            vals = [data[trace][cfg] for cfg in configs]
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
    save_figure(fig, out_dir, "hit_rate_by_config")


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

    for trace, (color, style, label) in TRACE_STYLES.items():
        y = [data[trace][latency] for latency in latencies]
        ax.plot(latencies, y, style, color=color, label=label)

    ax.set_xlabel("Backing Memory Latency (Cycles)")
    ax.set_ylabel("Average Memory Access Time (Cycles / Access)")
    ax.set_title("AMAT vs Memory Latency Sensitivity (Default 4 KB, 16-Byte Blocks)")
    ax.set_xticks(latencies)
    ax.grid(True)
    ax.legend(loc="upper left", framealpha=0.95)

    plt.tight_layout()
    save_figure(fig, out_dir, "amat_vs_latency")


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
            d = rows[key]
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

    ax.set_ylabel("Misses (count per 1,024 accesses)")
    ax.set_xlabel("Workload and cache geometry")
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
    save_figure(fig, out_dir, "miss_classification_breakdown")


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
    ax1.set_xlabel("Cache geometry")
    ax1.set_ylabel("Hit Count", color="#2ca02c")
    ax1_twin.set_ylabel("Total Cycles", color="#d62728")
    ax1.set_title("Conflict Ping-Pong: Hits vs Total Cycles")
    ax1.grid(True, axis="y")

    # Subplot 2: AMAT transition
    ax2.plot(cfgs, amats, "o-", color="#8c564b", linewidth=2.2, markersize=8)
    for i, txt in enumerate(amats):
        ax2.annotate(f"{txt:.2f} cyc", (cfgs[i], txt + 0.6), ha="center", fontsize=9, fontweight="bold")
    ax2.set_xlabel("Cache geometry")
    ax2.set_ylabel("AMAT (Cycles / Access)")
    ax2.set_title("Conflict ping-pong: AMAT decreases at 8 KiB")
    ax2.set_ylim(0, 19)
    ax2.grid(True)

    ax1.legend(loc="upper center", handles=[ax1.containers[0], ax1_twin.containers[0]])
    plt.tight_layout()
    save_figure(fig, out_dir, "conflict_resolution_amat")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directed-vcd", type=Path, help="VCD generated by tb_directed +DUMP")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    results_dir = repo_root / "results"
    out_dir = results_dir / "plots"
    out_dir.mkdir(parents=True, exist_ok=True)

    setup_style()
    print(f"Generating plots in {out_dir}...")
    verify_miss_classification(results_dir)
    plot_hit_rate_slice(results_dir, out_dir, name="cache_size", field="cache_size_kib",
                        values=[size // 1024 for size in DEFAULT_CACHE_SIZES],
                        xlabel="Cache size (KiB)", title="Hit rate at 16 B per block")
    plot_hit_rate_slice(results_dir, out_dir, name="block_size", field="block_size_bytes",
                        values=DEFAULT_BLOCK_SIZES,
                        xlabel="Block size (B)", title="Hit rate at 4 KiB cache size")
    plot_amat_by_config(results_dir, out_dir)
    plot_hit_rate_by_config(repo_root, out_dir)
    plot_amat_vs_latency(repo_root, out_dir)
    plot_miss_classification_breakdown(repo_root, out_dir)
    plot_conflict_resolution_amat(repo_root, out_dir)
    if args.directed_vcd:
        plot_directed_waveforms(args.directed_vcd, out_dir)
    print("[SUCCESS] All plots generated successfully!")


if __name__ == "__main__":
    main()
