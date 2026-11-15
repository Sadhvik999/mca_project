// =============================================================================
// File Name   : tb_cache.v
// Module Name : tb_cache
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Yachna Khanna (M4)
// Email       : yachna.2024@nst.rishihood.edu.in
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Reusable testbench harness with clock/reset generation,
//               timeout-guarded CPU bus driver tasks (cpu_read, cpu_write),
//               and a 65536-word golden memory reference model.
// =============================================================================

`timescale 1ns / 1ps

module tb_cache #(
    parameter MEM_LATENCY    = 10,
    parameter MEM_SIZE_WORDS = 65536,
    parameter INIT_FILE      = "traces/mem_init.hex"
);

    // -------------------------------------------------------------------------
    // Clock and Reset Signals
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

    // Clock generation: 100 MHz (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // CPU Interface Signals
    // -------------------------------------------------------------------------
    reg         req;
    reg         we;
    reg  [31:0] addr;
    reg  [31:0] wdata;
    wire [31:0] rdata;
    wire        ready;
    wire        hit;
    wire        miss;
    wire [1:0]  state;
    wire        dirty_evict;

    // -------------------------------------------------------------------------
    // Testbench Statistics & Bookkeeping
    // -------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // -------------------------------------------------------------------------
    // Golden Reference Model (Software Memory Array)
    // -------------------------------------------------------------------------
    // Mirrors the backing memory's initial contents and tracks all subsequent
    // CPU writes to serve as an independent verification oracle.
    reg [31:0] golden_mem [0:MEM_SIZE_WORDS-1];

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // -------------------------------------------------------------------------
    cache_top #(
        .CACHE_SIZE (4096),
        .BLOCK_SIZE (16),
        .ADDR_WIDTH (32),
        .MEM_LATENCY(MEM_LATENCY)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .req        (req),
        .we         (we),
        .addr       (addr),
        .wdata      (wdata),
        .rdata      (rdata),
        .ready      (ready),
        .hit        (hit),
        .miss       (miss),
        .state      (state),
        .dirty_evict(dirty_evict)
    );

    // -------------------------------------------------------------------------
    // Task: cpu_write
    // Drives a single CPU write transaction, waits on ready with a watchdog
    // timer, and synchronously updates the golden memory reference model.
    // -------------------------------------------------------------------------
    task automatic cpu_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        integer watchdog;
        begin
            watchdog = 0;
            @(negedge clk);
            addr  = write_addr;
            we    = 1'b1;
            wdata = write_data;
            req   = 1'b1;

            @(posedge clk); // Sampled by controller in IDLE

            while (!ready) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 200) begin
                    $display("ERROR [Timeout]: cpu_write to 0x%08h timed out waiting for ready!", write_addr);
                    fail_count = fail_count + 1;
                    disable cpu_write;
                end
            end

            // Update golden reference model with new data
            golden_mem[write_addr[17:2]] = write_data;
            pass_count = pass_count + 1;

            @(negedge clk);
            req   = 1'b0;
            we    = 1'b0;
            wdata = 32'h0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: cpu_read
    // Drives a single CPU read transaction, waits on ready with a watchdog,
    // and verifies rdata against both expected_val and golden reference memory.
    // -------------------------------------------------------------------------
    task automatic cpu_read;
        input [31:0] read_addr;
        input [31:0] expected_val;
        integer watchdog;
        reg [31:0] captured_rdata;
        begin
            watchdog = 0;
            @(negedge clk);
            addr  = read_addr;
            we    = 1'b0;
            wdata = 32'h0;
            req   = 1'b1;

            @(posedge clk); // Sampled by controller in IDLE

            while (!ready) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 200) begin
                    $display("ERROR [Timeout]: cpu_read to 0x%08h timed out waiting for ready!", read_addr);
                    fail_count = fail_count + 1;
                    disable cpu_read;
                end
            end

            captured_rdata = rdata;

            if (captured_rdata !== expected_val) begin
                $display("FAIL: cpu_read [0x%08h] expected=0x%08h got=0x%08h",
                         read_addr, expected_val, captured_rdata);
                fail_count = fail_count + 1;
            end else if (golden_mem[read_addr[17:2]] !== expected_val) begin
                $display("FAIL [Golden Mismatch]: cpu_read [0x%08h] expected=0x%08h but golden_mem=0x%08h",
                         read_addr, expected_val, golden_mem[read_addr[17:2]]);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS: cpu_read [0x%08h] = 0x%08h (golden match)",
                         read_addr, captured_rdata);
                pass_count = pass_count + 1;
            end

            @(negedge clk);
            req = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: reset_dut
    // Applies a clean synchronous reset to the cache controller and arrays.
    // -------------------------------------------------------------------------
    task automatic reset_dut;
        begin
            @(negedge clk);
            rst   = 1'b1;
            req   = 1'b0;
            we    = 1'b0;
            addr  = 32'h0;
            wdata = 32'h0;
            repeat (3) @(negedge clk);
            rst   = 1'b0;
            @(negedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Baseline Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        // Initialize golden model memory array from disk
        $readmemh(INIT_FILE, golden_mem);

        if ($test$plusargs("DUMP")) begin
            $dumpfile("build/tb_cache.vcd");
            $dumpvars(0, tb_cache);
        end

        $display("===============================================================");
        $display("  tb_cache: Golden Reference Model Verification Harness");
        $display("===============================================================");

        reset_dut();

        // 1. Cold read miss and verification against golden memory
        cpu_read(32'h0000_0010, 32'h0000_0004);

        // 2. Read hit to same address
        cpu_read(32'h0000_0010, 32'h0000_0004);

        // 3. Write to cache and verify golden model tracks update
        cpu_write(32'h0000_0010, 32'hA1B2_C3D4);

        // 4. Read back updated value
        cpu_read(32'h0000_0010, 32'hA1B2_C3D4);

        // 5. Read adjacent words in the same 16-byte block
        cpu_read(32'h0000_0014, 32'h0000_0005);
        cpu_read(32'h0000_0018, 32'h0000_0006);
        cpu_read(32'h0000_001C, 32'h0000_0007);

        // 6. Write miss (write-allocate) on another line
        cpu_write(32'h0000_0088, 32'h5566_7788);
        cpu_read(32'h0000_0088, 32'h5566_7788);

        $display("---------------------------------------------------------------");
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED: %0d transactions verified against golden model.", pass_count);
        end else begin
            $display("TESTS FAILED: %0d failures encountered.", fail_count);
        end
        $display("===============================================================");

        $finish;
    end

endmodule
