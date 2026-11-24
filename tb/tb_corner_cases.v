// =============================================================================
// File Name   : tb_corner_cases.v
// Module Name : tb_corner_cases
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Mustyala Sadhvik (M1)
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Comprehensive self-checking testbench covering 8 architectural
//               corner cases and protocol edge scenarios using a golden memory
//               reference model:
//                 1. First access after reset (all lines invalid)
//                 2. Read miss with a clean victim
//                 3. Write to a dirty line (hit)
//                 4. Write miss with a dirty victim
//                 5. Write to the same index with a different tag (conflict ping-pong)
//                 6. Reset in the middle of a transaction (abort & recover)
//                 7. Request held high through ready (continuous streaming)
//                 8. Back-to-back requests across distinct indices
// =============================================================================

`timescale 1ns / 1ps

module tb_corner_cases #(
    parameter MEM_LATENCY    = 10,
    parameter MEM_SIZE_WORDS = 65536,
    parameter INIT_FILE      = "traces/mem_init.hex"
);

    // -------------------------------------------------------------------------
    // Clock and Reset Signals (100 MHz, 10 ns clock period)
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;

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
    // Bookkeeping and Statistics
    // -------------------------------------------------------------------------
    integer total_cases = 0;
    integer pass_cases  = 0;
    integer fail_cases  = 0;
    integer case_errors = 0;

    // -------------------------------------------------------------------------
    // Golden Reference Model (64K-word software memory array)
    // -------------------------------------------------------------------------
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
    // Helper Tasks
    // -------------------------------------------------------------------------
    task automatic start_case(input [8*64-1:0] case_name);
        begin
            total_cases = total_cases + 1;
            case_errors = 0;
            $display("-------------------------------------------------------------------------------");
            $display("TEST CASE %0d: %0s", total_cases, case_name);
            $display("-------------------------------------------------------------------------------");
        end
    endtask

    task automatic end_case;
        begin
            if (case_errors == 0) begin
                $display(">>> RESULT: PASS (Test Case %0d)\n", total_cases);
                pass_cases = pass_cases + 1;
            end else begin
                $display(">>> RESULT: FAIL (Test Case %0d with %0d errors)\n", total_cases, case_errors);
                fail_cases = fail_cases + 1;
            end
        end
    endtask

    task automatic cpu_write(
        input [31:0] write_addr,
        input [31:0] write_data
    );
        integer watchdog;
        begin
            watchdog = 0;
            @(negedge clk);
            addr  = write_addr;
            we    = 1'b1;
            wdata = write_data;
            req   = 1'b1;

            @(posedge clk); // Captured by controller in IDLE

            while (!ready) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 300) begin
                    $display("  [ERROR] cpu_write timeout at addr 0x%08h", write_addr);
                    case_errors = case_errors + 1;
                    disable cpu_write;
                end
            end

            // Synchronously maintain golden oracle
            golden_mem[write_addr[17:2]] = write_data;

            @(negedge clk);
            req   = 1'b0;
            we    = 1'b0;
            wdata = 32'h0;
        end
    endtask

    task automatic cpu_read(
        input [31:0] read_addr,
        input [31:0] expected_val
    );
        integer watchdog;
        reg [31:0] captured_rdata;
        begin
            watchdog = 0;
            @(negedge clk);
            addr  = read_addr;
            we    = 1'b0;
            wdata = 32'h0;
            req   = 1'b1;

            @(posedge clk); // Captured by controller in IDLE

            while (!ready) begin
                @(posedge clk);
                watchdog = watchdog + 1;
                if (watchdog > 300) begin
                    $display("  [ERROR] cpu_read timeout at addr 0x%08h", read_addr);
                    case_errors = case_errors + 1;
                    disable cpu_read;
                end
            end

            captured_rdata = rdata;

            if (captured_rdata !== expected_val) begin
                $display("  [FAIL] Data mismatch at 0x%08h | Expected: 0x%08h | Actual: 0x%08h",
                         read_addr, expected_val, captured_rdata);
                case_errors = case_errors + 1;
            end else if (golden_mem[read_addr[17:2]] !== expected_val) begin
                $display("  [FAIL] Golden oracle mismatch at 0x%08h | Expected: 0x%08h | Golden: 0x%08h",
                         read_addr, expected_val, golden_mem[read_addr[17:2]]);
                case_errors = case_errors + 1;
            end

            @(negedge clk);
            req = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification Flow
    // -------------------------------------------------------------------------
    initial begin
        // Preload software golden model memory
        $readmemh(INIT_FILE, golden_mem);

        if ($test$plusargs("DUMP")) begin
            $dumpfile("build/corner_cases.vcd");
            $dumpvars(0, tb_corner_cases);
        end

        $display("===============================================================================");
        $display("   DIRECT-MAPPED CACHE CONTROLLER - CORNER CASE VERIFICATION SUITE");
        $display("===============================================================================\n");

        // Global Reset Initialization
        rst   = 1'b1;
        req   = 1'b0;
        we    = 1'b0;
        addr  = 32'h0;
        wdata = 32'h0;
        repeat (4) @(negedge clk);
        rst   = 1'b0;
        repeat (2) @(negedge clk);

        // =====================================================================
        // Case 1: First access after reset (all lines invalid)
        // =====================================================================
        start_case("First Access After Reset (All Lines Invalid)");
        // Addr: 0x00000010 (Index: 0x01, Tag: 0x00000, Word: 0)
        // Expected initial state: line 0x01 valid=0, dirty=0.
        // Golden value at word 0x00000010/4 = 4 is 0x00000004.
        cpu_read(32'h00000010, 32'h00000004);
        if (dut.tags.valid_mem[8'h01] !== 1'b1 || dut.tags.dirty_mem[8'h01] !== 1'b0) begin
            $display("  [FAIL] Line 0x01 metadata incorrect after initial fill (V=%b, D=%b)",
                     dut.tags.valid_mem[8'h01], dut.tags.dirty_mem[8'h01]);
            case_errors = case_errors + 1;
        end
        end_case();

        // =====================================================================
        // Case 2: Read miss with a clean victim
        // =====================================================================
        start_case("Read Miss with a Clean Victim");
        // Prime line 0x02 with clean block at Tag 0x00000 (Addr 0x00000028)
        cpu_read(32'h00000028, 32'h0000000A);
        // Verify line 0x02 is valid and clean
        if (dut.tags.valid_mem[8'h02] !== 1'b1 || dut.tags.dirty_mem[8'h02] !== 1'b0) begin
            $display("  [FAIL] Line 0x02 should be valid and clean before replacement");
            case_errors = case_errors + 1;
        end
        // Now issue read miss to Tag 0x00001 at same index 0x02 (Addr 0x00001028)
        // Expected: Bypasses WRITE_BACK, directly ALLOCATE, installs Tag 0x00001 as clean.
        cpu_read(32'h00001028, 32'h0000040A);
        if (dut.tags.tag_mem[8'h02] !== 20'h00001 || dut.tags.dirty_mem[8'h02] !== 1'b0) begin
            $display("  [FAIL] Line 0x02 failed to allocate clean victim correctly (Tag=0x%05h, D=%b)",
                     dut.tags.tag_mem[8'h02], dut.tags.dirty_mem[8'h02]);
            case_errors = case_errors + 1;
        end
        end_case();

        // =====================================================================
        // Case 3: Write to a dirty line (hit)
        // =====================================================================
        start_case("Write to a Dirty Line (Hit)");
        // Write to 0x00001028, setting line 0x02 dirty
        cpu_write(32'h00001028, 32'hDEADBEEF);
        if (dut.tags.dirty_mem[8'h02] !== 1'b1) begin
            $display("  [FAIL] Line 0x02 should be marked dirty after initial write");
            case_errors = case_errors + 1;
        end
        // Issue a second write to word 3 of the same block (0x0000102C)
        // Expected: Single-cycle hit, line remains dirty, no memory request generated.
        cpu_write(32'h0000102C, 32'hCAFEBABE);
        if (dut.tags.dirty_mem[8'h02] !== 1'b1) begin
            $display("  [FAIL] Line 0x02 lost dirty status on second write hit");
            case_errors = case_errors + 1;
        end
        // Verify both words retain their updated values
        cpu_read(32'h00001028, 32'hDEADBEEF);
        cpu_read(32'h0000102C, 32'hCAFEBABE);
        end_case();

        // =====================================================================
        // Case 4: Write miss with a dirty victim
        // =====================================================================
        start_case("Write Miss with a Dirty Victim");
        // Line 0x02 currently holds dirty block Tag 0x00001 (Addr 0x00001020).
        // Store to Tag 0x00002 at Index 0x02 (Addr 0x00002028).
        // Expected: Miss triggers WRITE_BACK of Tag 0x00001 to memory, then ALLOCATE
        // of Tag 0x00002, then writes new data 0x11223344.
        cpu_write(32'h00002028, 32'h11223344);
        // Verify line 0x02 now holds Tag 0x00002 and is dirty
        if (dut.tags.tag_mem[8'h02] !== 20'h00002 || dut.tags.dirty_mem[8'h02] !== 1'b1) begin
            $display("  [FAIL] Line 0x02 metadata incorrect after dirty miss allocate (Tag=0x%05h, D=%b)",
                     dut.tags.tag_mem[8'h02], dut.tags.dirty_mem[8'h02]);
            case_errors = case_errors + 1;
        end
        // Crucial Coherence Verification: Read back the evicted victim (0x00001028 and 0x0000102C)
        // from memory to prove that dirty writeback committed data to backing store!
        cpu_read(32'h00001028, 32'hDEADBEEF);
        cpu_read(32'h0000102C, 32'hCAFEBABE);
        end_case();

        // =====================================================================
        // Case 5: Write to the same index with a different tag (Conflict Ping-Pong)
        // =====================================================================
        start_case("Write to Same Index with Different Tag (Conflict Ping-Pong)");
        // Index 0x04: Alternating writes between Tag 0x00000 (0x00000040) and Tag 0x00001 (0x00001040)
        cpu_write(32'h00000040, 32'hAAAA0001);
        cpu_write(32'h00001040, 32'hBBBB0002);
        cpu_write(32'h00000040, 32'hCCCC0003);
        // Verify coherence: reading back both blocks recovers correct latest values
        cpu_read(32'h00001040, 32'hBBBB0002);
        cpu_read(32'h00000040, 32'hCCCC0003);
        end_case();

        // =====================================================================
        // Case 6: Reset in the middle of a transaction (Abort & Recover)
        // =====================================================================
        start_case("Reset in Middle of a Transaction (Abort & Recover)");
        // Initiate a cold read miss to 0x00000080 (Index 0x08)
        @(negedge clk);
        addr = 32'h00000080;
        we   = 1'b0;
        req  = 1'b1;
        @(posedge clk); // Latch in IDLE -> COMPARE_TAG

        // Wait until controller enters ALLOCATE (state == 2'd3)
        while (dut.state !== 2'd3) @(posedge clk);

        // Abruptly assert synchronous reset in the middle of the 10-cycle memory latency!
        @(negedge clk);
        rst = 1'b1;
        req = 1'b0;

        repeat (2) @(posedge clk);

        // Verify controller FSM immediately returned to IDLE and dropped bus control
        if (dut.state !== 2'd0 || dut.ready !== 1'b0 || dut.controller.mem_req !== 1'b0) begin
            $display("  [FAIL] Controller did not cleanly reset to IDLE during transaction abort");
            case_errors = case_errors + 1;
        end

        // Deassert reset
        @(negedge clk);
        rst = 1'b0;
        repeat (3) @(posedge clk);

        // Verify recovery: issue fresh read to same address and ensure it completes normally
        cpu_read(32'h00000080, 32'h00000020);
        end_case();

        // =====================================================================
        // Case 7: Request held high through ready (Continuous Streaming)
        // =====================================================================
        start_case("Request Held High Through Ready (Continuous Streaming)");
        // Prime line 0x09 with clean block (Addr 0x00000090)
        cpu_read(32'h00000090, 32'h00000024);

        // Issue Read 1 and keep req asserted high even across ready
        @(negedge clk);
        addr = 32'h00000090;
        we   = 1'b0;
        req  = 1'b1;

        @(posedge clk);
        // Wait for ready on Read 1
        while (!ready) @(posedge clk);

        // On the cycle ready is high, verify rdata, then update addr to 0x00000094
        // WITHOUT lowering req!
        if (rdata !== 32'h00000024) begin
            $display("  [FAIL] Request 1 data mismatch: expected 0x00000024, got 0x%08h", rdata);
            case_errors = case_errors + 1;
        end

        @(negedge clk);
        addr = 32'h00000094; // Word 1 of same line
        req  = 1'b1;         // Kept continuously high!

        // Wait for ready on Request 2
        @(posedge clk);
        while (!ready) @(posedge clk);

        if (rdata !== 32'h00000025) begin
            $display("  [FAIL] Request 2 data mismatch: expected 0x00000025, got 0x%08h", rdata);
            case_errors = case_errors + 1;
        end

        @(negedge clk);
        req = 1'b0;
        end_case();

        // =====================================================================
        // Case 8: Back-to-back requests across distinct indices
        // =====================================================================
        start_case("Back-to-Back Requests Across Distinct Indices");
        // Prime line 0x10 (0x00000100) and line 0x20 (0x00000200)
        cpu_read(32'h00000100, 32'h00000040);
        cpu_read(32'h00000200, 32'h00000080);

        // Execute Read Hit on line 0x10
        @(negedge clk);
        addr = 32'h00000100;
        we   = 1'b0;
        req  = 1'b1;

        @(posedge clk);
        while (!ready) @(posedge clk);

        // Immediately transition to Write Hit on line 0x20 on following cycle
        @(negedge clk);
        addr  = 32'h00000200;
        we    = 1'b1;
        wdata = 32'h99887766;
        req   = 1'b1;

        @(posedge clk);
        while (!ready) @(posedge clk);

        @(negedge clk);
        req = 1'b0;
        we  = 1'b0;

        // Verify updated write data
        golden_mem[32'h00000200 >> 2] = 32'h99887766;
        cpu_read(32'h00000200, 32'h99887766);
        end_case();

        // =====================================================================
        // Final Summary
        // =====================================================================
        $display("===============================================================================");
        $display("   CORNER CASE VERIFICATION SUMMARY");
        $display("===============================================================================");
        $display("   Total Corner Cases Evaluated : %0d", total_cases);
        $display("   Total Passed                 : %0d", pass_cases);
        $display("   Total Failed                 : %0d", fail_cases);
        $display("===============================================================================");

        if (fail_cases == 0) begin
            $display(">>> ALL TESTS PASSED <<<\n");
        end else begin
            $display(">>> %0d TESTS FAILED <<<\n", fail_cases);
        end

        $finish;
    end

endmodule
