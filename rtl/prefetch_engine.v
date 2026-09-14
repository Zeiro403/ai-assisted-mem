`timescale 1ns / 1ps

module prefetch_engine (
    input  wire        clk,
    input  wire        rst,

    // Start a prefetch
    input  wire        start,
    input  wire [5:0]  candidate_addr,

    // Engine status
    output reg         busy,

    // RAM interface
    output reg         ram_req,
    output reg  [5:0]  ram_addr,

    input  wire [15:0] ram_data,
    input  wire        ram_data_valid,

    // Cache fill interface
    output reg         fill_en,
    output reg  [5:0]  fill_addr,
    output reg  [15:0] fill_data,

    // Indicates successful completion
    output reg         prefetch_complete
);

    localparam IDLE = 2'd0;
    localparam WAIT = 2'd1;
    localparam FILL = 2'd2;

    reg [1:0] state;

    reg [5:0] saved_addr;


    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            busy <= 1'b0;

            ram_req  <= 1'b0;
            ram_addr <= 6'd0;

            fill_en   <= 1'b0;
            fill_addr <= 6'd0;
            fill_data <= 16'd0;

            prefetch_complete <= 1'b0;

            saved_addr <= 6'd0;

        end

        else begin

            ram_req            <= 1'b0;
            fill_en            <= 1'b0;
            prefetch_complete  <= 1'b0;


            case (state)

                IDLE: begin

                    busy <= 1'b0;

                    if (start) begin

                        saved_addr <= candidate_addr;

                        ram_addr <= candidate_addr;
                        ram_req  <= 1'b1;

                        busy  <= 1'b1;
                        state <= WAIT;

                    end

                end


                WAIT: begin

                    busy <= 1'b1;

                    if (ram_data_valid) begin

                        fill_addr <= saved_addr;
                        fill_data <= ram_data;
                        fill_en   <= 1'b1;

                        state <= FILL;

                    end

                end


                FILL: begin

                    busy <= 1'b0;

                    prefetch_complete <= 1'b1;

                    state <= IDLE;

                end


                default: begin
                    state <= IDLE;
                end

            endcase

        end

    end

endmodule