`timescale 1ns / 1ps

module tb_smoke #(parameter MEM_LATENCY = 10);
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, req = 0, we = 0;
    reg [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    wire ready, hit, miss, dirty_evict;
    wire [1:0] state;

    cache_top #(.MEM_LATENCY(MEM_LATENCY)) dut (
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
        begin
            lookups = 0;
            refills = 0;
            writebacks = 0;
            evictions = 0;

            @(negedge clk);
            addr = address;
            we = is_write;
            wdata = word_value;
            req = 1;
            @(posedge clk); // Request accepted in IDLE.
            @(negedge clk);
            // Leave req asserted and change the bus to check the operand latch.
            addr = ~address;
            we = !is_write;
            wdata = ~word_value;

            begin : wait_for_ready
                forever begin
                    @(posedge clk);
                    if (hit || miss) begin
                        lookups = lookups + 1;
                        if ({hit, miss} !== {!expect_miss, expect_miss})
                            $fatal(1, "Wrong initial hit/miss at %h", address);
                    end
                    if (dirty_evict)
                        evictions = evictions + 1;

                    if (dut.mem_ready) begin
                        if (dut.mem_we) begin
                            if (state !== 2'd2 || dut.mem_addr !== victim_block_addr)
                                $fatal(1, "Wrong write-back state or victim address at %h", address);
                            writebacks = writebacks + 1;
                        end else begin
                            if (state !== 2'd3 || dut.mem_addr !== {address[31:4], 4'b0}
                                || writebacks != expect_writeback)
                                $fatal(1, "Wrong refill state, address, or ordering at %h", address);
                            refills = refills + 1;
                        end
                    end

                    if (ready) begin
                        if (!is_write && rdata !== word_value)
                            $fatal(1, "Read %h gave %h, expected %h", address, rdata, word_value);
                        if (lookups != 1 || refills != expect_miss
                            || writebacks != expect_writeback || evictions != expect_writeback)
                            $fatal(1, "Wrong lookup or memory event counts at %h", address);
                        disable wait_for_ready;
                    end
                end
            end
            @(negedge clk);
            req = 0;
        end
    endtask

    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/smoke.vcd");
            $dumpvars(0, tb_smoke);
        end
        repeat (2) @(negedge clk);
        rst = 0;

        // Word 2 in the block at 0x20 is initialized to 0x28 / 4.
        access_cache(32'h0028, 0, 32'h000a, 1, 0, 0);
        access_cache(32'h0028, 0, 32'h000a, 0, 0, 0);
        $display("PASS: cold read miss and same-address hit");

        access_cache(32'h0028, 1, 32'hfeedface, 0, 0, 0);
        access_cache(32'h1028, 0, 32'h040a, 1, 1, 32'h0020);
        access_cache(32'h0028, 0, 32'hfeedface, 1, 0, 0);
        access_cache(32'h002c, 0, 32'h000b, 0, 0, 0);
        $display("PASS: dirty write-back, clean replacement, and preserved neighboring word");

        access_cache(32'h1024, 1, 32'hdecafbad, 1, 0, 0);
        access_cache(32'h1024, 0, 32'hdecafbad, 0, 0, 0);
        access_cache(32'h1028, 0, 32'h040a, 0, 0, 0);
        access_cache(32'h0028, 0, 32'hfeedface, 1, 1, 32'h1020);
        access_cache(32'h1024, 0, 32'hdecafbad, 1, 0, 0);
        $display("PASS: write allocate, dirty eviction, and memory readback");

        $display("PASS: cache_top smoke test (MEM_LATENCY=%0d)", MEM_LATENCY);
        $finish;
    end

    initial begin
        #(200 * (MEM_LATENCY + 1));
        $fatal(1, "Timed out waiting for a CPU response");
    end
endmodule
