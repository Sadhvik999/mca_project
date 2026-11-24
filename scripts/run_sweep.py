#!/usr/bin/env python3
"""Run parameterized cache sweeps across (CACHE_SIZE, BLOCK_SIZE) configs.

For a given trace file in traces/ and a list of configurations, this script:
  1. Compiles rtl/*.v + tb/tb_trace.v with iverilog -P parameter overrides
  2. Executes the simulation with vvp +TRACE=<trace>
  3. Parses Accesses, Hits, Misses, Write-backs, and Total cycles
  4. Appends rows (config, accesses, hits, misses, writebacks, cycles) to
     results/<name>.csv
"""

import argparse
import csv
import glob
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_CACHE_SIZES = (1024, 2048, 4096, 8192)
DEFAULT_BLOCK_SIZES = (8, 16, 32)
DEFAULT_CONFIGS = [
    (cs, bs) for cs in DEFAULT_CACHE_SIZES for bs in DEFAULT_BLOCK_SIZES
]

CSV_HEADER = ["config", "accesses", "hits", "misses", "writebacks", "cycles"]

COUNTER_PATTERNS = {
    "accesses": re.compile(r"^\s*Accesses:\s+(\d+)\s*$", re.MULTILINE),
    "hits": re.compile(r"^\s*Hits:\s+(\d+)\s*$", re.MULTILINE),
    "misses": re.compile(r"^\s*Misses:\s+(\d+)\s*$", re.MULTILINE),
    "writebacks": re.compile(r"^\s*Write-backs:\s+(\d+)\s*$", re.MULTILINE),
    "cycles": re.compile(r"^\s*Total cycles:\s+(\d+)\s*$", re.MULTILINE),
}


def parse_config(spec: str) -> tuple[int, int]:
    """Parse a config token such as '1024:8', '1024x8', '4096,16', or '4KB_16B'."""
    token = spec.strip().upper()
    match = re.fullmatch(r"(\d+)(K?B)?[:x,_](\d+)B?", token)
    if not match:
        raise argparse.ArgumentTypeError(
            f"Invalid config '{spec}'. Use e.g. '4096:16' or '4KB_16B'."
        )
    cs = int(match.group(1))
    if match.group(2) == "KB":
        cs *= 1024
    bs = int(match.group(3))
    if cs <= 0 or bs < 4 or (cs & (cs - 1)) != 0 or (bs & (bs - 1)) != 0 or bs > cs:
        raise argparse.ArgumentTypeError(
            f"Invalid power-of-two geometry in config '{spec}'."
        )
    return cs, bs


def format_config(cache_size: int, block_size: int) -> str:
    if cache_size % 1024 == 0:
        return f"{cache_size // 1024}KB_{block_size}B"
    return f"{cache_size}B_{block_size}B"


def resolve_trace_path(repo_root: Path, trace_arg: str) -> Path:
    candidate = Path(trace_arg)
    if candidate.is_file():
        return candidate.resolve()
    in_traces = repo_root / "traces" / trace_arg
    if in_traces.is_file():
        return in_traces.resolve()
    raise FileNotFoundError(f"Trace file not found: {trace_arg}")


def run_single_config(
    repo_root: Path,
    trace_rel: str,
    cache_size: int,
    block_size: int,
    mem_latency: int,
) -> dict[str, int | str]:
    build_dir = repo_root / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    cfg_name = format_config(cache_size, block_size)
    vvp_path = build_dir / f"tb_trace_{cfg_name}.vvp"
    rtl_files = sorted(glob.glob(str(repo_root / "rtl" / "*.v")))
    tb_file = str(repo_root / "tb" / "tb_trace.v")

    compile_cmd = [
        "iverilog",
        "-g2012",
        "-Wall",
        "-s",
        "tb_trace",
        "-P",
        f"tb_trace.CACHE_SIZE={cache_size}",
        "-P",
        f"tb_trace.BLOCK_SIZE={block_size}",
        "-P",
        f"tb_trace.MEM_LATENCY={mem_latency}",
        "-o",
        str(vvp_path),
        *rtl_files,
        tb_file,
    ]
    comp = subprocess.run(compile_cmd, cwd=repo_root, capture_output=True, text=True)
    if comp.returncode != 0:
        raise RuntimeError(
            f"iverilog failed for {cfg_name}:\n{comp.stdout}\n{comp.stderr}"
        )

    sim_cmd = ["vvp", str(vvp_path), f"+TRACE={trace_rel}"]
    sim = subprocess.run(sim_cmd, cwd=repo_root, capture_output=True, text=True)
    if sim.returncode != 0 or "PASS:" not in sim.stdout:
        raise RuntimeError(
            f"Simulation failed for {cfg_name}:\n{sim.stdout}\n{sim.stderr}"
        )

    parsed: dict[str, int | str] = {"config": cfg_name}
    for key, pattern in COUNTER_PATTERNS.items():
        m = pattern.search(sim.stdout)
        if not m:
            raise RuntimeError(f"Could not parse '{key}' from output for {cfg_name}")
        parsed[key] = int(m.group(1))

    vvp_path.unlink(missing_ok=True)
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--trace",
        default="traces/sequential.txt",
        help="Path to trace file (or filename inside traces/). Default: traces/sequential.txt",
    )
    parser.add_argument(
        "--configs",
        nargs="+",
        type=parse_config,
        default=DEFAULT_CONFIGS,
        help="Configurations as <CACHE_SIZE>:<BLOCK_SIZE> (default: all 12 configs)",
    )
    parser.add_argument(
        "--name",
        default=None,
        help="Output CSV name stem inside results/ (writes results/<name>.csv)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Explicit output CSV path (overrides --name)",
    )
    parser.add_argument(
        "--mem-latency",
        type=int,
        default=10,
        help="Backing memory latency in cycles (default: 10)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite output CSV instead of appending rows",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    trace_path = resolve_trace_path(repo_root, args.trace)
    try:
        trace_rel = str(trace_path.relative_to(repo_root))
    except ValueError:
        trace_rel = str(trace_path)

    if args.output is not None:
        csv_path = args.output if args.output.is_absolute() else repo_root / args.output
    else:
        stem = args.name or f"sweep_{trace_path.stem}"
        csv_path = repo_root / "results" / f"{stem}.csv"

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    if args.overwrite and csv_path.exists():
        csv_path.unlink()

    write_header = not csv_path.exists() or csv_path.stat().st_size == 0

    print(f"Running sweep on trace: {trace_rel} -> {csv_path}")
    print(f"{'config':<10} {'accesses':>10} {'hits':>10} {'misses':>10} {'writebacks':>12} {'cycles':>10}")
    print("-" * 66)

    with csv_path.open("a", newline="", encoding="ascii") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_HEADER, lineterminator="\n")
        if write_header:
            writer.writeheader()
            f.flush()

        for cs, bs in args.configs:
            row = run_single_config(repo_root, trace_rel, cs, bs, args.mem_latency)
            writer.writerow(row)
            f.flush()
            print(
                f"{row['config']:<10} {row['accesses']:>10} {row['hits']:>10} "
                f"{row['misses']:>10} {row['writebacks']:>12} {row['cycles']:>10}"
            )

    return 0


if __name__ == "__main__":
    sys.exit(main())
