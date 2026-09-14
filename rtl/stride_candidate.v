`timescale 1ns / 1ps

module stride_candidate (
    input  wire              clk,
    input  wire              rst,

    // Assert once for each CPU memory access we want to observe
    input  wire              access_valid,
    input  wire [5:0]        access_addr,

    // Candidate prediction
    output reg  [5:0]        candidate_addr,
    output reg               candidate_valid,

    // Information exposed to future ML feature generator
    output reg  signed [6:0] current_stride,
    output reg               stride_match,

    // Indicates that enough history exists to compare strides
    output reg               history_valid
);

    reg [5:0] previous_addr;

    reg signed [6:0] previous_stride;

    reg have_previous_addr;
    reg have_previous_stride;

    reg signed [6:0] new_stride;
    reg signed [6:0] predicted_addr;


    always @(posedge clk) begin

        if (rst) begin

            previous_addr        <= 6'd0;
            previous_stride      <= 7'sd0;

            have_previous_addr   <= 1'b0;
            have_previous_stride <= 1'b0;

            candidate_addr       <= 6'd0;
            candidate_valid      <= 1'b0;

            current_stride       <= 7'sd0;
            stride_match         <= 1'b0;
            history_valid        <= 1'b0;

            new_stride           <= 7'sd0;
            predicted_addr       <= 7'sd0;

        end

        else begin

            // Default outputs
            candidate_valid <= 1'b0;
            stride_match    <= 1'b0;

            if (access_valid) begin

                // ----------------------------------------
                // FIRST ACCESS
                // ----------------------------------------

                if (!have_previous_addr) begin

                    previous_addr      <= access_addr;
                    have_previous_addr <= 1'b1;

                    history_valid <= 1'b0;

                end


                // ----------------------------------------
                // SECOND OR LATER ACCESS
                // ----------------------------------------

                else begin

                    // Calculate signed stride.
                    new_stride =
                        $signed({1'b0, access_addr}) -
                        $signed({1'b0, previous_addr});

                    current_stride <= new_stride;


                    // ------------------------------------
                    // We already have a previous stride
                    // ------------------------------------

                    if (have_previous_stride) begin

                        history_valid <= 1'b1;

                        if (new_stride == previous_stride) begin

                            stride_match <= 1'b1;

                            // Predict using established stride
                            predicted_addr =
                                $signed({1'b0, access_addr})
                                + (new_stride <<< 1);

                            // Only generate candidates that
                            // remain inside our 64-word memory.
                            if (
                                predicted_addr >= 0 &&
                                predicted_addr <= 63
                            ) begin

                                candidate_addr  <=
                                    predicted_addr[5:0];

                                candidate_valid <= 1'b1;

                            end

                        end

                    end


                    // Save newly observed stride
                    previous_stride      <= new_stride;
                    have_previous_stride <= 1'b1;

                    // Save current address
                    previous_addr <= access_addr;

                end

            end

        end

    end

endmodule