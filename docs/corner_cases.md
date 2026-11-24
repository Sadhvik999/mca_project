# Cache Controller Corner Cases Specification

This document details the architectural edge cases, boundary conditions, and handshake timing scenarios for the **4 KB Direct-Mapped L1 Cache Controller** implemented in synthesizable Verilog HDL.

---

## Specification Overview

| Configuration Parameter | Value | Architectural Notes |
|---|---|---|
| **Cache Capacity** | 4096 Bytes (4 KB) | 256 lines $\times$ 16 bytes/line |
| **Associativity** | Direct-Mapped | 1 way per set ($S = 256$) |
| **Block Size** | 16 Bytes (128 bits) | 4 words $\times$ 32 bits/word |
| **Physical Address Width** | 32 bits | Tag [31:12], Index [11:4], Word [3:2], Byte [1:0] |
| **Write Policy** | Write-Back + Write-Allocate | Dirty flag per line; eviction of dirty line triggers writeback |
| **FSM Controller** | 4-state Mealy FSM | `IDLE`, `COMPARE_TAG`, `WRITE_BACK`, `ALLOCATE` |
| **Backing Memory Latency**| 10 clock cycles | Block-wide 128-bit synchronous handshake |

---

## Detailed Corner Cases and Expected Behavior

### 1. First Access After Reset (All Lines Invalid)
- **Description**: Immediately following system reset deassertion, every line in the 256-line cache has `valid = 0` and `dirty = 0`. The processor core issues its very first memory access (e.g., cold instruction fetch or initial data read).
- **Stimulus**: Assert `rst = 1` for $\ge 2$ cycles, deassert `rst = 0`, then present `req = 1`, `we = 0`, `addr = 0x00000010`.
- **Expected Behavior**:
  1. The controller transitions from `IDLE` to `COMPARE_TAG` on the rising clock edge.
  2. Because `valid = 0` for line index `0x01`, tag matching evaluates to false (`tag_hit = 0`), signaling a compulsory cold miss (`miss = 1`, `hit = 0`).
  3. Because `valid = 0`, `dirty_evict = 0` regardless of uninitialized tag/dirty memory bits.
  4. The FSM skips `WRITE_BACK` and advances directly to `ALLOCATE`.
  5. Backing memory is queried at base block address `0x00000010` (`mem_req = 1`, `mem_we = 0`).
  6. After 10 cycles, `mem_ready` asserts: the 128-bit block is written to `data_array`, line metadata is allocated (`valid = 1`, `dirty = 0`, `tag = 0x00000`), and FSM returns to `COMPARE_TAG` with `refilled = 1`.
  7. In `COMPARE_TAG`, the replayed request hits cleanly: `rdata` outputs word `golden_mem[4]`, `ready = 1` asserts, and FSM returns to `IDLE`.

---

### 2. Read Miss with a Clean Victim
- **Description**: The cache line at index $i$ currently contains a valid, clean block (`valid = 1`, `dirty = 0`, Tag $A$). The CPU requests a read from a different physical block mapping to the same index $i$ (Tag $B \neq A$).
- **Stimulus**: Prime line index `0x02` with clean block Tag `0x00000` (`addr = 0x00000028`). Next, issue a read to Tag `0x00001` at same index (`addr = 0x00001028`).
- **Expected Behavior**:
  1. In `COMPARE_TAG`, stored tag (`0x00000`) does not match requested tag (`0x00001`). Thus, `miss = 1`.
  2. Since `dirty = 0`, `dirty_evict = 0`.
  3. FSM bypasses `WRITE_BACK` entirely and transitions directly to `ALLOCATE`.
  4. No memory bus writeback occurs (`mem_we` remains `0`).
  5. Memory read is issued at `0x00001020` (`mem_req = 1`, `mem_we = 0`).
  6. When `mem_ready = 1`, new block is installed, `valid = 1`, `dirty = 0`, `tag = 0x00001`.
  7. Replayed read in `COMPARE_TAG` returns target word with `ready = 1`.

---

### 3. Write to a Dirty Line (Hit)
- **Description**: A cache line is already resident and marked dirty (`valid = 1`, `dirty = 1`). The CPU issues another write operation to the same block (either the same word or another word within the 16-byte block).
- **Stimulus**: Write to `0x00000028` with data `0xDEADBEEF` (marking line `0x02` dirty). On subsequent transaction, write `0xCAFEBABE` to word 3 of the same block (`0x0000002C`).
- **Expected Behavior**:
  1. In `COMPARE_TAG`, `tag_hit = 1` and `hit = 1`.
  2. Single-cycle hit response: `ready = 1` asserts immediately on the same clock cycle.
  3. `write_word_en` asserts, latching `0xCAFEBABE` into word 3 of line `0x02` without corrupting words 0, 1, or 2.
  4. `set_dirty` pulses high, preserving `dirty = 1`.
  5. Zero memory bus activity occurs (`mem_req = 0`, `mem_we = 0`).
  6. Controller transitions directly back to `IDLE`.

---

