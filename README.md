# Direct-Mapped Cache Controller in Verilog

Modern Computer Architecture · Phase II final submission

The RTL implements a blocking, direct-mapped cache with write-back and write-allocate. Phase II verifies the controller's corner cases, tests 12 cache geometries, and measures four workloads across geometry and backing-memory latency.

[Phase II IEEE report](docs/phase2_report.pdf) · [Results analysis](docs/results_analysis.md) · [Viva preparation](docs/viva_prep.md) · [Prototype demonstration video](docs/video/MCAProject.mp4) · [Google Drive video folder](https://drive.google.com/drive/folders/1WNsOvDRVHSj_vMWKZjpoxVolT6G_y51Q?usp=drive_link)

## Default design

| Item | Value |
|---|---|
| CPU interface | 32-bit byte address, aligned 32-bit word reads and writes |
| Cache | 4 KB (4,096 B), direct-mapped, 256 lines |
| Block | 16 B, four words, 128-bit memory datapath |
| Address split | Tag `[31:12]`, index `[11:4]`, block word offset `[3:2]`, byte offset `[1:0]` |
| Line metadata | Valid bit, dirty bit, 20-bit tag |
| Write policy | Write-back and write-allocate |
| Controller | Four-state Mealy FSM with `IDLE`, `COMPARE_TAG`, `WRITE_BACK`, and `ALLOCATE` |
| Memory protocol | Blocking, one outstanding CPU request, `MEM_LATENCY=10` cycles |

See the [address split](docs/diagrams/address_split.md), [block diagram](docs/diagrams/block_diagram.md), [FSM](docs/diagrams/fsm_diagram.md), and [parameterization specification](docs/parameterization.md).

## Team

| Stage | Member | Roll number | Completed work |
|---|---|---|---|
| M1 | Mustyala Sadhvik | 2401020099 | Tag array and unit tests, address mapping, corner-case suite |
| M2 | Udata Varun | 2401010481 | Data array and main memory, parameterized geometry, sweep runner and geometry tests |
| M3 | Amogha Raj Sandur | 2401010397 | Controller and integration, workload generation, latency runs and AMAT |
| M4 | Yachna Khanna | 2401010509 | Directed and golden-model verification, grid evaluation, 3Cs classification, initial plots |
| M5 | Shrihari K N | 2401010448 | Performance counters and trace replay, final sweeps and figures, IEEE report and viva guide |

## Run all testbenches

Use Bash from the repository root. Install Icarus Verilog (`iverilog` and `vvp`), Python 3.10 or later, and Matplotlib for plots. The final artifacts were generated with Icarus Verilog 13.0 and Matplotlib 3.10.0. GTKWave is optional. To build the PDF, install a TeX distribution with IEEEtran and `latexmk`.

```bash
python3 -m venv build/venv
source build/venv/bin/activate
python -m pip install 'matplotlib==3.10.0'
```

The repository includes the memory image and the four trace fixtures. To regenerate them with the measured settings:

```bash
python3 scripts/gen_mem_init.py
for trace in sequential strided conflict random; do
  python3 scripts/gen_trace.py --pattern "$trace" --count 1024 --seed 42
done
```

Run the module tests, integrated smoke/golden/directed tests, and Phase II corner and geometry checks:

```bash
for test in tb_tag_array tb_data_array tb_main_memory tb_corner_cases; do
  ./scripts/run_sim.sh --test "$test"
done
./scripts/run_sim.sh --test all  # tb_smoke, tb_cache, tb_directed
./scripts/check_params.sh       # tb_param_check at all 12 geometries
```

Run the self-checking trace testbench at the baseline geometry:

```bash
mkdir -p build
iverilog -g2012 -Wall -s tb_trace -o build/tb_trace.vvp rtl/*.v tb/tb_trace.v
for trace in sequential strided conflict random; do
  vvp build/tb_trace.vvp "+TRACE=traces/$trace.txt"
done
```

`tb_smoke` is the top-level smoke test. `tb_cache` is the golden-memory harness. The trace test checks returned words and performance counters. Custom trace rows use `R <hex_addr>` or `W <hex_addr> <hex_data>`, with word-aligned byte addresses from `0x00000000` through `0x0003FFFC`.

## Reproduce the results, plots, and report

```bash
python3 scripts/run_all_sweeps.py --latency-sweep
python3 scripts/miss_classification.py
./scripts/run_sim.sh --test tb_directed
MPLCONFIGDIR="$PWD/build/matplotlib" XDG_CACHE_HOME="$PWD/build/cache" \
  python3 scripts/plot_results.py --directed-vcd docs/waveforms/cache_directed.vcd
```

The first command invokes `run_sweep.py` for all 48 workload/geometry points at 10 cycles and adds the 5, 20, and 50-cycle runs at 4 KB / 16 B. At 10 cycles, the latency table reuses the four matching geometry runs. `amat.py` derives timing from the measured counters. The plot script checks the model's 3Cs totals against the RTL counters before rendering. To rerun an individual point:

```bash
python3 scripts/run_sweep.py --trace conflict.txt --configs 4096:16 8192:16 \
  --output build/conflict_demo.csv --overwrite
python3 scripts/amat.py build/conflict_demo.csv --output build/conflict_demo_amat.csv
```

| Output | What it contains |
|---|---|
| [Cache-size sweep](results/sweep_cache_size.csv) | All four traces at 1, 2, 4, and 8 KB with 16 B blocks |
| [Block-size sweep](results/sweep_block_size.csv) | All four traces at 8, 16, and 32 B with 4 KB capacity |
| [Full grid counters](results/sweep_all_traces.csv) · [AMAT](results/param_sweeps_amat.csv) | All 48 geometry runs |
| [Latency counters](results/latency_sweep.csv) · [AMAT](results/amat_table.csv) | All four traces at 5, 10, 20, and 50 cycles |
| [Miss classification](results/miss_classification.csv) | Compulsory, conflict, and capacity counts for each workload and geometry |
| [Figures](results/plots/) | PNG and PDF plots, including the directed VCD excerpts |

To demo the design, run the directed test and open its VCD in GTKWave. Show a cold refill and subsequent hit (TC-01/02), then a dirty write-back followed by a refill (TC-07). Finish by rerunning the conflict comparison above. [Waveform guide](docs/waveforms/README.md)

```bash
gtkwave docs/waveforms/cache_directed.vcd
```

Compile the final report from the repository root. On Overleaf, use the [report build instructions](docs/report/README.md).

```bash
mkdir -p build/report
(cd docs/report && latexmk -pdf -interaction=nonstopmode -halt-on-error \
  -outdir=../../build/report main.tex)
cp build/report/main.pdf docs/phase2_report.pdf
```

## Measured results at 4 KB / 16 B / 10 cycles

| Workload | Hits | Misses | Write-backs | Hit rate | Total cycles | AMAT (cycles/access) |
|---|---:|---:|---:|---:|---:|---:|
| Sequential | 768 | 256 | 0 | 75.00% | 5,121 | 5.00 |
| Strided | 0 | 1,024 | 0 | 0.00% | 14,337 | 14.00 |
| Conflict ping-pong | 0 | 1,024 | 256 | 0.00% | 17,153 | 16.75 |
| Random (seed 42) | 195 | 829 | 171 | 19.04% | 13,878 | 13.55 |

Each row has 1,024 accesses. Sequential hit rate rises from 50.00% at 8 B to 75.00% at 16 B and 87.50% at 32 B. The conflict workload hits 0.00% at 1–4 KB and 99.80% at 8 KB because its two blocks map to different lines. At the baseline geometry, increasing memory latency from 5 to 50 cycles raises conflict AMAT from 10.50 to 66.75 cycles/access. [Measured block-size sweep](results/sweep_block_size.csv) · [Measured cache-size sweep](results/sweep_cache_size.csv) · [AMAT table](results/amat_table.csv)

The one-way organization fixes the victim by index. Associativity with LRU, a victim cache, and prefetching remain future work. The reported cycle counts come from Icarus Verilog and a behavioral backing memory.
