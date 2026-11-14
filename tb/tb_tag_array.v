// =============================================================================
// File Name   : tb_tag_array.v
// Module Name : tb_tag_array
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Mustyala Sadhvik (M1)
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Comprehensive self-checking testbench for tag_array module.
//               Verifies reset initialization, write allocation, read latency,
//               selective dirty assertion, entry isolation across 256 lines,
//               and re-reset clearing. Reports explicit PASS/FAIL status.
// =============================================================================

`timescale 1ns / 1ps

module tb_tag_array;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam TAG_WIDTH   = 20;
    localparam INDEX_WIDTH = 8;
    localparam NUM_LINES   = 256;
    localparam CLK_PERIOD  = 10; // 10 ns clock (100 MHz)

    // -------------------------------------------------------------------------
    // Testbench Signals
    // -------------------------------------------------------------------------
    reg                   clk;
    reg                   rst;
    reg [INDEX_WIDTH-1:0] index;
    reg [TAG_WIDTH-1:0]   tag_in;
    reg                   valid_in;
    reg                   dirty_in;
    reg                   write_en;
    reg                   set_dirty;

    wire [TAG_WIDTH-1:0]  tag_out;
    wire                  valid_out;
    wire                  dirty_out;

    integer error_count = 0;
    integer test_count  = 0;
    integer idx;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // -------------------------------------------------------------------------
    tag_array #(
        .TAG_WIDTH(TAG_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH),
        .NUM_LINES(NUM_LINES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .index(index),
        .tag_in(tag_in),
        .valid_in(valid_in),
        .dirty_in(dirty_in),
        .write_en(write_en),
        .set_dirty(set_dirty),
        .tag_out(tag_out),
        .valid_out(valid_out),
        .dirty_out(dirty_out)
    );

    // -------------------------------------------------------------------------
    // Clock Generation: 100 MHz (10 ns period)
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Tasks: Synchronous Write & Set-Dirty Operations
    // -------------------------------------------------------------------------
    task write_entry(
        input [INDEX_WIDTH-1:0] wr_index,
        input [TAG_WIDTH-1:0]   wr_tag,
        input                   wr_valid,
        input                   wr_dirty
    );
        begin
            @(posedge clk);
            #(CLK_PERIOD / 4); // Drive after clock edge to avoid delta-cycle race
            index     = wr_index;
            tag_in    = wr_tag;
            valid_in  = wr_valid;
            dirty_in  = wr_dirty;
            write_en  = 1'b1;
            set_dirty = 1'b0;
            @(posedge clk);
            #(CLK_PERIOD / 4);
            write_en  = 1'b0;
        end
    endtask

    task mark_dirty(
        input [INDEX_WIDTH-1:0] d_index
    );
        begin
            @(posedge clk);
            #(CLK_PERIOD / 4);
            index     = d_index;
            write_en  = 1'b0;
            set_dirty = 1'b1;
            @(posedge clk);
            #(CLK_PERIOD / 4);
            set_dirty = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Assertion Helper Task
    // -------------------------------------------------------------------------
    task check_line(
        input [INDEX_WIDTH-1:0] target_index,
        input                   exp_valid,
        input                   exp_dirty,
        input [TAG_WIDTH-1:0]   exp_tag,
        input [8*32-1:0]        test_name
    );
        begin
            index = target_index;
            #1; // Allow asynchronous read propagation
            test_count = test_count + 1;
            if (valid_out !== exp_valid || dirty_out !== exp_dirty || tag_out !== exp_tag) begin
                $display("[ERROR] %0s @ index 0x%02h | Expected: V=%b D=%b Tag=0x%05h | Actual: V=%b D=%b Tag=0x%05h",
                         test_name, target_index, exp_valid, exp_dirty, exp_tag,
                         valid_out, dirty_out, tag_out);
                error_count = error_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Setup VCD Waveform Dump
        $dumpfile("tb/tag_array.vcd");
        $dumpvars(0, tb_tag_array);

        // Signal initialization
        rst       = 1'b1;
        index     = 8'h00;
        tag_in    = 20'h00000;
        valid_in  = 1'b0;
        dirty_in  = 1'b0;
        write_en  = 1'b0;
        set_dirty = 1'b0;

        $display("----------------------------------------------------------------");
        $display("Starting Self-Checking Testbench: tag_array (256 entries)");
        $display("----------------------------------------------------------------");

        // ---------------------------------------------------------------------
        // Stage 1: Power-On Reset & Initialization Check
        // ---------------------------------------------------------------------
        $display("[STAGE 1] Testing synchronous reset across all 256 entries...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b0; // Deassert reset

        for (idx = 0; idx < NUM_LINES; idx = idx + 1) begin
            check_line(idx[INDEX_WIDTH-1:0], 1'b0, 1'b0, 20'h00000, "Reset Check");
        end

        if (error_count == 0)
            $display("[STAGE 1] PASS: All 256 lines successfully initialized to V=0, D=0, Tag=0x00000.");
        else
            $display("[STAGE 1] FAIL: Errors detected during reset verification.");

        // ---------------------------------------------------------------------
        // Stage 2: Write Allocation (Clean Line)
        // ---------------------------------------------------------------------
        $display("\n[STAGE 2] Testing write allocation (clean line insertion)...");
        write_entry(8'h34, 20'h00012, 1'b1, 1'b0);
        check_line(8'h34, 1'b1, 1'b0, 20'h00012, "Clean Write Allocation");

        // ---------------------------------------------------------------------
        // Stage 3: Write Allocation (Dirty Line)
        // ---------------------------------------------------------------------
        $display("\n[STAGE 3] Testing write allocation (dirty line insertion)...");
        write_entry(8'h56, 20'h80004, 1'b1, 1'b1);
        check_line(8'h56, 1'b1, 1'b1, 20'h80004, "Dirty Write Allocation");

        // ---------------------------------------------------------------------
        // Stage 4: Selective set_dirty Assertion (Write Hit Behavior)
        // ---------------------------------------------------------------------
        $display("\n[STAGE 4] Testing selective set_dirty on clean line (8'h34)...");
        check_line(8'h34, 1'b1, 1'b0, 20'h00012, "Pre-condition set_dirty");

        mark_dirty(8'h34);

        // Line 8'h34 should now have dirty=1, while tag and valid remain unchanged
        check_line(8'h34, 1'b1, 1'b1, 20'h00012, "Post set_dirty Check");

        // ---------------------------------------------------------------------
        // Stage 5: Addressing Isolation & Boundary Line Check
        // ---------------------------------------------------------------------
        $display("\n[STAGE 5] Testing addressing isolation across boundary entries...");
        write_entry(8'h00, 20'hAAAAA, 1'b1, 1'b0);
        write_entry(8'h01, 20'h55555, 1'b1, 1'b1);
        write_entry(8'h7F, 20'h12345, 1'b1, 1'b0);
        write_entry(8'hFE, 20'h6789A, 1'b1, 1'b1);
        write_entry(8'hFF, 20'hFFFFF, 1'b1, 1'b0);

        // Read back and assert boundary values
        check_line(8'h00, 1'b1, 1'b0, 20'hAAAAA, "Boundary Line 0");
        check_line(8'h01, 1'b1, 1'b1, 20'h55555, "Boundary Line 1");
        check_line(8'h7F, 1'b1, 1'b0, 20'h12345, "Boundary Line 127");
        check_line(8'hFE, 1'b1, 1'b1, 20'h6789A, "Boundary Line 254");
        check_line(8'hFF, 1'b1, 1'b0, 20'hFFFFF, "Boundary Line 255");

        // Ensure untouched intermediate line (e.g., line 8'h10) remains unmodified (V=0, D=0)
        check_line(8'h10, 1'b0, 1'b0, 20'h00000, "Untouched Line 16 Isolation");

        // ---------------------------------------------------------------------
        // Stage 6: Line Overwrite / Eviction Replacement Check
        // ---------------------------------------------------------------------
        $display("\n[STAGE 6] Testing eviction overwrite at line 8'h00...");
        write_entry(8'h00, 20'hBEEF1, 1'b1, 1'b0);
        check_line(8'h00, 1'b1, 1'b0, 20'hBEEF1, "Overwritten Line 0");

        // ---------------------------------------------------------------------
        // Stage 7: Re-assert Reset Verification
        // ---------------------------------------------------------------------
        $display("\n[STAGE 7] Testing synchronous re-reset functionality...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b1;
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b0;

        // Verify previously populated entries are properly invalidated
        check_line(8'h00, 1'b0, 1'b0, 20'h00000, "Re-reset Line 0");
        check_line(8'h34, 1'b0, 1'b0, 20'h00000, "Re-reset Line 52");
        check_line(8'h56, 1'b0, 1'b0, 20'h00000, "Re-reset Line 86");
        check_line(8'hFF, 1'b0, 1'b0, 20'h00000, "Re-reset Line 255");

        // ---------------------------------------------------------------------
        // Testbench Summary & PASS/FAIL
        // ---------------------------------------------------------------------
        $display("----------------------------------------------------------------");
        $display("Tests Executed: %0d assertions checked", test_count);
        if (error_count == 0) begin
            $display(">>> TEST STATUS: PASS <<<");
            $display("All tag_array operations verified successfully!");
        end else begin
            $display(">>> TEST STATUS: FAIL (%0d errors detected) <<<", error_count);
        end
        $display("----------------------------------------------------------------");

        $finish;
    end

endmodule
