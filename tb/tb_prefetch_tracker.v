`timescale 1ns / 1ps

module tb_prefetch_tracker;

    reg clk;
    reg rst;

    reg       prefetch_issued;
    reg [5:0] prefetch_addr;
    reg [7:0] prefetch_features;

    reg       demand_access_valid;
    reg [5:0] demand_addr;

    wire       tracker_busy;

    wire       train_valid;
    wire [7:0] train_features;
    wire       train_target;

    wire       prefetch_useful_event;
    wire       prefetch_useless_event;


    prefetch_tracker dut (
        .clk                     (clk),
        .rst                     (rst),

        .prefetch_issued         (prefetch_issued),
        .prefetch_addr           (prefetch_addr),
        .prefetch_features       (prefetch_features),

        .demand_access_valid     (demand_access_valid),
        .demand_addr             (demand_addr),

        .tracker_busy            (tracker_busy),

        .train_valid             (train_valid),
        .train_features          (train_features),
        .train_target            (train_target),

        .prefetch_useful_event   (prefetch_useful_event),
        .prefetch_useless_event  (prefetch_useless_event)
    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    // ----------------------------------------------------
    // ISSUE PREFETCH
    // ----------------------------------------------------

    task issue_prefetch;

        input [5:0] addr;
        input [7:0] f;

        begin

            @(negedge clk);

            prefetch_addr     = addr;
            prefetch_features = f;
            prefetch_issued   = 1;

            @(negedge clk);

            prefetch_issued = 0;

        end

    endtask


    // ----------------------------------------------------
    // SEND CPU DEMAND ACCESS
    // ----------------------------------------------------

    task demand_access;

        input [5:0] addr;

        begin

            @(negedge clk);

            demand_addr         = addr;
            demand_access_valid = 1;

            @(negedge clk);

            demand_access_valid = 0;

        end

    endtask


    initial begin

        rst = 1;

        prefetch_issued   = 0;
        prefetch_addr     = 0;
        prefetch_features = 0;

        demand_access_valid = 0;
        demand_addr         = 0;

        #20;
        rst = 0;


        // ================================================
        // TEST 1: USEFUL PREFETCH
        // ================================================

        $display("");
        $display("================================");
        $display("TEST 1: USEFUL PREFETCH");
        $display("================================");

        issue_prefetch(
            6'd20,
            8'b10110111
        );

        demand_access(6'd5);
        demand_access(6'd8);

        // CPU eventually requests predicted address
        demand_access(6'd20);

        #1;

        if (
            train_valid &&
            train_target == 1'b1 &&
            train_features == 8'b10110111
        )
            $display("PASS: Useful prefetch correctly labelled");
        else
            $display("FAIL: Useful prefetch feedback incorrect");


        // ================================================
        // TEST 2: USELESS PREFETCH
        // ================================================

        $display("");
        $display("================================");
        $display("TEST 2: USELESS PREFETCH");
        $display("================================");

        issue_prefetch(
            6'd40,
            8'b00101100
        );

        demand_access(6'd1);
        demand_access(6'd2);
        demand_access(6'd3);
        demand_access(6'd4);
        demand_access(6'd5);
        demand_access(6'd6);
        demand_access(6'd7);

        // Eighth unrelated demand access
        demand_access(6'd8);

        #1;

        if (
            train_valid &&
            train_target == 1'b0 &&
            train_features == 8'b00101100
        )
            $display("PASS: Useless prefetch correctly labelled");
        else
            $display("FAIL: Useless prefetch feedback incorrect");


        // ================================================
        // TEST 3: ADDRESS JUST BEFORE TIMEOUT
        // ================================================

        $display("");
        $display("================================");
        $display("TEST 3: LATE USEFUL PREFETCH");
        $display("================================");

        issue_prefetch(
            6'd55,
            8'b11100011
        );

        demand_access(6'd10);
        demand_access(6'd11);
        demand_access(6'd12);
        demand_access(6'd13);
        demand_access(6'd14);
        demand_access(6'd15);
        demand_access(6'd16);

        // Eighth demand access is the target itself.
        demand_access(6'd55);

        #1;

        if (
            train_valid &&
            train_target == 1'b1 &&
            train_features == 8'b11100011
        )
            $display("PASS: Eighth-access target counted as useful");
        else
            $display("FAIL: Late useful prefetch incorrectly labelled");


        $display("");
        $display("================================");
        $display("TEST 4: MULTIPLE OUTSTANDING");
        $display("================================");
        
        issue_prefetch(
            6'd20,
            8'b11110000
        );
        
        issue_prefetch(
            6'd22,
            8'b11001100
        );
        
        issue_prefetch(
            6'd24,
            8'b10101010
        );
        
        
        // Resolve middle prediction first
        demand_access(6'd22);
        
        #1;
        
        if (
            train_valid &&
            train_target == 1'b1 &&
            train_features == 8'b11001100
        )
            $display(
                "PASS: Multiple outstanding tracking works"
            );
        else
            $display(
                "FAIL: Multiple outstanding tracking failed"
            );

        #20;

        $display("");
        $display("================================");
        $display("PREFETCH TRACKER TEST COMPLETE");
        $display("================================");

        $finish;

    end

endmodule