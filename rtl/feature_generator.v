`timescale 1ns / 1ps

module feature_generator #(
    parameter ADDR_WIDTH  = 6,
    parameter REGION_BITS = 4
)(
    input wire clk,
    input wire rst,

    input wire feature_valid,

    input wire [ADDR_WIDTH-1:0] current_addr,
    input wire [ADDR_WIDTH-1:0] candidate_addr,

    input wire signed [ADDR_WIDTH:0] current_stride,

    input wire stride_match,
    input wire recent_cache_miss,
    input wire previous_prefetch_useful,
    input wire recent_accuracy_high,

    output reg [7:0] features,
    output reg       features_valid
);

    reg signed [ADDR_WIDTH:0] abs_stride;


    always @(*) begin

        // -----------------------------------------------
        // ABSOLUTE STRIDE
        // -----------------------------------------------

        if (current_stride < 0)
            abs_stride = -current_stride;
        else
            abs_stride = current_stride;

    end


    always @(posedge clk) begin

        if (rst) begin

            features       <= 8'b0;
            features_valid <= 1'b0;

        end

        else begin

            features_valid <= 1'b0;

            if (feature_valid) begin

                // Feature 0:
                // repeated stride
                features[0] <= stride_match;


                // Feature 1:
                // non-zero small stride
                if (
                    abs_stride >= 1 &&
                    abs_stride <= 4
                )
                    features[1] <= 1'b1;
                else
                    features[1] <= 1'b0;


                // Feature 2:
                // forward access
                features[2] <=
                    (current_stride > 0);


                // Feature 3:
                // sequential access (+1 or -1)
                features[3] <=
                    (
                        current_stride == 7'sd1 ||
                        current_stride == -7'sd1
                    );


                // Feature 4:
                // previous demand access missed cache
                features[4] <= recent_cache_miss;


                // Feature 5:
                // previous evaluated prefetch was useful
                features[5] <= previous_prefetch_useful;


                // Feature 6:
                // candidate stays in same 16-word region
                features[6] <=
                    (
                        (current_addr >> REGION_BITS)
                        ==
                        (candidate_addr >> REGION_BITS)
                    );


                // Feature 7:
                // recent predictor performance is good
                features[7] <= recent_accuracy_high;


                features_valid <= 1'b1;

            end

        end

    end

endmodule