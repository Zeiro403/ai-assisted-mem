`timescale 1ns / 1ps

module memory #(
    parameter ADDR_WIDTH = 6,
    parameter DATA_WIDTH = 16,
    parameter DEPTH      = (1 << ADDR_WIDTH)
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire                  en,
    input  wire                  we,

    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [DATA_WIDTH-1:0] data_in,

    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   data_valid
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    integer i;

    always @(posedge clk) begin

        if (rst) begin

            data_out   <= {DATA_WIDTH{1'b0}};
            data_valid <= 1'b0;

            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end

        end

        else begin

            data_valid <= 1'b0;

            if (en) begin

                if (we) begin

                    mem[addr] <= data_in;

                end

                else begin

                    data_out   <= mem[addr];
                    data_valid <= 1'b1;

                end

            end

        end

    end

endmodule