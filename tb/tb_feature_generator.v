`timescale 1ns / 1ps

module tb_feature_generator;

    reg clk;
    reg rst;

    reg feature_valid;

    reg [5:0] current_addr;
    reg [5:0] candidate_addr;

    reg signed [6:0] current_stride;

    reg stride_match;
    reg recent_cache_miss;
    reg previous_prefetch_useful;
    reg recent_accuracy_high;

    wire [7:0] features;
    wire       features_valid;


    feature_generator dut (
        .clk                      (clk),
        .rst                      (rst),

        .feature_valid            (feature_valid),

        .current_addr             (current_addr),
        .candidate_addr           (candidate_addr),

        .current_stride           (current_stride),
        .stride_match             (stride_match),

        .recent_cache_miss        (recent_cache_miss),
        .previous_prefetch_useful (previous_prefetch_useful),
        .recent_accuracy_high     (recent_accuracy_high),

        .features                 (features),
        .features_valid           (features_valid)
    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    task test_feature;

        input [5:0] addr;
        input [5:0] candidate;
        input signed [6:0] stride;
        input match;
        input miss;
        input useful;
        input accuracy;

        begin

            @(negedge clk);

            current_addr             = addr;
            candidate_addr           = candidate;
            current_stride           = stride;

            stride_match             = match;
            recent_cache_miss        = miss;
            previous_prefetch_useful = useful;
            recent_accuracy_high     = accuracy;

            feature_valid = 1;

            @(negedge clk);

            feature_valid = 0;

            #1;

            $display(
                "addr=%0d candidate=%0d stride=%0d features=%b",
                addr,
                candidate,
                stride,
                features
            );

        end

    endtask


    initial begin

        rst                      = 1;
        feature_valid            = 0;

        current_addr             = 0;
        candidate_addr           = 0;
        current_stride           = 0;

        stride_match             = 0;
        recent_cache_miss        = 0;
        previous_prefetch_useful = 0;
        recent_accuracy_high     = 0;

        #20;
        rst = 0;


        // ================================================
        // TEST 1
        // Forward sequential access
        // ================================================

        $display("");
        $display("TEST 1: FORWARD SEQUENTIAL");

        test_feature(
            6'd10,
            6'd11,
            7'sd1,
            1'b1,
            1'b1,
            1'b1,
            1'b1
        );


        // ================================================
        // TEST 2
        // Reverse sequential access
        // ================================================

        $display("");
        $display("TEST 2: REVERSE SEQUENTIAL");

        test_feature(
            6'd10,
            6'd9,
            -7'sd1,
            1'b1,
            1'b0,
            1'b1,
            1'b1
        );


        // ================================================
        // TEST 3
        // Large irregular stride
        // ================================================

        $display("");
        $display("TEST 3: LARGE STRIDE");

        test_feature(
            6'd10,
            6'd25,
            7'sd15,
            1'b0,
            1'b1,
            1'b0,
            1'b0
        );


        // ================================================
        // TEST 4
        // +4 stride, but crosses region boundary
        //
        // current 14 = region 0
        // candidate 18 = region 1
        // ================================================

        $display("");
        $display("TEST 4: REGION CROSSING");

        test_feature(
            6'd14,
            6'd18,
            7'sd4,
            1'b1,
            1'b1,
            1'b0,
            1'b0
        );


        #20;

        $display("");
        $display("FEATURE GENERATOR TEST COMPLETE");

        $finish;

    end

endmodule