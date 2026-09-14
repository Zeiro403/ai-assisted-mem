`timescale 1ns / 1ps

module tb_prefetch_engine;

    reg clk;
    reg rst;

    reg       start;
    reg [5:0] candidate_addr;

    wire      busy;

    wire      ram_req;
    wire [5:0] ram_addr;

    reg [15:0] ram_data;
    reg        ram_data_valid;

    wire       fill_en;
    wire [5:0] fill_addr;
    wire [15:0] fill_data;

    wire       prefetch_complete;


    prefetch_engine dut (
        .clk               (clk),
        .rst               (rst),

        .start             (start),
        .candidate_addr    (candidate_addr),

        .busy              (busy),

        .ram_req           (ram_req),
        .ram_addr          (ram_addr),

        .ram_data          (ram_data),
        .ram_data_valid    (ram_data_valid),

        .fill_en           (fill_en),
        .fill_addr         (fill_addr),
        .fill_data         (fill_data),

        .prefetch_complete (prefetch_complete)
    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    initial begin

        rst            = 1;
        start          = 0;
        candidate_addr = 0;

        ram_data       = 0;
        ram_data_valid = 0;

        #20;
        rst = 0;


        // ================================================
        // START PREFETCH OF ADDRESS 14
        // ================================================

        @(negedge clk);

        candidate_addr = 6'd14;
        start          = 1;

        @(negedge clk);

        start = 0;


        // Engine should have requested address 14
        #1;

        if (busy && ram_addr == 6'd14)
            $display("PASS: Prefetch request accepted");
        else
            $display("FAIL: Prefetch request incorrect");


        // ================================================
        // SIMULATE RAM LATENCY
        // ================================================

        repeat (2)
            @(negedge clk);


        // Return data from RAM
        ram_data       = 16'hCAFE;
        ram_data_valid = 1;

        @(negedge clk);

        ram_data_valid = 0;


        // Cache fill should now have occurred
        #1;

        if (
            fill_addr == 6'd14 &&
            fill_data == 16'hCAFE
        )
            $display("PASS: Correct prefetch data received");
        else
            $display("FAIL: Prefetch data incorrect");


        // Wait for completion pulse
        wait(prefetch_complete);

        #1;

        if (!busy)
            $display("PASS: Prefetch completed");
        else
            $display("FAIL: Engine remained busy");


        #20;

        $display("");
        $display("PREFETCH ENGINE TEST COMPLETE");

        $finish;

    end

endmodule