// =============================================================================
// File Name   : tag_array.v
// Module Name : tag_array
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Mustyala Sadhvik (M1)
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Synthesizable 256-entry Tag Array with Valid and Dirty bit tracking.
//               Provides asynchronous read indexing for single-cycle hit/miss
//               evaluation, synchronous full-entry update (allocation), and
//               independent dirty-bit assertion (write hits).
// =============================================================================
// Interface & Integration Guide for M2 and M3:
//
// 1. Parameters:
//    - TAG_WIDTH   : 20 bits (Address[31:12])
//    - INDEX_WIDTH : 8 bits  (Address[11:4], selecting 256 lines)
//    - NUM_LINES   : 256 entries (2^INDEX_WIDTH)
//
// 2. Port Descriptions:
//    - clk         : System clock (positive-edge triggered)
//    - rst         : Synchronous active-high system reset
//                    Asserting rst clears valid and dirty bits across all 256 entries.
//    - index       : 8-bit line index [7:0] decoded from CPU memory address.
//    - tag_in      : 20-bit tag [19:0] to be written during cache line allocation.
//    - valid_in    : Valid bit written on allocation (typically 1'b1).
//    - dirty_in    : Dirty bit written on allocation (1'b0 on read miss, 1'b1 on write-allocate).
//    - write_en    : Synchronous write enable for full metadata replacement (allocation).
//    - set_dirty   : Synchronous pulse to set the dirty bit of the line at `index` to 1'b1
//                    without modifying tag or valid bits (used on write hit).
//    - tag_out     : 20-bit stored tag at `index` (asynchronous read).
//    - valid_out   : Stored valid bit at `index` (asynchronous read).
//    - dirty_out   : Stored dirty bit at `index` (asynchronous read).
//
// 3. Hit Logic Integration (in Controller / Top):
//    wire tag_match = (tag_out == addr[31:12]);
//    wire cache_hit  = valid_out && tag_match;
// =============================================================================

`timescale 1ns / 1ps

module tag_array #(
    parameter TAG_WIDTH   = 20,
    parameter INDEX_WIDTH = 8,
    parameter NUM_LINES   = 256
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire [TAG_WIDTH-1:0]   tag_in,
    input  wire                   valid_in,
    input  wire                   dirty_in,
    input  wire                   write_en,
    input  wire                   set_dirty,
    output wire [TAG_WIDTH-1:0]   tag_out,
    output wire                   valid_out,
    output wire                   dirty_out
);

    // -------------------------------------------------------------------------
    // Internal Storage Arrays: 256 lines
    // -------------------------------------------------------------------------
    reg [TAG_WIDTH-1:0] tag_mem   [0:NUM_LINES-1];
    reg                 valid_mem [0:NUM_LINES-1];
    reg                 dirty_mem [0:NUM_LINES-1];

    integer i;

    // -------------------------------------------------------------------------
    // Synchronous Write & Reset Logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            // Reset clears valid and dirty states for all lines to prevent false hits
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                valid_mem[i] <= 1'b0;
                dirty_mem[i] <= 1'b0;
                tag_mem[i]   <= {TAG_WIDTH{1'b0}};
            end
        end else begin
            if (write_en) begin
                // Full entry write: allocation upon cache miss refill
                valid_mem[index] <= valid_in;
                dirty_mem[index] <= dirty_in;
                tag_mem[index]   <= tag_in;
            end else if (set_dirty) begin
                // Selective dirty update: marks line dirty on CPU write hit
                dirty_mem[index] <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Asynchronous Read Logic
    // Continuous assignment allows single-cycle tag comparison in COMPARE_TAG state
    // -------------------------------------------------------------------------
    assign tag_out   = tag_mem[index];
    assign valid_out = valid_mem[index];
    assign dirty_out = dirty_mem[index];

endmodule
