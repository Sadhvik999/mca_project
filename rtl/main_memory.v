// =============================================================================
// File Name   : main_memory.v
// Module Name : main_memory
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Varun Udata (M2)
// Email       : varunudata@gmail.com
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Behavioral backing main memory model with configurable access
//               latency (default MEM_LATENCY = 10 cycles) and block-wide
//               128-bit (16-byte) transfers. Preloads deterministic initial
//               contents from traces/mem_init.hex via $readmemh.
// =============================================================================
// Interface & Integration Guide for M3 and M4:
//
// 1. Parameters:
//    - MEM_LATENCY    : 10 cycles (clock edges from request acceptance to
//                       mem_ready sampled high by a synchronous consumer)
//    - MEM_SIZE_WORDS : 65536 32-bit words (256 KB address window)
//    - BLOCK_SIZE     : Block transfer size in bytes (8, 16, or 32 bytes;
//                       corresponding to 64-bit, 128-bit, or 256-bit bus)
//    - ADDR_WIDTH     : 32-bit byte address width
//    - INIT_FILE      : Path to hex image loaded at t=0 via $readmemh
//
// 2. Port List:
//    - clk            : System clock (positive-edge triggered)
//    - rst            : Synchronous active-high reset (resets FSM/counters;
//                       preserves preloaded memory contents)
//    - mem_req        : Request strobe from cache controller (active high)
//    - mem_we         : 1 = block write, 0 = block read
//    - mem_addr[31:0] : Byte address; lower OFFSET_BITS are ignored so any
//                       unaligned address maps to its BLOCK_SIZE-aligned block
//    - mem_wdata      : BLOCK_SIZE*8-bit write-back block (Word 0 in [31:0] ..)
//    - mem_rdata      : BLOCK_SIZE*8-bit fetched block (valid when mem_ready == 1)
//    - mem_ready      : Single-cycle completion pulse after MEM_LATENCY cycles
//
// 3. Handshake Timing Notes:
//    - S_IDLE samples mem_req == 1 (Cycle 0), latches addr/we/wdata, and
//      counts MEM_LATENCY - 1 cycles in S_WAIT.
//    - On Cycle MEM_LATENCY - 1, memory performs the read/write and drives
//      mem_ready <= 1 for exactly one clock cycle (S_DONE).
//    - Synchronous consumers sample mem_ready == 1 at Cycle MEM_LATENCY.
//    - S_DONE ignores mem_req so a Moore controller deasserting/switching
//      mem_req on Cycle MEM_LATENCY never causes a spurious re-trigger.
// =============================================================================

