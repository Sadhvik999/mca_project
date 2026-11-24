#!/usr/bin/env python3
"""Generate word-aligned access traces for the cache simulation."""

import argparse
import random
from pathlib import Path


WORD_BYTES = 4
BLOCK_BYTES = 16
CACHE_BYTES = 4096
MEMORY_WORDS = 65536
RANDOM_WORDS = 16 * 1024 // WORD_BYTES
DEFAULT_SEED = 42


def generate_accesses(pattern, count, seed):
    """Yield (byte address, write data), using None for a read."""
    if pattern == "sequential":
        for word in range(count):
            yield WORD_BYTES * word, None
    elif pattern == "strided":
        # The first half visits distinct blocks. Start the second half on a
        # fresh cache-size boundary so its first two blocks are compulsory.
        cold_count = (count + 1) // 2
        conflict_base = ((cold_count * BLOCK_BYTES + CACHE_BYTES - 1)
                         // CACHE_BYTES) * CACHE_BYTES
        for block in range(cold_count):
            yield BLOCK_BYTES * block, None
        for access in range(count - cold_count):
            yield conflict_base + (access % 2) * CACHE_BYTES, None
    elif pattern == "conflict":
        # Both blocks map to index zero. A write to the first block returns
        # through backing memory when that block is next read.
        for access in range(count):
            address = (access % 2) * CACHE_BYTES
            yield address, access + 1 if access % 4 == 0 else None

    elif pattern == "random":
        # A private RNG makes each generated trace reproducible by seed.
        rng = random.Random(seed)
        for _ in range(count):
            address = WORD_BYTES * rng.randrange(RANDOM_WORDS)
            data = rng.getrandbits(32) if rng.randrange(4) == 0 else None
            yield address, data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--pattern", choices=("sequential", "strided", "conflict", "random"),
        default="sequential",
    )
    parser.add_argument("--count", type=int, default=1024, help="number of requests")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED,
                        help="random pattern seed (default: %(default)s)")
    parser.add_argument("--output", type=Path, help="default: traces/<pattern>.txt")
    args = parser.parse_args()

    # Reserve two full cache-size regions after the first strided phase.
    max_count = MEMORY_WORDS
    if args.pattern == "strided":
        max_count = 2 * (MEMORY_WORDS * WORD_BYTES - 2 * CACHE_BYTES) // BLOCK_BYTES
    if not 1 <= args.count <= max_count:
        parser.error(f"--count must be between 1 and {max_count} for {args.pattern}")

    output = args.output or Path("traces") / f"{args.pattern}.txt"
    with output.open("w", encoding="ascii", newline="\n") as trace:
        for address, data in generate_accesses(args.pattern, args.count, args.seed):
            if data is None:
                trace.write(f"R {address:08X}\n")
            else:
                trace.write(f"W {address:08X} {data:08X}\n")

    print(f"Wrote {args.count} {args.pattern} requests to {output}")


if __name__ == "__main__":
    main()
