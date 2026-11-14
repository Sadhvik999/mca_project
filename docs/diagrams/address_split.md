# Cache Address Decomposition Specification

This document defines the mathematical derivation, bit-field segmentation, and concrete worked examples for the **4 KB Direct-Mapped L1 Cache** used in this project.

---

## 1. Mathematical Derivation of Bit Fields

Given the architectural design constraints:
- **Physical Address Width ($A$)**: 32 bits ($4\text{ GB}$ byte-addressable address space).
- **Total Cache Capacity ($C$)**: $4\text{ KB} = 4096\text{ bytes} = 2^{12}\text{ bytes}$.
- **Cache Block / Line Size ($B$)**: $16\text{ bytes} = 2^4\text{ bytes}$ ($4\text{ words} \times 32\text{ bits} = 128\text{ bits}$).
- **Associativity ($W$)**: Direct-Mapped ($1\text{ way}$).

The address bit-fields are partitioned into four distinct segments:
$$\text{Address}[31:0] = \{\text{Tag}[31:12],\; \text{Index}[11:4],\; \text{Block Offset}[3:2],\; \text{Byte Offset}[1:0]\}$$

### Field Width Calculations:
1. **Byte Offset ($b$)**:
   $$\text{Word Size} = 4\text{ bytes} \implies b = \log_2(4) = 2\text{ bits} \quad (\text{Bits } [1:0])$$
   Selects the target byte within a 32-bit processor word (used for byte/halfword operations).

2. **Block Offset / Word Offset ($w$)**:
   $$\text{Words per Block} = \frac{B}{\text{Word Size}} = \frac{16\text{ bytes}}{4\text{ bytes}} = 4 \implies w = \log_2(4) = 2\text{ bits} \quad (\text{Bits } [3:2])$$
   Selects one of the four 32-bit words within a 128-bit cache line block:
   - `2'b00`: Word 0 (Bytes 0--3)
   - `2'b01`: Word 1 (Bytes 4--7)
   - `2'b10`: Word 2 (Bytes 8--11)
   - `2'b11`: Word 3 (Bytes 12--15)

3. **Index ($s$)**:
   $$\text{Number of Lines (Sets) } S = \frac{C}{B \times W} = \frac{4096}{16 \times 1} = 256 \implies s = \log_2(256) = 8\text{ bits} \quad (\text{Bits } [11:4])$$
   Directly indexes one of the 256 cache lines in the Tag Array and Data Array.

4. **Tag ($t$)**:
   $$t = A - (s + w + b) = 32 - (8 + 2 + 2) = 20\text{ bits} \quad (\text{Bits } [31:12])$$
   Identifies the unique physical memory block occupying the addressed line.

---

## 2. Bit Width Specification Table

| Field Name | Bit Range | Width | Function / Purpose | Hardware Destination |
|---|---|---|---|---|
| **Tag** | `[31:12]` | 20 bits | Distinguishes which memory block is cached | Tag Array comparator |
| **Index** | `[11:4]` | 8 bits | Selects line index ($0 \text{ to } 255$) | Tag & Data Array address decoder |
| **Block Offset (Word)** | `[3:2]` | 2 bits | Selects 32-bit word in 128-bit block | Data Array word multiplexer |
| **Byte Offset** | `[1:0]` | 2 bits | Selects byte within 32-bit word | Sub-word alignment logic |
| **Total** | `[31:0]` | 32 bits | Full physical memory byte address | CPU address bus |

---

## 3. Worked Concrete Examples

### Example 1: Address `0x00012348`

Consider memory read request to address `0x00012348`:

- **Full 32-bit Hexadecimal**: `0x00012348`
- **Full 32-bit Binary**:
  ```text
  0000 0000 0000 0001 0010 0011 0100 1000
  ```

- **Bit-by-Bit Field Decomposition**:
  ```text
  +--------------------------------+-----------------+-------------+-------------+
  |           Tag [31:12]          |   Index [11:4]  | Block [3:2] | Byte [1:0]  |
  +--------------------------------+-----------------+-------------+-------------+
  | 0000 0000 0000 0001 0010 (20b) | 0011 0100 (8b)  |   10 (2b)   |   00 (2b)   |
  +--------------------------------+-----------------+-------------+-------------+
  |          0x00012               |   0x34 (52)     |      2      |      0      |
  +--------------------------------+-----------------+-------------+-------------+
  ```

- **Interpretation**:
  - **Tag Value**: `0x00012` (compared against stored tag in line 52).
  - **Cache Line Index**: `0x34` (Line 52 of 256).
  - **Block Word Offset**: `2` (Word 2 of words 0, 1, 2, 3 in 128-bit block, corresponding to block bits `[95:64]`).
  - **Byte Offset**: `0` (Word-aligned byte 0).
  - **Memory Block Base Address**: `0x00012340` (`{Tag, Index, 4'b0000}`).

---

### Example 2: Address `0x8000456C`

Consider memory write request to address `0x8000456C`:

- **Full 32-bit Hexadecimal**: `0x8000456C`
- **Full 32-bit Binary**:
  ```text
  1000 0000 0000 0000 0100 0101 0110 1100
  ```

- **Bit-by-Bit Field Decomposition**:
  ```text
  +--------------------------------+-----------------+-------------+-------------+
  |           Tag [31:12]          |   Index [11:4]  | Block [3:2] | Byte [1:0]  |
  +--------------------------------+-----------------+-------------+-------------+
  | 1000 0000 0000 0000 0100 (20b) | 0101 0110 (8b)  |   11 (2b)   |   00 (2b)   |
  +--------------------------------+-----------------+-------------+-------------+
  |          0x80004               |   0x56 (86)     |      3      |      0      |
  +--------------------------------+-----------------+-------------+-------------+
  ```

- **Interpretation**:
  - **Tag Value**: `0x80004`.
  - **Cache Line Index**: `0x56` (Line 86 of 256).
  - **Block Word Offset**: `3` (Word 3, block bits `[127:96]`).
  - **Byte Offset**: `0`.
  - **Memory Block Base Address**: `0x80004560` (`{Tag, Index, 4'b0000}`).

---

## 4. Hardware Slicing in Verilog

In the RTL implementation (`rtl/cache_top.v` and controller modules), the bit slicing is wired directly as:
```verilog
wire [19:0] addr_tag    = addr[31:12]; // 20-bit tag
wire [7:0]  addr_index  = addr[11:4];  // 8-bit line index
wire [1:0]  addr_word   = addr[3:2];   // 2-bit word offset
wire [1:0]  addr_byte   = addr[1:0];   // 2-bit byte offset

// Backing memory 16-byte aligned block address:
wire [31:0] block_addr  = {addr[31:4], 4'b0000};
```
