`timescale 1ns / 1ps

module tb_ai_memory_1024;

    localparam ADDR_WIDTH = 10;
    localparam DATA_WIDTH = 16;

    reg clk;
    reg rst;

    reg                      req;
    reg                      we;
    reg  [ADDR_WIDTH-1:0]    addr;
    reg  [DATA_WIDTH-1:0]    data_in;

    wire [DATA_WIDTH-1:0]    data_out;
    wire                     data_valid;
    wire                     busy;

    wire cache_hit_event;
    wire cache_miss_event;

    wire [ADDR_WIDTH-1:0] predicted_addr;
    wire                  prediction_valid;

    wire signed [11:0] ml_score;
    wire               ml_decision;

    wire prefetch_start_event;
    wire prefetch_useful_event;
    wire prefetch_useless_event;

    wire [3:0] bootstrap_count;

    wire demand_ram_read_event;
    wire prefetch_ram_read_event;

    wire ml_accept_event;
    wire ml_reject_event;


    ai_memory_top #(
        .PREFETCH_MODE(0),

        .ADDR_WIDTH(10),
        .DATA_WIDTH(16),

        .CACHE_ENTRIES(16),

        .TRACKER_ENTRIES(8),
        .PREFETCH_LIFETIME(16),

        .PREFETCH_DISTANCE(2),

        .REGION_BITS(4),
        .FEATURE_WIDTH(8)
    ) dut (
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

        .bootstrap_count         (bootstrap_count),

        .demand_ram_read_event   (demand_ram_read_event),
        .prefetch_ram_read_event (prefetch_ram_read_event),

        .ml_accept_event         (ml_accept_event),
        .ml_reject_event         (ml_reject_event)
    );


    initial begin
        clk = 1'b0;

        forever #5
            clk = ~clk;
    end


    task write_mem;

        input [ADDR_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] d;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req     = 1'b1;
            we      = 1'b1;
            addr    = a;
            data_in = d;

            @(negedge clk);

            req = 1'b0;
            we  = 1'b0;

            while (busy)
                @(negedge clk);

        end

    endtask


    task read_check;

        input [ADDR_WIDTH-1:0] a;
        input [DATA_WIDTH-1:0] expected;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req  = 1'b1;
            we   = 1'b0;
            addr = a;

            @(negedge clk);

            req = 1'b0;

            wait(data_valid);

            #1;

            if (data_out === expected) begin

                $display(
                    "PASS addr=%0d expected=%h got=%h",
                    a,
                    expected,
                    data_out
                );

            end

            else begin

                $display(
                    "FAIL addr=%0d expected=%h got=%h",
                    a,
                    expected,
                    data_out
                );

            end

        end

    endtask


    initial begin

        rst     = 1'b1;
        req     = 1'b0;
        we      = 1'b0;
        addr    = 0;
        data_in = 0;

        repeat (3)
            @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        repeat (2)
            @(posedge clk);


        $display("");
        $display("========================================");
        $display("1024-WORD ADDRESS TEST");
        $display("========================================");


        // -----------------------------------------------
        // These addresses deliberately test boundaries
        // that would expose 6-bit truncation.
        // -----------------------------------------------

        write_mem(10'd0,    16'hA000);
        write_mem(10'd63,   16'hA063);

        write_mem(10'd64,   16'hA064);
        write_mem(10'd65,   16'hA065);

        write_mem(10'd127,  16'hA127);
        write_mem(10'd128,  16'hA128);

        write_mem(10'd500,  16'hA500);

        write_mem(10'd960,  16'hA960);

        write_mem(10'd1023, 16'hAFFF);


        $display("");
        $display("INTERNAL RAM CHECK");

        $display(
            "mem[0]    = %h",
            dut.ram_inst.mem[0]
        );

        $display(
            "mem[63]   = %h",
            dut.ram_inst.mem[63]
        );

        $display(
            "mem[64]   = %h",
            dut.ram_inst.mem[64]
        );

        $display(
            "mem[65]   = %h",
            dut.ram_inst.mem[65]
        );

        $display(
            "mem[127]  = %h",
            dut.ram_inst.mem[127]
        );

        $display(
            "mem[128]  = %h",
            dut.ram_inst.mem[128]
        );

        $display(
            "mem[500]  = %h",
            dut.ram_inst.mem[500]
        );

        $display(
            "mem[960]  = %h",
            dut.ram_inst.mem[960]
        );

        $display(
            "mem[1023] = %h",
            dut.ram_inst.mem[1023]
        );


        $display("");
        $display("WIDTH CHECK");

        $display(
            "TB addr             = %0d bits",
            $bits(addr)
        );

        $display(
            "DUT req_addr        = %0d bits",
            $bits(dut.req_addr)
        );

        $display(
            "DUT ram_addr        = %0d bits",
            $bits(dut.ram_addr)
        );

        $display(
            "RAM addr            = %0d bits",
            $bits(dut.ram_inst.addr)
        );

        $display(
            "DUT ADDR_WIDTH      = %0d",
            dut.ADDR_WIDTH
        );

        $display(
            "RAM ADDR_WIDTH      = %0d",
            dut.ram_inst.ADDR_WIDTH
        );

        $display(
            "RAM DEPTH           = %0d",
            dut.ram_inst.DEPTH
        );


        $display("");
        $display("CPU READ CHECK");


        read_check(
            10'd0,
            16'hA000
        );

        read_check(
            10'd63,
            16'hA063
        );

        read_check(
            10'd64,
            16'hA064
        );

        read_check(
            10'd65,
            16'hA065
        );

        read_check(
            10'd127,
            16'hA127
        );

        read_check(
            10'd128,
            16'hA128
        );

        read_check(
            10'd500,
            16'hA500
        );

        read_check(
            10'd960,
            16'hA960
        );

        read_check(
            10'd1023,
            16'hAFFF
        );


        $display("");
        $display("========================================");
        $display("1024-WORD ADDRESS TEST COMPLETE");
        $display("========================================");


        #20;
        $finish;

    end

endmodule