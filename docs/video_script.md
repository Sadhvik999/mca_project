# Phase I demo script

**Target runtime 4:45.** Open the block diagram, FSM diagram, and GTKWave before recording. Keep a terminal in the repository root.

## 0:00–0:30 · Team introductions

| Time | Speaker | Say |
|---|---|---|
| 0:00–0:06 | M1 | “Mustyala Sadhvik, roll 2401020099. Direct-mapped Verilog cache.” |
| 0:06–0:12 | M2 | “Varun Udata, roll 2401010481. Four-word cache blocks.” |
| 0:12–0:18 | M3 | “Amogha Raj Sandur, roll 2401010397. Cache controller FSM.” |
| 0:18–0:24 | M4 | “Yachna Khanna, roll 2401010509. Cache verification.” |
| 0:24–0:30 | M5 | “Shrihari K N, roll 2401010448. Cache performance counters.” |

## 0:30–1:12 · M1 · Problem and address split

*Show the [block diagram](diagrams/block_diagram.md) and point to the tag array.*

“Backing memory takes 10 cycles in our model. The cache keeps blocks near the CPU so it can serve hits from the array. Our 4 KB cache has 256 lines, each with a 16-byte block. Bits 11 through 4 select one line. Bits 31 through 12 identify the block mapped there, bits 3 and 2 select one of four words, and bits 1 and 0 are the byte offset. The tag array supplies the stored tag and the valid and dirty bits.”

## 1:12–1:49 · M2 · Arrays and backing memory

*Show `rtl/data_array.v` and `rtl/main_memory.v`.*

“The CPU reads or writes 32 bits at a time. The data array uses the word offset to select that word. A refill or write-back moves all 128 bits of the block. A CPU store sets the dirty bit. Main memory sees the modified data when the controller evicts that line. The memory model pulses `mem_ready` when the block transfer completes.”

## 1:49–2:33 · M3 · FSM and top-level wiring

*Show the [FSM diagram](diagrams/fsm_diagram.md), then `rtl/cache_controller.v`.*

“In IDLE, the controller captures one CPU request. COMPARE_TAG checks the valid bit and tag. A hit asserts `ready`. A clean miss goes straight to ALLOCATE. A dirty miss goes to WRITE_BACK first, so backing memory receives the old block at its own address. ALLOCATE then fetches the requested block. When memory signals completion, the arrays capture it and the controller returns to COMPARE_TAG to finish the original request.”

## 2:33–3:52 · M4 · Live simulation and waveforms

*Run `./scripts/run_sim.sh --test tb_directed`. Open or reload `docs/waveforms/cache_directed.vcd` in GTKWave and move between TC-01, TC-02, TC-03 and TC-07.*

- **2:33–2:52 · Cold read miss.** “TC-01 reads `0x00000028`. Watch `miss` pulse, the block at `0x00000020` arrive, and `ready` return `0x0000000A`.”
- **2:52–3:08 · Read hit.** “TC-02 repeats that address. This time `hit` and `ready` assert in COMPARE_TAG. `mem_req` stays low.”
- **3:08–3:25 · Write hit.** “TC-03 writes `0xDEADBEEF` to the same word. `write_word_en` asserts and the line becomes dirty.”
- **3:25–3:52 · Dirty eviction.** “TC-07 accesses `0x00001028`, which maps to the same line with a different tag. `mem_we` is high during WRITE_BACK and low during ALLOCATE. Reading the original address again recovers the stored data. The suite reports 60 successful checks and zero failures.”

## 3:52–4:45 · M5 · Counters and closing

*Show `rtl/perf_counters.v`. Run the trace commands from the README, with the simulator binary built in advance for the live run.*

“The counters record the initial hit or miss once per request. A miss replays after refill without adding a hit. A write-back increments when the block write completes. The replay test also checks the returned data against a reference memory model.”

*Run `vvp build/tb_trace.vvp +TRACE=traces/sequential.txt` and point to the output.*

“We ran 1,024 sequential reads. The first read of each block missed, and the next three hit. Icarus reports 768 hits, 256 misses, and zero write-backs, for a 75 percent hit rate. That completes our Phase I prototype. The repository includes the RTL, test commands, waveforms guide, and report. Thank you.”
