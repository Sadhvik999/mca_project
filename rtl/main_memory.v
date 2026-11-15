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
//    - BLOCK_SIZE     : 16 bytes per transfer (4 words = 128 bits)
//    - ADDR_WIDTH     : 32-bit byte address width
//    - INIT_FILE      : Path to hex image loaded at t=0 via $readmemh
//
// 2. Port List:
//    - clk            : System clock (positive-edge triggered)
//    - rst            : Synchronous active-high reset (resets FSM/counters;
//                       preserves preloaded memory contents)
//    - mem_req        : Request strobe from cache controller (active high)
//    - mem_we         : 1 = 128-bit block write, 0 = 128-bit block read
//    - mem_addr[31:0] : Byte address; lower 4 bits [3:0] are ignored so any
//                       unaligned address maps to its 16-byte aligned block
//    - mem_wdata[127:0]: 16-byte write-back block (Word 0 in [31:0] .. Word 3
//                        in [127:96])
//    - mem_rdata[127:0]: 16-byte fetched block (valid when mem_ready == 1)
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
    localparam BLOCK_BITS     = BLOCK_SIZE * 8;            // 128 bits
    localparam WORD_ADDR_BITS = $clog2(MEM_SIZE_WORDS);    // 16 bits for 65536 words
    localparam OFFSET_BITS    = $clog2(BLOCK_SIZE);        // 4 bits (byte + word offset)

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
    reg [BLOCK_BITS-1:0] req_wdata;

    // Zeroing [3:0] aligns any byte address to its enclosing 16-byte block;
    // low 2 bits [1:0] of word index select each of the 4 words in the block
    wire [WORD_ADDR_BITS-3:0] imm_block_idx = mem_addr[WORD_ADDR_BITS+1 : OFFSET_BITS];
    wire [WORD_ADDR_BITS-3:0] req_block_idx = req_addr[WORD_ADDR_BITS+1 : OFFSET_BITS];

    // -------------------------------------------------------------------------
    // Latency Timer & Block Read/Write FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            wait_cnt  <= 32'd0;
            req_addr  <= {ADDR_WIDTH{1'b0}};
            req_we    <= 1'b0;
            req_wdata <= {BLOCK_BITS{1'b0}};
            mem_rdata <= {BLOCK_BITS{1'b0}};
            mem_ready <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    mem_ready <= 1'b0;
                    if (mem_req) begin
                        if (MEM_LATENCY <= 1) begin
                            // Immediate 1-cycle completion path if parameterized latency is 1
                            if (mem_we) begin
                                mem[{imm_block_idx, 2'b00}] <= mem_wdata[31:0];
                                mem[{imm_block_idx, 2'b01}] <= mem_wdata[63:32];
                                mem[{imm_block_idx, 2'b10}] <= mem_wdata[95:64];
                                mem[{imm_block_idx, 2'b11}] <= mem_wdata[127:96];
                            end else begin
                                mem_rdata <= {
                                    mem[{imm_block_idx, 2'b11}],
                                    mem[{imm_block_idx, 2'b10}],
                                    mem[{imm_block_idx, 2'b01}],
                                    mem[{imm_block_idx, 2'b00}]
                                };
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
                        // Execute 128-bit block transfer on final wait cycle
                        if (req_we) begin
                            mem[{req_block_idx, 2'b00}] <= req_wdata[31:0];
                            mem[{req_block_idx, 2'b01}] <= req_wdata[63:32];
                            mem[{req_block_idx, 2'b10}] <= req_wdata[95:64];
                            mem[{req_block_idx, 2'b11}] <= req_wdata[127:96];
                        end else begin
                            mem_rdata <= {
                                mem[{req_block_idx, 2'b11}],
                                mem[{req_block_idx, 2'b10}],
                                mem[{req_block_idx, 2'b01}],
                                mem[{req_block_idx, 2'b00}]
                            };
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
