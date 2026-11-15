`timescale 1ns / 1ps

module cache_top #(
    parameter CACHE_SIZE = 4096,
    // The inherited data and memory modules use four 32-bit words per block.
    parameter BLOCK_SIZE = 16,
    parameter ADDR_WIDTH = 32,
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
    localparam NUM_LINES = CACHE_SIZE / BLOCK_SIZE;
    localparam INDEX_WIDTH = $clog2(NUM_LINES);
    localparam OFFSET_WIDTH = $clog2(BLOCK_SIZE) - 2;
    localparam TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH - 2;
    localparam BLOCK_BITS = BLOCK_SIZE * 8;

    wire [INDEX_WIDTH-1:0]  index;
    wire [OFFSET_WIDTH-1:0] word_offset;
    wire [TAG_WIDTH-1:0]    request_tag, stored_tag;
    wire                    valid, dirty;
    wire [31:0]             write_word, read_word;
    wire                    write_word_en, fill_line;
    wire                    mem_req, mem_we, mem_ready;
    wire [ADDR_WIDTH-1:0]   mem_addr;
    wire [BLOCK_BITS-1:0]   mem_wdata, mem_rdata;

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
        .TAG_WIDTH(TAG_WIDTH), .INDEX_WIDTH(INDEX_WIDTH), .NUM_LINES(NUM_LINES)
    ) tags (
        .clk(clk), .rst(rst), .index(index),
        .tag_in(request_tag), .valid_in(1'b1), .dirty_in(1'b0),
        .write_en(fill_line), .set_dirty(write_word_en),
        .tag_out(stored_tag), .valid_out(valid), .dirty_out(dirty)
    );

    data_array #(
        .INDEX_WIDTH(INDEX_WIDTH), .OFFSET_WIDTH(OFFSET_WIDTH),
        .BLOCK_BITS(BLOCK_BITS), .NUM_LINES(NUM_LINES)
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
endmodule
