# Workloads and methodology

Each trace starts with a cold 4 KB direct-mapped cache and 16-byte blocks.
The default comparisons use `MEM_LATENCY=10`. All traces use byte addresses
aligned to 32-bit words. The format is `R <hex_addr>` for reads and
`W <hex_addr> <hex_data>` for writes.

## Predictions before simulation

| Trace | Access pattern (1,024 requests) | Predicted hit rate |
| --- | --- | --- |
| Sequential | Read consecutive words starting at address zero. | 75%. The first word in each block misses and the next three hit. |
| Strided | First read 512 addresses with a 16-byte stride from zero. Then alternate between addresses `0x2000` and `0x3000`, separated by the 4 KB cache capacity, for 512 reads. | 0%. The first pass uses a new block every time. The second phase introduces two new blocks at one index and continually replaces them. Expect 514 compulsory and 510 conflict misses. |
| Conflict ping-pong | Alternate between `0x0000` and `0x1000` and write on every fourth request starting with the first. | 0%. Both addresses have index zero and different tags. Expect two compulsory misses and 1,022 conflict misses. Each of the 256 writes makes a line dirty, which the next request evicts. |
| Random | Use seed 42 to sample aligned words uniformly over 16 KiB. Choose a write with probability 1/4. | About 19% over the cold-start run. Four blocks compete per index, so a populated index has a 1/4 hit probability. Earlier accesses also face empty indices. |

For the random prediction, after `t` requests the chance that a particular
index has been visited is `1 - (255/256)^t`. Multiply by `1/4` for the chance
of requesting its resident tag, then average over `t = 0, ..., 1023`. This is an
expectation over random traces. The fixed seed gives one reproducible sample.
