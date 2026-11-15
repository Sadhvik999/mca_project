#!/usr/bin/env python3
"""Generate deterministic main memory initialization hex file (traces/mem_init.hex).

Creates MEM_SIZE_WORDS (65536) 32-bit hex words where each word at word address
`i` is initialized to `i` (0x00000000 through 0x0000FFFF) for $readmemh.
"""

from pathlib import Path

MEM_SIZE_WORDS = 65536


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    out_path = repo_root / "traces" / "mem_init.hex"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="ascii") as f:
        for word_addr in range(MEM_SIZE_WORDS):
            f.write(f"{word_addr:08x}\n")

    print(f"Generated {MEM_SIZE_WORDS} words in {out_path}")


if __name__ == "__main__":
    main()
