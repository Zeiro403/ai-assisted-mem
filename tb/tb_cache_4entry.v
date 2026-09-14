`timescale 1ns / 1ps

module tb_cache_4entry;

    reg         clk;
    reg         rst;

    reg         lookup_en;
    reg  [5:0]  lookup_addr;

    wire        hit;
    wire [15:0] lookup_data;

    reg         fill_en;
    reg  [5:0]  fill_addr;
    reg  [15:0] fill_data;

    reg         update_en;
    reg  [5:0]  update_addr;
    reg  [15:0] update_data;


    cache_4entry dut (
        .clk         (clk),
        .rst         (rst),

        .lookup_en   (lookup_en),
        .lookup_addr (lookup_addr),

        .hit         (hit),
        .lookup_data (lookup_data),

        .fill_en     (fill_en),
        .fill_addr   (fill_addr),
        .fill_data   (fill_data),

        .update_en   (update_en),
        .update_addr (update_addr),
        .update_data (update_data)
    );


    // 100 MHz clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    initial begin

        rst         = 1;

        lookup_en   = 0;
        lookup_addr = 0;

        fill_en     = 0;
        fill_addr   = 0;
        fill_data   = 0;

        update_en   = 0;
        update_addr = 0;
        update_data = 0;


        // ------------------------------------------------
        // RESET
        // ------------------------------------------------

        #20;
        rst = 0;


        // ------------------------------------------------
        // TEST 1: LOOKUP EMPTY CACHE
        // ------------------------------------------------

        @(negedge clk);

        lookup_en   = 1;
        lookup_addr = 6'd10;

        #1;

        if (!hit)
            $display("PASS: Empty cache correctly reports MISS");
        else
            $display("FAIL: Empty cache incorrectly reports HIT");

        lookup_en = 0;


        // ------------------------------------------------
        // TEST 2: FILL ADDRESS 10
        // ------------------------------------------------

        @(negedge clk);

        fill_en   = 1;
        fill_addr = 6'd10;
        fill_data = 16'hABCD;

        @(negedge clk);

        fill_en = 0;


        // ------------------------------------------------
        // TEST 3: LOOKUP ADDRESS 10
        // ------------------------------------------------

        lookup_en   = 1;
        lookup_addr = 6'd10;

        #1;

        if (hit && lookup_data == 16'hABCD)
            $display("PASS: Address 10 cache HIT = ABCD");
        else
            $display(
                "FAIL: Address 10 lookup. hit=%b data=%h",
                hit,
                lookup_data
            );

        lookup_en = 0;


        // ------------------------------------------------
        // TEST 4: FILL MORE ENTRIES
        // ------------------------------------------------

        @(negedge clk);

        fill_en   = 1;
        fill_addr = 6'd20;
        fill_data = 16'h1111;

        @(negedge clk);

        fill_addr = 6'd30;
        fill_data = 16'h2222;

        @(negedge clk);

        fill_addr = 6'd40;
        fill_data = 16'h3333;

        @(negedge clk);

        fill_en = 0;


        // ------------------------------------------------
        // TEST 5: CHECK ADDRESS 30
        // ------------------------------------------------

        lookup_en   = 1;
        lookup_addr = 6'd30;

        #1;

        if (hit && lookup_data == 16'h2222)
            $display("PASS: Address 30 cache HIT = 2222");
        else
            $display("FAIL: Address 30 lookup");

        lookup_en = 0;


        // ------------------------------------------------
        // TEST 6: UPDATE ADDRESS 10
        // ------------------------------------------------

        @(negedge clk);

        update_en   = 1;
        update_addr = 6'd10;
        update_data = 16'hDEAD;

        @(negedge clk);

        update_en = 0;


        // ------------------------------------------------
        // TEST 7: VERIFY UPDATE
        // ------------------------------------------------

        lookup_en   = 1;
        lookup_addr = 6'd10;

        #1;

        if (hit && lookup_data == 16'hDEAD)
            $display("PASS: Cached address 10 updated to DEAD");
        else
            $display("FAIL: Cache update failed");

        lookup_en = 0;


        // ------------------------------------------------
        // TEST 8: FORCE REPLACEMENT
        // ------------------------------------------------

        @(negedge clk);

        fill_en   = 1;
        fill_addr = 6'd50;
        fill_data = 16'h5555;

        @(negedge clk);

        fill_en = 0;


        // ------------------------------------------------
        // ADDRESS 10 SHOULD NOW HAVE BEEN REPLACED
        // ------------------------------------------------

        lookup_en   = 1;
        lookup_addr = 6'd10;

        #1;

        if (!hit)
            $display("PASS: Round-robin replacement works");
        else
            $display("FAIL: Expected address 10 to be replaced");

        lookup_en = 0;


        // ------------------------------------------------
        // NEW ADDRESS MUST EXIST
        // ------------------------------------------------

        lookup_en   = 1;
        lookup_addr = 6'd50;

        #1;

        if (hit && lookup_data == 16'h5555)
            $display("PASS: Replacement entry contains address 50");
        else
            $display("FAIL: Replacement entry incorrect");

        lookup_en = 0;


        #20;

        $display("--------------------------------");
        $display("CACHE TEST COMPLETE");
        $display("--------------------------------");

        $finish;

    end

endmodule