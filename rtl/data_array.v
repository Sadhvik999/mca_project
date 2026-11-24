// =============================================================================
// File Name   : data_array.v
// Module Name : data_array
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Varun Udata (M2)
// Email       : varunudata@gmail.com
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Synthesizable 256-entry x 128-bit Data Array for a 4 KB
//               direct-mapped cache (16-byte blocks, 4 words per line).
//               Provides combinational (asynchronous) read of both the full
//               128-bit cache block (for write-back eviction) and the selected
//               32-bit word (via 2-bit block offset addr[3:2]). Supports
//               synchronous single-word writes (preserving the other 3 words)
//               and full 128-bit block fills on cache miss allocation.
// =============================================================================
// Interface & Integration Guide for M3 (Controller / Cache Top):
//
// 1. Parameters:
//    - CACHE_SIZE   : Cache capacity in bytes (1024, 2048, 4096, 8192)
//    - BLOCK_SIZE   : Block size in bytes (8, 16, 32)
//    - WORD_WIDTH   : 32 bits  (CPU data word width)
//    - NUM_LINES    : Derived via CACHE_SIZE / BLOCK_SIZE
//    - INDEX_WIDTH  : Derived via $clog2(NUM_LINES)
//    - OFFSET_WIDTH : Derived via $clog2(BLOCK_SIZE / (WORD_WIDTH / 8))
//    - BLOCK_BITS   : Derived via BLOCK_SIZE * 8 (64, 128, or 256 bits)
//    (Direct overrides of INDEX_WIDTH/OFFSET_WIDTH/BLOCK_BITS/NUM_LINES remain
//     supported for standalone unit testbenches.)
//
// 2. Port List:
//    - clk            : System clock (positive-edge triggered)
//    - rst            : Synchronous active-high reset; clears all 256 lines
//    - index[7:0]     : Cache line index decoded from CPU addr[11:4]
//    - word_offset[1:0]: Word select within block decoded from CPU addr[3:2]
//    - word_in[31:0]  : 32-bit write data from CPU (connect to CPU wdata)
//    - block_in[127:0]: 128-bit block refill data from memory (mem_rdata)
//    - write_word_en  : Sync write enable for 1 word at (index, word_offset)
//                       (used on CPU write hit; leaves other 3 words untouched)
//    - write_block_en : Sync write enable for full 128-bit block at `index`
//                       (used in ALLOCATE when mem_ready pulses)
//                       Note: write_block_en has priority over write_word_en
//                       if both are high on the same clock edge.
//    - word_out[31:0] : Selected 32-bit word at (index, word_offset) -> CPU rdata
//    - block_out[127:0]: Full 128-bit block at `index` -> memory mem_wdata
//
// 3. Word-Lane Mapping inside 128-bit Block (Little-Endian Word Order):
//    - word_offset == 2'b00 -> block[31:0]    (Word 0, byte offset 0x0..0x3)
//    - word_offset == 2'b01 -> block[63:32]   (Word 1, byte offset 0x4..0x7)
//    - word_offset == 2'b10 -> block[95:64]   (Word 2, byte offset 0x8..0xB)
//    - word_offset == 2'b11 -> block[127:96]  (Word 3, byte offset 0xC..0xF)
//
// 4. Typical M3 Controller Usage:
//    - COMPARE_TAG (Read Hit)  : read `word_out` combinationally into `rdata`.
//    - COMPARE_TAG (Write Hit) : assert `write_word_en = 1` for 1 cycle along
//                                with `tag_array.set_dirty = 1`.
//    - WRITE_BACK              : drive `mem_wdata = block_out` while `mem_req=1`.
//    - ALLOCATE (mem_ready=1)  : assert `write_block_en = 1` to latch `mem_rdata`,
//                                then return to COMPARE_TAG to complete CPU op.
// =============================================================================

`timescale 1ns / 1ps

module data_array #(
    parameter CACHE_SIZE   = 4096,
    parameter BLOCK_SIZE   = 16,
    parameter WORD_WIDTH   = 32,
    parameter NUM_LINES    = CACHE_SIZE / BLOCK_SIZE,
    parameter INDEX_WIDTH  = $clog2(NUM_LINES),
    parameter OFFSET_WIDTH = $clog2(BLOCK_SIZE / (WORD_WIDTH / 8)),
    parameter BLOCK_BITS   = BLOCK_SIZE * 8
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire [INDEX_WIDTH-1:0]  index,
    input  wire [OFFSET_WIDTH-1:0] word_offset,
    input  wire [WORD_WIDTH-1:0]   word_in,
    input  wire [BLOCK_BITS-1:0]   block_in,
    input  wire                    write_word_en,
    input  wire                    write_block_en,
    output reg  [WORD_WIDTH-1:0]   word_out,
    output wire [BLOCK_BITS-1:0]   block_out
);

    // Derived bit widths using $clog2 for parameterized block/cache sizing
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam INDEX_BITS  = INDEX_WIDTH;
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;
    localparam DATA_WIDTH  = BLOCK_BITS;

    // -------------------------------------------------------------------------
    // Internal Storage: NUM_LINES cache lines x DATA_WIDTH bits
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] data_mem [0:NUM_LINES-1];

    integer i;

    // -------------------------------------------------------------------------
    // Synchronous Reset & Write Logic (Block Fill vs. Masked Single-Word Write)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            // Clear all data lines on reset so waveforms/reads start deterministic
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                data_mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (write_block_en) begin
            // Full line fill during ALLOCATE takes priority over word write
            data_mem[index] <= block_in;
        end else if (write_word_en) begin
            // Indexed part-select updates only the addressed 32-bit word lane
            // for any BLOCK_SIZE (8B = 2 words, 16B = 4 words, 32B = 8 words)
            data_mem[index][word_offset * WORD_WIDTH +: WORD_WIDTH] <= word_in;
        end
    end

    // -------------------------------------------------------------------------
    // Asynchronous Read Datapath
    // Exposes full block immediately for write-back, and muxes target 32b word
    // -------------------------------------------------------------------------
    assign block_out = data_mem[index];

    always @(*) begin
        word_out = block_out[word_offset * WORD_WIDTH +: WORD_WIDTH];
    end

endmodule
