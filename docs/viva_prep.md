# Phase II viva preparation

## Questions for everyone

1. **Why use a cache?** A small fast store can serve repeated or nearby word accesses without paying backing-memory latency. The sequential workload averages 5.00 cycles/access at the default geometry and latency.
2. **What are temporal and spatial locality?** Temporal locality is reuse of the same data, such as the two alternating conflict addresses. Spatial locality is access to nearby data, such as successive 4 B words that share a 16 B refill.
3. **Direct-mapped versus set-associative?** Direct mapping gives each block one legal line and uses one tag comparison. A set-associative cache gives each block multiple legal ways within its set, so it can retain competing blocks at the cost of extra comparison and victim-selection logic.
4. **Split a default address.** For the 32-bit byte address, tag is `[31:12]` (20 bits), index is `[11:4]` (8 bits), block word offset is `[3:2]` (2 bits), and byte offset is `[1:0]` (2 bits). For `0x00001028`, these are tag 1, index 2, word 2, byte 0. The 4 KB cache has 256 lines and each 16 B line holds four 32-bit words.
5. **What makes a hit or miss? What are valid and dirty?** Hit requires a valid indexed entry with the requested tag. An invalid entry or a different tag misses. Valid says the line contains usable cached data. Dirty records a store that makes the line newer than backing memory.
6. **Write-back versus write-through?** Write-back updates the cached word and writes the full dirty block on eviction. Write-through sends each store to backing memory as part of the write policy.
7. **What is write-allocate?** On a store miss, fetch the entire requested block, then replay the store into its selected word. A dirty victim must be written back before the refill.
8. **Describe the 3Cs.** A first reference to a block is compulsory. For a subsequent direct-mapped miss, an equal-capacity fully associative LRU miss is classified as capacity and an LRU hit as conflict.
9. **Work the default sequential AMAT.** The [measured row](../results/sweep_block_size.csv) has 1,024 requests, 256 misses, and 5,121 total cycles. The two-cycle hit baseline and one startup edge leave `(5121 − 1 − 2×1024)/256 = 12` cycles per miss. Thus `AMAT = 2 + (256/1024)×12 = 5.00 cycles/access`.
10. **Draw the FSM from memory.** `IDLE (0)` captures a request and goes to `COMPARE_TAG (1)`. A hit completes back to idle. A clean or invalid miss goes to `ALLOCATE (3)`. A dirty miss goes via `WRITE_BACK (2)`, which waits for `mem_ready` then advances to allocation. Allocation waits for `mem_ready`, fills the line, and returns to compare for replay.
11. **Walk through a cold read of `0x00000028`.** Capture, compare at index 2, miss, request block `0x00000020` with `mem_we=0`, install data and a valid clean tag when memory completes, then replay and assert `ready` with word 2, `0x0000000A` in the initial image.
12. **Walk through a write hit to that word.** In compare, `ready` and `write_word_en` assert. At the completion edge the data array writes word 2 and the tag array sets dirty. The other three words retain their values and `mem_req` stays low.

## M1 · Tag array and corner cases

1. **Why can a zero tag miss after reset?** Reset clears valid, so equality alone cannot satisfy the hit predicate.
2. **Which tag-array operations have priority?** Synchronous reset takes priority over full metadata writes, and a full metadata write takes priority over `set_dirty`.
3. **How do the asynchronous tag outputs help?** The indexed metadata is available for combinational comparison after request capture.
4. **What does a dirty-only update preserve?** Tag and validity stay as they were. Only the indexed dirty bit is set.
5. **How does a clean-victim case expose a controller bug?** Check allocation and completion with no write-back state or write command. Entering `WRITE_BACK` would create an extra transfer.
6. **How does a dirty write miss differ?** Save the entire victim at its stored-tag address, fill the requested block, then write the target lane and set dirty.
7. **What does reset during allocation prove?** At a reset edge the outstanding request and memory handshake abort and valid bits clear. A fresh request completes after reset. Dirty lines that had yet to be written back can be lost on reset.
8. **What happens if `req` stays high through completion?** The current request completes in compare. A later idle capture edge samples the next request, so the CPU must present the next address by that edge.
9. **Why test adjacent or boundary indices?** A wrong index width or write decoder can alias distinct lines or make the first or last entry unreachable.
10. **How do you prove two conflicting dirty blocks survive repeated eviction?** Store different words in blocks that share an index, alternate accesses, and compare values after backing-memory refill against the golden model.

