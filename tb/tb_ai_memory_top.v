`timescale 1ns / 1ps

module tb_ai_memory_top;

    reg clk;
    reg rst;

    reg         req;
    reg         we;
    reg  [5:0]  addr;
    reg  [15:0] data_in;

    wire [15:0] data_out;
    wire        data_valid;
    wire        busy;

    wire cache_hit_event;
    wire cache_miss_event;

    wire [5:0] predicted_addr;
    wire       prediction_valid;

    wire signed [11:0] ml_score;
    wire               ml_decision;

    wire prefetch_start_event;
    wire prefetch_useful_event;
    wire prefetch_useless_event;

    wire [3:0] bootstrap_count;

    integer hits;
    integer misses;
    integer prefetches;
    integer useful;
    integer useless;


    ai_memory_top dut (
        .clk                     (clk),
        .rst                     (rst),

        .req                     (req),
        .we                      (we),
        .addr                    (addr),
        .data_in                 (data_in),

        .data_out                (data_out),
        .data_valid              (data_valid),
        .busy                    (busy),

        .cache_hit_event         (cache_hit_event),
        .cache_miss_event        (cache_miss_event),

        .predicted_addr          (predicted_addr),
        .prediction_valid        (prediction_valid),

        .ml_score                (ml_score),
        .ml_decision             (ml_decision),

        .prefetch_start_event    (prefetch_start_event),

        .prefetch_useful_event   (prefetch_useful_event),
        .prefetch_useless_event  (prefetch_useless_event),

        .bootstrap_count         (bootstrap_count)
    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    always @(posedge clk) begin

        if (cache_hit_event)
            hits = hits + 1;

        if (cache_miss_event)
            misses = misses + 1;

        if (prefetch_start_event)
            prefetches = prefetches + 1;

        if (prefetch_useful_event)
            useful = useful + 1;

        if (prefetch_useless_event)
            useless = useless + 1;

    end


    task write_mem;

        input [5:0]  a;
        input [15:0] d;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req     = 1;
            we      = 1;
            addr    = a;
            data_in = d;

            @(negedge clk);

            req = 0;
            we  = 0;

            while (busy)
                @(negedge clk);

        end

    endtask


    task read_mem;

        input [5:0] a;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req  = 1;
            we   = 0;
            addr = a;

            @(negedge clk);

            req = 0;

            wait(data_valid);

            #1;

            $display(
                "READ addr=%0d data=%h score=%0d ML=%b bootstrap=%0d time=%0t",
                a,
                data_out,
                $signed(ml_score),
                ml_decision,
                bootstrap_count,
                $time
            );

        end

    endtask


    integer i;


    initial begin

        rst     = 1;
        req     = 0;
        we      = 0;
        addr    = 0;
        data_in = 0;

        hits       = 0;
        misses     = 0;
        prefetches = 0;
        useful     = 0;
        useless    = 0;

        #20;
        rst = 0;


        // ================================================
        // INITIALIZE RAM
        //
        // RAM[address] = 0x1000 + address
        // ================================================

        for (i = 0; i < 32; i = i + 1) begin

            write_mem(
                i,
                16'h1000 + i
            );

        end


        $display("");
        $display("========================================");
        $display("SEQUENTIAL AI MEMORY TEST");
        $display("========================================");


        // ================================================
        // SEQUENTIAL READ STREAM
        // ================================================

        for (i = 0; i < 16; i = i + 1) begin

            read_mem(i);

        end


        // Give final tracker events time to propagate
        repeat (10)
            @(posedge clk);

        #1;


        $display("");
        $display("========================================");
        $display("RESULTS");
        $display("========================================");

        $display("Cache hits       = %0d", hits);
        $display("Cache misses     = %0d", misses);
        $display("Prefetch starts  = %0d", prefetches);
        $display("Useful prefetch  = %0d", useful);
        $display("Useless prefetch = %0d", useless);
        $display("Bootstrap count  = %0d", bootstrap_count);

        $display("========================================");


        #20;
        $finish;

    end

endmodule