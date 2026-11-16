`timescale 1ns / 1ps

module tb_trace;
    localparam MEMORY_WORDS = 65536;
    localparam CACHE_LINES = 256;
    localparam MAX_WAIT_CYCLES = 250;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg req = 0;
    reg we = 0;
    reg [31:0] addr = 0, wdata = 0;
    wire [31:0] rdata;
    wire ready;
    cache_top dut (
        .clk(clk), .rst(rst), .req(req), .we(we), .addr(addr),
        .wdata(wdata), .ready(ready), .rdata(rdata),
        .hit(), .miss(), .state(), .dirty_evict()
    );

    // The oracle tracks CPU-visible words and cache metadata independently.
    reg [31:0] words [0:MEMORY_WORDS-1];
    reg [19:0] tags [0:CACHE_LINES-1];
    bit valid [0:CACHE_LINES-1];
    bit dirty [0:CACHE_LINES-1];
    longint unsigned reads = 0, writes = 0, hits = 0, misses = 0, write_backs = 0;
    time last_reset_edge;

    string trace_path;
    integer trace_file, line_number = 0, fields;
    reg [8*256-1:0] line;
    string opcode, address_token, data_token, extra_token;
    reg [31:0] address, data;

    // Accept up to eight hex digits with an optional 0x prefix.
    function automatic [31:0] parse_hex(input string token);
        integer first, i;
        reg [7:0] ch;
        reg [3:0] digit;
        reg [31:0] value;
        begin
            value = 0;
            first = 0;
            if (token.len() >= 2 && token[0] == "0" &&
                (token[1] == "x" || token[1] == "X"))
                first = 2;
            if (token.len() <= first || token.len() - first > 8)
                return 32'bx;

            for (i = first; i < token.len(); i = i + 1) begin
                ch = token[i];
                if (ch >= "0" && ch <= "9")
                    digit = ch - "0";
                else if (ch >= "a" && ch <= "f")
                    digit = ch - "a" + 10;
                else if (ch >= "A" && ch <= "F")
                    digit = ch - "A" + 10;
                else
                    return 32'bx;
                value = {value[27:0], digit};
            end
            return value;
        end
    endfunction

    task automatic transact(input bit is_write, input [31:0] address, data);
        reg [7:0] index;
        reg [15:0] word_index;
        integer wait_cycles;
        begin
            index = address[11:4];
            word_index = address[17:2];
            if (valid[index] && tags[index] == address[31:12]) begin
                hits = hits + 1;
            end else begin
                misses = misses + 1;
                if (valid[index] && dirty[index])
                    write_backs = write_backs + 1;
                tags[index] = address[31:12];
                valid[index] = 1;
                dirty[index] = 0;
            end

            // Drive before the capture edge. Sample the completion edge before
            // the controller's nonblocking updates move it back to IDLE.
            @(negedge clk);
            req = 1;
            we = is_write;
            addr = address;
            wdata = data;
            @(posedge clk);
            @(negedge clk);
            req = 0;
            @(posedge clk);
            wait_cycles = 1;
            while (ready !== 1'b1 && wait_cycles < MAX_WAIT_CYCLES) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (ready !== 1'b1)
                $fatal(1, "%s:%0d: timed out at address %08h", trace_path, line_number, address);

            if (is_write) begin
                words[word_index] = data;
                dirty[index] = 1;
                writes = writes + 1;
            end else begin
                if (rdata !== words[word_index])
                    $fatal(1, "%s:%0d: read %08h returned %08h, expected %08h",
                        trace_path, line_number, address, rdata, words[word_index]);
                reads = reads + 1;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path))
            trace_path = "traces/sequential.txt";
        trace_file = $fopen(trace_path, "r");
        if (trace_file == 0)
            $fatal(1, "Cannot open trace %s", trace_path);

        if ($test$plusargs("DUMP")) begin
            $dumpfile("build/trace.vcd");
            $dumpvars(0, tb_trace);
        end

        $readmemh("traces/mem_init.hex", words);
        repeat (2) @(posedge clk);
        last_reset_edge = $time;
        @(negedge clk);
        rst = 0;

        while ($fgets(line, trace_file) != 0) begin
            line_number = line_number + 1;
            if (line[8*255 +: 8] != 0)
                $fatal(1, "%s:%0d: trace line is too long", trace_path, line_number);
            fields = $sscanf(line, "%s %s %s %s", opcode, address_token, data_token, extra_token);
            if (fields > 0) begin
                if (!((opcode == "R" && fields == 2) || (opcode == "W" && fields == 3)))
                    $fatal(1, "%s:%0d: expected R <hex_addr> or W <hex_addr> <hex_data>",
                        trace_path, line_number);
                address = parse_hex(address_token);
                if ($isunknown(address) || address[1:0] != 0 ||
                    address >= MEMORY_WORDS * 4)
                    $fatal(1, "%s:%0d: expected an aligned address in the backing memory",
                        trace_path, line_number);
                data = opcode == "W" ? parse_hex(data_token) : 0;
                if ($isunknown(data))
                    $fatal(1, "%s:%0d: invalid 32-bit write data", trace_path, line_number);
                transact(opcode == "W", address, data);
            end
        end
        $fclose(trace_file);
        if (reads + writes == 0)
            $fatal(1, "Trace %s contains no accesses", trace_path);

        // Allow the final completion edge to update the RTL registers.
        @(negedge clk);
        $display("Trace: %s", trace_path);
        $display("Accesses:     %0d", dut.perf.accesses);
        $display("Hits:         %0d", dut.perf.hits);
        $display("Misses:       %0d", dut.perf.misses);
        $display("Write-backs:  %0d", dut.perf.write_backs);
        $display("Total cycles: %0d", dut.perf.total_cycles);
        $display("Reads:        %0d", dut.perf.reads);
        $display("Writes:       %0d", dut.perf.writes);
        if (dut.perf.accesses !== (reads + writes) ||
            dut.perf.hits !== hits || dut.perf.misses !== misses ||
            dut.perf.write_backs !== write_backs ||
            dut.perf.reads !== reads || dut.perf.writes !== writes ||
            dut.perf.total_cycles !== (($time - last_reset_edge) / 10))
            $fatal(1, "Trace counters disagree with the reference model or elapsed clock cycles");

        $display("Hit rate:     %0.2f%%", 100.0 * hits / dut.perf.accesses);
        $display("Miss rate:    %0.2f%%", 100.0 * misses / dut.perf.accesses);
        $display("PASS: trace data and counters match the reference model");
        $finish;
    end
endmodule
