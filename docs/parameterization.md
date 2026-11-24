# Parameterized Cache Design Specification

This document specifies how the direct-mapped L1 cache controller scales across all **12 supported `(CACHE_SIZE, BLOCK_SIZE)` configurations** (`CACHE_SIZE` $\in \{1024, 2048, 4096, 8192\}$ bytes, `BLOCK_SIZE` $\in \{8, 16, 32\}$ bytes, `ADDR_WIDTH = 32` bits).

---

## 1. Derived Parameters (`$clog2` Formulas)

Every RTL module (`tag_array.v`, `data_array.v`, `cache_controller.v`, `cache_top.v`, and `main_memory.v`) derives its geometry from top-level parameters using Verilog `$clog2` and `localparam` expressions:

$$\text{NUM\_LINES} = \frac{\text{CACHE\_SIZE}}{\text{BLOCK\_SIZE}}$$

$$\text{OFFSET\_BITS} = \log_2(\text{BLOCK\_SIZE}) = \underbrace{(\text{OFFSET\_BITS} - 2)}_{\text{Word Offset}} + \underbrace{2}_{\text{Byte Offset}}$$

$$\text{INDEX\_BITS} = \log_2(\text{NUM\_LINES})$$

$$\text{TAG\_BITS} = \text{ADDR\_WIDTH} - \text{INDEX\_BITS} - \text{OFFSET\_BITS}$$

$$\text{DATA\_WIDTH} = \text{BLOCK\_SIZE} \times 8 \text{ bits} \quad (\text{Words/Block} = \text{BLOCK\_SIZE} / 4)$$

---

## 2. All 12 Configuration Bit-Width & Slice Table

| Config | `CACHE_SIZE` | `BLOCK_SIZE` | `NUM_LINES` | `TAG_BITS` | `INDEX_BITS` | `OFFSET_BITS` (`word`+`byte`) | `DATA_WIDTH` | Address Split `[Tag | Index | Word | Byte]` |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `1KB_8B`   | 1024 B | 8 B  | 128  | 22 | 7  | 3 (`1+2`) | 64 b  | `[31:10] \| [9:3]  \| [2]   \| [1:0]` |
| `1KB_16B`  | 1024 B | 16 B | 64   | 22 | 6  | 4 (`2+2`) | 128 b | `[31:10] \| [9:4]  \| [3:2] \| [1:0]` |
| `1KB_32B`  | 1024 B | 32 B | 32   | 22 | 5  | 5 (`3+2`) | 256 b | `[31:10] \| [9:5]  \| [4:2] \| [1:0]` |
| `2KB_8B`   | 2048 B | 8 B  | 256  | 21 | 8  | 3 (`1+2`) | 64 b  | `[31:11] \| [10:3] \| [2]   \| [1:0]` |
| `2KB_16B`  | 2048 B | 16 B | 128  | 21 | 7  | 4 (`2+2`) | 128 b | `[31:11] \| [10:4] \| [3:2] \| [1:0]` |
| `2KB_32B`  | 2048 B | 32 B | 64   | 21 | 6  | 5 (`3+2`) | 256 b | `[31:11] \| [10:5] \| [4:2] \| [1:0]` |
| `4KB_8B`   | 4096 B | 8 B  | 512  | 20 | 9  | 3 (`1+2`) | 64 b  | `[31:12] \| [11:3] \| [2]   \| [1:0]` |
| **`4KB_16B` (Default)** | **4096 B** | **16 B** | **256** | **20** | **8** | **4 (`2+2`)** | **128 b** | **`[31:12] \| [11:4] \| [3:2] \| [1:0]`** |
| `4KB_32B`  | 4096 B | 32 B | 128  | 20 | 7  | 5 (`3+2`) | 256 b | `[31:12] \| [11:5] \| [4:2] \| [1:0]` |
| `8KB_8B`   | 8192 B | 8 B  | 1024 | 19 | 10 | 3 (`1+2`) | 64 b  | `[31:13] \| [12:3] \| [2]   \| [1:0]` |
| `8KB_16B`  | 8192 B | 16 B | 512  | 19 | 9  | 4 (`2+2`) | 128 b | `[31:13] \| [12:4] \| [3:2] \| [1:0]` |
| `8KB_32B`  | 8192 B | 32 B | 256  | 19 | 8  | 5 (`3+2`) | 256 b | `[31:13] \| [12:5] \| [4:2] \| [1:0]` |

---

## 3. How the Address Split Scales

1. **Invariant Tag Width at Fixed `CACHE_SIZE`**:
   Because a direct-mapped cache has 1 way per set,
   $$\text{INDEX\_BITS} + \text{OFFSET\_BITS} = \log_2\left(\frac{\text{CACHE\_SIZE}}{\text{BLOCK\_SIZE}}\right) + \log_2(\text{BLOCK\_SIZE}) = \log_2(\text{CACHE\_SIZE}).$$
   Consequently, `TAG_BITS = 32 - log2(CACHE_SIZE)` depends **only** on total cache capacity: 22 bits for 1 KB, 21 bits for 2 KB, 20 bits for 4 KB, and 19 bits for 8 KB.
2. **Effect of Doubling `BLOCK_SIZE` (at Fixed `CACHE_SIZE`)**:
   - `OFFSET_BITS` increases by 1 bit (word offset grows `1 -> 2 -> 3` bits, doubling `DATA_WIDTH` from 64 to 128 to 256 bits).
   - `NUM_LINES` halves, so `INDEX_BITS` decreases by 1 bit.
   - `TAG_BITS` and the Tag/Index boundary stay fixed (e.g., always at bit 12 for 4 KB).
3. **Effect of Doubling `CACHE_SIZE` (at Fixed `BLOCK_SIZE`)**:
   - `NUM_LINES` doubles, so `INDEX_BITS` grows by 1 bit toward the MSB.
   - `TAG_BITS` shrinks by 1 bit, while `OFFSET_BITS` and `DATA_WIDTH` stay constant.
4. **Backing Memory Block Alignment**:
   In `rtl/main_memory.v`, `WORDS_PER_BLOCK = BLOCK_SIZE / 4` (2, 4, or 8 words) and `mem_wdata`/`mem_rdata` scale to `BLOCK_SIZE * 8` bits. Memory masks `OFFSET_BITS` low address bits so every block transfer aligns automatically to 8-, 16-, or 32-byte boundaries.

---

## 4. Verification & Sweep Commands

```bash
# Verify all 12 (CACHE_SIZE, BLOCK_SIZE) configurations with tb_param_check
./scripts/check_params.sh

# Run a trace sweep across all 12 configurations into results/sweep_<name>.csv
python3 scripts/run_sweep.py --trace traces/sequential.txt --name sweep_sequential
```