`timescale 1ns / 1ps

module main_memory #(
    parameter MEM_LATENCY    = 10,
    parameter MEM_SIZE_WORDS = 65536,
    parameter BLOCK_SIZE     = 16,
    parameter ADDR_WIDTH     = 32,
    parameter INIT_FILE      = "traces/mem_init.hex"
)(
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      mem_req,
    input  wire                      mem_we,
    input  wire [ADDR_WIDTH-1:0]     mem_addr,
    input  wire [BLOCK_SIZE*8-1:0]   mem_wdata,
    output reg  [BLOCK_SIZE*8-1:0]   mem_rdata,
    output reg                       mem_ready
);

    // -------------------------------------------------------------------------
    // Local Parameters & State Encoding
    // -------------------------------------------------------------------------
    localparam DATA_WIDTH       = BLOCK_SIZE * 8;             // 64, 128, or 256 bits
    localparam BLOCK_BITS       = DATA_WIDTH;
    localparam WORDS_PER_BLOCK  = BLOCK_SIZE / 4;             // 2, 4, or 8 words
    localparam WORD_OFFSET_BITS = $clog2(WORDS_PER_BLOCK);    // 1, 2, or 3 bits
    localparam OFFSET_BITS      = $clog2(BLOCK_SIZE);         // 3, 4, or 5 bits
    localparam WORD_ADDR_BITS   = $clog2(MEM_SIZE_WORDS);     // 16 bits for 65536 words
    localparam BLOCK_ADDR_BITS  = WORD_ADDR_BITS - WORD_OFFSET_BITS;

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_WAIT = 2'd1;
    localparam [1:0] S_DONE = 2'd2;

    // -------------------------------------------------------------------------
    // Backing Storage Array (Word-addressed 32-bit storage, 256 KB total)
    // -------------------------------------------------------------------------
    reg [31:0] mem [0:MEM_SIZE_WORDS-1];

    // Preload deterministic memory contents at simulation start (not wiped by rst)
    initial begin
        $readmemh(INIT_FILE, mem);
    end

    // -------------------------------------------------------------------------
    // Internal Controller Registers & Alignment Calculation
    // -------------------------------------------------------------------------
    reg [1:0]            state;
    reg [31:0]           wait_cnt;
    reg [ADDR_WIDTH-1:0] req_addr;
    reg                  req_we;
    reg [DATA_WIDTH-1:0] req_wdata;
    integer              w;

    // Zeroing [OFFSET_BITS-1:0] aligns any byte address to its enclosing block;
    // low WORD_OFFSET_BITS of word index select each word inside the block
    wire [BLOCK_ADDR_BITS-1:0] imm_block_idx = mem_addr[WORD_ADDR_BITS+1 : OFFSET_BITS];
    wire [BLOCK_ADDR_BITS-1:0] req_block_idx = req_addr[WORD_ADDR_BITS+1 : OFFSET_BITS];

    // -------------------------------------------------------------------------
    // Latency Timer & Block Read/Write FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            wait_cnt  <= 32'd0;
            req_addr  <= {ADDR_WIDTH{1'b0}};
            req_we    <= 1'b0;
            req_wdata <= {DATA_WIDTH{1'b0}};
            mem_rdata <= {DATA_WIDTH{1'b0}};
            mem_ready <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    mem_ready <= 1'b0;
                    if (mem_req) begin
                        if (MEM_LATENCY <= 1) begin
                            // Immediate 1-cycle completion path if parameterized latency is 1
                            if (mem_we) begin
                                for (w = 0; w < WORDS_PER_BLOCK; w = w + 1) begin
                                    mem[{imm_block_idx, w[WORD_OFFSET_BITS-1:0]}] <= mem_wdata[w*32 +: 32];
                                end
                            end else begin
                                for (w = 0; w < WORDS_PER_BLOCK; w = w + 1) begin
                                    mem_rdata[w*32 +: 32] <= mem[{imm_block_idx, w[WORD_OFFSET_BITS-1:0]}];
                                end
                            end
                            mem_ready <= 1'b1;
                            state     <= S_DONE;
                        end else begin
                            // Latch request operands so bus stays safe throughout wait window
                            req_addr  <= mem_addr;
                            req_we    <= mem_we;
                            req_wdata <= mem_wdata;
                            wait_cnt  <= 32'd1;
                            state     <= S_WAIT;
                        end
                    end
                end

                S_WAIT: begin
                    if (wait_cnt == (MEM_LATENCY - 1)) begin
                        // Execute BLOCK_SIZE-wide block transfer on final wait cycle
                        if (req_we) begin
                            for (w = 0; w < WORDS_PER_BLOCK; w = w + 1) begin
                                mem[{req_block_idx, w[WORD_OFFSET_BITS-1:0]}] <= req_wdata[w*32 +: 32];
                            end
                        end else begin
                            for (w = 0; w < WORDS_PER_BLOCK; w = w + 1) begin
                                mem_rdata[w*32 +: 32] <= mem[{req_block_idx, w[WORD_OFFSET_BITS-1:0]}];
                            end
                        end
                        mem_ready <= 1'b1;
                        state     <= S_DONE;
                    end else begin
                        wait_cnt <= wait_cnt + 32'd1;
                    end
                end

                S_DONE: begin
                    // Deassert mem_ready after 1 full cycle; ignore trailing mem_req
                    mem_ready <= 1'b0;
                    wait_cnt  <= 32'd0;
                    state     <= S_IDLE;
                end

                default: begin
                    mem_ready <= 1'b0;
                    wait_cnt  <= 32'd0;
                    state     <= S_IDLE;
                end
            endcase
        end
    end

endmodule
