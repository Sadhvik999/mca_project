#!/usr/bin/env python3
"""Run parameterized cache sweeps across all four workloads.

Iterates over sequential, strided, conflict, and random traces across all 12
(CACHE_SIZE, BLOCK_SIZE) configurations using `scripts/run_sweep.py`.
Generates:
  - results/sweep_<trace>.csv for each workload
  - results/sweep_all_traces.csv (consolidated hardware counters)
  - results/param_sweeps_amat.csv (with AMAT, hit/miss rates, and miss penalties)
  - results/sweep_cache_size.csv and sweep_block_size.csv (slices of the grid)
  - results/latency_sweep.csv and amat_table.csv (with --latency-sweep)
"""

import argparse
import csv
import subprocess
import sys
from pathlib import Path

from run_sweep import CSV_HEADER, format_config, run_single_config

TRACES = ["sequential", "strided", "conflict", "random"]
LATENCIES = (5, 10, 20, 50)


def write_rows(path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_sweep_slices(results_dir, amat_csv, mem_latency):
    with amat_csv.open(newline="", encoding="utf-8") as input_file:
        reader = csv.DictReader(input_file)
        fields = ["trace", "cache_size_kib", "block_size_bytes", "mem_latency"]
        fields.extend(field for field in reader.fieldnames if field != "trace")
        rows = []
        for row in reader:
            cache, block = row["config"].split("_")
            rows.append({
                **row,
                "cache_size_kib": int(cache.removesuffix("KB")),
                "block_size_bytes": int(block.removesuffix("B")),
                "mem_latency": mem_latency,
            })
    for name, field, value in (
        ("cache_size", "block_size_bytes", 16),
        ("block_size", "cache_size_kib", 4),
    ):
        path = results_dir / f"sweep_{name}.csv"
        write_rows(path, fields, (row for row in rows if row[field] == value))
        print(f"Wrote {path}")


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
    parser.add_argument(
        "--latency-sweep",
        action="store_true",
        help="Also simulate 5, 10, 20 and 50 cycles at 4 KiB / 16 B",
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
    write_rows(consolidated_csv, ["trace", *CSV_HEADER], all_rows)
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
    if not args.skip_simulation:
        write_sweep_slices(results_dir, amat_output_csv, args.mem_latency)

    if args.latency_sweep:
        baseline = {
            row["trace"]: {field: row[field] for field in CSV_HEADER}
            for row in all_rows if row["config"] == format_config(4096, 16)
        }
        latency_rows = []
        for latency in LATENCIES:
            for trace in args.traces:
                if latency == args.mem_latency and not args.skip_simulation:
                    row = baseline[trace]
                else:
                    row = run_single_config(repo_root, f"traces/{trace}.txt", 4096, 16, latency)
                latency_rows.append({"trace": trace, "mem_latency": latency, **row})
        latency_csv = results_dir / "latency_sweep.csv"
        write_rows(latency_csv, ["trace", "mem_latency", *CSV_HEADER], latency_rows)
        subprocess.run([
            sys.executable, str(amat_script), str(latency_csv),
        ], check=True)

    print("[SUCCESS] All multi-trace parameterized sweeps completed successfully!")


if __name__ == "__main__":
    main()
