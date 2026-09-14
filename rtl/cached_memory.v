`timescale 1ns / 1ps

module cached_memory (
    input  wire        clk,
    input  wire        rst,

    // CPU request interface
    input  wire        req,
    input  wire        we,
    input  wire [5:0]  addr,
    input  wire [15:0] data_in,

    // CPU response interface
    output reg  [15:0] data_out,
    output reg         data_valid,
    output reg         busy,

    // Debug / performance signals
    output reg         cache_hit_event,
    output reg         cache_miss_event
);

    // ====================================================
    // FSM STATES
    // ====================================================

    localparam IDLE      = 3'd0;
    localparam LOOKUP    = 3'd1;
    localparam RAM_READ  = 3'd2;
    localparam FILL      = 3'd3;
    localparam WRITE     = 3'd4;

    reg [2:0] state;


    // ====================================================
    // LATCHED CPU REQUEST
    // ====================================================

    reg [5:0]  req_addr;
    reg [15:0] req_data;


    // ====================================================
    // CACHE SIGNALS
    // ====================================================

    reg         cache_lookup_en;
    reg  [5:0]  cache_lookup_addr;

    wire        cache_hit;
    wire [15:0] cache_lookup_data;

    reg         cache_fill_en;
    reg  [5:0]  cache_fill_addr;
    reg  [15:0] cache_fill_data;

    reg         cache_update_en;
    reg  [5:0]  cache_update_addr;
    reg  [15:0] cache_update_data;


    // ====================================================
    // RAM SIGNALS
    // ====================================================

    reg         ram_en;
    reg         ram_we;
    reg  [5:0]  ram_addr;
    reg  [15:0] ram_data_in;

    wire [15:0] ram_data_out;
    wire        ram_data_valid;


    // ====================================================
    // CACHE INSTANCE
    // ====================================================

    cache_4entry cache_inst (
        .clk         (clk),
        .rst         (rst),

        .lookup_en   (cache_lookup_en),
        .lookup_addr (cache_lookup_addr),

        .hit         (cache_hit),
        .lookup_data (cache_lookup_data),

        .fill_en     (cache_fill_en),
        .fill_addr   (cache_fill_addr),
        .fill_data   (cache_fill_data),

        .update_en   (cache_update_en),
        .update_addr (cache_update_addr),
        .update_data (cache_update_data)
    );


    // ====================================================
    // RAM INSTANCE
    // ====================================================

    memory_64x16 ram_inst (
        .clk        (clk),
        .rst        (rst),

        .en         (ram_en),
        .we         (ram_we),

        .addr       (ram_addr),
        .data_in    (ram_data_in),

        .data_out   (ram_data_out),
        .data_valid (ram_data_valid)
    );


    // ====================================================
    // CONTROLLER FSM
    // ====================================================

    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            req_addr <= 0;
            req_data <= 0;

            data_out   <= 0;
            data_valid <= 0;
            busy       <= 0;

            cache_hit_event  <= 0;
            cache_miss_event <= 0;

            cache_lookup_en <= 0;
            cache_fill_en   <= 0;
            cache_update_en <= 0;

            cache_lookup_addr <= 0;
            cache_fill_addr   <= 0;
            cache_fill_data   <= 0;

            cache_update_addr <= 0;
            cache_update_data <= 0;

            ram_en      <= 0;
            ram_we      <= 0;
            ram_addr    <= 0;
            ram_data_in <= 0;

        end

        else begin

            // Default one-cycle control pulses
            data_valid       <= 0;
            cache_hit_event  <= 0;
            cache_miss_event <= 0;

            cache_fill_en   <= 0;
            cache_update_en <= 0;

            ram_en <= 0;


            case (state)

                // ========================================
                // WAIT FOR CPU REQUEST
                // ========================================

                IDLE: begin

                    busy            <= 0;
                    cache_lookup_en <= 0;

                    if (req) begin

                        req_addr <= addr;
                        req_data <= data_in;

                        busy <= 1;

                        if (we) begin
                            state <= WRITE;
                        end

                        else begin
                            cache_lookup_addr <= addr;
                            cache_lookup_en   <= 1;

                            state <= LOOKUP;
                        end

                    end

                end


                // ========================================
                // CACHE LOOKUP
                // ========================================

                LOOKUP: begin

                    cache_lookup_en <= 0;

                    if (cache_hit) begin

                        data_out   <= cache_lookup_data;
                        data_valid <= 1;

                        cache_hit_event <= 1;

                        busy  <= 0;
                        state <= IDLE;

                    end

                    else begin

                        cache_miss_event <= 1;

                        ram_en   <= 1;
                        ram_we   <= 0;
                        ram_addr <= req_addr;

                        state <= RAM_READ;

                    end

                end


                // ========================================
                // WAIT FOR RAM READ
                // ========================================

                RAM_READ: begin

                    if (ram_data_valid) begin

                        data_out   <= ram_data_out;
                        data_valid <= 1;

                        cache_fill_addr <= req_addr;
                        cache_fill_data <= ram_data_out;
                        cache_fill_en   <= 1;

                        state <= FILL;

                    end

                end


                // ========================================
                // CACHE FILL COMPLETED
                // ========================================

                FILL: begin

                    busy  <= 0;
                    state <= IDLE;

                end


                // ========================================
                // WRITE-THROUGH
                // ========================================

                WRITE: begin

                    ram_en      <= 1;
                    ram_we      <= 1;
                    ram_addr    <= req_addr;
                    ram_data_in <= req_data;

                    cache_update_en   <= 1;
                    cache_update_addr <= req_addr;
                    cache_update_data <= req_data;

                    busy  <= 0;
                    state <= IDLE;

                end


                default: begin
                    state <= IDLE;
                end

            endcase

        end

    end

endmodule