### 4. Write Miss with a Dirty Victim
- **Description**: The cache line at index $i$ holds a valid, modified block (`valid = 1`, `dirty = 1`, Tag $A$). The CPU initiates a store to a different address mapping to index $i$ (Tag $B$).
- **Stimulus**: Line `0x02` contains modified data for block `0x00000020`. CPU issues write `0x11223344` to `0x00001028` (Tag `0x00001`).
- **Expected Behavior**:
  1. In `COMPARE_TAG`, tag mismatch triggers `miss = 1`. Because `valid = 1` and `dirty = 1`, `dirty_evict = 1` asserts.
  2. Controller transitions to `WRITE_BACK`.
  3. Memory writeback begins at victim block address `{Tag A, index, 4'b0}` (`0x00000020`) using 128-bit `block_out` from `data_array`.
  4. `mem_req = 1`, `mem_we = 1`. Latency counter waits 10 cycles until `mem_ready = 1`.
  5. On `mem_ready`, backing memory captures the 128-bit block, committing the modified victim to memory.
  6. FSM transitions to `ALLOCATE`, requesting new block `0x00001020` (`mem_req = 1`, `mem_we = 0`).
  7. When allocation completes after 10 cycles, `data_array` is populated with fetched block, and metadata updates (`valid = 1`, `dirty = 0`, `tag = Tag B`).
  8. Controller transitions to `COMPARE_TAG`. The write operation is replayed: target word is overwritten with `0x11223344`, line is marked dirty (`set_dirty = 1`), and `ready = 1` asserts.
  9. Subsequent read of victim address `0x00000028` confirms that the previously modified data was committed to backing memory.

---

### 5. Write to the Same Index with a Different Tag (Conflict Thrashing)
- **Description**: Two distinct memory blocks share the exact same 8-bit cache line index $i$. Alternating writes are performed between Address $A$ (`{Tag A, i, ...}`) and Address $B$ (`{Tag B, i, ...}`).
- **Stimulus**: Write `0xAAAA0001` to `0x00000040` (Index `0x04`, Tag `0x00000`). Then write `0xBBBB0002` to `0x00001040` (Index `0x04`, Tag `0x00001`). Then repeat alternating writes/reads.
- **Expected Behavior**:
  1. First write allocates block `0x00000040`, applies write, and sets dirty.
  2. Second write to `0x00001040` detects conflict miss with dirty victim: safely writes back block $A$ to memory, allocates block $B$, applies write, and sets dirty.
  3. Reading back block $A$ (`0x00000040`) forces eviction and writeback of block $B$, then re-fetches block $A$. Read data matches `0xAAAA0001`.
  4. Reading back block $B$ (`0x00001040`) forces eviction of block $A$ and recovers `0xBBBB0002`.
  5. Both blocks maintain absolute data coherence across multiple dirty conflict cycles.

---

### 6. Reset in the Middle of a Transaction
- **Description**: A multi-cycle memory transaction is currently underway (e.g., FSM is in `ALLOCATE` waiting on 10-cycle memory latency). The processor asserts synchronous system reset `rst = 1`.
- **Stimulus**: Issue a cold read miss to `0x00000050`. Wait until controller is in state `ALLOCATE` (`state = 2'd3`, cycle 5 of memory latency). Assert `rst = 1` for 2 cycles, then deassert `rst = 0`.
- **Expected Behavior**:
  1. While `rst = 1`, controller FSM immediately forces `state <= IDLE`.
  2. Internal registers (`request_addr`, `request_we`, `write_word`, `refilled`) clear to zero.
  3. All 256 lines in `tag_array` have `valid` and `dirty` reset to `0`.
  4. External control strobes (`ready`, `mem_req`, `mem_we`, `hit`, `miss`) deassert to zero.
  5. Backing memory model resets its internal handshake FSM back to `S_IDLE` while retaining storage array contents.
  6. Upon releasing `rst`, the controller is in a clean `IDLE` state and immediately services new CPU requests without hang or stale state.

---

### 7. Request Held High Through Ready (Continuous Streaming)
- **Description**: The CPU maintains `req = 1` before, during, and after the cycle where `ready = 1` asserts, emulating pipelined CPU backpressure or an immediate subsequent transaction.
- **Stimulus**: Issue Read 1 to `0x00000060`. Hold `req = 1` continuously. When `ready = 1` appears, update `addr` to `0x00000064` (same block, word 1) while maintaining `req = 1`.
- **Expected Behavior**:
  1. For Request 1, controller signals `ready = 1` in `COMPARE_TAG` and transitions to `IDLE` on the next rising clock edge.
  2. Upon entering `IDLE`, the controller samples `req = 1` with the new address `0x00000064` and advances immediately to `COMPARE_TAG`.
  3. The second request resolves as a cache hit (`ready = 1`) on the very next cycle.
  4. No spurious duplicate transactions, deadlock, or data corruption occurs.

---

### 8. Back-to-Back Requests Across Distinct Indices
- **Description**: Two completely independent requests are issued back-to-back across different line indices (e.g., Read Hit on line `0x10` followed immediately by Write Hit on line `0x20`).
- **Stimulus**: Pre-load cache lines `0x10` (`0x00000100`) and `0x20` (`0x00000200`). Execute read at `0x00000100`, and on the cycle `ready` asserts, present write request for `0x00000200`.
- **Expected Behavior**:
  1. Request 1 completes in `COMPARE_TAG` with `ready = 1`.
  2. At the next clock edge, controller transitions to `IDLE` and latches Request 2.
  3. Request 2 completes in `COMPARE_TAG` with `ready = 1` on the following cycle.
  4. Proves zero-bubble transition capability for hits without requiring dummy idle cycles.
