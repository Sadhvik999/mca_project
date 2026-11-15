# Direct-Mapped Cache Controller in Verilog (Phase I)

[![Course](https://img.shields.io/badge/Course-Modern%20Computer%20Architecture-blue.svg)](#)
[![Simulation](https://img.shields.io/badge/Simulator-Icarus%20Verilog%2013.0-green.svg)](#)
[![Report](https://img.shields.io/badge/Format-IEEEtran-red.svg)](#)

## Overview

This project implements a synthetically verifiable, cycle-accurate **Direct-Mapped L1 Cache Controller** designed in Verilog HDL. The cache bridges a high-performance 32-bit pipelined processor core and a high-latency backing main memory subsystem. The design employs a **write-back** policy with **write-allocate** on write misses, minimizing redundant bus transactions while guaranteeing memory coherence upon eviction.

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

The project is developed sequentially by a team of 5 members adhering strictly to the handoff protocol:

| Member | Stage | Role & Key Responsibilities | Branch | Status |
|---|---|---|---|---|
| **M1 (Mustyala Sadhvik)** | Stage 1 | Repository foundation, directory layout, `.gitignore`, IEEEtran report skeleton & references, address split spec, block diagram, `tag_array.v` RTL, self-checking `tb_tag_array.v`, Abstract & Introduction & Lit Review (Locality/Orgs). | `feature/foundation` | [x] Completed |
| **M2 (Varun Udata)** | Stage 2 | Data storage array (`data_array.v`), main memory model (`main_memory.v`), self-checking testbenches (`tb_data_array.v`, `tb_main_memory.v`), memory init script (`gen_mem_init.py`), write policy & datapath report sections. | `feature/data-and-memory` | [x] Completed |
| **M3 (Amogha Raj Sandur)** | Stage 3 | Cache controller FSM (`cache_controller.v`), top-level cache integration (`cache_top.v`), smoke testbench (`tb_smoke.v`), FSM diagrams, and controller report sections. | `feature/fsm-controller` | [x] Completed |
| **M4 (Team Member 4)** | Stage 4 | Memory trace driver, benchmark execution framework, system verification testbench (`tb_cache_top.v`). | `feature/system-tb` | [ ] Pending |
| **M5 (Team Member 5)** | Stage 5 | Performance benchmarks & hit rate / AMAT analysis, GTKWave waveform generation, video demonstration script, final report synthesis. | `feature/eval-final` | [ ] Pending |

---

## Directory Structure

```text
mca_project/
├── .gitignore                     # Ignores simulation dumps, binaries, and LaTeX aux files
├── CONTRIBUTING.md                # Collaboration guidelines, branch & commit standards
├── README.md                      # Project documentation and specifications
├── docs/                          # Architectural and technical documentation
│   ├── memory_model_spec.md       # Memory subsystem and latency handshake specifications
│   ├── diagrams/                  # Microarchitectural diagrams & address split tables
│   │   ├── address_split.md       # Detailed bit-field breakdown and worked examples
│   │   ├── block_diagram.md       # Full microarchitecture Mermaid block diagram
│   │   └── fsm_diagram.md         # Mealy/Moore FSM state transitions and handshake timing
│   ├── report/                    # IEEEtran conference report source
│   │   ├── main.tex               # Primary LaTeX manuscript
│   │   ├── references.bib         # Verified classic architectural references
│   │   └── README.md              # Report compilation instructions
│   └── waveforms/                 # GTKWave configuration and captured waveforms
├── results/                       # Simulation logs, benchmarks, and performance metrics
│   ├── simulation_summary.md      # Summary of all module & integrated test outputs
│   ├── tag_array_simulation.log   # M1 Tag Array testbench execution log (271 checks passed)
│   ├── data_array_simulation.log  # M2 Data Array testbench execution log (283 checks passed)
│   ├── main_memory_simulation.log # M2 Main Memory testbench execution log (42 checks passed)
│   └── cache_top_smoke_simulation.log # M3 Integrated Cache Controller smoke test log (PASS)
├── rtl/                           # Synthesizable Verilog RTL source files
│   ├── tag_array.v                # 256-line Tag Array with valid & dirty bit tracking
│   ├── data_array.v               # 256-line x 128-bit Data Array with word multiplexing
│   ├── main_memory.v              # Backing memory model with 10-cycle latency handshake
│   ├── cache_controller.v         # 4-state Mealy FSM Cache Controller
│   └── cache_top.v                # Top-level cache module integrating controller and arrays
├── scripts/                       # Trace generation and evaluation utility scripts
│   └── gen_mem_init.py            # Generates deterministic memory preload hex file
├── tb/                            # Verilog self-checking testbenches
│   ├── tb_tag_array.v             # Verification suite for tag_array
│   ├── tb_data_array.v            # Verification suite for data_array
│   ├── tb_main_memory.v           # Verification suite for main_memory model
│   └── tb_smoke.v                 # End-to-end integrated cache controller verification
└── traces/                        # Benchmark memory trace files
    └── mem_init.hex               # 64K-word memory initialization hex file
```

---

## How to Run & Verification

### Prerequisites
- **Icarus Verilog** (`iverilog` v10+ or v13+)
- **GTKWave** (for viewing `.vcd` waveform dumps)
- **Python 3** (for analysis and trace generators)
- **LaTeX / pdflatex** or **Overleaf** (for IEEEtran report compilation)

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

### Compiling the Technical Report
```bash
cd docs/report
pdflatex main.tex
bibtex main
pdflatex main.tex
pdflatex main.tex
```

---

## Technical Demonstration Video

- **Video Link**: TBD (5-minute demonstration video link will be provided upon completion of Phase I).

---

## Phase I Milestone Checklist

- [x] Repository architecture, directory structure, and contribution rules established (`M1`).
- [x] Detailed address split mapping and microarchitectural block diagrams documented (`M1`).
- [x] Synthesizable Tag Array (`tag_array.v`) implemented with synchronous reset and dirty update (`M1`).
- [x] Self-checking testbench (`tb_tag_array.v`) executed with 100% verification pass (`M1`).
- [x] IEEEtran report skeleton initialized with verified classical citations (`M1`).
- [x] Abstract, Introduction, and Literature Review Section II-A written (`M1`).
- [x] Synthesizable Data Array (`data_array.v`) and unit testbench (`tb_data_array.v`) implemented (`M2`).
- [x] Backing Main Memory behavioral model (`main_memory.v`) with 10-cycle latency handshake (`M2`).
- [x] 4-state Cache Controller FSM (`cache_controller.v`) and top integration (`cache_top.v`) implemented (`M3`).
- [x] Integrated cache smoke test (`tb_smoke.v`) verified with 100% pass (`M3`).
- [x] Simulation logs and verification summary updated in `results/` (`M1`--`M3`).
- [ ] System-level trace verification & hit rate analysis (`M4`/`M5`).
- [ ] Final 5-minute video demonstration script and presentation (`M5`).
