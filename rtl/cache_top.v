`timescale 1ns / 1ps

// Top-level parameterized direct-mapped cache controller (default 4 KB, 16 B block).
// CACHE_SIZE (1024..8192 B) and BLOCK_SIZE (8, 16, 32 B) propagate to all submodules.
module cache_top #(
    parameter CACHE_SIZE  = 4096,
    parameter BLOCK_SIZE  = 16,
    parameter ADDR_WIDTH  = 32,
    parameter MEM_LATENCY = 10
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  req,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [31:0]           wdata,
    output wire [31:0]           rdata,
    output wire                  ready,
    output wire                  hit,
    output wire                  miss,
    output wire [1:0]            state,
    output wire                  dirty_evict
);
    // Derived address split and storage dimensions
    localparam NUM_LINES        = CACHE_SIZE / BLOCK_SIZE;
    localparam OFFSET_BITS      = $clog2(BLOCK_SIZE);
    localparam WORD_OFFSET_BITS = OFFSET_BITS - 2;
    localparam INDEX_BITS       = $clog2(NUM_LINES);
    localparam TAG_BITS         = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam DATA_WIDTH       = BLOCK_SIZE * 8;

    wire [INDEX_BITS-1:0]       index;
    wire [WORD_OFFSET_BITS-1:0] word_offset;
    wire [TAG_BITS-1:0]         request_tag, stored_tag;
    wire                        valid, dirty;
    wire [31:0]                 write_word, read_word;
    wire                        write_word_en, fill_line;
    wire                        mem_req, mem_we, mem_ready;
    wire [ADDR_WIDTH-1:0]       mem_addr;
    wire [DATA_WIDTH-1:0]       mem_wdata, mem_rdata;

    cache_controller #(
        .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE), .ADDR_WIDTH(ADDR_WIDTH)
    ) controller (
        .clk(clk), .rst(rst),
        .req(req), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata), .ready(ready),
        .index(index), .word_offset(word_offset), .request_tag(request_tag),
        .stored_tag(stored_tag), .valid(valid), .dirty(dirty),
        .write_word(write_word), .read_word(read_word),
        .write_word_en(write_word_en), .fill_line(fill_line),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_ready(mem_ready),
        .hit(hit), .miss(miss), .state(state), .dirty_evict(dirty_evict)
    );

    // A refill installs clean metadata. A replayed write marks it dirty.
    tag_array #(
        .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE), .ADDR_WIDTH(ADDR_WIDTH)
    ) tags (
        .clk(clk), .rst(rst), .index(index),
        .tag_in(request_tag), .valid_in(1'b1), .dirty_in(1'b0),
        .write_en(fill_line), .set_dirty(write_word_en),
        .tag_out(stored_tag), .valid_out(valid), .dirty_out(dirty)
    );

    data_array #(
        .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE)
    ) data (
        .clk(clk), .rst(rst), .index(index), .word_offset(word_offset),
        .word_in(write_word), .block_in(mem_rdata),
        .write_word_en(write_word_en), .write_block_en(fill_line),
        .word_out(read_word), .block_out(mem_wdata)
    );

    main_memory #(
        .MEM_LATENCY(MEM_LATENCY), .BLOCK_SIZE(BLOCK_SIZE), .ADDR_WIDTH(ADDR_WIDTH)
    ) memory (
        .clk(clk), .rst(rst),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    // Observe existing handshake events without changing the CPU interface.
    // The testbench and GTKWave read the totals under this instance.
    perf_counters perf (
        .clk(clk), .rst(rst), .hit(hit), .miss(miss),
        .write_back_done(mem_req && mem_we && mem_ready),
        .ready(ready), .write_word_en(write_word_en),
        .accesses(), .hits(), .misses(), .write_backs(),
        .total_cycles(), .reads(), .writes()
    );
endmodule