## M2 · Data array, backing memory, and geometry

1. **What determines the line count?** `CACHE_SIZE / BLOCK_SIZE` gives 256 for the default.
2. **Where does word 2 live in a 16 B block?** Bits `[95:64]` in the 128-bit packed line.
3. **What if both data write enables assert?** The complete block fill has priority over the single-word write.
4. **How is a selected lane addressed when the block grows?** The word slice starts at `word_offset × 32` and spans 32 bits. A 32 B block has eight lanes.
5. **Why does the backing memory latch the request operands?** It retains the transfer address, direction, and write data while counting latency.
6. **What does the memory's done state prevent?** It ignores the tail of the old `mem_req` pulse while the cache consumes `mem_ready`, so the old transfer is not accepted again.
7. **What does the memory model reset clear?** It clears transaction state and handshake registers. The word array retains its initialized and committed contents.
8. **Derive 4 KB with 32 B blocks.** There are 128 lines, 7 index bits, 5 total offset bits, 20 tag bits, and a 256-bit memory bus.
9. **Why is the tag width unchanged when only block size varies?** The sum of index and total offset widths is `log2(CACHE_SIZE)`. A wider offset at fixed capacity takes one bit from the index.
10. **What checks separate an 8 B or 32 B datapath from a default-only implementation?** Write and read the last word, verify neighboring lanes, force dirty eviction, and reload through memory. Run the checks for all 12 geometries.

## M3 · Controller, traces, and AMAT

1. **Why latch CPU inputs in idle?** The miss can outlive live bus inputs. The stored address, opcode, and data keep lookup, refill, and replay tied to the same CPU request.
2. **Which outputs are Mealy-style?** `ready` uses the current tag result and `fill_line` uses the current `mem_ready` input along with state.
3. **How do write-back and fill addresses differ?** Use the stored tag for the victim and the requested tag for the refill, with the same latched index and zeroed block-offset bits.
4. **Why does a refill replay increment no hit counter?** `refilled` gates the lookup pulses. The original miss is counted, and replay still produces `ready`.
5. **How does the strided trace exercise two effects?** Its first 512 16 B-spaced reads measure block coverage. Its last 512 reads alternate between addresses 4 KB apart to test index aliasing.
6. **Why does the conflict trace have write traffic?** Every fourth access stores into its selected block. Through 4 KB, the very next access replaces it and causes a dirty write-back.
7. **How is random repeatable?** A private Python RNG uses seed 42, samples aligned addresses over 16 KiB, and chooses a write with probability 1/4.
8. **How do one-cycle comparison and two-cycle measured hit time coexist?** The request consumes a capture edge and a completion edge. Combinational tag comparison happens between them.
9. **Why does conflict AMAT have slope 1.25?** Each extra latency cycle is paid for 1,024 refills and 256 write-backs over 1,024 requests.
10. **How does timing affect the hit counts?** With one outstanding request and the same ordered trace, changing latency stretches transfers while retaining the same sequence of mappings and evictions.

## M4 · Testbenches and classification

1. **How do the directed suite and golden model complement one another?** Directed cases require expected hit or miss and data outcomes for known paths. The word-based oracle tracks architectural memory independently.
2. **Why does the oracle record stores at CPU completion?** The CPU can observe the store on subsequent reads after completion even though backing memory may be stale.
3. **How do you prove write-back instead of simply a cache hit?** Force a same-index eviction, check its block write handshake, and reload the original address from backing memory.
4. **What does TC-04 catch?** It reads each word lane and verifies that writes to selected lanes preserve neighboring words.
5. **Why distinguish launch and completion edges in a testbench?** Present requests before the capture edge and sample completed data at the handshake. This avoids racing synchronous RTL updates.
6. **Why track seen blocks separately from the fully associative cache?** An LRU eviction removes a resident entry, but the block's first-reference history must persist.
7. **When is the LRU model updated?** On every reference, including direct-mapped hits. Otherwise the simulated recency order could produce false capacity labels.
8. **Which capacity does the LRU model use?** The same number of lines and block size as the direct-mapped run. For 4 KB / 16 B that is 256 lines.
9. **How does the 3Cs result get checked?** Its direct-mapped accesses, hits, and misses must match the RTL totals, and its three class counts must add up to the measured misses.
10. **What is the strongly diagnostic baseline conflict count?** Two compulsory, zero capacity, and 1,022 conflict misses. Two frequently reused blocks fit in a fully associative model while colliding in the direct-mapped cache.

