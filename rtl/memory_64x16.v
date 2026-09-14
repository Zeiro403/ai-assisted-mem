`timescale 1ns / 1ps

module memory_64x16 (
    input  wire        clk,
    input  wire        rst,

    input  wire        en,
    input  wire        we,

    input  wire [5:0]  addr,
    input  wire [15:0] data_in,

    output reg  [15:0] data_out,
    output reg         data_valid
);

    // 64 words, each 16 bits wide
    reg [15:0] mem [0:63];

    integer i;

    always @(posedge clk) begin

        if (rst) begin
            data_out   <= 16'b0;
            data_valid <= 1'b0;

            // Simulation-friendly initialization.
            // We can revisit initialization for synthesis later.
            for (i = 0; i < 64; i = i + 1) begin
                mem[i] <= 16'b0;
            end
        end

        else begin
            // Default: no completed read this cycle
            data_valid <= 1'b0;

            if (en) begin

                if (we) begin
                    // Synchronous write
                    mem[addr] <= data_in;
                end

                else begin
                    // Synchronous read
                    data_out   <= mem[addr];
                    data_valid <= 1'b1;
                end

            end
        end

    end

endmodule