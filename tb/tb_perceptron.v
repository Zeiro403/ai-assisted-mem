`timescale 1ns / 1ps

module tb_perceptron;

    reg               clk;
    reg               rst;

    reg               infer_valid;
    reg  [7:0]        features;

    wire              decision_valid;
    wire              prefetch_decision;
    wire signed [11:0] score;

    reg               train_valid;
    reg  [7:0]        train_features;
    reg               train_target;


    perceptron dut (
        .clk               (clk),
        .rst               (rst),

        .infer_valid       (infer_valid),
        .features          (features),

        .decision_valid    (decision_valid),
        .prefetch_decision (prefetch_decision),
        .score             (score),

        .train_valid       (train_valid),
        .train_features    (train_features),
        .train_target      (train_target)
    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    // ----------------------------------------------------
    // TRAIN ONE EXAMPLE
    // ----------------------------------------------------

    task train_example;

        input [7:0] f;
        input       target;

        begin

            @(negedge clk);

            train_features = f;
            train_target   = target;
            train_valid    = 1;

            @(negedge clk);

            train_valid = 0;

        end

    endtask


    // ----------------------------------------------------
    // RUN INFERENCE
    // ----------------------------------------------------

    task infer_example;

        input [7:0] f;

        begin

            @(negedge clk);

            features    = f;
            infer_valid = 1;

            @(negedge clk);

            infer_valid = 0;

            #1;

            $display(
                "features=%b score=%0d decision=%s",
                f,
                $signed(score),
                prefetch_decision ? "PREFETCH" : "REJECT"
            );

        end

    endtask


    integer n;


    initial begin

        rst            = 1;

        infer_valid    = 0;
        features       = 0;

        train_valid    = 0;
        train_features = 0;
        train_target   = 0;

        #20;
        rst = 0;


        // ================================================
        // INITIAL STATE
        // ================================================

        $display("");
        $display("================================");
        $display("INITIAL PERCEPTRON");
        $display("================================");

        infer_example(8'b11110000);


        // ================================================
        // TEACH PATTERN A AS USEFUL
        // ================================================

        $display("");
        $display("================================");
        $display("TRAIN A AS USEFUL");
        $display("================================");

        for (n = 0; n < 5; n = n + 1)
            train_example(
                8'b11110000,
                1'b1
            );

        infer_example(8'b11110000);


        // ================================================
        // TEST OPPOSITE PATTERN
        // ================================================

        $display("");
        $display("================================");
        $display("OPPOSITE PATTERN");
        $display("================================");

        infer_example(8'b00001111);


        // ================================================
        // TEACH PATTERN B AS USELESS
        // ================================================

        $display("");
        $display("================================");
        $display("TRAIN B AS USELESS");
        $display("================================");

        for (n = 0; n < 5; n = n + 1)
            train_example(
                8'b00110011,
                1'b0
            );

        infer_example(8'b00110011);


        // ================================================
        // CHECK PATTERN A AGAIN
        // ================================================

        $display("");
        $display("================================");
        $display("CHECK A AGAIN");
        $display("================================");

        infer_example(8'b11110000);


        #20;

        $display("");
        $display("================================");
        $display("PERCEPTRON TEST COMPLETE");
        $display("================================");

        $finish;

    end

endmodule