## M5 · Sweeps, plots, and interpretation

1. **Which points are actual simulations?** All 48 geometry/workload pairs come from `run_sweep.py` compiling RTL and running `vvp`. The 16 cache-size and 12 block-size rows are selections from that grid. The fixed-geometry sweep reuses the four 10-cycle runs and simulates the remaining 12 points.
2. **How do you keep comparisons fair?** Use the same cold-start fixture for each trace, hold latency at 10 for the geometry comparisons, and hold geometry at 4 KB / 16 B for the latency sweep.
3. **Where does 75.00% come from?** A 16 B refill holds four sequential words. One miss followed by three hits gives 768/1,024.
4. **Why does sequential improve less on the second block-size doubling?** The cold miss fraction is halved each time. Hit rate increases by 25.00 points and then by 12.50 points.
5. **Why does strided flatten initially?** Both 8 and 16 B blocks cover only one access of a 16 B stride. At 32 B the first half gets 256 hits, while the second-half collision remains.
6. **Does the conflict trace always perform poorly?** It has zero hits at 1, 2, and 4 KB. At 8 KB, address bit 12 becomes an index bit and the two hot blocks can coexist, producing 1,022 hits.
7. **What could a victim cache change?** A one-entry victim cache could retain the other block in this two-block alternation. The existing 3Cs results identify 1,022 repeated misses that are candidates for elimination after warm-up.
8. **When can hit rate and AMAT move in opposite directions?** At 1 KB, random gains six hits from 8 to 32 B but incurs 16 more write-backs. AMAT rises from 15.72 to 15.82 cycles/access.
9. **Why is random's latency slope close to strided's?** Random has 829 misses plus 171 write-backs, or 1,000 transfers. Strided has 1,024 refills. Divide by 1,024 accesses in each case.
10. **How can an examiner audit a plot point?** Identify its trace and geometry in the plot, find the row in [the full grid](../results/param_sweeps_amat.csv), rerun `run_sweep.py` with matching overrides, and compare the raw counters and AMAT.

## Modify live

Run from the repository root. Make each prediction before starting the simulation.

1. **Cache size.** Compare conflict at 4 and 8 KB with 16 B blocks. Predict index 0 versus indices 0 and 256, then compare zero hits and 256 write-backs against 1,022 hits and zero write-backs.

   ```bash
   python3 scripts/run_sweep.py --trace conflict.txt --configs 4096:16 8192:16 \
     --output build/viva_cache.csv --overwrite
   ```

2. **Block size.** Compare sequential at 8, 16, and 32 B with 4 KB capacity. Predict 512, 768, and 896 hits and explain the one-miss-per-block pattern.

   ```bash
   python3 scripts/run_sweep.py --trace sequential.txt --configs 4096:8 4096:16 4096:32 \
     --output build/viva_block.csv --overwrite
   ```

3. **Latency.** Compare the default conflict run at 10 and 20 cycles. Predict the same 1,024 misses and 256 write-backs, with AMAT rising by `10 × 1.25 = 12.50` cycles/access.

   ```bash
   for latency in 10 20; do
     python3 scripts/run_sweep.py --trace conflict.txt --configs 4096:16 \
       --mem-latency "$latency" --output "build/viva_latency_$latency.csv" --overwrite
     python3 scripts/amat.py "build/viva_latency_$latency.csv" \
       --output "build/viva_amat_$latency.csv"
   done
   ```

## Mock-viva checklist

- [ ] Each member gives a 30-second explanation of their contribution and points to the relevant Git commit and module.
- [ ] Everyone can draw the address split and FSM on a blank board and explain one hit, one clean miss, and one dirty miss.
- [ ] Start with the README commands in a clean checkout, run the directed suite, and open TC-01 and TC-07 in GTKWave.
- [ ] Choose a chart point, reproduce its counters, and work AMAT by hand with units.
- [ ] Make one live parameter change and explain both the expected and observed result.
- [ ] Explain the difference between behavioral RTL timing and FPGA timing or area.

## Limitations and future work

- The cache blocks and accepts one outstanding request. There is no overlap between outstanding CPU accesses.
- One way per set gives each block a single legal line. There is no replacement policy such as LRU.
- The CPU interface handles aligned 32-bit words and the backing memory is a fixed-latency behavioral model.
- The results describe four synthetic traces. FPGA utilization, achievable frequency, and performance on application traces remain unmeasured.
- Next experiments could compare set associativity with LRU, a small victim cache, and stream prefetching.
