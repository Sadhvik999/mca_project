// =============================================================================
// File Name   : tb_main_memory.v
// Module Name : tb_main_memory
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Varun Udata (M2)
// Email       : varunudata@gmail.com
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Self-checking testbench for main_memory. Verifies:
//               1) Deterministic $readmemh initialization (traces/mem_init.hex)
//               2) Exact MEM_LATENCY (10-cycle) handshake and 1-cycle pulse
//               3) Block write followed by block read-back without neighbor
//                  corruption
//               4) Unaligned addresses mapping to enclosing 16-byte block
//               5) Back-to-back Moore write-back -> allocate transition
//               6) Synchronous reset preserving backing memory contents
// =============================================================================

`timescale 1ns / 1ps

module tb_main_memory;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam MEM_LATENCY    = 10;
    localparam MEM_SIZE_WORDS = 65536;
    localparam BLOCK_SIZE     = 16;
    localparam ADDR_WIDTH     = 32;
    localparam CLK_PERIOD     = 10;

    // -------------------------------------------------------------------------
    // Testbench Signals
    // -------------------------------------------------------------------------
    reg                    clk;
    reg                    rst;
    reg                    mem_req;
    reg                    mem_we;
    reg  [ADDR_WIDTH-1:0]  mem_addr;
    reg  [127:0]           mem_wdata;

    wire [127:0]           mem_rdata;
    wire                   mem_ready;

    integer error_count = 0;
    integer test_count  = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    main_memory #(
        .MEM_LATENCY(MEM_LATENCY),
        .MEM_SIZE_WORDS(MEM_SIZE_WORDS),
        .BLOCK_SIZE(BLOCK_SIZE),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INIT_FILE("traces/mem_init.hex")
    ) dut (
        .clk(clk),
        .rst(rst),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    // -------------------------------------------------------------------------
    // 100 MHz Clock Generator
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Helper Task: Perform Block Read or Write & Verify Exact Latency + Pulse
    // -------------------------------------------------------------------------
    task run_mem_tx(
        input                   is_write,
        input  [ADDR_WIDTH-1:0] addr_in,
        input  [127:0]          wdata_in,
        output [127:0]          rdata_out,
        input  [8*40-1:0]       label
    );
        integer cyc;
        begin
            // Drive request cleanly after clock edge
            @(posedge clk);
            #(CLK_PERIOD / 4);
            mem_req   = 1'b1;
            mem_we    = is_write;
            mem_addr  = addr_in;
            mem_wdata = wdata_in;

            // Edge 0: DUT samples mem_req == 1 in S_IDLE; count cycles until
            // synchronous consumer samples mem_ready == 1.
            @(posedge clk); // Cycle 0 (request accepted)
            cyc = 0;

            while (mem_ready !== 1'b1 && cyc < (MEM_LATENCY + 10)) begin
                @(posedge clk);
                cyc = cyc + 1;
            end

            // Check exact latency (should equal MEM_LATENCY = 10 cycles)
            test_count = test_count + 1;
            if (mem_ready !== 1'b1) begin
                $display("[ERROR] %0s | Timeout waiting for mem_ready", label);
                error_count = error_count + 1;
            end else if (cyc !== MEM_LATENCY) begin
                $display("[ERROR] %0s | Latency mismatch: expected %0d cycles, got %0d cycles",
                         label, MEM_LATENCY, cyc);
                error_count = error_count + 1;
            end

            // Latch read data at the exact completion clock edge
            rdata_out = mem_rdata;

            // Deassert request and verify mem_ready drops after 1 cycle
            #(CLK_PERIOD / 4);
            mem_req   = 1'b0;
            mem_we    = 1'b0;
            mem_wdata = 128'h0;

            test_count = test_count + 1;
            if (mem_ready !== 1'b0) begin
                $display("[ERROR] %0s | mem_ready stayed high longer than 1 cycle", label);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_block_eq(
        input [127:0]    actual,
        input [127:0]    expected,
        input [8*40-1:0] label
    );
        begin
            test_count = test_count + 1;
            if (actual !== expected) begin
                $display("[ERROR] %0s | Expected: 0x%032h | Actual: 0x%032h",
                         label, expected, actual);
                error_count = error_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification Sequence
    // -------------------------------------------------------------------------
    reg [127:0] rx_block;
    integer     b2b_cyc;

    initial begin
        $dumpfile("tb/main_memory.vcd");
        $dumpvars(0, tb_main_memory);

        rst       = 1'b1;
        mem_req   = 1'b0;
        mem_we    = 1'b0;
        mem_addr  = 32'h0000_0000;
        mem_wdata = 128'h0;

        $display("----------------------------------------------------------------");
        $display("Starting Self-Checking Testbench: main_memory (MEM_LATENCY=%0d)", MEM_LATENCY);
        $display("----------------------------------------------------------------");

        // Release reset after 2 cycles
        repeat (2) @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b0;

        test_count = test_count + 1;
        if (mem_ready !== 1'b0) begin
            $display("[ERROR] Post-reset mem_ready should be 0");
            error_count = error_count + 1;
        end

        // Stage 1: Verify Preloaded $readmemh Contents & Exact Read Latency
        $display("[STAGE 1] Verifying $readmemh preload and %0d-cycle read latency...", MEM_LATENCY);
        run_mem_tx(1'b0, 32'h0000_0000, 128'h0, rx_block, "Preload Block 0");
        check_block_eq(rx_block, {32'h0000_0003, 32'h0000_0002, 32'h0000_0001, 32'h0000_0000},
                       "Preload Data @ 0x00000000");

        run_mem_tx(1'b0, 32'h0000_0010, 128'h0, rx_block, "Preload Block 1");
        check_block_eq(rx_block, {32'h0000_0007, 32'h0000_0006, 32'h0000_0005, 32'h0000_0004},
                       "Preload Data @ 0x00000010");

        run_mem_tx(1'b0, 32'h0003_FFF0, 128'h0, rx_block, "Preload Top Block");
        check_block_eq(rx_block, {32'h0000_FFFF, 32'h0000_FFFE, 32'h0000_FFFD, 32'h0000_FFFC},
                       "Preload Data @ 0x0003FFF0");

        // Stage 2: Block Write Followed by Block Read-Back
        $display("[STAGE 2] Testing 128-bit block write & read-back on 0x0000_0100...");
        run_mem_tx(1'b1, 32'h0000_0100, 128'hCAFE_BABE_DEAD_BEEF_1234_5678_9ABC_DEF0,
                   rx_block, "Write @ 0x00000100");
        run_mem_tx(1'b0, 32'h0000_0100, 128'h0, rx_block, "Readback @ 0x00000100");
        check_block_eq(rx_block, 128'hCAFE_BABE_DEAD_BEEF_1234_5678_9ABC_DEF0,
                       "Readback Match @ 0x00000100");

        // Ensure adjacent block at 0x0000_0110 (words 0x44..0x47) was untouched
        run_mem_tx(1'b0, 32'h0000_0110, 128'h0, rx_block, "Neighbor Block @ 0x00000110");
        check_block_eq(rx_block, {32'h0000_0047, 32'h0000_0046, 32'h0000_0045, 32'h0000_0044},
                       "Neighbor Untouched @ 0x00000110");

        // Stage 3: Unaligned Address Mapping to Aligned 16-Byte Block
        $display("[STAGE 3] Testing unaligned addresses map to aligned 16-byte blocks...");
        // Read preloaded block 0x0000_0020 using unaligned address 0x0000_002B
        run_mem_tx(1'b0, 32'h0000_002B, 128'h0, rx_block, "Unaligned Preload Read 0x2B");
        check_block_eq(rx_block, {32'h0000_000B, 32'h0000_000A, 32'h0000_0009, 32'h0000_0008},
                       "Unaligned 0x2B -> 0x20 Block");

        // Write via unaligned 0x0000_020D, read back via 0x0200, 0x0204, 0x0208, 0x020F
        run_mem_tx(1'b1, 32'h0000_020D, 128'hF0E1_D2C3_B4A5_9687_7869_5A4B_3C2D_1E0F,
                   rx_block, "Unaligned Write 0x020D");

        run_mem_tx(1'b0, 32'h0000_0200, 128'h0, rx_block, "Aligned Read 0x0200");
        check_block_eq(rx_block, 128'hF0E1_D2C3_B4A5_9687_7869_5A4B_3C2D_1E0F,
                       "Read via 0x0200");

        run_mem_tx(1'b0, 32'h0000_0204, 128'h0, rx_block, "Unaligned Read 0x0204");
        check_block_eq(rx_block, 128'hF0E1_D2C3_B4A5_9687_7869_5A4B_3C2D_1E0F,
                       "Read via 0x0204");

        run_mem_tx(1'b0, 32'h0000_0208, 128'h0, rx_block, "Unaligned Read 0x0208");
        check_block_eq(rx_block, 128'hF0E1_D2C3_B4A5_9687_7869_5A4B_3C2D_1E0F,
                       "Read via 0x0208");

        run_mem_tx(1'b0, 32'h0000_020F, 128'h0, rx_block, "Unaligned Read 0x020F");
        check_block_eq(rx_block, 128'hF0E1_D2C3_B4A5_9687_7869_5A4B_3C2D_1E0F,
                       "Read via 0x020F");

        // Stage 4: Back-to-Back Moore Transition (WRITE_BACK -> ALLOCATE)
        $display("[STAGE 4] Testing back-to-back Moore write-back -> allocate handshake...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        mem_req   = 1'b1;
        mem_we    = 1'b1;
        mem_addr  = 32'h0000_0300;
        mem_wdata = 128'h1111_2222_3333_4444_5555_6666_7777_8888;

        @(posedge clk); // Cycle 0: write accepted
        b2b_cyc = 0;
        while (mem_ready !== 1'b1 && b2b_cyc < 20) begin
            @(posedge clk);
            b2b_cyc = b2b_cyc + 1;
        end
        test_count = test_count + 1;
        if (b2b_cyc !== MEM_LATENCY) begin
            $display("[ERROR] B2B Write latency expected %0d, got %0d", MEM_LATENCY, b2b_cyc);
            error_count = error_count + 1;
        end

        // Immediately switch to ALLOCATE read on next cycle without dropping mem_req
        #(CLK_PERIOD / 4);
        mem_req   = 1'b1;
        mem_we    = 1'b0;
        mem_addr  = 32'h0000_0300;
        mem_wdata = 128'h0;

        // Verify mem_ready dropped cleanly and 2nd transaction takes MEM_LATENCY cycles
        test_count = test_count + 1;
        if (mem_ready !== 1'b0) begin
            $display("[ERROR] B2B mem_ready did not clear between transactions");
            error_count = error_count + 1;
        end

        @(posedge clk); // Cycle 0: back-to-back read accepted
        b2b_cyc = 0;
        while (mem_ready !== 1'b1 && b2b_cyc < 20) begin
            @(posedge clk);
            b2b_cyc = b2b_cyc + 1;
        end
        test_count = test_count + 1;
        if (b2b_cyc !== MEM_LATENCY) begin
            $display("[ERROR] B2B Read latency expected %0d, got %0d", MEM_LATENCY, b2b_cyc);
            error_count = error_count + 1;
        end
        check_block_eq(mem_rdata, 128'h1111_2222_3333_4444_5555_6666_7777_8888,
                       "B2B Readback @ 0x00000300");

        #(CLK_PERIOD / 4);
        mem_req = 1'b0;

        // Stage 5: Reset Preserves Memory Contents
        $display("[STAGE 5] Checking synchronous reset preserves memory contents...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b1;
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b0;

        run_mem_tx(1'b0, 32'h0000_0030, 128'h0, rx_block, "Post-Reset Preload 0x30");
        check_block_eq(rx_block, {32'h0000_000F, 32'h0000_000E, 32'h0000_000D, 32'h0000_000C},
                       "Preload Preserved After Reset");

        // Final Summary
        $display("----------------------------------------------------------------");
        $display("Tests Executed: %0d assertions checked", test_count);
        if (error_count == 0) begin
            $display(">>> TEST STATUS: PASS <<<");
            $display("All main_memory operations verified successfully!");
        end else begin
            $display(">>> TEST STATUS: FAIL (%0d errors detected) <<<", error_count);
        end
        $display("----------------------------------------------------------------");

        $finish;
    end

endmodule
