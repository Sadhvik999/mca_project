`timescale 1ns / 1ps

module perf_counters (
    input  wire        clk,
    input  wire        rst,
    input  wire        hit,
    input  wire        miss,
    input  wire        write_back_done,
    input  wire        ready,
    input  wire        write_word_en,
    output wire [63:0] accesses,
    output reg  [63:0] hits,
    output reg  [63:0] misses,
    output reg  [63:0] write_backs,
    output reg  [63:0] total_cycles,
    output reg  [63:0] reads,
    output reg  [63:0] writes
);
    assign accesses = hits + misses;

    always @(posedge clk) begin
        if (rst) begin
            hits         <= 0;
            misses       <= 0;
            write_backs  <= 0;
            total_cycles <= 0;
            reads        <= 0;
            writes       <= 0;
        end else begin
            // Count all non-reset cycles, including idle cycles.
            total_cycles <= total_cycles + 1'b1;

            // The controller suppresses the hit pulse on a refill replay.
            if (hit)
                hits <= hits + 1'b1;
            if (miss)
                misses <= misses + 1'b1;
            if (write_back_done)
                write_backs <= write_backs + 1'b1;

            // On ready, the write enable reflects the latched CPU operation.
            if (ready) begin
                if (write_word_en)
                    writes <= writes + 1'b1;
                else
                    reads <= reads + 1'b1;
            end
        end
    end
endmodule
