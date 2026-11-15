`timescale 1ns / 1ps

module cache_controller #(
    parameter CACHE_SIZE = 4096,
    parameter BLOCK_SIZE = 16,
    parameter ADDR_WIDTH = 32,
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE),
    localparam INDEX_WIDTH = $clog2(CACHE_SIZE / BLOCK_SIZE),
    localparam TAG_WIDTH = ADDR_WIDTH - INDEX_WIDTH - OFFSET_BITS
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  req,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [31:0]           wdata,
    output wire [31:0]           rdata,
    output wire                  ready,

    output wire [INDEX_WIDTH-1:0]     index,
    output wire [OFFSET_BITS-3:0]     word_offset,
    output wire [TAG_WIDTH-1:0]       request_tag,
    input  wire [TAG_WIDTH-1:0]       stored_tag,
    input  wire                       valid,
    output reg  [31:0]                write_word,
    input  wire [31:0]                read_word,
    output wire                       write_word_en,

    output wire                       fill_line,

    output wire                       mem_req,
    output wire                       mem_we,
    output wire [ADDR_WIDTH-1:0]      mem_addr,
    input  wire                       mem_ready,

    output wire                  hit,
    output wire                  miss,
    output reg  [1:0]            state
);

    localparam [1:0] IDLE        = 2'd0;
    localparam [1:0] COMPARE_TAG = 2'd1;
    localparam [1:0] ALLOCATE    = 2'd3;

    reg [ADDR_WIDTH-1:0] request_addr;
    reg                  request_we;
    reg                  refilled;
    wire                 tag_hit;

    assign {request_tag, index} = request_addr[ADDR_WIDTH-1:OFFSET_BITS];
    assign word_offset = request_addr[OFFSET_BITS-1:2];

    // Mealy: ready and write enables depend on the current lookup and state.
    assign tag_hit = valid && (stored_tag == request_tag);
    assign ready = (state == COMPARE_TAG) && tag_hit;
    // Count the initial lookup once, even when a miss replays as a tag hit.
    assign hit = ready && !refilled;
    assign miss = (state == COMPARE_TAG) && !tag_hit && !refilled;
    assign rdata = read_word;
    assign write_word_en = ready && request_we;

    assign mem_req = (state == ALLOCATE);
    assign mem_we = 1'b0;
    assign mem_addr = {request_tag, index, {OFFSET_BITS{1'b0}}};
    assign fill_line = (state == ALLOCATE) && mem_ready;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            request_addr <= 0;
            request_we <= 0;
            write_word <= 0;
            refilled <= 0;
        end else begin
            case (state)
                IDLE: if (req) begin
                    request_addr <= addr;
                    request_we <= we;
                    write_word <= wdata;
                    refilled <= 0;
                    state <= COMPARE_TAG;
                end

                COMPARE_TAG: state <= tag_hit ? IDLE : ALLOCATE;

                // The arrays capture the block and metadata on this same edge.
                ALLOCATE: if (mem_ready) begin
                    refilled <= 1;
                    state <= COMPARE_TAG;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
