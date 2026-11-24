# Parameterized Sweeps, Miss Classification, and AMAT Analysis

This document records the Phase II Stage 4 evaluation conducted by **Yachna Khanna (M4)**.
It provides full empirical verification of the cache controller across:
- **48 Hardware Configurations**: 4 cache sizes (1, 2, 4, 8 KB) × 3 block sizes (8, 16, 32 B) × 4 workloads (sequential, strided, conflict, random).
- **Classic 3Cs Miss Decomposition**: Compulsory vs Capacity vs Conflict breakdown (Mark D. Hill 1988).
- **AMAT Sensitivity**: Cycle-accurate average memory access time across memory latencies and geometries.
- **Conflict Resolution Threshold**: Elimination of direct-mapped ping-pong thrashing at 8 KB capacity.

---

## 1. Reproduction Commands

From the repository root (`mca_project`):

```bash
# 1. Run full 48-configuration sweep across all 4 traces
python3 scripts/run_all_sweeps.py

# 2. Run 3Cs miss classification analysis
python3 scripts/miss_classification.py

# 3. Generate high-resolution evaluation plots (PNG & PDF)
python3 scripts/plot_results.py

# 4. Run full regression suite across all Phase I and Phase II testbenches
./scripts/run_sim.sh --test all
iverilog -g2012 -Wall -s tb_corner_cases -o build/tb_corner_cases.vvp rtl/*.v tb/tb_corner_cases.v && vvp build/tb_corner_cases.vvp
iverilog -g2012 -Wall -s tb_param_check -o build/tb_param_check.vvp rtl/*.v tb/tb_param_check.v && vvp build/tb_param_check.vvp
```

Generated artefacts:
- `results/sweep_*.csv` and `results/sweep_all_traces.csv`: Raw hardware counter logs.
- `results/param_sweeps_amat.csv`: Complete AMAT and miss penalty table for all 48 configurations.
- `results/miss_classification.csv`: Compulsory, Capacity, and Conflict decomposition.
- `results/plots/`: High-resolution figures (`hit_rate_by_config`, `amat_vs_latency`, `miss_classification_breakdown`, `conflict_resolution_amat`).
- `results/m4_regression.log`: Full simulation log with zero errors.

---

## 2. Comprehensive 48-Configuration AMAT & Counter Results

Measured under default backing memory latency `MEM_LATENCY = 10` cycles ($T_{\mathrm{hit}} = 2$ cycles):

