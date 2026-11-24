#!/usr/bin/env python3
"""Miss classification analyzer for direct-mapped caches.

Implements the classic 3Cs miss classification model (Mark D. Hill 1988,
Hennessy & Patterson) for trace-driven cache architectures:
  - Compulsory (cold) miss: Occurs on the first reference to a memory block.
    These misses would occur even in an infinite cache.
  - Capacity miss: Occurs when the working set exceeds cache capacity,
    measured as misses in a fully-associative cache of the same capacity
    with LRU replacement that are not compulsory.
  - Conflict miss: Occurs in a direct-mapped cache because multiple active
    blocks map to the same set/line, which would hit in a fully-associative
    cache of the same capacity.

Outputs a consolidated breakdown across workloads and geometries to
results/miss_classification.csv.
"""

import argparse
import csv
from collections import OrderedDict
from pathlib import Path

DEFAULT_CACHE_SIZES = (1024, 2048, 4096, 8192)
DEFAULT_BLOCK_SIZES = (8, 16, 32)
DEFAULT_CONFIGS = [
    (cs, bs) for cs in DEFAULT_CACHE_SIZES for bs in DEFAULT_BLOCK_SIZES
]

TRACE_NAMES = ["sequential", "strided", "conflict", "random"]


def format_config(cache_size: int, block_size: int) -> str:
    """Format cache and block size into e.g. '4KB_16B'."""
    if cache_size % 1024 == 0:
        return f"{cache_size // 1024}KB_{block_size}B"
    return f"{cache_size}B_{block_size}B"


def parse_trace(trace_path: Path):
    """Yield (is_write, address) tuples from a trace file."""
    with trace_path.open("r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            is_write = parts[0].upper() == "W"
            addr = int(parts[1], 16)
            yield is_write, addr


def simulate_cache_hierarchy(trace_path: Path, cache_size: int, block_size: int):
    """Simulate infinite, fully-associative LRU, and direct-mapped caches.

    Returns dictionary with miss counts and classifications:
      accesses, hits, total_misses, compulsory_misses, capacity_misses, conflict_misses.
    """
    num_lines = cache_size // block_size
    offset_bits = block_size.bit_length() - 1

    # 1. Infinite cache state: set of unique block addresses seen
    seen_blocks = set()

    # 2. Fully-associative cache state: OrderedDict acting as LRU queue
    fa_capacity = num_lines
    fa_cache = OrderedDict()  # block_addr -> True (most recent at end)

    # 3. Direct-mapped cache state: array of tags
    dm_tags = [None] * num_lines

    accesses = 0
    dm_hits = 0
    dm_misses = 0
    compulsory_misses = 0
    capacity_misses = 0
    conflict_misses = 0

    for is_write, addr in parse_trace(trace_path):
        accesses += 1
        block_addr = addr >> offset_bits
        set_index = block_addr % num_lines
        tag = block_addr // num_lines

        # Direct-mapped lookup
        dm_hit = (dm_tags[set_index] == tag)
        if dm_hit:
            dm_hits += 1
        else:
            dm_misses += 1
            # Classify miss using 3Cs hierarchy:
            if block_addr not in seen_blocks:
                # First reference ever -> Compulsory
                compulsory_misses += 1
            elif block_addr not in fa_cache:
                # Referenced before, but displaced from FA cache -> Capacity
                capacity_misses += 1
            else:
                # Resident in FA cache, but displaced from DM set -> Conflict
                conflict_misses += 1

            # Update DM state on miss
            dm_tags[set_index] = tag

        # Update Infinite cache state
        seen_blocks.add(block_addr)

        # Update Fully-Associative LRU cache state
        if block_addr in fa_cache:
            fa_cache.move_to_end(block_addr)
        else:
            if len(fa_cache) >= fa_capacity:
                fa_cache.popitem(last=False)  # evict least-recently used
            fa_cache[block_addr] = True

    return {
        "accesses": accesses,
        "hits": dm_hits,
        "misses": dm_misses,
        "compulsory": compulsory_misses,
        "capacity": capacity_misses,
        "conflict": conflict_misses,
    }


def main():
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--traces",
        nargs="+",
        default=TRACE_NAMES,
        help="Trace names to evaluate (without .txt suffix)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "results" / "miss_classification.csv",
        help="Path to output CSV file",
    )
    args = parser.parse_args()

    results = []
    print(f"{'Trace':<12} {'Config':<10} {'Accesses':>8} {'Hits':>6} {'Misses':>6} "
          f"{'Compulsory':>10} {'Capacity':>8} {'Conflict':>8} {'%Comp':>7} {'%Conf':>7}")
    print("-" * 90)

    for trace_name in args.traces:
        trace_path = repo_root / "traces" / f"{trace_name}.txt"
        if not trace_path.is_file():
            print(f"Warning: {trace_path} not found, skipping.")
            continue

        for cs, bs in DEFAULT_CONFIGS:
            cfg_name = format_config(cs, bs)
            sim = simulate_cache_hierarchy(trace_path, cs, bs)
            comp = sim["compulsory"]
            cap = sim["capacity"]
            conf = sim["conflict"]
            total_m = sim["misses"]

            comp_pct = (comp / total_m * 100.0) if total_m > 0 else 0.0
            conf_pct = (conf / total_m * 100.0) if total_m > 0 else 0.0

            results.append({
                "trace": trace_name,
                "config": cfg_name,
                "cache_size_bytes": cs,
                "block_size_bytes": bs,
                "accesses": sim["accesses"],
                "hits": sim["hits"],
                "misses": sim["misses"],
                "compulsory_misses": comp,
                "capacity_misses": cap,
                "conflict_misses": conf,
                "compulsory_rate": f"{(comp / sim['accesses']):.6f}",
                "capacity_rate": f"{(cap / sim['accesses']):.6f}",
                "conflict_rate": f"{(conf / sim['accesses']):.6f}",
                "compulsory_pct_of_misses": f"{comp_pct:.2f}",
                "conflict_pct_of_misses": f"{conf_pct:.2f}",
            })

            # Print default or representative rows
            if cfg_name in ("4KB_16B", "8KB_16B"):
                print(f"{trace_name:<12} {cfg_name:<10} {sim['accesses']:>8} "
                      f"{sim['hits']:>6} {sim['misses']:>6} {comp:>10} {cap:>8} "
                      f"{conf:>8} {comp_pct:>6.1f}% {conf_pct:>6.1f}%")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "trace", "config", "cache_size_bytes", "block_size_bytes",
        "accesses", "hits", "misses",
        "compulsory_misses", "capacity_misses", "conflict_misses",
        "compulsory_rate", "capacity_rate", "conflict_rate",
        "compulsory_pct_of_misses", "conflict_pct_of_misses",
    ]
    with args.output.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(results)

    print("-" * 90)
    print(f"Wrote miss classification for {len(results)} configurations to {args.output}")


if __name__ == "__main__":
    main()
