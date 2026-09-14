`timescale 1ns / 1ps

module cache_4entry (
    input  wire        clk,
    input  wire        rst,

    // Lookup interface
    input  wire        lookup_en,
    input  wire [5:0]  lookup_addr,

    output reg         hit,
    output reg  [15:0] lookup_data,

    // Fill interface
    input  wire        fill_en,
    input  wire [5:0]  fill_addr,
    input  wire [15:0] fill_data,

    // Update interface
    input  wire        update_en,
    input  wire [5:0]  update_addr,
    input  wire [15:0] update_data
);

    reg        valid [0:3];
    reg [5:0]  tag   [0:3];
    reg [15:0] data  [0:3];

    reg [1:0] replacement_ptr;

    integer i;
    integer fill_match;


    // ----------------------------------------------------
    // COMBINATIONAL LOOKUP
    // ----------------------------------------------------

    always @(*) begin

        hit         = 1'b0;
        lookup_data = 16'b0;

        if (lookup_en) begin

            for (i = 0; i < 4; i = i + 1) begin

                if (valid[i] && tag[i] == lookup_addr) begin
                    hit         = 1'b1;
                    lookup_data = data[i];
                end

            end

        end

    end


    // ----------------------------------------------------
    // CACHE FILL / UPDATE
    // ----------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            replacement_ptr <= 2'b00;

            for (i = 0; i < 4; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i]   <= 6'b0;
                data[i]  <= 16'b0;
            end

        end

        else begin

            // Fill a new cache entry
            if (fill_en) begin

                fill_match = 0;
            
                // Update existing copy if address is already cached
                for (i = 0; i < 4; i = i + 1) begin
            
                    if (valid[i] && tag[i] == fill_addr) begin
            
                        data[i] <= fill_data;
                        fill_match = 1;
            
                    end
            
                end
            
                // Otherwise allocate a new entry
                if (!fill_match) begin
            
                    valid[replacement_ptr] <= 1'b1;
                    tag[replacement_ptr]   <= fill_addr;
                    data[replacement_ptr]  <= fill_data;
            
                    replacement_ptr <= replacement_ptr + 1'b1;
            
                end
            
            end 


            // Update an existing cache entry
            if (update_en) begin

                for (i = 0; i < 4; i = i + 1) begin

                    if (valid[i] && tag[i] == update_addr) begin
                        data[i] <= update_data;
                    end

                end

            end

        end

    end

endmodule