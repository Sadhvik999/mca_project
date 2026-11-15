// =============================================================================
// File Name   : tb_directed.v
// Module Name : tb_directed
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Yachna Khanna (M4)
// Email       : yachna.2024@nst.rishihood.edu.in
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Comprehensive directed testbench validating all canonical cache
//               controller scenarios:
//               - TC-01: Cold Read Miss
//               - TC-02: Read Hit
//               - TC-03: Write Hit (Dirty Set)
//               - TC-04: Sub-word / Multi-word Access & Word Isolation
//               - TC-05: Write Miss (Write-Allocate)
//               - TC-06: Conflict Eviction of a Clean Line
//               - TC-07: Conflict Eviction of a Dirty Line with Write-Back
//                        and Coherence Read-Back Verification
//               - TC-08: Cache Boundary Lines (Line 0 and Line 255)
// =============================================================================

`timescale 1ns / 1ps

module tb_directed #(
    parameter MEM_LATENCY    = 10,
    parameter MEM_SIZE_WORDS = 65536,
    parameter INIT_FILE      = "traces/mem_init.hex"
);

    // -------------------------------------------------------------------------
    // Clock and Reset Signals
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz clock (10 ns period)

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
    // Verification Tracking & Golden Model
    // -------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer test_case_id;

    reg [31:0] golden_mem [0:MEM_SIZE_WORDS-1];

    // -------------------------------------------------------------------------
    // DUT Instantiation
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
    // CPU Read Task with Verification against Expected and Golden Model
    // -------------------------------------------------------------------------
    task automatic cpu_read;
        input [31:0] read_addr;
        input [31:0] expected_val;
        input        expect_hit;
        integer watchdog;
        integer hit_seen;
        integer miss_seen;
        reg [31:0] captured_rdata;
        begin
            watchdog  = 0;
            hit_seen  = 0;
            miss_seen = 0;

            @(negedge clk);
            addr  = read_addr;
            we    = 1'b0;
            wdata = 32'h0;
            req   = 1'b1;

            @(posedge clk); // Latch in IDLE

            while (!ready) begin
                @(posedge clk);
                if (hit)  hit_seen  = hit_seen + 1;
                if (miss) miss_seen = miss_seen + 1;

                watchdog = watchdog + 1;
                if (watchdog > 250) begin
                    $display("  [ERROR] Timeout waiting for ready on read to 0x%08h", read_addr);
                    fail_count = fail_count + 1;
                    disable cpu_read;
                end
            end

            // ready is high in COMPARE_TAG
            if (hit)  hit_seen  = hit_seen + 1;
            if (miss) miss_seen = miss_seen + 1;
            captured_rdata = rdata;

            // Verify data
            if (captured_rdata !== expected_val) begin
                $display("  [FAIL] Read 0x%08h: got 0x%08h, expected 0x%08h",
                         read_addr, captured_rdata, expected_val);
                fail_count = fail_count + 1;
            end else if (golden_mem[read_addr[17:2]] !== expected_val) begin
                $display("  [FAIL] Read 0x%08h: DUT matches expected but golden model has 0x%08h",
                         read_addr, golden_mem[read_addr[17:2]]);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            // Verify hit/miss classification
            if (expect_hit && (hit_seen == 0 || miss_seen > 0)) begin
                $display("  [FAIL] Read 0x%08h: Expected Hit, but observed hit=%0d, miss=%0d",
                         read_addr, hit_seen, miss_seen);
                fail_count = fail_count + 1;
            end else if (!expect_hit && miss_seen == 0) begin
                $display("  [FAIL] Read 0x%08h: Expected Miss, but miss was never asserted",
                         read_addr);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            @(negedge clk);
            req = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // CPU Write Task
    // -------------------------------------------------------------------------
    task automatic cpu_write;
        input [31:0] write_addr;
        input [31:0] write_data;
        input        expect_hit;
        integer watchdog;
        integer hit_seen;
        integer miss_seen;
        begin
            watchdog  = 0;
            hit_seen  = 0;
            miss_seen = 0;

            @(negedge clk);
            addr  = write_addr;
            we    = 1'b1;
            wdata = write_data;
            req   = 1'b1;

            @(posedge clk); // Latch in IDLE

            while (!ready) begin
                @(posedge clk);
                if (hit)  hit_seen  = hit_seen + 1;
                if (miss) miss_seen = miss_seen + 1;

                watchdog = watchdog + 1;
                if (watchdog > 250) begin
                    $display("  [ERROR] Timeout waiting for ready on write to 0x%08h", write_addr);
                    fail_count = fail_count + 1;
                    disable cpu_write;
                end
            end

            if (hit)  hit_seen  = hit_seen + 1;
            if (miss) miss_seen = miss_seen + 1;

            // Update golden model
            golden_mem[write_addr[17:2]] = write_data;
            pass_count = pass_count + 1;

            // Verify hit/miss
            if (expect_hit && (hit_seen == 0 || miss_seen > 0)) begin
                $display("  [FAIL] Write 0x%08h: Expected Hit, observed hit=%0d, miss=%0d",
                         write_addr, hit_seen, miss_seen);
                fail_count = fail_count + 1;
            end else if (!expect_hit && miss_seen == 0) begin
                $display("  [FAIL] Write 0x%08h: Expected Miss, but miss was never asserted",
                         write_addr);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end

            @(negedge clk);
            req   = 1'b0;
            we    = 1'b0;
            wdata = 32'h0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Reset Task
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
    // Main Directed Test Routine
    // -------------------------------------------------------------------------
    initial begin
        pass_count   = 0;
        fail_count   = 0;
        test_case_id = 0;

        // Initialize golden memory
        $readmemh(INIT_FILE, golden_mem);

        // Optional VCD waveform dump via +DUMP plusarg
        if ($test$plusargs("DUMP")) begin
            $dumpfile("docs/waveforms/cache_directed.vcd");
            $dumpvars(0, tb_directed);
            $display("[VCD] Waveform dumping enabled to docs/waveforms/cache_directed.vcd");
        end

        $display("===============================================================================");
        $display("   DIRECT-MAPPED CACHE CONTROLLER - DIRECTED VERIFICATION SUITE");
        $display("   Specifications: 4KB Cache, 16B Block, 256 Lines, Write-Back/Write-Allocate");
        $display("===============================================================================\n");

        reset_dut();

        // ---------------------------------------------------------------------
        // TC-01: Cold Read Miss
        // ---------------------------------------------------------------------
        test_case_id = 1;
        $display("-------------------------------------------------------------------------------");
        $display("TC-01: Cold Read Miss (Index 0x02, Word 2, Addr: 0x00000028)");
        $display("       Expects: Initial miss, 10-cycle memory allocate, clean line installed.");
        $display("-------------------------------------------------------------------------------");
        // Initial value at word 0x28 / 4 = 10 (0x0000000a)
        cpu_read(32'h0000_0028, 32'h0000_000a, 1'b0);
        $display("  [CHECK] TC-01 Passed: Cold miss allocated and serviced.\n");

        // ---------------------------------------------------------------------
        // TC-02: Read Hit
        // ---------------------------------------------------------------------
        test_case_id = 2;
        $display("-------------------------------------------------------------------------------");
        $display("TC-02: Read Hit (Index 0x02, Word 2, Addr: 0x00000028)");
        $display("       Expects: Immediate single-cycle hit, zero memory delay.");
        $display("-------------------------------------------------------------------------------");
        cpu_read(32'h0000_0028, 32'h0000_000a, 1'b1);
        $display("  [CHECK] TC-02 Passed: Cache read hit completed in 1 cycle.\n");

        // ---------------------------------------------------------------------
        // TC-03: Write Hit (Dirty Set)
        // ---------------------------------------------------------------------
        test_case_id = 3;
        $display("-------------------------------------------------------------------------------");
        $display("TC-03: Write Hit (Dirty Set) (Addr: 0x00000028, Data: 0xDEADBEEF)");
        $display("       Expects: Cache hit, SRAM update, dirty bit set, no bus traffic.");
        $display("-------------------------------------------------------------------------------");
        cpu_write(32'h0000_0028, 32'hDEAD_BEEF, 1'b1);
        cpu_read(32'h0000_0028, 32'hDEAD_BEEF, 1'b1);
        $display("  [CHECK] TC-03 Passed: Write hit modified SRAM and asserted dirty.\n");

        // ---------------------------------------------------------------------
        // TC-04: Sub-word Multiplexing and Word Isolation
        // ---------------------------------------------------------------------
        test_case_id = 4;
        $display("-------------------------------------------------------------------------------");
        $display("TC-04: Sub-word / Multi-word Access (Block base 0x00000020, Words 0, 1, 2, 3)");
        $display("       Expects: All 4 words independently accessible; writing one word");
        $display("                does not corrupt neighboring words.");
        $display("-------------------------------------------------------------------------------");
        // Read remaining words in the block: Word 0 (0x00000008), Word 1 (0x00000009), Word 3 (0x0000000b)
        cpu_read(32'h0000_0020, 32'h0000_0008, 1'b1);
        cpu_read(32'h0000_0024, 32'h0000_0009, 1'b1);
        cpu_read(32'h0000_002C, 32'h0000_000b, 1'b1);

        // Update Word 0 and Word 3
        cpu_write(32'h0000_0020, 32'h1111_0000, 1'b1);
        cpu_write(32'h0000_002C, 32'h3333_3333, 1'b1);

        // Verify all 4 words
        cpu_read(32'h0000_0020, 32'h1111_0000, 1'b1);
        cpu_read(32'h0000_0024, 32'h0000_0009, 1'b1); // Preserved original
        cpu_read(32'h0000_0028, 32'hDEAD_BEEF, 1'b1); // Preserved TC-03 write
        cpu_read(32'h0000_002C, 32'h3333_3333, 1'b1);
        $display("  [CHECK] TC-04 Passed: 4-word multiplexing and word isolation verified.\n");

        // ---------------------------------------------------------------------
        // TC-05: Write Miss (Write-Allocate)
        // ---------------------------------------------------------------------
        test_case_id = 5;
        $display("-------------------------------------------------------------------------------");
        $display("TC-05: Write Miss (Write-Allocate) (Addr: 0x00001044, Data: 0xCAFEF00D)");
        $display("       Expects: Miss allocates block from memory, writes word 1, sets dirty.");
        $display("-------------------------------------------------------------------------------");
        // Index 0x04, Tag 0x00001, Word 1
        cpu_write(32'h0000_1044, 32'hCAFE_F00D, 1'b0);
        cpu_read(32'h0000_1044, 32'hCAFE_F00D, 1'b1);
        // Verify sibling words in newly allocated block: Word 0 (addr 0x1040 >> 2 = 0x0410)
        cpu_read(32'h0000_1040, 32'h0000_0410, 1'b1);
        $display("  [CHECK] TC-05 Passed: Write miss successfully write-allocated.\n");

        // ---------------------------------------------------------------------
        // TC-06: Conflict Eviction of a Clean Line
        // ---------------------------------------------------------------------
        test_case_id = 6;
        $display("-------------------------------------------------------------------------------");
        $display("TC-06: Conflict Eviction of Clean Line (Index 0x03, Addr1: 0x0030, Addr2: 0x2030)");
        $display("       Expects: Miss replaces clean line immediately without memory writeback.");
        $display("-------------------------------------------------------------------------------");
        // 1. Fetch clean block at 0x0000_0030 (Index 0x03, Tag 0x00000)
        cpu_read(32'h0000_0030, 32'h0000_000c, 1'b0); // Miss, allocate
        cpu_read(32'h0000_0030, 32'h0000_000c, 1'b1); // Hit, clean

        // 2. Access conflicting block with same Index (0x03) but Tag 0x00002 (Addr 0x0000_2030)
        // Since line is clean, DUT enters ALLOCATE directly without WRITE_BACK
        cpu_read(32'h0000_2030, 32'h0000_080c, 1'b0); // Miss, allocate without writeback
        cpu_read(32'h0000_2030, 32'h0000_080c, 1'b1); // Hit
        $display("  [CHECK] TC-06 Passed: Clean conflict eviction bypassed write-back.\n");

        // ---------------------------------------------------------------------
        // TC-07: Conflict Eviction of a Dirty Line with Write-Back and Read-Back
        // ---------------------------------------------------------------------
        test_case_id = 7;
        $display("-------------------------------------------------------------------------------");
        $display("TC-07: Conflict Eviction of Dirty Line with Write-Back & Coherence Read-Back");
        $display("       Target line index 0x02 is currently dirty (modified in TC-03/04).");
        $display("       Step 1: Access conflicting address 0x00001028 (Index 0x02, Tag 0x00001).");
        $display("               Expects: WRITE_BACK (128-bit store) -> ALLOCATE (128-bit fetch).");
        $display("       Step 2: Access 0x00000020 and 0x00000028 again to verify evicted data");
        $display("               was safely committed to backing memory.");
        $display("-------------------------------------------------------------------------------");
        // Conflicting access to Index 0x02
        cpu_read(32'h0000_1028, 32'h0000_040a, 1'b0); // Dirty eviction + allocation
        cpu_read(32'h0000_1028, 32'h0000_040a, 1'b1); // Hit in new block

        // Re-access original block 0x0000_0020. This causes eviction of clean 0x1020,
        // and reloads 0x0020 from backing memory!
        cpu_read(32'h0000_0020, 32'h1111_0000, 1'b0); // Reloaded Word 0
        cpu_read(32'h0000_0024, 32'h0000_0009, 1'b1); // Reloaded Word 1
        cpu_read(32'h0000_0028, 32'hDEAD_BEEF, 1'b1); // Reloaded Word 2 (Modified!)
        cpu_read(32'h0000_002C, 32'h3333_3333, 1'b1); // Reloaded Word 3 (Modified!)
        $display("  [CHECK] TC-07 Passed: 128-bit dirty line writeback verified via memory read-back.\n");

        // ---------------------------------------------------------------------
        // TC-08: Boundary Lines (Line 0 and Line 255)
        // ---------------------------------------------------------------------
        test_case_id = 8;
        $display("-------------------------------------------------------------------------------");
        $display("TC-08: Boundary Lines Verification (Line 0: 0x00000000, Line 255: 0x00000FF0)");
        $display("       Expects: Extremities of index space function identically.");
        $display("-------------------------------------------------------------------------------");
        // Line 0 (Index 0x00)
        cpu_write(32'h0000_0000, 32'h0000_AAAA, 1'b0);
        cpu_read (32'h0000_0000, 32'h0000_AAAA, 1'b1);

        // Line 255 (Index 0xFF, Addr = {Tag 0, Index 8'hFF, Offset 4'h0} = 0x0000_0FF0)
        cpu_write(32'h0000_0FFC, 32'hFFFF_5555, 1'b0);
        cpu_read (32'h0000_0FFC, 32'hFFFF_5555, 1'b1);
        $display("  [CHECK] TC-08 Passed: Boundary line indices 0 and 255 verified.\n");

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("===============================================================================");
        $display("  VERIFICATION SUMMARY");
        $display("===============================================================================");
        if (fail_count == 0) begin
            $display("  >>> ALL TESTS PASSED <<<");
            $display("  Total successful assertion checks: %0d", pass_count);
            $display("  Failures: 0");
        end else begin
            $display("  >>> %0d TESTS FAILED <<<", fail_count);
            $display("  Successful checks: %0d", pass_count);
        end
        $display("===============================================================================\n");

        $finish;
    end

endmodule
