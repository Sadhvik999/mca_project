#!/usr/bin/env python3
"""Run parameterized cache sweeps across all four workloads.

Iterates over sequential, strided, conflict, and random traces across all 12
(CACHE_SIZE, BLOCK_SIZE) configurations using `scripts/run_sweep.py`.
Generates:
  - results/sweep_<trace>.csv for each workload
  - results/sweep_all_traces.csv (consolidated hardware counters)
  - results/param_sweeps_amat.csv (with AMAT, hit/miss rates, and miss penalties)
"""

import argparse
import csv
import subprocess
import sys
from pathlib import Path

TRACES = ["sequential", "strided", "conflict", "random"]
DEFAULT_CONFIGS = [
    "1024:8", "1024:16", "1024:32",
    "2048:8", "2048:16", "2048:32",
    "4096:8", "4096:16", "4096:32",
    "8192:8", "8192:16", "8192:32",
]


def main():
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--traces",
        nargs="+",
        default=TRACES,
        help="Traces to sweep (default: sequential, strided, conflict, random)",
    )
    parser.add_argument(
        "--mem-latency",
        type=int,
        default=10,
        help="Backing memory latency cycles (default: 10)",
    )
    parser.add_argument(
        "--skip-simulation",
        action="store_true",
        help="Skip Verilog simulation if individual sweep CSVs already exist",
    )
    args = parser.parse_args()

    results_dir = repo_root / "results"
    results_dir.mkdir(parents=True, exist_ok=True)
    sweep_script = repo_root / "scripts" / "run_sweep.py"
    amat_script = repo_root / "scripts" / "amat.py"

    all_rows = []

    for trace_name in args.traces:
        trace_file = f"{trace_name}.txt"
        trace_csv = results_dir / f"sweep_{trace_name}.csv"

        if not (args.skip_simulation and trace_csv.is_file()):
            print(f"\n>>> Running Verilog parameter sweep for: {trace_name} <<<")
            cmd = [
                sys.executable,
                str(sweep_script),
                "--trace", trace_file,
                "--mem-latency", str(args.mem_latency),
                "--output", str(trace_csv),
                "--overwrite",
            ]
            subprocess.run(cmd, check=True)

        # Read back results and tag with trace name
        with trace_csv.open("r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                all_rows.append({
                    "trace": trace_name,
                    **row,
                })

    # Write consolidated raw sweep counters
    consolidated_csv = results_dir / "sweep_all_traces.csv"
    fieldnames = ["trace", "config", "accesses", "hits", "misses", "writebacks", "cycles"]
    with consolidated_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(all_rows)
    print(f"\n[INFO] Consolidated {len(all_rows)} runs into {consolidated_csv}")

    # Compute AMAT table using scripts/amat.py
    amat_output_csv = results_dir / "param_sweeps_amat.csv"
    print(f"[INFO] Computing AMAT table using {amat_script} -> {amat_output_csv}")
    subprocess.run([
        sys.executable,
        str(amat_script),
        str(consolidated_csv),
        "--output",
        str(amat_output_csv),
    ], check=True)

    print("[SUCCESS] All multi-trace parameterized sweeps completed successfully!")


if __name__ == "__main__":
    main()
