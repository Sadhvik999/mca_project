# Behavioral Main Memory Model Specification

This document defines the hardware interface, cycle-accurate handshake protocol, block alignment semantics, and modeling assumptions for the backing main memory module (`rtl/main_memory.v`).

---

## 1. Module Parameters & Interface

### Parameters
| Parameter | Default | Description |
|---|---|---|
| `MEM_LATENCY` | `10` | Fixed access latency in clock cycles from request acceptance |
| `MEM_SIZE_WORDS` | `65536` | Backing memory capacity in 32-bit words ($65536 \times 4\text{ B} = 256\text{ KB}$) |
| `BLOCK_SIZE` | `16` | Transfer block width in bytes (4 words = 128 bits) |
| `ADDR_WIDTH` | `32` | Physical byte address width from cache controller |
| `INIT_FILE` | `"traces/mem_init.hex"` | Hex initialization image loaded via `$readmemh` |

### Port Specification
| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 | System clock (positive-edge triggered) |
| `rst` | Input | 1 | Active-high synchronous reset (resets FSM/counters; preserves `$readmemh` memory contents) |
| `mem_req` | Input | 1 | Request valid from cache controller; initiates a block read or write when memory is idle |
| `mem_we` | Input | 1 | Write enable (`1` = 128-bit block write-back, `0` = 128-bit block read/allocate) |
| `mem_addr` | Input | 32 | Target byte address; lower 4 bits `[3:0]` are ignored for 16-byte block alignment |
| `mem_wdata` | Input | 128 | 16-byte block written to memory during `WRITE_BACK` (`mem_we = 1`) |
| `mem_rdata` | Output | 128 | 16-byte block returned by memory during `ALLOCATE` (`mem_we = 0`) |
| `mem_ready` | Output | 1 | Single-cycle completion pulse indicating write completion or valid `mem_rdata` |

---

## 2. Block-Wide Transfers & Alignment

The cache-to-memory bus transfers an entire **16-byte cache block (128 bits)** per transaction rather than individual 32-bit words.

