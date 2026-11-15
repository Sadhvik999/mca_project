# GTKWave Waveform Inspection Guide

## Overview

The simulation generates a Value Change Dump (VCD) waveform file at `docs/waveforms/cache_directed.vcd` when running the directed test suite with `+DUMP`. This document provides guidance for loading the trace into GTKWave and inspecting critical signal transitions across all canonical cache operational phases.

---

## 1. Opening the Waveform

Run the simulation runner with the `--wave` flag, or launch GTKWave directly:

```bash
# Via simulation runner (launches GTKWave automatically if installed)
./scripts/run_sim.sh --test tb_directed --wave

# Or launch directly with GTKWave:
gtkwave docs/waveforms/cache_directed.vcd &
```

---

## 2. Recommended Signal Hierarchy and Display Format

Add the following signals from `tb_directed` and `tb_directed.dut` into the waveform viewer:

| Signal | Scope / Path | Radix | Description / Significance |
|---|---|---|---|
| `clk` | `tb_directed` | Binary | 100 MHz reference clock |
| `rst` | `tb_directed` | Binary | Synchronous active-high reset |
| `state[1:0]` | `tb_directed.dut.controller` | Decimal / Enum | Controller state: `0=IDLE`, `1=COMPARE_TAG`, `2=WRITE_BACK`, `3=ALLOCATE` |
| `req` | `tb_directed` | Binary | CPU request strobe |
| `we` | `tb_directed` | Binary | CPU write enable (1=Write, 0=Read) |
| `addr[31:0]` | `tb_directed` | Hexadecimal | 32-bit physical memory address |
| `wdata[31:0]` | `tb_directed` | Hexadecimal | CPU 32-bit write word |
| `rdata[31:0]` | `tb_directed` | Hexadecimal | CPU 32-bit read word |
| `ready` | `tb_directed` | Binary | Cache response ready strobe |
| `hit` | `tb_directed` | Binary | Cache hit indicator (asserted once per initial request) |
| `miss` | `tb_directed` | Binary | Cache miss indicator (asserted once per initial request) |
| `dirty` | `tb_directed.dut` | Binary | Dirty status bit of indexed cache line |
| `dirty_evict`| `tb_directed.dut` | Binary | Asserted during `COMPARE_TAG` when miss targets a dirty line |
| `mem_req` | `tb_directed.dut` | Binary | Backing memory access request |
| `mem_we` | `tb_directed.dut` | Binary | Backing memory transfer direction (1=Write, 0=Read) |
| `mem_addr[31:0]`| `tb_directed.dut` | Hexadecimal | 16-byte aligned block address sent to backing memory |
| `mem_ready` | `tb_directed.dut` | Binary | Single-cycle completion pulse from backing memory after 10 cycles |

---

## 3. Waveform Walkthrough by Operational Scenario

### A. Cold Read Miss & Allocation (TC-01, ~45 ns – 165 ns)
- **Signals to observe**: `req`, `state`, `miss`, `mem_req`, `mem_we`, `mem_ready`, `ready`.
- **Behavior**:
  - `req = 1` latched at `state = IDLE` (0).
  - Transitions to `COMPARE_TAG` (1). Since line is uninitialized (`valid=0`), `miss` pulses high.
  - Controller enters `ALLOCATE` (3), asserting `mem_req = 1` and `mem_we = 0`.
  - Exactly 10 clock cycles later, `mem_ready` pulses high.
  - Line data and tag are captured, and state advances to `COMPARE_TAG` (1).
  - `ready` pulses high with valid `rdata` (`0x0000000a`), and state returns to `IDLE` (0).

### B. Single-Cycle Read Hit (TC-02, ~175 ns – 195 ns)
- **Signals to observe**: `state`, `hit`, `miss`, `ready`, `mem_req`.
- **Behavior**:
  - `req = 1` in `IDLE`.
  - Next cycle enters `COMPARE_TAG` (1). `tag_hit` evaluates true immediately.
  - `hit = 1`, `miss = 0`, and Mealy `ready = 1` in the very same cycle.
  - Zero memory bus activity (`mem_req = 0`). Next cycle returns to `IDLE`.

### C. Write Hit with Dirty Bit Set (TC-03, ~205 ns – 235 ns)
- **Signals to observe**: `we`, `wdata`, `write_word_en`, `dirty`, `ready`.
- **Behavior**:
  - In `COMPARE_TAG` (1), `hit = 1` and `ready = 1`.
  - `write_word_en` asserts high, writing `0xDEADBEEF` into data array Word 2.
  - Tag array `set_dirty` asserts, latching `dirty = 1` on the rising clock edge.
  - `mem_req` stays low (0), verifying write-back policy.

### D. Sub-word Multiplexing across 4 Words (TC-04, ~245 ns – 415 ns)
- **Signals to observe**: `addr[3:2]`, `wdata`, `rdata`, `ready`.
- **Behavior**:
  - Accesses to `addr[3:2] = 2'b00, 2'b01, 2'b10, 2'b11` select distinct words without reloading the cache.
  - Writes to Word 0 and Word 3 update only the addressed word lane, leaving Word 1 and Word 2 intact.

### E. Write Miss (Write-Allocate) (TC-05, ~425 ns – 565 ns)
- **Signals to observe**: `we`, `state`, `miss`, `mem_req`, `mem_we`, `dirty`.
- **Behavior**:
  - Initial `COMPARE_TAG` causes a miss.
  - Transitions to `ALLOCATE` (3) with `mem_we = 0` to fetch the 128-bit block from memory.
  - Upon `mem_ready`, state returns to `COMPARE_TAG`, where the pending store completes: `wdata` is written and `dirty` asserts.

### F. Clean Line Replacement (TC-06, ~575 ns – 775 ns)
- **Signals to observe**: `dirty`, `dirty_evict`, `mem_we`, `state`.
- **Behavior**:
  - Index conflict occurs with `dirty = 0`.
  - Controller skips `WRITE_BACK` entirely and transitions directly from `COMPARE_TAG` (1) to `ALLOCATE` (3).
  - `mem_we` remains 0 throughout, confirming that no writeback traffic is generated for clean lines.

### G. Dirty Line Eviction with 128-bit Write-Back (TC-07, ~785 ns – 1105 ns)
- **Signals to observe**: `dirty`, `dirty_evict`, `state`, `mem_req`, `mem_we`, `mem_addr`, `mem_wdata`.
- **Behavior**:
  - In `COMPARE_TAG`, `miss = 1`, `valid = 1`, and `dirty = 1`, triggering `dirty_evict = 1`.
  - Controller enters `WRITE_BACK` (2):
    - Asserts `mem_req = 1`, `mem_we = 1`.
    - `mem_addr` drives the victim block address (`0x00000020`).
    - `mem_wdata` presents all 128 bits `{Word 3, Word 2, Word 1, Word 0}` with updated values (`0x33333333` and `0xDEADBEEF`).
  - Upon `mem_ready` from writeback, controller transitions directly to `ALLOCATE` (3) with `mem_we = 0` to load the incoming conflicting block.
  - Later reload from memory confirms the modified data was safely preserved in main memory.
