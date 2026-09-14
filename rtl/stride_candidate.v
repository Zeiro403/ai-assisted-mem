`timescale 1ns / 1ps

module stride_candidate #(
    parameter ADDR_WIDTH        = 6,
    parameter PREFETCH_DISTANCE = 2
)(
    input wire clk,
    input wire rst,

    input wire                  access_valid,
    input wire [ADDR_WIDTH-1:0] access_addr,

    output reg [ADDR_WIDTH-1:0] candidate_addr,
    output reg                  candidate_valid,

    output reg signed [ADDR_WIDTH:0] current_stride,
    output reg                         stride_match,
    output reg                         history_valid
);

    reg [ADDR_WIDTH-1:0] previous_addr;

    reg signed [ADDR_WIDTH:0] previous_stride;

    reg have_previous_addr;
    reg have_previous_stride;

    reg signed [ADDR_WIDTH:0] new_stride;

    // Extra width for prediction arithmetic.
    reg signed [ADDR_WIDTH+2:0] predicted_addr;

    localparam signed [ADDR_WIDTH+2:0] MAX_ADDR =
        (1 << ADDR_WIDTH) - 1;


    always @(posedge clk) begin

        if (rst) begin

            previous_addr        <= 0;
            previous_stride      <= 0;

            have_previous_addr   <= 1'b0;
            have_previous_stride <= 1'b0;

            candidate_addr       <= 0;
            candidate_valid      <= 1'b0;

            current_stride       <= 0;
            stride_match         <= 1'b0;
            history_valid        <= 1'b0;

            new_stride           <= 0;
            predicted_addr       <= 0;

        end

        else begin

            candidate_valid <= 1'b0;
            stride_match    <= 1'b0;

            if (access_valid) begin

                if (!have_previous_addr) begin

                    previous_addr      <= access_addr;
                    have_previous_addr <= 1'b1;

                    history_valid <= 1'b0;

                end

                else begin

                    new_stride =
                        $signed({1'b0, access_addr}) -
                        $signed({1'b0, previous_addr});

                    current_stride <= new_stride;


                    if (have_previous_stride) begin

                        history_valid <= 1'b1;

                        if (new_stride == previous_stride) begin

                            stride_match <= 1'b1;

                            predicted_addr =
                                $signed({1'b0, access_addr})
                                +
                                (
                                    new_stride *
                                    PREFETCH_DISTANCE
                                );

                            if (
                                predicted_addr >= 0 &&
                                predicted_addr <= MAX_ADDR
                            ) begin

                                candidate_addr <=
                                    predicted_addr[
                                        ADDR_WIDTH-1:0
                                    ];

                                candidate_valid <= 1'b1;

                            end

                        end

                    end


                    previous_stride      <= new_stride;
                    have_previous_stride <= 1'b1;

                    previous_addr <= access_addr;

                end

            end

        end

    end

endmodule