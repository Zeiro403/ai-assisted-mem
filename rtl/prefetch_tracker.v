`timescale 1ns / 1ps

module prefetch_tracker #(
    parameter ADDR_WIDTH        = 6,
    parameter FEATURE_WIDTH     = 8,
    parameter TRACKER_ENTRIES   = 4,
    parameter PREFETCH_LIFETIME = 8
)(
    input  wire                     clk,
    input  wire                     rst,

    // ====================================================
    // REGISTER NEW PREFETCH
    // ====================================================

    input  wire                     prefetch_issued,
    input  wire [ADDR_WIDTH-1:0]    prefetch_addr,
    input  wire [FEATURE_WIDTH-1:0] prefetch_features,

    // ====================================================
    // DEMAND ACCESS
    // ====================================================

    input  wire                     demand_access_valid,
    input  wire [ADDR_WIDTH-1:0]    demand_addr,

    // ====================================================
    // STATUS
    //
    // tracker_busy = all slots occupied
    // ====================================================

    output wire                     tracker_busy,

    // ====================================================
    // TRAINING OUTPUT
    // ====================================================

    output reg                      train_valid,
    output reg [FEATURE_WIDTH-1:0]  train_features,
    output reg                      train_target,

    // ====================================================
    // FEEDBACK EVENTS
    // ====================================================

    output reg                      prefetch_useful_event,
    output reg                      prefetch_useless_event
);

    // ====================================================
    // HELPER FUNCTION
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


    localparam AGE_WIDTH =
        (PREFETCH_LIFETIME <= 1)
            ? 1
            : clog2(PREFETCH_LIFETIME + 1);


    // ====================================================
    // TRACKER STORAGE
    // ====================================================

    reg                     valid
                            [0:TRACKER_ENTRIES-1];

    reg [ADDR_WIDTH-1:0]    tracked_addr
                            [0:TRACKER_ENTRIES-1];

    reg [FEATURE_WIDTH-1:0] tracked_features
                            [0:TRACKER_ENTRIES-1];

    reg [AGE_WIDTH-1:0]     age
                            [0:TRACKER_ENTRIES-1];


    integer i;

    integer free_index;
    integer match_index;
    integer timeout_index;

    reg free_found;
    reg match_found;
    reg timeout_found;

    reg all_valid;


    // ====================================================
    // TRACKER FULL DETECTION
    // ====================================================

    always @(*) begin

        all_valid = 1'b1;

        for (i = 0; i < TRACKER_ENTRIES; i = i + 1) begin

            if (!valid[i])
                all_valid = 1'b0;

        end

    end

    assign tracker_busy = all_valid;


    // ====================================================
    // TRACKER
    // ====================================================

    always @(posedge clk) begin

        if (rst) begin

            train_valid    <= 1'b0;
            train_features <= {FEATURE_WIDTH{1'b0}};
            train_target   <= 1'b0;

            prefetch_useful_event  <= 1'b0;
            prefetch_useless_event <= 1'b0;


            for (i = 0; i < TRACKER_ENTRIES; i = i + 1) begin

                valid[i] <= 1'b0;

                tracked_addr[i] <=
                    {ADDR_WIDTH{1'b0}};

                tracked_features[i] <=
                    {FEATURE_WIDTH{1'b0}};

                age[i] <=
                    {AGE_WIDTH{1'b0}};

            end

        end

        else begin

            // ============================================
            // DEFAULT EVENT PULSES
            // ============================================

            train_valid <= 1'b0;

            prefetch_useful_event  <= 1'b0;
            prefetch_useless_event <= 1'b0;


            // ============================================
            // FIND MATCH / TIMEOUT
            // ============================================

            match_found   = 1'b0;
            timeout_found = 1'b0;

            match_index   = 0;
            timeout_index = 0;


            if (demand_access_valid) begin

                // ----------------------------------------
                // FIRST PRIORITY:
                // Was any tracked address demanded?
                // ----------------------------------------

                for (i = 0; i < TRACKER_ENTRIES; i = i + 1) begin

                    if (
                        valid[i] &&
                        !match_found &&
                        tracked_addr[i] == demand_addr
                    ) begin

                        match_found = 1'b1;
                        match_index = i;

                    end

                end


                // ----------------------------------------
                // SECOND PRIORITY:
                // Find a timed-out entry.
                //
                // If lifetime = 8, age == 7 means this
                // demand is the eighth unrelated access.
                // ----------------------------------------

                if (!match_found) begin

                    for (i = 0; i < TRACKER_ENTRIES; i = i + 1) begin

                        if (
                            valid[i] &&
                            !timeout_found &&
                            age[i] >=
                                (PREFETCH_LIFETIME - 1)
                        ) begin

                            timeout_found = 1'b1;
                            timeout_index = i;

                        end

                    end

                end


                // ========================================
                // USEFUL PREFETCH
                // ========================================

                if (match_found) begin

                    train_valid <= 1'b1;

                    train_features <=
                        tracked_features[match_index];

                    train_target <= 1'b1;

                    prefetch_useful_event <= 1'b1;

                    valid[match_index] <= 1'b0;

                    age[match_index] <=
                        {AGE_WIDTH{1'b0}};

                end


                // ========================================
                // USELESS / TIMED-OUT PREFETCH
                // ========================================

                else if (timeout_found) begin

                    train_valid <= 1'b1;

                    train_features <=
                        tracked_features[timeout_index];

                    train_target <= 1'b0;

                    prefetch_useless_event <= 1'b1;

                    valid[timeout_index] <= 1'b0;

                    age[timeout_index] <=
                        {AGE_WIDTH{1'b0}};

                end


                // ========================================
                // AGE REMAINING ENTRIES
                // ========================================

                for (i = 0; i < TRACKER_ENTRIES; i = i + 1) begin

                    if (
                        valid[i] &&
                        !(match_found && i == match_index) &&
                        !(timeout_found && i == timeout_index)
                    ) begin

                        if (
                            age[i] <
                            (PREFETCH_LIFETIME - 1)
                        )
                            age[i] <= age[i] + 1'b1;

                    end

                end

            end


            // ============================================
            // INSERT NEW PREFETCH
            // ============================================

            if (prefetch_issued) begin

                free_found = 1'b0;
                free_index = 0;


                for (i = 0; i < TRACKER_ENTRIES; i = i + 1) begin

                    if (
                        !valid[i] &&
                        !free_found
                    ) begin

                        free_found = 1'b1;
                        free_index = i;

                    end

                end


                if (free_found) begin

                    valid[free_index] <= 1'b1;

                    tracked_addr[free_index] <=
                        prefetch_addr;

                    tracked_features[free_index] <=
                        prefetch_features;

                    age[free_index] <=
                        {AGE_WIDTH{1'b0}};

                end

            end

        end

    end

endmodule