`timescale 1ns / 1ps

module ai_memory_top #(

    // Operating mode
    parameter PREFETCH_MODE = 2,

    // Memory configuration
    parameter ADDR_WIDTH = 6,
    parameter DATA_WIDTH = 16,

    // Cache configuration
    parameter CACHE_ENTRIES = 4,

    // Prefetch tracking
    parameter TRACKER_ENTRIES   = 4,
    parameter PREFETCH_LIFETIME = 8,

    // Predictor
    parameter PREFETCH_DISTANCE = 2,

    // Feature generation
    parameter REGION_BITS = 4,

    // ML
    parameter FEATURE_WIDTH = 8

)(
    input wire clk,
    input wire rst,

    // CPU interface
    input wire                  req,
    input wire                  we,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] data_in,

    output reg [DATA_WIDTH-1:0] data_out,
    output reg                  data_valid,
    output reg                  busy,

    // Cache events
    output reg cache_hit_event,
    output reg cache_miss_event,

    // Prediction
    output wire [ADDR_WIDTH-1:0] predicted_addr,
    output wire                  prediction_valid,

    // ML
    output wire signed [11:0] ml_score,
    output wire               ml_decision,

    // Prefetch
    output reg  prefetch_start_event,
    output wire prefetch_useful_event,
    output wire prefetch_useless_event,

    output wire [3:0] bootstrap_count,

    // Benchmarking
    output reg demand_ram_read_event,
    output reg prefetch_ram_read_event,

    output reg ml_accept_event,
    output reg ml_reject_event
);


    // ====================================================
    // DEMAND CONTROLLER STATES
    // ====================================================

    localparam D_IDLE       = 3'd0;
    localparam D_LOOKUP     = 3'd1;
    localparam D_RAM_REQ    = 3'd2;
    localparam D_RAM_WAIT   = 3'd3;
    localparam D_FILL       = 3'd4;
    localparam D_WRITE      = 3'd5;
    localparam D_WRITE_DONE = 3'd6;

    reg [2:0] demand_state;


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
    // CACHE INSTANCE
    // ====================================================

    cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .CACHE_ENTRIES(CACHE_ENTRIES)
    ) cache_inst (
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
    // RAM SIGNALS
    // ====================================================

    reg         ram_en;
    reg         ram_we;
    reg  [ADDR_WIDTH-1:0]  ram_addr;
    reg  [DATA_WIDTH-1:0] ram_data_in;

    wire [DATA_WIDTH-1:0] ram_data_out;
    wire        ram_data_valid;


    // ====================================================
    // RAM INSTANCE
    // ====================================================

    memory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(1 << ADDR_WIDTH)
    ) ram_inst (
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
    // STRIDE CANDIDATE GENERATOR
    // ====================================================

    reg        predictor_access_valid;
    reg [5:0]  predictor_access_addr;

    wire [5:0] candidate_addr;
    wire       candidate_valid;

    wire signed [6:0] current_stride;
    wire              stride_match;
    wire              history_valid;


    stride_candidate #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .PREFETCH_DISTANCE(PREFETCH_DISTANCE)
    ) predictor_inst (
        .clk             (clk),
        .rst             (rst),

        .access_valid    (predictor_access_valid),
        .access_addr     (predictor_access_addr),

        .candidate_addr  (candidate_addr),
        .candidate_valid (candidate_valid),

        .current_stride  (current_stride),
        .stride_match    (stride_match),

        .history_valid   (history_valid)
    );


    assign predicted_addr   = candidate_addr;
    assign prediction_valid = candidate_valid;


    // ====================================================
    // CANDIDATE PIPELINE REGISTERS
    //
    // Preserve both:
    //   - candidate address
    //   - address that produced candidate
    //
    // across registered feature / ML stages.
    // ====================================================

    reg [5:0] pending_candidate;
    reg [5:0] pending_current_addr;

    reg candidate_pending;


    // ====================================================
    // FEATURE GENERATOR
    // ====================================================

    reg feature_request;

    reg recent_cache_miss;
    reg previous_prefetch_useful;

    reg recent_accuracy_high;

    wire [7:0] feature_vector;
    wire       features_valid;

    feature_generator #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .REGION_BITS(REGION_BITS)
    ) feature_inst (
        .clk                      (clk),
        .rst                      (rst),

        .feature_valid            (feature_request),

        .current_addr             (pending_current_addr),
        .candidate_addr           (pending_candidate),

        .current_stride           (current_stride),
        .stride_match             (stride_match),

        .recent_cache_miss        (recent_cache_miss),
        .previous_prefetch_useful (previous_prefetch_useful),
        .recent_accuracy_high     (recent_accuracy_high),

        .features                 (feature_vector),
        .features_valid           (features_valid)
    );


    // ====================================================
    // PERCEPTRON
    // ====================================================

    reg       infer_valid;
    reg [7:0] infer_features;

    wire       decision_valid;
    wire       prefetch_decision;
    wire signed [11:0] perceptron_score;

    wire       tracker_train_valid;
    wire [7:0] tracker_train_features;
    wire       tracker_train_target;


    perceptron #(
        .FEATURE_WIDTH(FEATURE_WIDTH)
    ) perceptron_inst (
        .clk               (clk),
        .rst               (rst),

        .infer_valid       (infer_valid),
        .features          (infer_features),

        .decision_valid    (decision_valid),
        .prefetch_decision (prefetch_decision),
        .score             (perceptron_score),

        .train_valid       (tracker_train_valid),
        .train_features    (tracker_train_features),
        .train_target      (tracker_train_target)
    );


    assign ml_score    = perceptron_score;
    assign ml_decision = prefetch_decision;


    // ====================================================
    // PREFETCH TRACKER
    // ====================================================

    reg        tracker_prefetch_issued;
    reg [5:0]  tracker_prefetch_addr;
    reg [7:0]  tracker_prefetch_features;

    reg        demand_access_event;
    reg [5:0]  demand_access_addr;

    wire tracker_busy;


    prefetch_tracker #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .FEATURE_WIDTH(FEATURE_WIDTH),
        .TRACKER_ENTRIES(TRACKER_ENTRIES),
        .PREFETCH_LIFETIME(PREFETCH_LIFETIME)
    ) tracker_inst (
        .clk                     (clk),
        .rst                     (rst),

        .prefetch_issued         (tracker_prefetch_issued),
        .prefetch_addr           (tracker_prefetch_addr),
        .prefetch_features       (tracker_prefetch_features),

        .demand_access_valid     (demand_access_event),
        .demand_addr             (demand_access_addr),

        .tracker_busy            (tracker_busy),

        .train_valid             (tracker_train_valid),
        .train_features          (tracker_train_features),
        .train_target            (tracker_train_target),

        .prefetch_useful_event   (prefetch_useful_event),
        .prefetch_useless_event  (prefetch_useless_event)
    );


    // ====================================================
    // PREFETCH CONTROLLER STATES
    // ====================================================

    localparam P_IDLE     = 2'd0;
    localparam P_RAM_REQ  = 2'd1;
    localparam P_RAM_WAIT = 2'd2;
    localparam P_FILL     = 2'd3;

    reg [1:0] prefetch_state;

    reg [5:0] prefetch_addr_reg;
    reg [7:0] prefetch_features_reg;


    // ====================================================
    // ML BOOTSTRAP
    // ====================================================

    reg [3:0] bootstrap_counter;

    assign bootstrap_count = bootstrap_counter;


    // ====================================================
    // RECENT PREFETCH ACCURACY HISTORY
    //
    // Last four evaluated prefetches:
    //
    // 1 = useful
    // 0 = useless
    //
    // recent_accuracy_high = at least 2 useful results
    // among the last four outcomes.
    // ====================================================

    reg [3:0] outcome_history;
    reg [2:0] outcome_count;


    always @(*) begin

        if (outcome_count < 2) begin

            recent_accuracy_high = 1'b0;

        end

        else if (
            (
                outcome_history[0] +
                outcome_history[1] +
                outcome_history[2] +
                outcome_history[3]
            ) >= 2
        ) begin

            recent_accuracy_high = 1'b1;

        end

        else begin

            recent_accuracy_high = 1'b0;

        end

    end


    // ====================================================
    // MAIN CONTROL
    // ====================================================

    always @(posedge clk) begin

        // =================================================
        // RESET
        // =================================================

        if (rst) begin

            demand_state   <= D_IDLE;
            prefetch_state <= P_IDLE;

            req_addr <= 6'd0;
            req_data <= 16'd0;

            data_out   <= 16'd0;
            data_valid <= 1'b0;
            busy       <= 1'b0;


            // ---------------------------------------------
            // CACHE
            // ---------------------------------------------

            cache_hit_event  <= 1'b0;
            cache_miss_event <= 1'b0;

            cache_lookup_en   <= 1'b0;
            cache_lookup_addr <= 6'd0;

            cache_fill_en   <= 1'b0;
            cache_fill_addr <= 6'd0;
            cache_fill_data <= 16'd0;

            cache_update_en   <= 1'b0;
            cache_update_addr <= 6'd0;
            cache_update_data <= 16'd0;


            // ---------------------------------------------
            // RAM
            // ---------------------------------------------

            ram_en      <= 1'b0;
            ram_we      <= 1'b0;
            ram_addr    <= 6'd0;
            ram_data_in <= 16'd0;


            // ---------------------------------------------
            // PREDICTOR
            // ---------------------------------------------

            predictor_access_valid <= 1'b0;
            predictor_access_addr  <= 6'd0;


            // ---------------------------------------------
            // CANDIDATE PIPELINE
            // ---------------------------------------------

            pending_candidate    <= 6'd0;
            pending_current_addr <= 6'd0;

            candidate_pending <= 1'b0;


            // ---------------------------------------------
            // FEATURES / ML
            // ---------------------------------------------

            feature_request <= 1'b0;

            infer_valid    <= 1'b0;
            infer_features <= 8'd0;


            // ---------------------------------------------
            // TRACKER
            // ---------------------------------------------

            tracker_prefetch_issued   <= 1'b0;
            tracker_prefetch_addr     <= 6'd0;
            tracker_prefetch_features <= 8'd0;

            demand_access_event <= 1'b0;
            demand_access_addr  <= 6'd0;


            // ---------------------------------------------
            // PREFETCH
            // ---------------------------------------------

            prefetch_addr_reg     <= 6'd0;
            prefetch_features_reg <= 8'd0;

            prefetch_start_event <= 1'b0;


            // ---------------------------------------------
            // ML BOOTSTRAP / HISTORY
            // ---------------------------------------------

            bootstrap_counter <= 4'd0;

            recent_cache_miss        <= 1'b0;
            previous_prefetch_useful <= 1'b0;

            outcome_history <= 4'b0000;
            outcome_count   <= 3'd0;


            // ---------------------------------------------
            // PERFORMANCE EVENTS
            // ---------------------------------------------

            demand_ram_read_event   <= 1'b0;
            prefetch_ram_read_event <= 1'b0;

            ml_accept_event <= 1'b0;
            ml_reject_event <= 1'b0;

        end


        // =================================================
        // NORMAL OPERATION
        // =================================================

        else begin

            // =================================================
            // DEFAULT ONE-CYCLE PULSES
            // =================================================

            data_valid <= 1'b0;

            cache_hit_event  <= 1'b0;
            cache_miss_event <= 1'b0;

            cache_fill_en   <= 1'b0;
            cache_update_en <= 1'b0;

            ram_en <= 1'b0;
            ram_we <= 1'b0;

            predictor_access_valid <= 1'b0;

            feature_request <= 1'b0;
            infer_valid     <= 1'b0;

            tracker_prefetch_issued <= 1'b0;

            demand_access_event <= 1'b0;

            prefetch_start_event <= 1'b0;

            demand_ram_read_event   <= 1'b0;
            prefetch_ram_read_event <= 1'b0;

            ml_accept_event <= 1'b0;
            ml_reject_event <= 1'b0;


            // =================================================
            // PREFETCH FEEDBACK HISTORY
            // =================================================

            if (prefetch_useful_event) begin

                previous_prefetch_useful <= 1'b1;

                outcome_history <= {
                    outcome_history[2:0],
                    1'b1
                };

                if (outcome_count < 4)
                    outcome_count <= outcome_count + 1'b1;

            end

            else if (prefetch_useless_event) begin

                previous_prefetch_useful <= 1'b0;

                outcome_history <= {
                    outcome_history[2:0],
                    1'b0
                };

                if (outcome_count < 4)
                    outcome_count <= outcome_count + 1'b1;

            end


            // =================================================
            // CPU DEMAND CONTROLLER
            // =================================================

            case (demand_state)

                // =============================================
                // IDLE
                // =============================================

                D_IDLE: begin

                    busy <= 1'b0;

                    cache_lookup_en <= 1'b0;

                    if (req) begin

                        req_addr <= addr;
                        req_data <= data_in;

                        busy <= 1'b1;


                        // -------------------------------------
                        // Tracker observes every accepted
                        // CPU memory access.
                        // -------------------------------------

                        demand_access_event <= 1'b1;
                        demand_access_addr  <= addr;


                        // -------------------------------------
                        // READ
                        // -------------------------------------

                        if (!we) begin

                            predictor_access_valid <= 1'b1;
                            predictor_access_addr  <= addr;

                            cache_lookup_en   <= 1'b1;
                            cache_lookup_addr <= addr;

                            demand_state <= D_LOOKUP;

                        end


                        // -------------------------------------
                        // WRITE
                        // -------------------------------------

                        else begin

                            demand_state <= D_WRITE;

                        end

                    end

                end


                // =============================================
                // CACHE LOOKUP
                // =============================================

                D_LOOKUP: begin

                    cache_lookup_en <= 1'b0;

                    if (cache_hit) begin

                        data_out   <= cache_lookup_data;
                        data_valid <= 1'b1;

                        cache_hit_event <= 1'b1;

                        recent_cache_miss <= 1'b0;

                        busy <= 1'b0;

                        demand_state <= D_IDLE;

                    end

                    else begin

                        cache_miss_event <= 1'b1;

                        recent_cache_miss <= 1'b1;

                        demand_state <= D_RAM_REQ;

                    end

                end


                // =============================================
                // DEMAND RAM REQUEST
                // =============================================

                D_RAM_REQ: begin

                    // Demand has priority.
                    //
                    // Wait until speculative transaction
                    // is no longer active.

                    if (prefetch_state == P_IDLE) begin

                        ram_en   <= 1'b1;
                        ram_we   <= 1'b0;
                        ram_addr <= req_addr;

                        demand_ram_read_event <= 1'b1;

                        demand_state <= D_RAM_WAIT;

                    end

                end


                // =============================================
                // DEMAND RAM WAIT
                // =============================================

                D_RAM_WAIT: begin

                    // Keep request asserted until RAM
                    // produces valid data.

                    ram_en   <= 1'b1;
                    ram_we   <= 1'b0;
                    ram_addr <= req_addr;

                    if (ram_data_valid) begin

                        data_out   <= ram_data_out;
                        data_valid <= 1'b1;

                        cache_fill_en   <= 1'b1;
                        cache_fill_addr <= req_addr;
                        cache_fill_data <= ram_data_out;

                        ram_en <= 1'b0;

                        demand_state <= D_FILL;

                    end

                end


                // =============================================
                // DEMAND CACHE FILL
                // =============================================

                D_FILL: begin

                    busy <= 1'b0;

                    demand_state <= D_IDLE;

                end


                // =============================================
                // WRITE THROUGH
                // =============================================

                D_WRITE: begin

                    if (prefetch_state == P_IDLE) begin

                        ram_en      <= 1'b1;
                        ram_we      <= 1'b1;
                        ram_addr    <= req_addr;
                        ram_data_in <= req_data;

                        cache_update_en   <= 1'b1;
                        cache_update_addr <= req_addr;
                        cache_update_data <= req_data;

                        demand_state <= D_WRITE_DONE;

                    end

                end


                // =============================================
                // WRITE COMPLETE
                // =============================================

                D_WRITE_DONE: begin

                    ram_en <= 1'b0;
                    ram_we <= 1'b0;

                    busy <= 1'b0;

                    demand_state <= D_IDLE;

                end


                default: begin

                    demand_state <= D_IDLE;

                end

            endcase


            // =================================================
            // CANDIDATE → FEATURE PIPELINE
            // =================================================

            if (
                candidate_valid &&
                !candidate_pending
            ) begin

                pending_candidate <= candidate_addr;

                pending_current_addr <=
                    predictor_access_addr;

                candidate_pending <= 1'b1;

                feature_request <= 1'b1;

            end


            // =================================================
            // FEATURES → PERCEPTRON
            // =================================================

            if (
                features_valid &&
                candidate_pending
            ) begin

                infer_features <= feature_vector;

                infer_valid <= 1'b1;

            end


            // =================================================
            // ML DECISION / PREFETCH ADMISSION
            // =================================================

            if (
                decision_valid &&
                candidate_pending
            ) begin

                // ---------------------------------------------
                // Need:
                //
                // - free tracker slot
                // - idle prefetch engine
                // ---------------------------------------------

                if (
                    !tracker_busy &&
                    prefetch_state == P_IDLE
                ) begin


                    // =========================================
                    // MODE 0
                    // NO PREFETCH
                    // =========================================

                    if (PREFETCH_MODE == 0) begin

                        // Candidate intentionally ignored.

                    end


                    // =========================================
                    // MODE 1
                    // CONVENTIONAL STRIDE PREFETCH
                    // =========================================

                    else if (PREFETCH_MODE == 1) begin

                        prefetch_addr_reg <=
                            pending_candidate;

                        prefetch_features_reg <=
                            infer_features;

                        prefetch_state <= P_RAM_REQ;

                        prefetch_start_event <= 1'b1;

                    end


                    // =========================================
                    // MODE 2
                    // ML-ASSISTED
                    // =========================================

                    else begin

                        // -------------------------------------
                        // BOOTSTRAP
                        //
                        // First eight eligible candidates are
                        // always admitted to generate training
                        // examples.
                        // -------------------------------------

                        if (bootstrap_counter < 8) begin

                            prefetch_addr_reg <=
                                pending_candidate;

                            prefetch_features_reg <=
                                infer_features;

                            prefetch_state <= P_RAM_REQ;

                            prefetch_start_event <= 1'b1;

                            bootstrap_counter <=
                                bootstrap_counter + 1'b1;

                        end


                        // -------------------------------------
                        // ML ACCEPT
                        // -------------------------------------

                        else if (prefetch_decision) begin

                            ml_accept_event <= 1'b1;

                            prefetch_addr_reg <=
                                pending_candidate;

                            prefetch_features_reg <=
                                infer_features;

                            prefetch_state <= P_RAM_REQ;

                            prefetch_start_event <= 1'b1;

                        end


                        // -------------------------------------
                        // ML REJECT
                        // -------------------------------------

                        else begin

                            ml_reject_event <= 1'b1;

                        end

                    end

                end

                // Candidate has now been processed.
                candidate_pending <= 1'b0;

            end


            // =================================================
            // PREFETCH CONTROLLER
            // =================================================

            case (prefetch_state)

                // =============================================
                // IDLE
                // =============================================

                P_IDLE: begin

                    // No action.

                end


                // =============================================
                // PREFETCH RAM REQUEST
                // =============================================

                P_RAM_REQ: begin

                    // Demand traffic always has priority.
                    //
                    // Only launch speculative RAM access
                    // while demand side is not using RAM.

                    if (
                        demand_state == D_IDLE ||
                        demand_state == D_LOOKUP
                    ) begin

                        ram_en   <= 1'b1;
                        ram_we   <= 1'b0;
                        ram_addr <= prefetch_addr_reg;

                        prefetch_ram_read_event <= 1'b1;

                        prefetch_state <= P_RAM_WAIT;

                    end

                end


                // =============================================
                // PREFETCH RAM WAIT
                // =============================================

                P_RAM_WAIT: begin

                    ram_en   <= 1'b1;
                    ram_we   <= 1'b0;
                    ram_addr <= prefetch_addr_reg;

                    if (ram_data_valid) begin

                        cache_fill_en <= 1'b1;

                        cache_fill_addr <=
                            prefetch_addr_reg;

                        cache_fill_data <=
                            ram_data_out;

                        ram_en <= 1'b0;

                        prefetch_state <= P_FILL;

                    end

                end


                // =============================================
                // PREFETCH CACHE FILL COMPLETE
                // =============================================

                P_FILL: begin

                    // Data has now been inserted into cache.
                    // Register it with the feedback tracker.

                    tracker_prefetch_issued <= 1'b1;

                    tracker_prefetch_addr <=
                        prefetch_addr_reg;

                    tracker_prefetch_features <=
                        prefetch_features_reg;

                    prefetch_state <= P_IDLE;

                end


                default: begin

                    prefetch_state <= P_IDLE;

                end

            endcase

        end

    end

endmodule