`timescale 1ns / 1ps

module perceptron (
    input  wire              clk,
    input  wire              rst,

    // ----------------------------------------------------
    // INFERENCE INTERFACE
    // ----------------------------------------------------

    input  wire              infer_valid,
    input  wire [7:0]        features,

    output reg               decision_valid,
    output reg               prefetch_decision,
    output reg signed [11:0] score,

    // ----------------------------------------------------
    // TRAINING INTERFACE
    // ----------------------------------------------------

    input  wire              train_valid,

    // Features belonging to the example being trained.
    // Later these will be saved when a prediction is made.
    input  wire [7:0]        train_features,

    // 1 = useful prefetch
    // 0 = useless prefetch
    input  wire              train_target
);

    // ----------------------------------------------------
    // WEIGHTS
    // ----------------------------------------------------

    reg signed [7:0] bias;

    reg signed [7:0] weight [0:7];

    integer i;

    reg signed [11:0] sum;


    // ====================================================
    // SATURATING INCREMENT
    // ====================================================

    function signed [7:0] sat_inc;

        input signed [7:0] value;

        begin

            if (value >= 8'sd31)
                sat_inc = 8'sd31;
            else
                sat_inc = value + 8'sd1;

        end

    endfunction


    // ====================================================
    // SATURATING DECREMENT
    // ====================================================

    function signed [7:0] sat_dec;

        input signed [7:0] value;

        begin

            if (value <= -8'sd31)
                sat_dec = -8'sd31;
            else
                sat_dec = value - 8'sd1;

        end

    endfunction


    // ====================================================
    // PERCEPTRON
    // ====================================================

    always @(posedge clk) begin

        if (rst) begin

            bias <= 8'sd0;

            for (i = 0; i < 8; i = i + 1)
                weight[i] <= 8'sd0;

            decision_valid    <= 1'b0;
            prefetch_decision <= 1'b0;
            score             <= 12'sd0;

            sum <= 12'sd0;

        end

        else begin

            decision_valid <= 1'b0;


            // ============================================
            // INFERENCE
            // ============================================

            if (infer_valid) begin

                sum = bias;

                for (i = 0; i < 8; i = i + 1) begin

                    if (features[i])
                        sum = sum + weight[i];

                    else
                        sum = sum - weight[i];

                end

                score <= sum;

                if (sum >= 0)
                    prefetch_decision <= 1'b1;
                else
                    prefetch_decision <= 1'b0;

                decision_valid <= 1'b1;

            end


            // ============================================
            // ONLINE TRAINING
            // ============================================

            if (train_valid) begin

                // ----------------------------------------
                // UPDATE BIAS
                // ----------------------------------------

                if (train_target)
                    bias <= sat_inc(bias);
                else
                    bias <= sat_dec(bias);


                // ----------------------------------------
                // UPDATE WEIGHTS
                //
                // w = w + target * feature
                //
                // target:
                // useful   = +1
                // useless  = -1
                //
                // feature:
                // bit 1 = +1
                // bit 0 = -1
                // ----------------------------------------

                for (i = 0; i < 8; i = i + 1) begin

                    if (train_target) begin

                        if (train_features[i])
                            weight[i] <= sat_inc(weight[i]);
                        else
                            weight[i] <= sat_dec(weight[i]);

                    end

                    else begin

                        if (train_features[i])
                            weight[i] <= sat_dec(weight[i]);
                        else
                            weight[i] <= sat_inc(weight[i]);

                    end

                end

            end

        end

    end

endmodule