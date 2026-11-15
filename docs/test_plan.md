# Direct-Mapped Cache Controller Test Plan (Phase I)

## 1. Overview and Objectives

This document establishes the comprehensive functional verification plan for the 4 KB Direct-Mapped L1 Cache Controller implemented in Verilog HDL. The cache subsystem interfaces a 32-bit pipelined CPU core to a 128-bit backing main memory with a fixed 10-cycle latency (`MEM_LATENCY = 10`).

The primary objectives of this verification suite are:
1. **Protocol Compliance**: Verify handshakes with the CPU interface (`req`, `we`, `addr`, `wdata`, `rdata`, `ready`) and backing memory interface (`mem_req`, `mem_we`, `mem_addr`, `mem_wdata`, `mem_rdata`, `mem_ready`).
2. **Coherence & Policy Integrity**: Validate write-back eviction and write-allocate refill policies across all line states (clean, dirty, invalid).
3. **Multi-Word Datapath Verification**: Verify word multiplexing and sub-word preservation across all four 32-bit words within a 16-byte block.
4. **Conflict Handling**: Verify deterministic line replacement, dirty writeback timing, and data retention across address aliasing on identical cache indices.
5. **Golden Model Reference Checking**: Verify all read data against an independently updated software memory array reference model.

---

## 2. Architectural Parameters and Address Decomposition

The direct-mapped cache is parameterized as follows:
- **Cache Capacity**: 4096 Bytes (4 KB)
- **Block Size**: 16 Bytes (128 bits, 4 words per block)
- **Number of Lines**: $256$ ($S = 4096 / 16$)
- **Address Width**: 32 bits physical byte address
- **Backing Memory Latency**: 10 clock cycles

### Address Split
```
+---------------------------+-------------------+-------------------+-------------------+
|      Tag [31:12]          |   Index [11:4]    | Block Offset[3:2] | Byte Offset [1:0] |
|        20 bits            |      8 bits       |      2 bits       |      2 bits       |
+---------------------------+-------------------+-------------------+-------------------+
```
- **Byte Offset `[1:0]`**: Ignored for word-aligned accesses.
- **Block Offset `[3:2]`**: 4:1 multiplexer index selecting Word 0 (`2'b00`), Word 1 (`2'b01`), Word 2 (`2'b10`), or Word 3 (`2'b11`).
- **Index `[11:4]`**: Selects one of 256 cache lines ($0 \dots 255$).
- **Tag `[31:12]`**: Matched against stored tag for hit evaluation.

---

## 3. Test Scenarios and Matrix

| Test ID | Scenario Name | Primary Mechanism Verified | Key Signals Checked | Expected Result |
|---|---|---|---|---|
| **TC-01** | Cold Read Miss | Line allocation on invalid line | `miss`, `mem_req`, `mem_ready`, `fill_line`, `ready`, `rdata` | 10-cycle memory read, valid bit set, clean line, correct data returned |
| **TC-02** | Read Hit | Single-cycle hit lookup on valid line | `hit`, `miss`, `ready`, `rdata`, `mem_req` | Single-cycle completion (`ready=1`), no memory request (`mem_req=0`) |
| **TC-03** | Write Hit (Dirty Set) | Write-back policy and dirty tracking | `hit`, `ready`, `write_word_en`, `set_dirty`, `mem_req` | SRAM word updated, dirty bit asserted, no memory write transaction |
| **TC-04** | Sub-word / Multi-word Access | 4-word block multiplexing and isolation | `word_offset`, `rdata`, `write_word_en` | Independent access to all 4 words; writing one word preserves neighboring words |
| **TC-05** | Write Miss (Write-Allocate) | Allocation prior to write completion | `miss`, `mem_req`, `fill_line`, `write_word_en`, `dirty` | Block fetched from memory, target word updated, line marked dirty |
| **TC-06** | Conflict Eviction (Clean Line)| Replacement without writeback | `miss`, `dirty_evict`, `mem_we`, `fill_line` | Clean victim discarded without memory write (`mem_we=0`), new block refilled |
| **TC-07** | Conflict Eviction (Dirty Line)| Write-back of modified block + memory reload | `dirty_evict`, `mem_we`, `mem_wdata`, `mem_ready` | Full 128-bit dirty block written back; later readback confirms memory was updated |

---

## 4. Detailed Test Case Specifications

### TC-01: Cold Read Miss
- **Purpose**: Verify that an initial read access to an invalid cache line triggers an external memory allocation fetch, populates the tag and data arrays, asserts `valid=1, dirty=0`, and returns the correct word.
- **Stimulus**:
  1. Apply synchronous reset `rst = 1` for 2 clock cycles, then deassert.
  2. Issue CPU read: `req = 1, we = 0, addr = 32'h0000_0028` (Tag `0x00000`, Index `0x02`, Word `2`).
