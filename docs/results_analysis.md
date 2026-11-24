# Phase II results analysis

The four cold-cache traces contain 1,024 requests each. The geometry sweep covers 48 RTL runs: 1, 2, 4, and 8 KiB crossed with 8, 16, and 32 B blocks at a 10-cycle backing-memory latency. The two requested CSVs select 16 rows at 16 B and 12 rows at 4 KiB from this grid. Their four shared rows come from the same simulations. The miss classifier models a fully associative LRU cache with the same line count and updates it on every reference. Across all 48 rows its direct-mapped hit and miss totals agree with the RTL counters. [Full RTL grid](../results/sweep_all_traces.csv) · [Cache-size sweep](../results/sweep_cache_size.csv) · [Block-size sweep](../results/sweep_block_size.csv) · [3Cs breakdown](../results/miss_classification.csv)

## Block size at 4 KiB

| Workload | 8 B hit rate | 16 B hit rate | 32 B hit rate |
|---|---:|---:|---:|
| Sequential | 50.00% | 75.00% | 87.50% |
| Strided | 0.00% | 0.00% | 25.00% |
| Conflict ping-pong | 0.00% | 0.00% | 0.00% |
| Random | 14.36% | 19.04% | 23.34% |

All values are from the [block-size sweep](../results/sweep_block_size.csv).

- **Sequential.** A 16 B refill brings in four 4 B words. The first word misses, then the next three hit. Over 1,024 reads that gives exactly 256 compulsory misses and 768 hits, or 75.00%. The measured gain shrinks from 25.00 percentage points on the first doubling to 12.50 on the second because there is only one compulsory miss per block to amortize. With 16 B blocks, all four capacities record the same 768 hits since the stream reads each block once and immediately consumes its neighboring words. [Block-size sweep](../results/sweep_block_size.csv) · [Cache-size sweep](../results/sweep_cache_size.csv) · [3Cs breakdown](../results/miss_classification.csv)
- **Strided.** At 4 KiB, widening from 8 B to 16 B leaves 514 compulsory and 510 conflict misses. A 32 B refill then covers two successive 16 B-spaced references in the first part of the trace. The compulsory count drops to 258 while the second part still incurs 510 conflict misses, yielding 256 hits. The first plateau reflects the stride and the persistent index collisions. [Block-size sweep](../results/sweep_block_size.csv) · [3Cs breakdown](../results/miss_classification.csv)
- **Random.** At 4 KiB, increasing the block from 8 B to 32 B cuts compulsory misses from 800 to 442 while reducing the number of slots from 512 to 128. The classifier's capacity misses rise from 23 to 273 and the experiment still gains 92 hits. At 1 KiB the same block-size change gains only 6 hits (53 to 59), while dirty write-backs rise from 218 to 234 and AMAT rises from 15.72 to 15.82 cycles/access. Larger blocks help when fetched neighbors are used. The measured rows show flat or rising hit rates, and the extra evictions show how wider blocks can erode the gain or raise execution cost. [Full grid with AMAT](../results/param_sweeps_amat.csv) · [3Cs breakdown](../results/miss_classification.csv)

## Cache size and conflict misses

At 16 B per block, the conflict trace records zero hits, 1,022 conflict misses, two compulsory misses, and 256 write-backs at each of 1, 2, and 4 KiB. The addresses are 4,096 B apart. For 64, 128, and 256 lines, both block numbers, 0 and 256, reduce to index 0. At 8 KiB there are 512 lines, so the same block numbers map to indices 0 and 256. The run then has 1,022 hits (99.80%), two compulsory misses, and zero write-backs. The three block sizes show the same threshold across the full grid. [Cache-size sweep](../results/sweep_cache_size.csv) · [3Cs breakdown](../results/miss_classification.csv) · [Full RTL grid](../results/sweep_all_traces.csv)

At 4 KiB the two hot blocks occupy 32 B total and the classifier identifies zero capacity misses. Keeping both blocks in a two-way set, or retaining the most recent eviction in a one-entry victim cache, could recover the 1,022 repeated misses of this alternating pattern after warm-up. This is a proposed design change. The measured comparison is between 4 KiB and 8 KiB direct-mapped runs, whose AMATs are 16.75 and 2.02 cycles/access. [3Cs breakdown](../results/miss_classification.csv) · [Cache-size sweep](../results/sweep_cache_size.csv)

At 16 B, the strided trace improves from zero hits to 510 at 8 KiB because its two alternating blocks also stop colliding. The random trace improves more gradually from 55 to 111, 195, and 296 hits as cache size increases. For random, the 1 KiB to 8 KiB endpoints have 644 compulsory misses each, and capacity misses fall from 307 to 9. [Cache-size sweep](../results/sweep_cache_size.csv) · [3Cs breakdown](../results/miss_classification.csv)

## AMAT and backing-memory latency

The trace driver measures two counted clock edges for the hit path and one idle startup edge for the entire run. Using the default sequential row, AMAT is `(5121 - 1) / 1024 = 5.00 cycles/access`. With 256 misses, the extra time averages `(5121 - 1 - 2 × 1024) / 256 = 12 cycles/miss`, which gives the same result as `2 + (256 / 1024) × 12 = 5.00`. [Latency counters](../results/latency_sweep.csv) · [AMAT table](../results/amat_table.csv)

| Workload | 5 cycles | 10 cycles | 20 cycles | 50 cycles | AMAT increase per added latency cycle |
|---|---:|---:|---:|---:|---:|
| Sequential | 3.75 | 5.00 | 7.50 | 15.00 | 0.2500 |
| Strided | 9.00 | 14.00 | 24.00 | 54.00 | 1.0000 |
| Conflict ping-pong | 10.50 | 16.75 | 29.25 | 66.75 | 1.2500 |
| Random | 8.67 | 13.55 | 23.32 | 52.61 | 0.9766 |

AMAT entries are cycles/access at 4 KiB / 16 B. Slopes come from the endpoints in the [AMAT table](../results/amat_table.csv).

Hit, miss, and write-back counts are identical at 5, 10, 20, and 50 cycles for each fixed trace. Each additional memory cycle is paid once per refill and once per dirty write-back. Sequential increases by `256 / 1024 = 0.25` cycles/access per latency cycle, while conflict increases by `(1024 + 256) / 1024 = 1.25`. Random has 829 refills and 171 write-backs, giving `1000 / 1024 = 0.9765625`, close to the strided trace's `1024 / 1024 = 1` despite its lower miss count. These slopes describe the simulated blocking cache with fixed block-transfer latency. [Latency counters](../results/latency_sweep.csv) · [AMAT table](../results/amat_table.csv)