| Trace | Config | Accesses | Hits | Misses | Dirty WB | Total Cycles | Hit Rate | Miss Rate | Miss Penalty | AMAT (Cycles) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Sequential** | 1KB_8B  | 1024 | 512 | 512 | 0 | 8193 | 50.00% | 50.00% | 12.00 | 8.00 |
| Sequential | 1KB_16B | 1024 | 768 | 256 | 0 | 5121 | 75.00% | 25.00% | 12.00 | 5.00 |
| Sequential | 1KB_32B | 1024 | 896 | 128 | 0 | 3585 | 87.50% | 12.50% | 12.00 | 3.50 |
| Sequential | 2KB_8B  | 1024 | 512 | 512 | 0 | 8193 | 50.00% | 50.00% | 12.00 | 8.00 |
| Sequential | 2KB_16B | 1024 | 768 | 256 | 0 | 5121 | 75.00% | 25.00% | 12.00 | 5.00 |
| Sequential | 2KB_32B | 1024 | 896 | 128 | 0 | 3585 | 87.50% | 12.50% | 12.00 | 3.50 |
| Sequential | 4KB_8B  | 1024 | 512 | 512 | 0 | 8193 | 50.00% | 50.00% | 12.00 | 8.00 |
| **Sequential (Default)** | **4KB_16B** | **1024** | **768** | **256** | **0** | **5121** | **75.00%** | **25.00%** | **12.00** | **5.00** |
| Sequential | 4KB_32B | 1024 | 896 | 128 | 0 | 3585 | 87.50% | 12.50% | 12.00 | 3.50 |
| Sequential | 8KB_8B  | 1024 | 512 | 512 | 0 | 8193 | 50.00% | 50.00% | 12.00 | 8.00 |
| Sequential | 8KB_16B | 1024 | 768 | 256 | 0 | 5121 | 75.00% | 25.00% | 12.00 | 5.00 |
| Sequential | 8KB_32B | 1024 | 896 | 128 | 0 | 3585 | 87.50% | 12.50% | 12.00 | 3.50 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Strided** | 1KB_8B  | 1024 | 0 | 1024 | 0 | 14337 | 0.00% | 100.00% | 12.00 | 14.00 |
| Strided | 1KB_16B | 1024 | 0 | 1024 | 0 | 14337 | 0.00% | 100.00% | 12.00 | 14.00 |
| Strided | 1KB_32B | 1024 | 256 | 768 | 0 | 11265 | 25.00% | 75.00% | 12.00 | 11.00 |
| Strided | 2KB_8B  | 1024 | 0 | 1024 | 0 | 14337 | 0.00% | 100.00% | 12.00 | 14.00 |
| Strided | 2KB_16B | 1024 | 0 | 1024 | 0 | 14337 | 0.00% | 100.00% | 12.00 | 14.00 |
| Strided | 2KB_32B | 1024 | 256 | 768 | 0 | 11265 | 25.00% | 75.00% | 12.00 | 11.00 |
| Strided | 4KB_8B  | 1024 | 0 | 1024 | 0 | 14337 | 0.00% | 100.00% | 12.00 | 14.00 |
| **Strided (Default)** | **4KB_16B** | **1024** | **0** | **1024** | **0** | **14337** | **0.00%** | **100.00%** | **12.00** | **14.00** |
| Strided | 4KB_32B | 1024 | 256 | 768 | 0 | 11265 | 25.00% | 75.00% | 12.00 | 11.00 |
| Strided | 8KB_8B  | 1024 | 510 | 514 | 0 | 8217 | 49.80% | 50.20% | 12.00 | 8.02 |
| Strided | 8KB_16B | 1024 | 510 | 514 | 0 | 8217 | 49.80% | 50.20% | 12.00 | 8.02 |
| Strided | 8KB_32B | 1024 | 766 | 258 | 0 | 5145 | 74.80% | 25.20% | 12.00 | 5.02 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Conflict** | 1KB_8B  | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 1KB_16B | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 1KB_32B | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 2KB_8B  | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 2KB_16B | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 2KB_32B | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 4KB_8B  | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| **Conflict (Default)** | **4KB_16B** | **1024** | **0** | **1024** | **256** | **17153** | **0.00%** | **100.00%** | **14.75** | **16.75** |
| Conflict | 4KB_32B | 1024 | 0 | 1024 | 256 | 17153 | 0.00% | 100.00% | 14.75 | 16.75 |
| Conflict | 8KB_8B  | 1024 | 1022 | 2 | 0 | 2073 | 99.80% | 0.20% | 12.00 | 2.02 |
| **Conflict (8KB)** | **8KB_16B** | **1024** | **1022** | **2** | **0** | **2073** | **99.80%** | **0.20%** | **12.00** | **2.02** |
| Conflict | 8KB_32B | 1024 | 1022 | 2 | 0 | 2073 | 99.80% | 0.20% | 12.00 | 2.02 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Random** | 1KB_8B  | 1024 | 53 | 971 | 218 | 16099 | 5.18% | 94.82% | 14.47 | 15.72 |
| Random | 1KB_16B | 1024 | 55 | 969 | 228 | 16185 | 5.37% | 94.63% | 14.59 | 15.80 |
| Random | 1KB_32B | 1024 | 59 | 965 | 234 | 16203 | 5.76% | 94.24% | 14.67 | 15.82 |
| Random | 2KB_8B  | 1024 | 95 | 929 | 182 | 15199 | 9.28% | 90.72% | 14.15 | 14.84 |
| Random | 2KB_16B | 1024 | 111 | 913 | 215 | 15370 | 10.84% | 89.16% | 14.58 | 15.00 |
| Random | 2KB_32B | 1024 | 118 | 906 | 224 | 15385 | 11.52% | 88.48% | 14.72 | 15.02 |
| Random | 4KB_8B  | 1024 | 147 | 877 | 127 | 13970 | 14.36% | 85.64% | 13.59 | 13.64 |
| **Random (Default)** | **4KB_16B** | **1024** | **195** | **829** | **171** | **13878** | **19.04%** | **80.96%** | **14.27** | **13.55** |
| Random | 4KB_32B | 1024 | 239 | 785 | 197 | 13636 | 23.34% | 76.66% | 14.76 | 13.31 |
| Random | 8KB_8B  | 1024 | 194 | 830 | 65 | 12724 | 18.95% | 81.05% | 12.86 | 12.43 |
| Random | 8KB_16B | 1024 | 296 | 728 | 92 | 11797 | 28.91% | 71.09% | 13.39 | 11.52 |
| Random | 8KB_32B | 1024 | 395 | 629 | 124 | 10961 | 38.57% | 61.43% | 14.17 | 10.70 |