- **DUT Cycle Sequence**:
  - `IDLE` -> latches request.
  - `COMPARE_TAG` -> `valid=0` $\rightarrow$ tag comparison fails, pulses `miss=1`.
  - Next state is `ALLOCATE` (clean/invalid miss). Controller asserts `mem_req=1, mem_we=0, mem_addr=32'h0000_0020`.
  - Backing memory counts 10 cycles (`MEM_LATENCY = 10`), then asserts `mem_ready=1` with block payload.
  - Cache arrays capture block on `fill_line = 1`: `valid <= 1, dirty <= 0, tag <= 20'h00000`.
  - Controller returns to `COMPARE_TAG` (`refilled=1`), asserts `ready=1`, outputs `rdata = 32'h0000_000a`.
- **Expected Result**:
  - Read value matches expected initialization value (`0x0000_000a`).
  - Lookup count = 1 miss, 0 initial hits.
  - Line marked valid, clean.

### TC-02: Read Hit
- **Purpose**: Validate single-cycle zero-wait-state response when accessing a valid block already resident in cache.
- **Stimulus**:
  - Issue CPU read: `req = 1, we = 0, addr = 32'h0000_0028` immediately following TC-01.
- **DUT Cycle Sequence**:
  - `IDLE` -> `COMPARE_TAG`.
  - `valid=1` and `stored_tag == request_tag` $\rightarrow$ `tag_hit=1`.
  - Mealy `ready` asserts high immediately in `COMPARE_TAG`.
  - Controller returns to `IDLE` on next clock edge.
  - `mem_req` remains `0` throughout.
- **Expected Result**:
  - `hit=1, miss=0, ready=1`.
  - Read completes in 1 cycle of `COMPARE_TAG`.
  - `rdata` equals `32'h0000_000a`.
  - Zero memory bus activity.

### TC-03: Write Hit (Dirty Set)
- **Purpose**: Verify write-back policy on write hit: the cache word is updated in SRAM, `dirty` flag is asserted, and no transaction is dispatched to backing memory.
- **Stimulus**:
  - Issue CPU write: `req = 1, we = 1, addr = 32'h0000_0028, wdata = 32'hFEED_FACE`.
- **DUT Cycle Sequence**:
  - `IDLE` -> `COMPARE_TAG`.
  - `tag_hit=1`.
  - `write_word_en = 1`, `set_dirty = 1`, `ready = 1`.
  - Data array updates Word 2 of line `0x02` with `32'hFEED_FACE`.
  - Tag array asserts `dirty <= 1` while preserving `valid = 1, tag = 20'h00000`.
  - `mem_req` remains low (`0`).
- **Expected Result**:
  - Transaction completes with `hit=1, ready=1`.
  - Line metadata: `valid=1, dirty=1`.
  - Backing memory is NOT updated.

### TC-04: Sub-word Multiplexing & Multi-word Integrity
- **Purpose**: Verify that all 4 words within a 16-byte block can be independently addressed and updated without corrupting adjacent words.
- **Stimulus**:
  1. For block base `0x0000_0020`, read Word 0 (`0x0000_0020`), Word 1 (`0x0000_0024`), Word 3 (`0x0000_002C`).
  2. Write Word 0 with `32'hAAAA_0000`.
  3. Write Word 3 with `32'hCCCC_3333`.
  4. Read back all four words: Word 0, Word 1, Word 2 (`0x0000_0028`), Word 3.
- **Expected Result**:
  - Word 0 returns `32'hAAAA_0000`.
  - Word 1 returns unmodified initial data (`32'h0000_0009`).
  - Word 2 returns `32'hFEED_FACE` (written in TC-03).
  - Word 3 returns `32'hCCCC_3333`.
  - All four operations hit in cache without memory traffic.

### TC-05: Write Miss (Write-Allocate)
- **Purpose**: Verify that a write miss to an uncached line brings the missing 16-byte block from backing memory into cache first, applies the write to the target word, and marks the line dirty.
- **Stimulus**:
  - Issue CPU write: `req = 1, we = 1, addr = 32'h0000_1044, wdata = 32'hBEEF_CAFE` (Index `0x04`, Word 1, Tag `0x00001`).
