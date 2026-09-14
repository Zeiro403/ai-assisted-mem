`timescale 1ns / 1ps

module tb_memory_64x16;

    reg         clk;
    reg         rst;
    reg         en;
    reg         we;
    reg  [5:0]  addr;
    reg  [15:0] data_in;

    wire [15:0] data_out;
    wire        data_valid;


    memory_64x16 dut (
        .clk        (clk),
        .rst        (rst),
        .en         (en),
        .we         (we),
        .addr       (addr),
        .data_in    (data_in),
        .data_out   (data_out),
        .data_valid (data_valid)
    );


    // 100 MHz clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    initial begin

        // Initial values
        rst     = 1;
        en      = 0;
        we      = 0;
        addr    = 0;
        data_in = 0;

        // Reset
        #20;
        rst = 0;

        // -------------------------------------------------
        // WRITE TEST
        // -------------------------------------------------

        @(negedge clk);
        en      = 1;
        we      = 1;
        addr    = 6'd10;
        data_in = 16'hABCD;

        @(negedge clk);
        en      = 0;
        we      = 0;


        // -------------------------------------------------
        // READ TEST
        // -------------------------------------------------

        @(negedge clk);
        en   = 1;
        we   = 0;
        addr = 6'd10;

        @(negedge clk);
        en = 0;


        // -------------------------------------------------
        // CHECK RESULT
        // -------------------------------------------------

        #1;

        if (data_valid && data_out == 16'hABCD)
            $display("PASS: Address 10 contains ABCD");
        else
            $display(
                "FAIL: Expected ABCD, received %h",
                data_out
            );


        // -------------------------------------------------
        // SECOND WRITE
        // -------------------------------------------------

        @(negedge clk);
        en      = 1;
        we      = 1;
        addr    = 6'd25;
        data_in = 16'h1234;

        @(negedge clk);
        en      = 0;
        we      = 0;


        // -------------------------------------------------
        // SECOND READ
        // -------------------------------------------------

        @(negedge clk);
        en   = 1;
        we   = 0;
        addr = 6'd25;

        @(negedge clk);
        en = 0;

        #1;

        if (data_valid && data_out == 16'h1234)
            $display("PASS: Address 25 contains 1234");
        else
            $display(
                "FAIL: Expected 1234, received %h",
                data_out
            );


        // -------------------------------------------------
        // VERIFY FIRST LOCATION WAS NOT CORRUPTED
        // -------------------------------------------------

        @(negedge clk);
        en   = 1;
        we   = 0;
        addr = 6'd10;

        @(negedge clk);
        en = 0;

        #1;

        if (data_valid && data_out == 16'hABCD)
            $display("PASS: Address 10 still contains ABCD");
        else
            $display(
                "FAIL: Address 10 corrupted. Received %h",
                data_out
            );


        #20;

        $display("--------------------------------");
        $display("RAM TEST COMPLETE");
        $display("--------------------------------");

        $finish;

    end

endmodule