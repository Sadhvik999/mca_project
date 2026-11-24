#!/usr/bin/env python3
"""Calculate AMAT in cycles from tb_trace counter CSVs."""

import argparse
import csv
from pathlib import Path

COUNTER_FIELDS = ("accesses", "hits", "misses", "cycles")
METRIC_FIELDS = (
    "hit_rate", "miss_rate", "hit_time_cycles", "miss_penalty_cycles", "amat_cycles",
)
# The back-to-back trace driver starts with one idle edge. Each hit then
# occupies a request-capture edge and a completion edge.
STARTUP_CYCLES = 1
HIT_TIME_CYCLES = 2
DEFAULT_OUTPUT = Path(__file__).resolve().parent.parent / "results" / "amat_table.csv"


def calculate_metrics(row):
    accesses, hits, misses, cycles = (int(row[field]) for field in COUNTER_FIELDS)
    if accesses <= 0 or min(hits, misses) < 0 or accesses != hits + misses:
        raise ValueError("accesses must be positive and equal hits plus misses")

    # The remaining elapsed cycles cover miss handling, including any dirty
    # write-backs. Each miss is already charged the hit-path baseline.
    extra_cycles = cycles - STARTUP_CYCLES - accesses * HIT_TIME_CYCLES
    if extra_cycles < 0 or (misses == 0 and extra_cycles != 0):
        raise ValueError("cycle count is inconsistent with tb_trace timing")

    hit_rate = hits / accesses
    miss_rate = misses / accesses
    penalty = extra_cycles / misses if misses else 0
    amat = HIT_TIME_CYCLES + miss_rate * penalty
    return {
        "hit_rate": f"{hit_rate:.6f}",
        "miss_rate": f"{miss_rate:.6f}",
        "hit_time_cycles": HIT_TIME_CYCLES,
        "miss_penalty_cycles": f"{penalty:.6f}" if misses else "",
        "amat_cycles": f"{amat:.6f}",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("counters", type=Path, help="CSV written from tb_trace counters")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    rows = []
    try:
        with args.counters.open(newline="", encoding="utf-8") as input_file:
            reader = csv.DictReader(input_file)
            fields = reader.fieldnames or []
            missing = [field for field in COUNTER_FIELDS if field not in fields]
            if missing:
                parser.error("missing CSV columns: " + ", ".join(missing))
            for row in reader:
                if None in row or None in row.values():
                    parser.error(f"{args.counters}:{reader.line_num}: incomplete or extra fields")
                try:
                    rows.append({**row, **calculate_metrics(row)})
                except ValueError as error:
                    parser.error(f"{args.counters}:{reader.line_num}: {error}")
            if not rows:
                parser.error("the counters CSV has no data rows")

        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", newline="", encoding="utf-8") as output_file:
            fieldnames = list(dict.fromkeys([*fields, *METRIC_FIELDS]))
            writer = csv.DictWriter(output_file, fieldnames=fieldnames, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
    except (OSError, UnicodeError, csv.Error) as error:
        parser.error(str(error))

    print(f"Wrote AMAT for {len(rows)} runs to {args.output}")


if __name__ == "__main__":
    main()
