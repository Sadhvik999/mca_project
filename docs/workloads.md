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

## Default run and latency sensitivity

All four traces passed the Icarus Verilog testbench's checks against its
independent reference model for read data and counters.

| Trace | Hits | Misses | Write-backs | Hit rate | Miss rate | Total cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Sequential | 768 | 256 | 0 | 75.00% | 25.00% | 5,121 |
| Strided | 0 | 1,024 | 0 | 0.00% | 100.00% | 14,337 |
| Conflict ping-pong | 0 | 1,024 | 256 | 0.00% | 100.00% | 17,153 |
| Random | 195 | 829 | 171 | 19.04% | 80.96% | 13,878 |

The first three hit rates matched the exact predictions. The random hit
rate landed 0.18 percentage points above the 18.86% cold-start expectation.
The full default run is in [default_trace_runs.log](../results/default_trace_runs.log).

The [latency sweep](../results/latency_sweep.csv) holds geometry and trace
contents constant. For each trace, hit, miss, and write-back counts stayed
the same at memory latencies of 5, 10, 20, and 50 cycles. Higher latency
increased the cycle count by one cycle per refill and per dirty write-back
for each additional cycle of backing-memory latency.

### Reproduce from the repository root

```bash
mkdir -p build
for trace in sequential strided conflict random; do
  python3 scripts/gen_trace.py --pattern "$trace"
done

iverilog -g2012 -Wall -s tb_trace -o build/m3_trace.vvp rtl/*.v tb/tb_trace.v
for trace in sequential strided conflict random; do
  vvp build/m3_trace.vvp "+TRACE=traces/$trace.txt"
done
```

`run_sweep.py --mem-latency` sets `tb_trace.MEM_LATENCY` at elaboration.
The testbench forwards it to `cache_top`, which forwards it to
`main_memory`. The loop adds trace and latency metadata to the runner's
counter rows.

```bash
(
  set -e
  {
    printf 'trace,mem_latency,config,accesses,hits,misses,writebacks,cycles\n'
    for latency in 5 10 20 50; do
      for trace in sequential strided conflict random; do
        python3 scripts/run_sweep.py --trace "$trace.txt" --configs 4096:16 \
          --mem-latency "$latency" --output build/m3_latency_row.csv --overwrite >&2
        awk -v trace="$trace" -v latency="$latency" \
          'NR > 1 {print trace "," latency "," $0}' build/m3_latency_row.csv
      done
    done
  } > build/m3_latency_sweep.csv
  mv build/m3_latency_sweep.csv results/latency_sweep.csv
)
```