### Address Alignment
- Any byte address `mem_addr[31:0]` maps to its enclosing 16-byte aligned block by zeroing the lower 4 bits:
  $$\text{Aligned Block Byte Address} = \{\text{mem\_addr}[31:4],\; 4'\text{b}0000\}$$
- Because `MEM_SIZE_WORDS = 65536` covers $256\text{ KB}$ ($2^{18}$ bytes, byte addresses `0x00000`–`0x3FFFF`), word indexing uses `mem_addr[17:2]`.
- The base word index of the aligned block is:
  $$\text{base\_word\_idx} = \{\text{mem\_addr}[17:4],\; 2'\text{b}00\}$$
- Consequently, unaligned addresses such as `0x0000_0200`, `0x0000_0204`, `0x0000_0208`, and `0x0000_020F` all map cleanly to the same aligned block starting at `0x0000_0200`.

### 128-bit Word Packing Order (Little-Endian Word Layout)
| 128-bit Bus Slice | Word Offset | Memory Word Index | Byte Offsets in Block |
|---|---|---|---|
| `[31:0]` | Word 0 | `base_word_idx + 0` | `+0x0 .. +0x3` |
| `[63:32]` | Word 1 | `base_word_idx + 1` | `+0x4 .. +0x7` |
| `[95:64]` | Word 2 | `base_word_idx + 2` | `+0x8 .. +0xB` |
| `[127:96]` | Word 3 | `base_word_idx + 3` | `+0xC .. +0xF` |

---

## 3. Latency Behaviour & Handshake Timing

`main_memory.v` uses a three-state internal controller (`S_IDLE`, `S_WAIT`, `S_DONE`):

1. **`S_IDLE`**:
   - Monitors `mem_req`. When `mem_req == 1`, it latches `mem_addr`, `mem_we`, and `mem_wdata` on that rising clock edge (Cycle 0) and initializes a wait counter (`count <= 1`).
   - Latching on acceptance means the controller only needs `mem_req` and operands stable on the acceptance cycle (though a Moore FSM typically keeps them steady until `mem_ready`).
2. **`S_WAIT`**:
   - Holds `mem_ready = 0` while incrementing `count` once per clock cycle.
   - On Cycle `MEM_LATENCY - 1` (Cycle 9 for `MEM_LATENCY = 10`):
     - If `req_we == 1`, writes all 4 words of `req_wdata` into `mem[base_word_idx .. base_word_idx+3]`.
     - If `req_we == 0`, drives `mem_rdata` with `{mem[base+3], mem[base+2], mem[base+1], mem[base+0]}`.
     - Sets `mem_ready <= 1` and transitions to `S_DONE`.
3. **`S_DONE`**:
   - Keeps `mem_ready = 1` for exactly **one clock period** (from Cycle 9's posedge until Cycle 10's posedge), so synchronous consumers sample `mem_ready == 1` on **Cycle 10** (`10` cycles after Cycle 0).
   - At Cycle 10's posedge, `mem_ready` returns to `0` and the FSM returns to `S_IDLE`.
   - Ignoring `mem_req` during `S_DONE` prevents a Moore cache controller (which deasserts or switches `mem_req` synchronously upon seeing `mem_ready == 1` at Cycle 10) from accidentally re-triggering on the old request. A back-to-back transaction (e.g., `WRITE_BACK` followed immediately by `ALLOCATE`) begins cleanly on Cycle 11.

### ASCII Timing Diagram (`MEM_LATENCY = 10`)

```text
Cycle       :   0     1     2         8     9    10    11    12
              ___   ___   ___       ___   ___   ___   ___   ___
clk         _|   |_|   |_|   |_..._|   |_|   |_|   |_|   |_|   |_
               _________________________________
mem_req     __/                                 \________________
            --<         Aligned / Req Addr      >----------------
mem_addr
            --<   mem_we (0=Read, 1=Write)      >----------------
mem_we
                                            _____
mem_ready   _______________________________/     \_______________
                                            <----------->
mem_rdata   -------------------------------< Valid Block >-------
              ^                             ^     ^
              |                             |     |
        Req accepted                  mem_ready   Sampled by controller
        (S_IDLE -> S_WAIT)            asserted    at Cycle 10 (10 cycles
                                      at Cycle 9  after Cycle 0); S_DONE
                                                  clears mem_ready -> 0
```

---

## 4. Initialization via `$readmemh`

- At time 0 (`initial` block), `main_memory` invokes `$readmemh(INIT_FILE, mem)` to preload all `65536` 32-bit words from `traces/mem_init.hex`.
- Each line in `traces/mem_init.hex` stores an 8-digit hex word equal to its word address (`00000000` through `0000ffff`), generated by `scripts/gen_mem_init.py`.
- Asserting synchronous `rst` resets only the controller FSM (`S_IDLE`), cycle counter, `mem_ready`, and `mem_rdata` output register—preserving the preloaded memory contents.

---

## 5. Differences from Real DRAM Hardware

While `main_memory.v` accurately models the **block-transfer latency penalty** seen by the cache controller, it abstracts away physical DRAM complexities:

1. **Fixed vs. Variable Access Latency**: Real DDR SDRAM latency depends on row-buffer locality (row hit vs. row miss vs. row conflict, governed by `tRCD`, `tCAS`, and `tRP`). This model uses a constant `MEM_LATENCY = 10` cycles for every read and write.
2. **No Refresh Overhead**: Physical DRAM cells leak charge and require periodic `AUTO REFRESH` commands (`tREFI` / `tRFC`), stalling requests unpredictably. Our behavioral SRAM-style array is non-volatile during simulation.
3. **Wide Parallel Block Bus vs. Narrow Burst Transfers**: Real DRAM interfaces move data in sequential bursts (e.g., BL4 or BL8) over narrower 16/32/64-bit double-data-rate (DDR) pins with multiplexed row/column addressing. Here, all 128 bits are transferred in parallel on `mem_wdata`/`mem_rdata` when `mem_ready` pulses.
4. **No Bank/Rank Scheduling or Out-of-Order Completion**: Real memory controllers reorder queued requests across multiple banks and channels. Because our L1 cache is blocking (one outstanding request at a time), a simple single-request FSM suffices.
5. **Bounded Modulo Address Space**: To remain lightweight in simulation, storage is sized to `65536` words (`256 KB`), wrapping addresses above `0x3FFFF` via `mem_addr[17:2]` rather than implementing gigabyte-scale sparse memory.