- **DUT Cycle Sequence**:
  - `IDLE` -> `COMPARE_TAG` (miss on invalid line `0x04`).
  - Transitions to `ALLOCATE`. Issues memory read `mem_addr = 32'h0000_1040`.
  - Memory responds with 128-bit block.
  - Refill loads line with `valid=1, dirty=0`.
  - Replayed `COMPARE_TAG` executes write: Word 1 overwritten with `32'hBEEF_CAFE`, dirty flag set (`dirty=1`), `ready=1`.
- **Expected Result**:
  - Memory read performed for `32'h0000_1040`.
  - Subsequent read to Word 1 returns `32'hBEEF_CAFE`.
  - Subsequent read to Word 0 (`0x0000_1040`) returns backing memory word (`32'h0000_0410`), confirming surrounding block words were correctly preserved.

### TC-06: Conflict Eviction of a Clean Line
- **Purpose**: Verify that when a conflict occurs on an indexed line whose current contents are clean (`dirty=0`), the controller immediately overwrites the line without an external memory writeback.
- **Stimulus**:
  1. Read `addr = 32'h0000_0030` (Index `0x03`, Tag `0x00000`). Line becomes valid and clean (`dirty=0`).
  2. Read conflicting address `addr = 32'h0000_2030` (Index `0x03`, Tag `0x00002`).
- **DUT Cycle Sequence**:
  - In `COMPARE_TAG`, stored tag (`0x00000`) != request tag (`0x00002`).
  - `dirty_evict = miss && valid && dirty = 0`.
  - Controller transitions directly from `COMPARE_TAG` to `ALLOCATE`.
  - `mem_we` remains `0` (no writeback performed).
  - Memory read is executed for `32'h0000_2030`.
- **Expected Result**:
  - Zero writeback cycles (`mem_we=0`).
  - Line `0x03` now stores Tag `0x00002`, `valid=1, dirty=0`.

### TC-07: Conflict Eviction of a Dirty Line with Write-Back and Read-Back
- **Purpose**: Verify the complete write-back eviction sequence:
  1. A dirty victim block is evicted due to an index conflict.
  2. Controller enters `WRITE_BACK` and transfers the entire 128-bit modified block to backing memory.
  3. Controller transitions to `ALLOCATE` and fetches the new block.
  4. Later, the evicted block is reloaded from memory to prove that the backing memory successfully retained the written-back data.
- **Stimulus**:
  1. Ensure line `0x02` is dirty with modified data (`32'hFEED_FACE` at `0x0000_0028`).
  2. Issue read to conflicting address: `addr = 32'h0000_1028` (Tag `0x00001`, Index `0x02`, Word 2).
  3. Verify controller writes back block `0x0000_0020` to memory, then allocates `0x0000_1020`.
  4. Issue read to conflicting address `addr = 32'h0000_0028` to evict `0x0000_1020` and reload `0x0000_0020`.
  5. Read back Word 2 at `0x0000_0028`.
- **DUT Cycle Sequence**:
  - `COMPARE_TAG` detects tag mismatch while `valid=1, dirty=1` $\rightarrow$ `dirty_evict=1`.
  - Controller enters `WRITE_BACK`. Sets `mem_req=1, mem_we=1, mem_addr=32'h0000_0020`.
  - Backing memory performs 128-bit store of `{Word 3, Word 2, Word 1, Word 0}` and asserts `mem_ready=1`.
  - Controller enters `ALLOCATE`, requests `mem_addr = 32'h0000_1020` with `mem_we=0`.
  - When memory returns block, line is refilled.
  - When `0x0000_0028` is accessed again, it is fetched back from memory.
- **Expected Result**:
  - `mem_we` pulses during `WRITE_BACK` with address `32'h0000_0020`.
  - Data read back from `0x0000_0028` after reloading equals `32'hFEED_FACE`, confirming memory coherence across eviction and reallocation.

---

## 5. Verification Architecture & Pass/Fail Criteria

### Self-Checking Testbench Structure
- **Golden Memory Array**: An array `reg [31:0] golden_mem [0:65535]` maintains the true architectural memory state.
  - Initialized with identical contents from `traces/mem_init.hex`.
  - Every CPU write updates `golden_mem[addr[17:2]] = data`.
  - Every CPU read compares DUT output `rdata` against `golden_mem[addr[17:2]]`.
- **Watchdog Timer**: A timeout watchdog terminates simulation if `ready` fails to assert within 100 clock cycles of a request, preventing infinite simulation hangs.
- **Pass/Fail Counters**:
  - `pass_count` increments for every verified transaction matching golden expectations.
  - `fail_count` increments on any mismatch or protocol violation.
  - At test termination, the simulation prints:
    - `ALL TESTS PASSED: X checks succeeded` if `fail_count == 0`.
    - `N TESTS FAILED` if `fail_count > 0`.
