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
  - `mem_addr` (Output, 32-bit): Block-aligned address formed with the victim tag on write-back and the requested tag on refill.
  - `mem_wdata` (Output, 128-bit): 16-byte block written back to memory.
  - `mem_rdata` (Input, 128-bit): 16-byte block fetched from memory.
  - `mem_ready` (Input): High when backing memory transfer completes (after 10 cycles).

---

## Team Members & Responsibilities

The project is developed sequentially by a team of 5 members adhering strictly to the handoff protocol:

| Member | Stage | Role & Key Responsibilities | Branch | Status |
|---|---|---|---|---|
| **M1** | Stage 1 | Repository foundation, directory layout, `.gitignore`, IEEEtran report skeleton & references, address split spec, block diagram, `tag_array.v` RTL, self-checking `tb_tag_array.v`, Abstract & Introduction & Lit Review (Locality/Orgs). | `feature/foundation` | [x] Completed |
| **M2** | Stage 2 | Data storage array (`data_array.v`), read/write word masking logic, `tb_data_array.v`, top-level cache structure integration. | `feature/data-array` | [ ] Pending |
| **M3** | Stage 3 | Cache controller FSM (`cache_controller.v`), hit/miss evaluation, write-back and allocate sequence control. | `feature/fsm-controller` | [x] Completed |
| **M4** | Stage 4 | Backing memory behavioral model (`memory_model.v`, 10-cycle latency), system testbench (`tb_cache_top.v`), synthetic memory trace driver. | `feature/system-tb` | [ ] Pending |
| **M5** | Stage 5 | Performance benchmarks & hit rate / AMAT analysis, GTKWave waveform generation, video demonstration script, final report synthesis. | `feature/eval-final` | [ ] Pending |

---

## Directory Structure

```text
mca_project/
├── .gitignore                     # Ignores simulation dumps, binaries, and LaTeX aux files
├── CONTRIBUTING.md                # Collaboration guidelines, branch & commit standards
├── README.md                      # Project documentation and specifications
├── docs/                          # Architectural and technical documentation
│   ├── diagrams/                  # Markdown/Mermaid block diagrams & address split tables
│   │   ├── address_split.md       # Detailed bit-field breakdown and worked examples
│   │   └── block_diagram.md       # Full microarchitecture Mermaid block diagram
│   ├── report/                    # IEEEtran conference report source
│   │   ├── main.tex               # LaTeX source document
│   │   ├── references.bib         # Verified classic architectural references
│   │   └── README.md              # Report compilation instructions
│   └── waveforms/                 # GTKWave configuration and captured waveform screenshots
├── results/                       # Simulation logs, benchmarks, and performance metrics
├── rtl/                           # Verilog synthesizable RTL source code
│   └── tag_array.v                # 256-line Tag Array with valid & dirty bit tracking
├── scripts/                       # Trace generation and evaluation utility scripts
├── tb/                            # Verilog self-checking testbenches
│   └── tb_tag_array.v             # Comprehensive verification suite for tag_array
└── traces/                        # Benchmark memory trace files (read/write sequences)
```

---

## How to Run & Verification

### Prerequisites
- **Icarus Verilog** (`iverilog` v10+ or v13+)
- **GTKWave** (for viewing `.vcd` waveform dumps)
- **Python 3** (for analysis and trace generators)
- **LaTeX / pdflatex** or **Overleaf** (for IEEEtran report compilation)

### Compiling and Testing RTL Modules

#### 1. Tag Array Module (`tag_array.v`)
```bash
# Compile tag_array testbench
iverilog -g2012 -o tb/tb_tag_array.vvp rtl/tag_array.v tb/tb_tag_array.v

# Run self-checking simulation
vvp tb/tb_tag_array.vvp

# (Optional) Open waveform in GTKWave
gtkwave tb/tag_array.vcd
```

#### 2. Integrated Cache Smoke Test

Run from the repository root so the memory model can load `traces/mem_init.hex`.

```bash
mkdir -p build
iverilog -g2012 -Wall -s tb_smoke -o build/tb_smoke.vvp rtl/*.v tb/tb_smoke.v
vvp build/tb_smoke.vvp +vcd
# Optional waveform viewer
gtkwave build/smoke.vcd
```

The smoke test checks a cold read miss, a repeated hit, a write hit, write allocation,
and dirty write-back. See the [FSM and CPU handshake](docs/diagrams/fsm_diagram.md)
for the debug outputs and the edge on which to sample `ready`.

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

- [x] Repository architecture, directory structure, and contribution rules established.
- [x] Detailed address split mapping and microarchitectural block diagrams documented.
- [x] Synthesizable Tag Array (`tag_array.v`) implemented with synchronous reset and dirty update.
- [x] Self-checking testbench (`tb_tag_array.v`) executed with 100% verification pass.
- [x] IEEEtran report skeleton initialized with verified classical citations.
- [x] Abstract, Introduction, and Literature Review Section II-A written.
- [ ] Data Array RTL and testbench (`M2`).
- [x] 4-state Cache Controller FSM and integrated smoke test (`M3`).
- [ ] Behavioral Main Memory Model with 10-cycle latency (`M4`).
- [ ] System-level trace verification & hit rate analysis (`M4`/`M5`).
- [ ] Final 5-minute video demonstration script and presentation (`M5`).
