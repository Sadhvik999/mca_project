// =============================================================================
// File Name   : tb_data_array.v
// Module Name : tb_data_array
// Project     : Modern Computer Architecture - Direct-Mapped Cache Controller
// Author      : Varun Udata (M2)
// Email       : varunudata@gmail.com
// Standard    : IEEE 1364-2001 / IEEE 1800-2012 (Verilog HDL)
// Description : Self-checking testbench for data_array (256 x 128-bit).
//               Covers reset clearing, single-word write & read, 128-bit block
//               fill & word-offset reads, partial word overwrites without
//               corrupting adjacent words, boundary line isolation, and
//               block-vs-word write priority. Reports PASS/FAIL.
// =============================================================================

`timescale 1ns / 1ps

module tb_data_array;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam INDEX_WIDTH  = 8;
    localparam OFFSET_WIDTH = 2;
    localparam WORD_WIDTH   = 32;
    localparam BLOCK_BITS   = 128;
    localparam NUM_LINES    = 256;
    localparam CLK_PERIOD   = 10;

    // -------------------------------------------------------------------------
    // Testbench Signals
    // -------------------------------------------------------------------------
    reg                     clk;
    reg                     rst;
    reg  [INDEX_WIDTH-1:0]  index;
    reg  [OFFSET_WIDTH-1:0] word_offset;
    reg  [WORD_WIDTH-1:0]   word_in;
    reg  [BLOCK_BITS-1:0]   block_in;
    reg                     write_word_en;
    reg                     write_block_en;

    wire [WORD_WIDTH-1:0]   word_out;
    wire [BLOCK_BITS-1:0]   block_out;

    integer error_count = 0;
    integer test_count  = 0;
    integer idx;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    data_array #(
        .INDEX_WIDTH(INDEX_WIDTH),
        .OFFSET_WIDTH(OFFSET_WIDTH),
        .WORD_WIDTH(WORD_WIDTH),
        .BLOCK_BITS(BLOCK_BITS),
        .NUM_LINES(NUM_LINES)
    ) dut (
        .clk(clk),
        .rst(rst),
        .index(index),
        .word_offset(word_offset),
        .word_in(word_in),
        .block_in(block_in),
        .write_word_en(write_word_en),
        .write_block_en(write_block_en),
        .word_out(word_out),
        .block_out(block_out)
    );

    // -------------------------------------------------------------------------
    // 100 MHz Clock Generator
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Helper Tasks: Synchronous Writes & Combinational Checks
    // -------------------------------------------------------------------------
    task write_word(
        input [INDEX_WIDTH-1:0]  wr_index,
        input [OFFSET_WIDTH-1:0] wr_offset,
        input [WORD_WIDTH-1:0]   wr_data
    );
        begin
            @(posedge clk);
            #(CLK_PERIOD / 4);
            index          = wr_index;
            word_offset    = wr_offset;
            word_in        = wr_data;
            write_word_en  = 1'b1;
            write_block_en = 1'b0;
            @(posedge clk);
            #(CLK_PERIOD / 4);
            write_word_en  = 1'b0;
        end
    endtask

    task write_block(
        input [INDEX_WIDTH-1:0] wr_index,
        input [BLOCK_BITS-1:0]  wr_block
    );
        begin
            @(posedge clk);
            #(CLK_PERIOD / 4);
            index          = wr_index;
            block_in       = wr_block;
            write_block_en = 1'b1;
            write_word_en  = 1'b0;
            @(posedge clk);
            #(CLK_PERIOD / 4);
            write_block_en = 1'b0;
        end
    endtask

    task check_word(
        input [INDEX_WIDTH-1:0]  target_index,
        input [OFFSET_WIDTH-1:0] target_offset,
        input [WORD_WIDTH-1:0]   exp_word,
        input [8*40-1:0]         label
    );
        begin
            index       = target_index;
            word_offset = target_offset;
            #1;
            test_count = test_count + 1;
            if (word_out !== exp_word) begin
                $display("[ERROR] %0s @ line 0x%02h word %0d | Expected: 0x%08h | Actual: 0x%08h",
                         label, target_index, target_offset, exp_word, word_out);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_block(
        input [INDEX_WIDTH-1:0] target_index,
        input [BLOCK_BITS-1:0]  exp_block,
        input [8*40-1:0]        label
    );
        begin
            index = target_index;
            #1;
            test_count = test_count + 1;
            if (block_out !== exp_block) begin
                $display("[ERROR] %0s @ line 0x%02h | Expected: 0x%032h | Actual: 0x%032h",
                         label, target_index, exp_block, block_out);
                error_count = error_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification Sequence
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb/data_array.vcd");
        $dumpvars(0, tb_data_array);

        // Initialize inputs under reset
        rst            = 1'b1;
        index          = 8'h00;
        word_offset    = 2'b00;
        word_in        = 32'h0000_0000;
        block_in       = 128'h0;
        write_word_en  = 1'b0;
        write_block_en = 1'b0;

        $display("----------------------------------------------------------------");
        $display("Starting Self-Checking Testbench: data_array (256 x 128-bit)");
        $display("----------------------------------------------------------------");

        // Stage 1: Synchronous Reset Check across all 256 lines
        $display("[STAGE 1] Checking synchronous reset across all 256 lines...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b0;

        for (idx = 0; idx < NUM_LINES; idx = idx + 1) begin
            check_block(idx[INDEX_WIDTH-1:0], 128'h0, "Reset Clear");
        end
        if (error_count == 0)
            $display("[STAGE 1] PASS: All 256 lines reset to zero.");

        // Stage 2: Single-Word Write and Word Read across all 4 offsets
        $display("[STAGE 2] Testing single-word write & word read on line 8'h12...");
        write_word(8'h12, 2'b00, 32'h1111_AAAA);
        write_word(8'h12, 2'b01, 32'h2222_BBBB);
        write_word(8'h12, 2'b10, 32'h3333_CCCC);
        write_word(8'h12, 2'b11, 32'h4444_DDDD);

        check_word(8'h12, 2'b00, 32'h1111_AAAA, "Word 0 Read");
        check_word(8'h12, 2'b01, 32'h2222_BBBB, "Word 1 Read");
        check_word(8'h12, 2'b10, 32'h3333_CCCC, "Word 2 Read");
        check_word(8'h12, 2'b11, 32'h4444_DDDD, "Word 3 Read");
        check_block(8'h12, 128'h4444_DDDD_3333_CCCC_2222_BBBB_1111_AAAA, "Assembled Block");

        // Stage 3: Full 128-bit Block Fill then Word Reads
        $display("[STAGE 3] Testing 128-bit block fill and word-offset reads on line 8'h34...");
        write_block(8'h34, 128'hDEAD_BEEF_CAFE_BABE_8765_4321_0123_4567);

        check_block(8'h34, 128'hDEAD_BEEF_CAFE_BABE_8765_4321_0123_4567, "Block Fill Readback");
        check_word(8'h34, 2'b00, 32'h0123_4567, "Fill Word 0");
        check_word(8'h34, 2'b01, 32'h8765_4321, "Fill Word 1");
        check_word(8'h34, 2'b10, 32'hCAFE_BABE, "Fill Word 2");
        check_word(8'h34, 2'b11, 32'hDEAD_BEEF, "Fill Word 3");

        // Stage 4: Partial Word Write Without Corrupting Other Three Words
        $display("[STAGE 4] Testing word write isolation (no corruption of sibling words)...");
        // Overwrite Word 2 only -> Words 0, 1, 3 must stay intact
        write_word(8'h34, 2'b10, 32'hA5A5_5A5A);
        check_word(8'h34, 2'b00, 32'h0123_4567, "Word 0 Uncorrupted");
        check_word(8'h34, 2'b01, 32'h8765_4321, "Word 1 Uncorrupted");
        check_word(8'h34, 2'b10, 32'hA5A5_5A5A, "Word 2 Updated");
        check_word(8'h34, 2'b11, 32'hDEAD_BEEF, "Word 3 Uncorrupted");

        // Overwrite Word 0 only -> Words 1, 2, 3 must stay intact
        write_word(8'h34, 2'b00, 32'hFACE_B00C);
        check_block(8'h34, 128'hDEAD_BEEF_A5A5_5A5A_8765_4321_FACE_B00C, "Block After Word 0 Update");

        // Overwrite Word 1 only -> Words 0, 2, 3 must stay intact
        write_word(8'h34, 2'b01, 32'h1020_3040);
        check_block(8'h34, 128'hDEAD_BEEF_A5A5_5A5A_1020_3040_FACE_B00C, "Block After Word 1 Update");

        // Overwrite Word 3 only -> Words 0, 1, 2 must stay intact
        write_word(8'h34, 2'b11, 32'h9988_7766);
        check_block(8'h34, 128'h9988_7766_A5A5_5A5A_1020_3040_FACE_B00C, "Block After Word 3 Update");

        // Stage 5: Boundary Line Isolation (0x00, 0x01, 0x7F, 0xFE, 0xFF)
        $display("[STAGE 5] Testing boundary line addressing and isolation...");
        write_block(8'h00, 128'h0000_0000_0000_0000_0000_0000_AAAA_0001);
        write_block(8'h01, 128'h0000_0000_0000_0000_0000_0000_BBBB_0002);
        write_block(8'h7F, 128'h1122_3344_5566_7788_99AA_BBCC_DDEE_FF00);
        write_block(8'hFE, 128'hFFFF_EEEE_DDDD_CCCC_BBBB_AAAA_9999_8888);
        write_block(8'hFF, 128'hFEDC_BA98_7654_3210_0123_4567_89AB_CDEF);

        check_block(8'h00, 128'h0000_0000_0000_0000_0000_0000_AAAA_0001, "Boundary Line 0x00");
        check_block(8'h01, 128'h0000_0000_0000_0000_0000_0000_BBBB_0002, "Boundary Line 0x01");
        check_block(8'h7F, 128'h1122_3344_5566_7788_99AA_BBCC_DDEE_FF00, "Boundary Line 0x7F");
        check_block(8'hFE, 128'hFFFF_EEEE_DDDD_CCCC_BBBB_AAAA_9999_8888, "Boundary Line 0xFE");
        check_block(8'hFF, 128'hFEDC_BA98_7654_3210_0123_4567_89AB_CDEF, "Boundary Line 0xFF");
        check_block(8'h10, 128'h0, "Untouched Line 0x10");

        // Stage 6: Write Priority Check (write_block_en overrides write_word_en)
        $display("[STAGE 6] Testing simultaneous write_block_en and write_word_en priority...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        index          = 8'h55;
        word_offset    = 2'b01;
        word_in        = 32'hBAD0_BAD0;
        block_in       = 128'h1111_2222_3333_4444_5555_6666_7777_8888;
        write_word_en  = 1'b1;
        write_block_en = 1'b1;
        @(posedge clk);
        #(CLK_PERIOD / 4);
        write_word_en  = 1'b0;
        write_block_en = 1'b0;
        check_block(8'h55, 128'h1111_2222_3333_4444_5555_6666_7777_8888, "Block Write Priority");

        // Stage 7: Re-Reset Verification
        $display("[STAGE 7] Testing synchronous re-reset...");
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b1;
        @(posedge clk);
        #(CLK_PERIOD / 4);
        rst = 1'b0;

        check_block(8'h12, 128'h0, "Re-reset Line 0x12");
        check_block(8'h34, 128'h0, "Re-reset Line 0x34");
        check_block(8'hFF, 128'h0, "Re-reset Line 0xFF");

        // Final Summary
        $display("----------------------------------------------------------------");
        $display("Tests Executed: %0d assertions checked", test_count);
        if (error_count == 0) begin
            $display(">>> TEST STATUS: PASS <<<");
            $display("All data_array operations verified successfully!");
        end else begin
            $display(">>> TEST STATUS: FAIL (%0d errors detected) <<<", error_count);
        end
        $display("----------------------------------------------------------------");

        $finish;
    end

endmodule
