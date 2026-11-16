#!/usr/bin/env python3
"""Generate word-aligned access traces for the Phase I cache simulation."""

import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pattern", choices=("sequential",), default="sequential")
    parser.add_argument("--count", type=int, default=1024, help="number of word reads")
    parser.add_argument("--output", type=Path, default=Path("traces/sequential.txt"))
    args = parser.parse_args()

    # Keep the trace inside the simulation model's 256 KiB backing memory.
    if not 1 <= args.count <= 65536:
        parser.error("--count must be between 1 and 65536")

    with args.output.open("w", encoding="ascii", newline="\n") as trace:
        for word in range(args.count):
            trace.write(f"R {4 * word:08X}\n")

    print(f"Wrote {args.count} {args.pattern} word reads to {args.output}")


if __name__ == "__main__":
    main()