---

## 3. Miss Classification Breakdown (Mark D. Hill's 3Cs Taxonomy)

| Trace | Config | Total Misses | Compulsory | Capacity | Conflict | % Compulsory | % Conflict |
|---|---|---:|---:|---:|---:|---:|---:|
| Sequential | 4KB_8B | 512 | 512 | 0 | 0 | 100.0% | 0.0% |
| Sequential | 4KB_16B | 256 | 256 | 0 | 0 | 100.0% | 0.0% |
| Sequential | 4KB_32B | 128 | 128 | 0 | 0 | 100.0% | 0.0% |
| Strided | 4KB_16B | 1,024 | 514 | 0 | 510 | 50.2% | 49.8% |
| Strided | 8KB_16B | 514 | 514 | 0 | 0 | 100.0% | 0.0% |
| Conflict | 4KB_16B | 1,024 | 2 | 0 | 1,022 | 0.2% | 99.8% |
| Conflict | 8KB_16B | 2 | 2 | 0 | 0 | 100.0% | 0.0% |
| Random | 1KB_16B | 969 | 644 | 273 | 52 | 66.5% | 5.4% |
| Random | 4KB_16B | 829 | 644 | 133 | 52 | 77.7% | 6.3% |
| Random | 8KB_16B | 728 | 644 | 9 | 75 | 88.5% | 10.3% |

---

## 4. Key Architectural Insights for Viva Defense

1. **Why does Sequential hit rate double with block size?**
   Sequential word accesses experience strictly compulsory cold misses. In an $N$-word block, the first word misses, and the remaining $N-1$ words hit due to spatial locality.
   $$\text{Hit Rate} = \frac{N-1}{N}$$
   - 8 B ($N=2$): $1/2 = 50.00\%$
   - 16 B ($N=4$): $3/4 = 75.00\%$
   - 32 B ($N=8$): $7/8 = 87.50\%$

2. **Why does Conflict Ping-Pong resolve at 8 KB?**
   In a 4 KB cache with 16 B blocks ($S=256$ lines), the index is bits `[11:4]`. Addresses `0x0000` and `0x1000` have identical index bits (`8'h00`), colliding on set 0 and thrashing continuously.
   In an 8 KB cache ($S=512$ lines), the index widens to bits `[12:4]` (9 bits). Address `0x0000` maps to index `9'h000`, while `0x1000` maps to `9'h100` (line 256). The conflict is completely eliminated, reducing misses from 1,024 to 2 (99.80% hit rate) and AMAT from 16.75 to 2.02 cycles.

3. **What is the difference between Compulsory, Capacity, and Conflict misses?**
   - **Compulsory**: First time the cache ever sees that block (misses even in an infinite cache).
   - **Capacity**: Misses due to finite cache capacity (misses in fully-associative cache of size $C$).
   - **Conflict**: Misses resulting from multiple active blocks mapping to the same direct-mapped set (would hit in a fully-associative cache of size $C$).
