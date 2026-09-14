`timescale 1ns / 1ps

module tb_stride_candidate;

    reg        clk;
    reg        rst;

    reg        access_valid;
    reg [5:0]  access_addr;

    wire [5:0] candidate_addr;
    wire       candidate_valid;

    wire signed [6:0] current_stride;
    wire              stride_match;
    wire              history_valid;


    stride_candidate dut (
        .clk              (clk),
        .rst              (rst),

        .access_valid     (access_valid),
        .access_addr      (access_addr),

        .candidate_addr   (candidate_addr),
        .candidate_valid  (candidate_valid),

        .current_stride   (current_stride),
        .stride_match     (stride_match),

        .history_valid    (history_valid)
    );


    // 100 MHz clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    // ----------------------------------------------------
    // SEND ONE MEMORY ACCESS
    // ----------------------------------------------------

    task send_access;

        input [5:0] test_addr;

        begin

            @(negedge clk);

            access_valid = 1;
            access_addr  = test_addr;

            @(negedge clk);

            #1;

            $display(
                "Access=%0d  stride=%0d  match=%b  candidate_valid=%b  candidate=%0d",
                test_addr,
                $signed(current_stride),
                stride_match,
                candidate_valid,
                candidate_addr
            );

            access_valid = 0;

        end

    endtask


    // ----------------------------------------------------
    // RESET PREDICTOR
    // ----------------------------------------------------

    task reset_predictor;

        begin

            @(negedge clk);
            rst = 1;

            @(negedge clk);
            rst = 0;

        end

    endtask


    initial begin

        rst          = 1;
        access_valid = 0;
        access_addr  = 0;

        #20;
        rst = 0;


        // ================================================
        // TEST 1: +2 STRIDE
        // ================================================

        $display("");
        $display("================================");
        $display("TEST 1: +2 STRIDE");
        $display("================================");

        send_access(6'd10);
        send_access(6'd12);
        send_access(6'd14);
        send_access(6'd16);
        send_access(6'd18);


        // ================================================
        // TEST 2: -2 STRIDE
        // ================================================

        reset_predictor();

        $display("");
        $display("================================");
        $display("TEST 2: -2 STRIDE");
        $display("================================");

        send_access(6'd20);
        send_access(6'd18);
        send_access(6'd16);
        send_access(6'd14);
        send_access(6'd12);


        // ================================================
        // TEST 3: PATTERN BREAK
        // ================================================

        reset_predictor();

        $display("");
        $display("================================");
        $display("TEST 3: PATTERN BREAK");
        $display("================================");

        send_access(6'd5);
        send_access(6'd8);
        send_access(6'd11);

        // Break +3 pattern
        send_access(6'd25);

        // Establish new +2 pattern
        send_access(6'd27);
        send_access(6'd29);
        send_access(6'd31);


        // ================================================
        // TEST 4: BOUNDARY
        // ================================================

        reset_predictor();

        $display("");
        $display("================================");
        $display("TEST 4: MEMORY BOUNDARY");
        $display("================================");

        send_access(6'd57);
        send_access(6'd60);
        send_access(6'd63);

        // Candidate would be 66, which is invalid.
        // candidate_valid must remain zero.


        #20;

        $display("");
        $display("================================");
        $display("STRIDE CANDIDATE TEST COMPLETE");
        $display("================================");

        $finish;

    end

endmodule