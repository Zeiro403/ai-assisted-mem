`timescale 1ns / 1ps

module tb_cached_memory;

    reg         clk;
    reg         rst;

    reg         req;
    reg         we;
    reg  [5:0]  addr;
    reg  [15:0] data_in;

    wire [15:0] data_out;
    wire        data_valid;
    wire        busy;

    wire        cache_hit_event;
    wire        cache_miss_event;


    integer hit_count;
    integer miss_count;


    cached_memory dut (
        .clk              (clk),
        .rst              (rst),

        .req              (req),
        .we               (we),
        .addr             (addr),
        .data_in          (data_in),

        .data_out         (data_out),
        .data_valid       (data_valid),
        .busy             (busy),

        .cache_hit_event  (cache_hit_event),
        .cache_miss_event (cache_miss_event)
    );


    // 100 MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    // ----------------------------------------------------
    // PERFORMANCE COUNTERS
    // ----------------------------------------------------

    always @(posedge clk) begin

        if (cache_hit_event)
            hit_count = hit_count + 1;

        if (cache_miss_event)
            miss_count = miss_count + 1;

    end


    // ----------------------------------------------------
    // WRITE TASK
    // ----------------------------------------------------

    task write_mem;

        input [5:0]  write_addr;
        input [15:0] write_data;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req     = 1;
            we      = 1;
            addr    = write_addr;
            data_in = write_data;

            @(negedge clk);

            req = 0;
            we  = 0;

            // Wait until controller has returned idle
            while (busy)
                @(negedge clk);

        end

    endtask


    // ----------------------------------------------------
    // READ TASK
    // ----------------------------------------------------

    task read_mem;

        input [5:0] read_addr;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req  = 1;
            we   = 0;
            addr = read_addr;

            @(negedge clk);

            req = 0;

            wait(data_valid);

            #1;

            $display(
                "READ address=%0d data=%h time=%0t",
                read_addr,
                data_out,
                $time
            );

        end

    endtask


    initial begin

        req     = 0;
        we      = 0;
        addr    = 0;
        data_in = 0;

        hit_count  = 0;
        miss_count = 0;

        rst = 1;

        #20;
        rst = 0;


        // ================================================
        // INITIALIZE SOME RAM LOCATIONS
        // ================================================

        write_mem(6'd10, 16'hAAAA);
        write_mem(6'd20, 16'hBBBB);
        write_mem(6'd30, 16'hCCCC);


        $display("");
        $display("================================");
        $display("FIRST READS -- EXPECT MISSES");
        $display("================================");


        // First access: not cached
        read_mem(6'd10);

        // First access: not cached
        read_mem(6'd20);


        $display("");
        $display("================================");
        $display("REPEATED READS -- EXPECT HITS");
        $display("================================");


        // Should now be cached
        read_mem(6'd10);

        // Should now be cached
        read_mem(6'd20);


        $display("");
        $display("================================");
        $display("WRITE-THROUGH TEST");
        $display("================================");


        // Address 10 is already cached.
        // Update both RAM and cache.
        write_mem(6'd10, 16'hDEAD);

        read_mem(6'd10);
        
        @(posedge clk);
        #1;


        $display("");
        $display("================================");
        $display("RESULTS");
        $display("================================");

        $display("Cache hits   = %0d", hit_count);
        $display("Cache misses = %0d", miss_count);

        $display("================================");


        #30;
        $finish;

    end

endmodule