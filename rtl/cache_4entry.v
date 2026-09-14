`timescale 1ns / 1ps

module cache #(
    parameter ADDR_WIDTH    = 6,
    parameter DATA_WIDTH    = 16,
    parameter CACHE_ENTRIES = 4
)(
    input  wire                  clk,
    input  wire                  rst,

    // Lookup interface
    input  wire                  lookup_en,
    input  wire [ADDR_WIDTH-1:0] lookup_addr,

    output reg                   hit,
    output reg  [DATA_WIDTH-1:0] lookup_data,

    // Fill interface
    input  wire                  fill_en,
    input  wire [ADDR_WIDTH-1:0] fill_addr,
    input  wire [DATA_WIDTH-1:0] fill_data,

    // Update interface
    input  wire                  update_en,
    input  wire [ADDR_WIDTH-1:0] update_addr,
    input  wire [DATA_WIDTH-1:0] update_data
);

    // ====================================================
    // HELPER FUNCTION
    //
    // Verilog-2001 compatible ceiling(log2(value)).
    // ====================================================

    function integer clog2;
        input integer value;
        integer temp;

        begin
            temp = value - 1;

            for (clog2 = 0; temp > 0; clog2 = clog2 + 1)
                temp = temp >> 1;
        end
    endfunction


    localparam PTR_WIDTH =
        (CACHE_ENTRIES <= 1) ? 1 : clog2(CACHE_ENTRIES);


    // ====================================================
    // CACHE STORAGE
    // ====================================================

    reg                  valid [0:CACHE_ENTRIES-1];
    reg [ADDR_WIDTH-1:0] tag   [0:CACHE_ENTRIES-1];
    reg [DATA_WIDTH-1:0] data  [0:CACHE_ENTRIES-1];

    reg [PTR_WIDTH-1:0] replacement_ptr;

    integer i;
    integer fill_match;


    // ====================================================
    // COMBINATIONAL LOOKUP
    // ====================================================

    always @(*) begin

        hit         = 1'b0;
        lookup_data = {DATA_WIDTH{1'b0}};

        if (lookup_en) begin

            for (i = 0; i < CACHE_ENTRIES; i = i + 1) begin

                if (
                    valid[i] &&
                    tag[i] == lookup_addr
                ) begin

                    hit         = 1'b1;
                    lookup_data = data[i];

                end

            end

        end

    end


    // ====================================================
    // CACHE FILL / UPDATE
    // ====================================================

    always @(posedge clk) begin

        if (rst) begin

            replacement_ptr <= {PTR_WIDTH{1'b0}};

            for (i = 0; i < CACHE_ENTRIES; i = i + 1) begin

                valid[i] <= 1'b0;
                tag[i]   <= {ADDR_WIDTH{1'b0}};
                data[i]  <= {DATA_WIDTH{1'b0}};

            end

        end

        else begin

            // ============================================
            // FILL
            //
            // If address already exists, update it rather
            // than creating a duplicate cache entry.
            // ============================================

            if (fill_en) begin

                fill_match = 0;

                for (i = 0; i < CACHE_ENTRIES; i = i + 1) begin

                    if (
                        valid[i] &&
                        tag[i] == fill_addr
                    ) begin

                        data[i] <= fill_data;
                        fill_match = 1;

                    end

                end


                // ----------------------------------------
                // Allocate new entry
                // ----------------------------------------

                if (!fill_match) begin

                    valid[replacement_ptr] <= 1'b1;
                    tag[replacement_ptr]   <= fill_addr;
                    data[replacement_ptr]  <= fill_data;


                    // Explicit wrap allows CACHE_ENTRIES
                    // that are not powers of two.
                    if (
                        replacement_ptr ==
                        CACHE_ENTRIES - 1
                    )
                        replacement_ptr <=
                            {PTR_WIDTH{1'b0}};
                    else
                        replacement_ptr <=
                            replacement_ptr + 1'b1;

                end

            end


            // ============================================
            // UPDATE EXISTING CACHE ENTRY
            // ============================================

            if (update_en) begin

                for (i = 0; i < CACHE_ENTRIES; i = i + 1) begin

                    if (
                        valid[i] &&
                        tag[i] == update_addr
                    ) begin

                        data[i] <= update_data;

                    end

                end

            end

        end

    end

endmodule