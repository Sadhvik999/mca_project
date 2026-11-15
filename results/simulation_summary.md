# Phase I Simulation Verification Results

This document summarizes the simulation execution results and verification coverage across all RTL modules implemented by **Member 1 (M1)**, **Member 2 (M2)**, and **Member 3 (M3)**.

---

## Verification Summary Table

| Testbench | Target Module(s) | Lead Member | Assertions / Test Cases | Result | VCD Dump |
|---|---|---|---|---|---|
| `tb/tb_tag_array.v` | `rtl/tag_array.v` | M1 (Mustyala Sadhvik) | 271 assertions checked | **PASS** | `tb/tag_array.vcd` |
| `tb/tb_data_array.v` | `rtl/data_array.v` | M2 (Varun Udata) | 283 assertions checked | **PASS** | `tb/data_array.vcd` |
| `tb/tb_main_memory.v`| `rtl/main_memory.v` | M2 (Varun Udata) | 42 assertions checked | **PASS** | `tb/main_memory.vcd` |
| `tb/tb_smoke.v` | `rtl/cache_top.v` (all modules) | M3 (Amogha Raj Sandur)| 4 end-to-end integration scenarios | **PASS** | `build/smoke.vcd` |

---

## 1. Tag Array Verification (`tb_tag_array.v`)
- **Objective**: Verify 256-line metadata tracking (`{valid, dirty, tag[19:0]}`), reset clearing, single-cycle asynchronous read indexing, write allocation, and selective `set_dirty` assertion on write hits.
- **Log File**: [`results/tag_array_simulation.log`](tag_array_simulation.log)
- **Key Results**:
  - Stage 1: Synchronous reset across all 256 lines initialized to `V=0`, `D=0`, `Tag=0x00000` (PASS).
  - Stage 2: Clean write allocation at index `0x34` (PASS).
  - Stage 3: Dirty write allocation at index `0x56` (PASS).
  - Stage 4: Selective `set_dirty` on clean line marks `D=1` while preserving tag and valid bits (PASS).
  - Stage 5: Addressing isolation across boundary lines (`0x00`, `0x01`, `0x7F`, `0xFE`, `0xFF`) (PASS).
  - Stage 6: Line eviction and overwrite replacement (PASS).
  - Stage 7: Synchronous re-reset invalidation (PASS).
  - **Total**: 271 assertions checked, 0 errors.

---

## 2. Data Array Verification (`tb_data_array.v`)
- **Objective**: Verify 256-line $\times$ 128-bit storage, 32-bit word read multiplexing via `addr[3:2]`, single-word write insertion, full 128-bit block refills, and word isolation.
- **Log File**: [`results/data_array_simulation.log`](data_array_simulation.log)
- **Key Results**:
  - Stage 1: All 256 lines reset to zero (PASS).
  - Stage 2: Single-word write and word read on line `0x12` (PASS).
  - Stage 3: 128-bit block fill and word-offset reads (`0` to `3`) on line `0x34` (PASS).
  - Stage 4: Word write isolation ensuring neighboring words are unaffected (PASS).
  - Stage 5: Boundary line addressing (`0x00`, `0x01`, `0xFE`, `0xFF`) (PASS).
  - Stage 6: Simultaneous `write_block_en` and `write_word_en` priority handling (PASS).
  - Stage 7: Synchronous re-reset clearing (PASS).
  - **Total**: 283 assertions checked, 0 errors.

---

## 3. Main Memory Behavioral Model Verification (`tb_main_memory.v`)
- **Objective**: Verify 256 KB memory model, `$readmemh` deterministic initialization from `traces/mem_init.hex`, 10-cycle fixed access latency, 16-byte block alignment, and Moore handshake sequencing.
- **Log File**: [`results/main_memory_simulation.log`](main_memory_simulation.log)
- **Key Results**:
  - Stage 1: Preload verification and 10-cycle read latency handshake (PASS).
  - Stage 2: 128-bit block write and read-back on `0x0000_0100` (PASS).
  - Stage 3: Unaligned address requests properly resolve to aligned 16-byte blocks (PASS).
  - Stage 4: Back-to-back Moore write-back $\rightarrow$ allocate handshake (PASS).
  - Stage 5: Synchronous reset preserving preloaded memory contents (PASS).
  - **Total**: 42 assertions checked, 0 errors.

---

## 4. Integrated Cache Controller Verification (`tb_smoke.v`)
- **Objective**: Verify end-to-end integration of CPU core interface, Cache Controller FSM (`IDLE`, `COMPARE_TAG`, `WRITE_BACK`, `ALLOCATE`), Tag Array, Data Array, and Backing Memory with `MEM_LATENCY = 10`.
- **Log File**: [`results/cache_top_smoke_simulation.log`](cache_top_smoke_simulation.log)
- **Scenarios Verified**:
  1. **Cold Read Miss & Same-Address Hit**: First access triggers memory allocation (10-cycle latency); subsequent read to same block hits in 1 cycle with `ready = 1`.
  2. **Dirty Write-Back, Clean Replacement, and Preserved Neighboring Word**: Writing to an existing block marks it dirty; on conflict eviction, dirty block is written back to main memory, new block is allocated, and non-modified words in the block remain coherent.
  3. **Write-Allocate, Dirty Eviction, and Memory Readback**: Write miss allocates block into cache, writes CPU data word, marks line dirty, and subsequent eviction flushes data back to memory verified by readback.
  4. **Watchdog and Handshake Timing**: Evaluated at 100 MHz with valid CPU ready handshakes.
  - **Status**: **PASS: cache_top smoke test (MEM_LATENCY=10)**.
