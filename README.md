# Direct-Mapped Cache Controller in Verilog (Phase I)

[![Course](https://img.shields.io/badge/Course-Modern%20Computer%20Architecture-blue.svg)](#)
[![Simulation](https://img.shields.io/badge/Simulator-Icarus%20Verilog%2013.0-green.svg)](#)
[![Report](https://img.shields.io/badge/Format-IEEEtran-red.svg)](#)

## Overview

This Phase I prototype implements a blocking, direct-mapped L1 cache controller in Verilog for a 32-bit CPU interface. A write hit updates the cached word and marks its line dirty. A write miss allocates the block, and a dirty victim is written to backing memory before replacement.

This repository encompasses **Phase I** deliverables:
1. Complete RTL architecture specifications and modular Verilog modules.
2. Self-checking testbenches executable via Icarus Verilog (`iverilog`).
3. Memory hierarchy trace generator and verification scripts.
4. Comprehensive IEEEtran conference report and technical presentation materials.

---

## Architecture & Design Specifications

| Parameter | Specification | Details / Description |
|---|---|---|
| **Cache Size** | 4 KB ($4096\text{ bytes}$) | Total data storage capacity |
| **Organization** | Direct-Mapped | 1 way per set ($S = 256$ sets/lines) |
| **Block / Line Size** | 16 Bytes | 4 words ($4 \times 32\text{ bits} = 128\text{ bits}$) |
| **Number of Cache Lines**| 256 | Indexed via $2^8 = 256$ lines |
| **Address Width** | 32 bits | Byte-addressable physical memory space |
| **Tag Field** | Bits `[31:12]` (20 bits) | Stored in tag array to verify cache hits |
| **Index Field** | Bits `[11:4]` (8 bits) | Maps address to one of 256 cache lines |
| **Block Offset** | Bits `[3:2]` (2 bits) | Selects 32-bit word within 16-byte block |
| **Byte Offset** | Bits `[1:0]` (2 bits) | Selects byte within 32-bit word |
| **Line Metadata** | Valid, Dirty, Tag[19:0] | 1 valid bit, 1 dirty bit, 20-bit tag per line |
| **Write Policy** | Write-Back + Write-Allocate | Writes update cache; dirty line written on eviction |
| **Concurrency Mode** | Blocking | Single outstanding request serviced at a time |
| **Memory Latency** | `MEM_LATENCY = 10` cycles | Block-wide 128-bit memory transfer latency |
| **FSM Controller States**| `IDLE`, `COMPARE_TAG`, `WRITE_BACK`, `ALLOCATE` | 4-state Mealy FSM |

### CPU & Memory Interface Summary

- **CPU Core Interface**:
  - `req` (Input): High when CPU requests memory transaction.
  - `we` (Input): High for Write, Low for Read.
  - `addr` (Input, 32-bit): Target memory address.
  - `wdata` (Input, 32-bit): Data word to be written.
  - `rdata` (Output, 32-bit): Read data word returned to CPU.
  - `ready` (Output): High when cache has fulfilled the request.

- **Backing Memory Interface**:
  - `mem_req` (Output): Initiates block transfer with backing memory.
  - `mem_we` (Output): High for block writeback, Low for block allocation read.
  - `mem_addr` (Output, 32-bit): Block-aligned address formed with the victim tag on write-back and requested tag on refill.
  - `mem_wdata` (Output, 128-bit): 16-byte block written back to memory.
  - `mem_rdata` (Input, 128-bit): 16-byte block fetched from memory.
  - `mem_ready` (Input): High when backing memory transfer completes (after 10 cycles).

---

## Team Members & Responsibilities

| Member | Stage | Roll No. | Work |
|---|---|---|---|
| Mustyala Sadhvik | M1 | 2401020099 | Repository and report foundation, address split, tag array and unit test |
| Varun Udata | M2 | 2401010481 | Data array, backing memory, module tests, write policy and datapath documentation |
| Amogha Raj Sandur | M3 | 2401010397 | Controller FSM, top-level integration, smoke test and FSM documentation |
| Yachna Khanna | M4 | 2401010509 | Golden model, directed suite, simulation runner and waveform guide |
| Shrihari K N | M5 | 2401010448 | Performance counters, trace generation and replay, video script and report finalization |

## Directory Structure

```text
rtl/              Tag and data arrays, controller, memory, top, performance counters
tb/               Module tests, smoke test, golden model, directed suite, trace driver
traces/           Backing memory initialization and sequential word-read trace
scripts/          Simulation runner, memory initialization and trace generators
docs/
  diagrams/       Address split, block diagram and FSM
  waveforms/      Directed simulation log and GTKWave inspection guide
  report/         IEEEtran source and bibliography
  phase1_report.pdf Compiled Phase I report
  video_script.md Timed five-member demo script
results/          Simulation summaries and module logs
```

## How to Run & Verification

Run these commands from the repository root so the simulations can load `traces/mem_init.hex`. Install Icarus Verilog (`iverilog` and `vvp`) and Python 3. GTKWave is used to open the optional VCD dumps.

### Directed and integration tests

```bash
./scripts/run_sim.sh --test tb_directed
./scripts/run_sim.sh --test all
```

The directed suite covers TC-01 through TC-08, including dirty eviction and read-back. The `all` target also runs the smoke test and golden reference model harness.

To inspect the directed waveform, run:

```bash
gtkwave docs/waveforms/cache_directed.vcd
```

In `tb_directed`, add `clk`, `req`, `we`, `addr`, `wdata`, `rdata`, `ready`, `hit`, and `miss`. In `tb_directed.dut`, add `state`, `dirty`, `dirty_evict`, `write_word_en`, `mem_req`, `mem_we`, `mem_addr`, `mem_ready`, and `mem_wdata`. Display addresses and data in hex, and use decimal state values (`0=IDLE`, `1=COMPARE_TAG`, `2=WRITE_BACK`, `3=ALLOCATE`). Use the [waveform guide](docs/waveforms/README.md) to locate each scenario.

### Sequential trace and counters

```bash
python3 scripts/gen_trace.py --pattern sequential --count 1024 --output traces/sequential.txt
mkdir -p build
iverilog -g2012 -Wall -s tb_trace -o build/tb_trace.vvp rtl/*.v tb/tb_trace.v
vvp build/tb_trace.vvp +TRACE=traces/sequential.txt
```

The run reports 1,024 reads, 768 hits, 256 misses, zero writes and write-backs, and 5,121 cycles. The 75.00% hit rate comes from one cold miss and three hits per 16-byte block. The cycle counter includes every non-reset clock edge through the last response, including idle time.

Use `+TRACE=path/to/file` for a custom trace. Each line is `R <hex_addr>` or `W <hex_addr> <hex_data>`. Use word-aligned byte addresses from `0x00000000` through `0x0003FFFC` and up to eight hex digits per value, with an optional `0x` prefix. The testbench checks read data and final counters against its reference model. Pass `+DUMP` to write `build/trace.vcd`, then inspect the counters under `tb_trace.dut.perf` in GTKWave.

### Running Module-Level Unit Testbenches

#### 1. Tag Array Module (`tag_array.v`)
```bash
iverilog -g2012 -o tb/tb_tag_array.vvp rtl/tag_array.v tb/tb_tag_array.v
vvp tb/tb_tag_array.vvp
# Optional: gtkwave tb/tag_array.vcd
```

#### 2. Data Array Module (`data_array.v`)
```bash
iverilog -g2012 -o tb/tb_data_array.vvp rtl/data_array.v tb/tb_data_array.v
vvp tb/tb_data_array.vvp
# Optional: gtkwave tb/data_array.vcd
```

#### 3. Main Memory Behavioral Model (`main_memory.v`)
```bash
iverilog -g2012 -o tb/tb_main_memory.vvp rtl/main_memory.v tb/tb_main_memory.v
vvp tb/tb_main_memory.vvp
# Optional: gtkwave tb/main_memory.vcd
```

#### 4. Integrated Cache Controller Smoke Test (`cache_top.v`)
Run from the repository root so the memory model can load `traces/mem_init.hex`:
```bash
mkdir -p build
iverilog -g2012 -Wall -s tb_smoke -o build/tb_smoke.vvp rtl/*.v tb/tb_smoke.v
vvp build/tb_smoke.vvp +vcd
# Optional: gtkwave build/smoke.vcd
```

The smoke test verifies cold read misses, hit servicing, dirty write-back on eviction, write allocation, and CPU ready handshakes across the 10-cycle memory latency.

### Phase I Technical Report

Report preparation and final integration were led by Mustyala Sadhvik (M1) and Shrihari K N (M5). The report credits all five members and describes their individual contributions.

- [Compiled PDF](docs/phase1_report.pdf)
- [LaTeX source](docs/report/main.tex) and [BibTeX bibliography](docs/report/references.bib)

To compile locally, run these commands from the repository root.

```bash
cd docs/report
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
cp main.pdf ../phase1_report.pdf
```

See the [report instructions](docs/report/README.md) for Overleaf.

---

## Technical Demonstration Video

- [Timed recording script](docs/video_script.md)
- **Video link** TBD after recording and upload.

---

## Phase I Milestone Checklist

- [x] M1 foundation, address split, tag RTL, unit test and report sections.
- [x] M2 data array, backing memory, unit tests and report sections.
- [x] M3 controller FSM, integration, smoke test and report sections.
- [x] M4 golden model, directed suite, waveform guide and report sections.
- [x] M5 performance counters and trace verification with a measured 75.00% sequential hit rate.
- [x] M5 timed demonstration script.
- [ ] Confirm all five members appear in GitHub Insights > Contributors.
- [ ] Record the demo and add its video link above.
- [ ] Resolve the report's IEEE Xplore verification note.
- [x] Compile and include the Phase I PDF in `docs/`.
- [x] [Repository link for the submission form](https://github.com/Sadhvik999/mca_project).
