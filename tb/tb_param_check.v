// =============================================================================
// File Name   : tb_param_check.v
// Module Name : tb_param_check
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Varun Udata (M2)
// Email       : varunudata@gmail.com
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Parameterized smoke testbench for cache_top. Supports -P
//               overrides across all 12 (CACHE_SIZE, BLOCK_SIZE) pairs:
//               CACHE_SIZE in {1024, 2048, 4096, 8192}
//               BLOCK_SIZE in {8, 16, 32}
// =============================================================================

`timescale 1ns / 1ps

module tb_param_check #(
    parameter CACHE_SIZE  = 4096,
    parameter BLOCK_SIZE  = 16,
    parameter ADDR_WIDTH  = 32,
    parameter MEM_LATENCY = 10
);
    localparam NUM_LINES   = CACHE_SIZE / BLOCK_SIZE;
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam INDEX_BITS  = $clog2(NUM_LINES);
    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, req = 0, we = 0;
    reg [ADDR_WIDTH-1:0] addr = 0;
    reg [31:0] wdata = 0;
    wire [31:0] rdata;
    wire ready, hit, miss, dirty_evict;
    wire [1:0] state;

    cache_top #(
        .CACHE_SIZE(CACHE_SIZE),
        .BLOCK_SIZE(BLOCK_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEM_LATENCY(MEM_LATENCY)
    ) dut (
        .clk(clk), .rst(rst), .req(req), .we(we), .addr(addr), .wdata(wdata),
        .rdata(rdata), .ready(ready), .hit(hit), .miss(miss),
        .state(state), .dirty_evict(dirty_evict)
    );

    task automatic access_cache;
        input [31:0] address;
        input is_write;
        input [31:0] word_value;
        input expect_miss;
        input expect_writeback;
        input [31:0] victim_block_addr;
        integer lookups, refills, writebacks, evictions;
        reg [31:0] expected_block_addr;
        begin
            lookups = 0;
            refills = 0;
            writebacks = 0;
            evictions = 0;
            expected_block_addr = address & ~(BLOCK_SIZE - 1);

            @(negedge clk);
            addr = address;
            we = is_write;
            wdata = word_value;
            req = 1;
            @(posedge clk); // Request latched in IDLE
            @(negedge clk);
            // Mutate CPU inputs after acceptance to verify request latching
            addr = ~address;
            we = !is_write;
            wdata = ~word_value;

            begin : wait_for_ready
                forever begin
                    @(posedge clk);
                    if (hit || miss) begin
                        lookups = lookups + 1;
                        if ({hit, miss} !== {!expect_miss, expect_miss})
                            $fatal(1, "Wrong hit/miss at %h (CACHE=%0d, BLOCK=%0d)",
                                   address, CACHE_SIZE, BLOCK_SIZE);
                    end
                    if (dirty_evict)
                        evictions = evictions + 1;

                    if (dut.mem_ready) begin
                        if (dut.mem_we) begin
                            if (state !== 2'd2 || dut.mem_addr !== victim_block_addr)
                                $fatal(1, "Wrong write-back state or victim addr %h vs %h",
                                       dut.mem_addr, victim_block_addr);
                            writebacks = writebacks + 1;
                        end else begin
                            if (state !== 2'd3 || dut.mem_addr !== expected_block_addr
                                || writebacks != expect_writeback)
                                $fatal(1, "Wrong refill state/addr %h vs %h",
                                       dut.mem_addr, expected_block_addr);
                            refills = refills + 1;
                        end
                    end

                    if (ready) begin
                        if (!is_write && rdata !== word_value)
                            $fatal(1, "Read %h gave %h, expected %h", address, rdata, word_value);
                        if (lookups != 1 || refills != expect_miss
                            || writebacks != expect_writeback || evictions != expect_writeback)
                            $fatal(1, "Event count mismatch at %h (L=%0d R=%0d WB=%0d E=%0d)",
                                   address, lookups, refills, writebacks, evictions);
                        disable wait_for_ready;
                    end
                end
            end
            @(negedge clk);
            req = 0;
        end
    endtask

    // 0x20 is aligned for 8B, 16B, and 32B blocks; adding CACHE_SIZE keeps the
    // exact same index bits and flips a tag bit across all 12 configurations.
    localparam [31:0] BASE_A    = 32'h0000_0020;
    localparam [31:0] BASE_B    = 32'h0000_0020 + CACHE_SIZE;
    localparam [31:0] LAST_OFF  = BLOCK_SIZE - 4;
    localparam [31:0] LAST_LINE = (NUM_LINES - 1) * BLOCK_SIZE;

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;

        // 1. Cold read miss, same-word hit, and highest-word spatial hit
        access_cache(BASE_A, 0, BASE_A >> 2, 1, 0, 0);
        access_cache(BASE_A, 0, BASE_A >> 2, 0, 0, 0);
        access_cache(BASE_A + LAST_OFF, 0, (BASE_A + LAST_OFF) >> 2, 0, 0, 0);

        // 2. Write hit -> dirty eviction by BASE_B -> clean reload of BASE_A
        access_cache(BASE_A, 1, 32'hfeedface, 0, 0, 0);
        access_cache(BASE_B, 0, BASE_B >> 2, 1, 1, BASE_A);
        access_cache(BASE_A, 0, 32'hfeedface, 1, 0, 0);
        access_cache(BASE_A + 4, 0, (BASE_A + 4) >> 2, 0, 0, 0);

        // 3. Write-allocate on highest word of BASE_B -> dirty eviction -> readback
        access_cache(BASE_B + LAST_OFF, 1, 32'hdecafbad, 1, 0, 0);
        access_cache(BASE_B + LAST_OFF, 0, 32'hdecafbad, 0, 0, 0);
        access_cache(BASE_B, 0, BASE_B >> 2, 0, 0, 0);
        access_cache(BASE_A, 0, 32'hfeedface, 1, 1, BASE_B);
        access_cache(BASE_B + LAST_OFF, 0, 32'hdecafbad, 1, 0, 0);

        // 4. Highest cache line index check (line NUM_LINES - 1)
        if (LAST_LINE != BASE_A && LAST_LINE != BASE_B) begin
            access_cache(LAST_LINE, 1, 32'h1357_2468, 1, 0, 0);
            access_cache(LAST_LINE, 0, 32'h1357_2468, 0, 0, 0);
        end

        $display("PASS: CACHE_SIZE=%0d BLOCK_SIZE=%0d LINES=%0d (TAG=%0db INDEX=%0db OFFSET=%0db DATA=%0db)",
                 CACHE_SIZE, BLOCK_SIZE, NUM_LINES, TAG_BITS, INDEX_BITS, OFFSET_BITS, BLOCK_SIZE * 8);
        $finish;
    end

    initial begin
        #(2000 + 200 * MEM_LATENCY);
        $fatal(1, "Timed out waiting for CPU response (CACHE=%0d, BLOCK=%0d)",
               CACHE_SIZE, BLOCK_SIZE);
    end
endmodule
