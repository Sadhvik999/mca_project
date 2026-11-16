# Direct-Mapped Cache Controller in Verilog — Phase I

[![Course](https://img.shields.io/badge/Course-Modern%20Computer%20Architecture-blue.svg)](#)
[![Simulator](https://img.shields.io/badge/Simulator-Icarus%20Verilog%2013.0-green.svg)](#)
[![Format](https://img.shields.io/badge/Report-IEEEtran%20Conference-red.svg)](#)
[![Video](https://img.shields.io/badge/Prototype%20Video-Google%20Drive-yellow.svg)](https://drive.google.com/drive/folders/1WNsOvDRVHSj_vMWKZjpoxVolT6G_y51Q?usp=drive_link)

This repository contains the complete **Phase I** deliverable (30% weightage) for **Modern Computer Architecture**: a cycle-accurate, synthetically verifiable **4 KB Direct-Mapped L1 Cache Controller** implemented in Verilog HDL with write-back and write-allocate policies, accompanied by comprehensive directed and trace-driven verification testbenches, GTKWave waveform artifacts, a timed 5-member video demonstration, and a publication-format IEEEtran technical conference report.

---

## Phase I Submission Deliverables Summary

| Deliverable | Evaluation Weight | Primary Artefact Links | Description |
|---|---|---|---|
| **1. IEEE Project Report** | **10 Marks** | • [Compiled PDF](docs/phase1_report.pdf)<br>• [LaTeX Source](docs/report/main.tex)<br>• [BibTeX References](docs/report/references.bib) | Full IEEEtran manuscript covering Abstract, Literature Review, Microarchitectural Solution, Subsystem Verification, Individual Contributions, and verified references. |
| **2. Prototype Demonstration Video** | **15 Marks** | • [**Video Link (Google Drive)**](https://drive.google.com/drive/folders/1WNsOvDRVHSj_vMWKZjpoxVolT6G_y51Q?usp=drive_link)<br>• [Timed Demo Script](docs/video_script.md) | 4:45 technical walkthrough introducing all 5 members, presenting block/FSM diagrams, live simulation execution, GTKWave waveform analysis, and 75.00% hit rate trace verification. |
| **3. GitHub Repository & Code Artefacts** | **5 Marks** | • [GitHub Repository](https://github.com/Sadhvik999/mca_project)<br>• [RTL Directory](rtl/)<br>• [Verification Suites](tb/)<br>• [Simulation Logs](results/) | Modular RTL modules, self-checking testbenches, trace benchmarks, architectural diagrams, reproducible simulation runner, and verified commit history across all 5 members. |

---

## Prototype Video Demonstration (15 Marks)

- **Video Access Link**: **[Google Drive Folder](https://drive.google.com/drive/folders/1WNsOvDRVHSj_vMWKZjpoxVolT6G_y51Q?usp=drive_link)**
- **Timed Script Reference**: [`docs/video_script.md`](docs/video_script.md) (Target Runtime: 4:45 $\le$ 5 minutes)

### Video Presentation Structure & Member Introductions

| Timestamp | Presenter | Roll No. | Topic / Demonstration Point | Visual Artefact |
|---|---|---|---|---|
| **0:00 – 0:30** | All 5 Members | — | **Team Introductions**: Mustyala Sadhvik, Varun Udata, Amogha Raj Sandur, Yachna Khanna, Shrihari K N. | Title Slide / Video Camera |
| **0:30 – 1:12** | Mustyala Sadhvik (M1) | 2401020099 | **Project Concept & Address Partitioning**: 4 KB direct-mapped cache, 16-byte lines, 20-bit tag, 8-bit index, 2-bit word, 2-bit byte offset. | [`docs/diagrams/address_split.md`](docs/diagrams/address_split.md), [`block_diagram.md`](docs/diagrams/block_diagram.md) |
| **1:12 – 1:49** | Varun Udata (M2) | 2401010481 | **Storage Arrays & Memory Handshake**: 256-line Data Array, 32-bit word muxing, 128-bit block bus, 10-cycle memory latency model. | [`rtl/data_array.v`](rtl/data_array.v), [`rtl/main_memory.v`](rtl/main_memory.v) |
| **1:49 – 2:33** | Amogha Raj Sandur (M3) | 2401010397 | **Cache Controller FSM**: 4 states (`IDLE`, `COMPARE_TAG`, `WRITE_BACK`, `ALLOCATE`), single-cycle hit, dirty write-back before refill. | [`docs/diagrams/fsm_diagram.md`](docs/diagrams/fsm_diagram.md), [`rtl/cache_controller.v`](rtl/cache_controller.v) |
| **2:33 – 3:52** | Yachna Khanna (M4) | 2401010509 | **Live Simulation & Waveform Inspection**: Directed test execution (`run_sim.sh`), cold misses, hits, dirty evictions, GTKWave trace analysis. | [`docs/waveforms/README.md`](docs/waveforms/README.md), GTKWave (`cache_directed.vcd`) |
| **3:52 – 4:45** | Shrihari K N (M5) | 2401010448 | **Performance Counters & Trace Verification**: 1,024 sequential reads, 768 hits, 256 misses, 75.00% hit rate, summary & closing. | [`rtl/perf_counters.v`](rtl/perf_counters.v), Sequential Trace (`tb_trace`) |

---

## Team Members & Individual Contributions

The project was executed in strictly sequential, collaborative stages. All 5 members authored their respective RTL modules, self-checking testbenches, and report sections:

| Member | Stage | Roll No. | Core RTL / Verification Module | Assigned Report Sections | Primary Deliverable |
|---|---|---|---|---|---|
| **Mustyala Sadhvik** | M1 | 2401020099 | [`rtl/tag_array.v`](rtl/tag_array.v), [`tb/tb_tag_array.v`](tb/tb_tag_array.v) | Abstract, Section I (Intro), Section II-A (Locality & Orgs) | Repository structure, address split specs, Tag Array with async read & `set_dirty`, 271 unit tests passed. |
| **Varun Udata** | M2 | 2401010481 | [`rtl/data_array.v`](rtl/data_array.v), [`rtl/main_memory.v`](rtl/main_memory.v), [`tb/tb_data_array.v`](tb/tb_data_array.v), [`tb/tb_main_memory.v`](tb/tb_main_memory.v) | Section II-B (Write Policies), Section III-C & E (Datapath & Memory) | 256-line Data Array, 10-cycle backing memory model with `$readmemh` preload, memory model spec, 325 unit tests passed. |
| **Amogha Raj Sandur** | M3 | 2401010397 | [`rtl/cache_controller.v`](rtl/cache_controller.v), [`rtl/cache_top.v`](rtl/cache_top.v), [`tb/tb_smoke.v`](tb/tb_smoke.v) | Section II-C (Miss Classes), Section III-A & D (Architecture & FSM) | 4-state Mealy FSM controller, top-level integration, smoke test with dirty eviction & refill replay, FSM transition table. |
| **Yachna Khanna** | M4 | 2401010509 | [`tb/tb_cache.v`](tb/tb_cache.v), [`tb/tb_directed.v`](tb/tb_directed.v), [`scripts/run_sim.sh`](scripts/run_sim.sh) | Section II-D (Verification Methods), Section IV-B (Directed Results) | Golden reference memory model, 8-case directed verification suite (TC-01 to TC-08, 60 checks), simulation runner script, GTKWave waveform guide. |
| **Shrihari K N** | M5 | 2401010448 | [`rtl/perf_counters.v`](rtl/perf_counters.v), [`tb/tb_trace.v`](tb/tb_trace.v), [`scripts/gen_trace.py`](scripts/gen_trace.py) | Section II-E (FPGA Review), Section IV-C (Trace Results), Section V & VI | Hardware performance counters, sequential trace generator (1,024 accesses), trace verification harness (75.00% hit rate), report assembly. |

---

## Architectural & Design Specifications

| Parameter | Specification | Details / Description |
|---|---|---|
| **Cache Capacity** | 4 KB ($4096\text{ bytes}$) | Total on-chip SRAM data capacity |
| **Organization** | Direct-Mapped | 1 way per set ($S = 256$ lines) |
| **Block / Line Size** | 16 Bytes | 4 words ($4 \times 32\text{ bits} = 128\text{ bits}$ block bus) |
| **Number of Cache Lines** | 256 | Indexed via $2^8 = 256$ entries |
| **Physical Address Width** | 32 bits | Byte-addressable physical memory space |
| **Tag Field** | Bits `[31:12]` (20 bits) | Compared in single cycle to verify cache hit |
| **Index Field** | Bits `[11:4]` (8 bits) | Addresses line in Tag and Data Arrays ($0 \dots 255$) |
| **Block (Word) Offset** | Bits `[3:2]` (2 bits) | Selects 32-bit word within 128-bit cache line block |
| **Byte Offset** | Bits `[1:0]` (2 bits) | Byte alignment within 32-bit word |
| **Line Metadata** | Valid, Dirty, Tag[19:0] | 1 valid bit, 1 dirty bit, 20-bit tag per line |
| **Write Policy** | Write-Back + Write-Allocate | CPU writes update cache and set dirty; dirty blocks written to memory on eviction |
| **Concurrency Mode** | Blocking | Single outstanding transaction serviced at a time |
| **Backing Memory Latency**| `MEM_LATENCY = 10` cycles | Block-wide 128-bit memory transfer handshake |
| **Controller States** | `IDLE`, `COMPARE_TAG`, `WRITE_BACK`, `ALLOCATE` | 4-state Mealy FSM |

---

## Repository Structure & Project Artefacts

```text
mca_project/
├── CONTRIBUTING.md                # Collaboration standards, branch conventions, and commit policies
├── README.md                      # Primary Phase I submission documentation
├── docs/                          # Architectural and technical documentation
│   ├── phase1_report.pdf          # Compiled Phase I IEEE conference report (PDF)
│   ├── memory_model_spec.md       # Memory subsystem and latency handshake specifications
│   ├── test_plan.md               # Directed verification matrix and coverage goals
│   ├── video_script.md            # Timed 5-member video presentation script (4:45)
│   ├── diagrams/                  # Architectural diagrams and specifications
│   │   ├── address_split.md       # 32-bit address field decomposition and worked examples
│   │   ├── block_diagram.md       # Microarchitectural Mermaid block diagram
│   │   └── fsm_diagram.md         # Mealy FSM state transitions and handshake timing
│   ├── report/                    # LaTeX IEEEtran report source files
│   │   ├── main.tex               # Primary IEEE conference LaTeX manuscript
│   │   ├── references.bib         # Verified classic architectural references
│   │   └── README.md              # Compilation guide for local pdflatex and Overleaf
│   └── waveforms/                 # GTKWave inspection documentation
│       ├── README.md              # Waveform navigation guide for directed testcases TC-01..TC-08
│       └── sim_log.txt            # Directed testbench console output log
├── results/                       # Verification logs and execution summaries
│   ├── simulation_summary.md      # Consolidated verification summary across all testbenches
│   ├── tag_array_simulation.log   # M1 Tag Array unit test log (271 checks passed)
│   ├── data_array_simulation.log  # M2 Data Array unit test log (283 checks passed)
│   ├── main_memory_simulation.log # M2 Main Memory model test log (42 checks passed)
│   └── cache_top_smoke_simulation.log # M3 Integrated smoke test log (PASS)
├── rtl/                           # Synthesizable Verilog RTL source code
│   ├── tag_array.v                # 256-entry Tag Array with valid & dirty tracking (M1)
│   ├── data_array.v               # 256-entry x 128-bit Data Array with word multiplexing (M2)
│   ├── main_memory.v              # Backing memory model with 10-cycle latency handshake (M2)
│   ├── cache_controller.v         # 4-state Mealy FSM Cache Controller (M3)
│   ├── cache_top.v                # Top-level cache controller integrating arrays and memory (M3)
│   └── perf_counters.v            # Performance counters for hits, misses, evictions, cycles (M5)
├── scripts/                       # Simulation automation and trace generators
│   ├── run_sim.sh                 # Unified bash runner for directed, smoke, and trace suites
│   ├── gen_mem_init.py            # Generates deterministic 64K-word memory preload hex file
│   └── gen_trace.py               # Generates synthetic memory trace access files
├── tb/                            # Verilog self-checking testbenches
│   ├── tb_tag_array.v             # Unit testbench for tag_array (271 assertions)
│   ├── tb_data_array.v            # Unit testbench for data_array (283 assertions)
│   ├── tb_main_memory.v           # Unit testbench for main_memory (42 assertions)
│   ├── tb_smoke.v                 # Integration smoke testbench
│   ├── tb_cache.v                 # Golden reference software memory model
│   ├── tb_directed.v              # 8-scenario directed verification suite (60 assertions)
│   └── tb_trace.v                 # Benchmark memory trace driver and scoreboard
└── traces/                        # Trace benchmarks and initialization data
    ├── mem_init.hex               # 65,536-word backing memory initial state
    └── sequential.txt             # 1,024-operation sequential word access benchmark
```

---

## How to Run & Verify All Artefacts

### Prerequisites
- **Icarus Verilog** (`iverilog` and `vvp`, version 10+ or 13+)
- **Python 3** (for trace generation and memory initialization)
- **GTKWave** (optional, for inspecting `.vcd` waveform dumps)
- **LaTeX / pdflatex** or **Overleaf** (for report compilation)

### 1. Unified Automated Simulation Runner
The easiest way to execute all tests is via the provided shell script:

```bash
# Run directed test suite (TC-01 through TC-08, 60 assertions)
./scripts/run_sim.sh --test tb_directed

# Run entire verification suite (smoke, directed, and golden model checks)
./scripts/run_sim.sh --test all
```

### 2. Sequential Benchmark Trace Verification (75.00% Hit Rate)
Run the 1,024-access sequential word trace to verify cache hit rate and performance counters:

```bash
# 1. Generate sequential memory trace
python3 scripts/gen_trace.py --pattern sequential --count 1024 --output traces/sequential.txt

# 2. Compile and run trace driver testbench
mkdir -p build
iverilog -g2012 -Wall -s tb_trace -o build/tb_trace.vvp rtl/*.v tb/tb_trace.v
vvp build/tb_trace.vvp +TRACE=traces/sequential.txt
```

**Benchmark Output:**
- Total Operations: **1,024**
- Cache Hits: **768**
- Cache Misses: **256**
- Write-backs: **0**
- Execution Cycles: **5,121**
- **Measured Hit Rate**: **75.00%** (Exactly 1 cold compulsory miss followed by 3 spatial hits per 16-byte block)

### 3. Module-Level Unit Testbenches
Each individual hardware module is self-checking:

```bash
# Tag Array (M1): 271 assertions checked
iverilog -g2012 -o tb/tb_tag_array.vvp rtl/tag_array.v tb/tb_tag_array.v && vvp tb/tb_tag_array.vvp

# Data Array (M2): 283 assertions checked
iverilog -g2012 -o tb/tb_data_array.vvp rtl/data_array.v tb/tb_data_array.v && vvp tb/tb_data_array.vvp

# Main Memory Model (M2): 42 assertions checked
iverilog -g2012 -o tb/tb_main_memory.vvp rtl/main_memory.v tb/tb_main_memory.v && vvp tb/tb_main_memory.vvp

# Integrated Cache Smoke Test (M3): 4 end-to-end scenarios
iverilog -g2012 -Wall -s tb_smoke -o build/tb_smoke.vvp rtl/*.v tb/tb_smoke.v && vvp build/tb_smoke.vvp +vcd
```

### 4. Waveform Inspection in GTKWave
To inspect the cycle-accurate signals (state, tag match, memory handshake) from the directed test suite:

```bash
gtkwave docs/waveforms/cache_directed.vcd
```
Refer to the [Waveform Guide](docs/waveforms/README.md) for marker locations of TC-01 through TC-08.

### 5. Compiling the Technical Report
```bash
cd docs/report
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
cp main.pdf ../phase1_report.pdf
```
Alternatively, upload `docs/report/` to [Overleaf](https://www.overleaf.com/) and compile using pdfLaTeX.
