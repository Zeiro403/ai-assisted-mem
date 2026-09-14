`timescale 1ns / 1ps

module ai_memory_top (
    input  wire        clk,
    input  wire        rst,

    input  wire        req,
    input  wire        we,
    input  wire [5:0]  addr,
    input  wire [15:0] data_in,

    output reg  [15:0] data_out,
    output reg         data_valid,
    output reg         busy,

    output reg         cache_hit_event,
    output reg         cache_miss_event,

    output wire [5:0]  predicted_addr,
    output wire        prediction_valid,

    output wire signed [11:0] ml_score,
    output wire        ml_decision,

    output reg         prefetch_start_event,

    output wire        prefetch_useful_event,
    output wire        prefetch_useless_event,

    output wire [3:0]  bootstrap_count
);

    // ====================================================
    // DEMAND CONTROLLER STATES
    // ====================================================

    localparam D_IDLE     = 3'd0;
    localparam D_LOOKUP   = 3'd1;
    localparam D_RAM_REQ  = 3'd2;
    localparam D_RAM_WAIT = 3'd3;
    localparam D_FILL     = 3'd4;
    localparam D_WRITE    = 3'd5;
    localparam D_WRITE_DONE = 3'd6;

    reg [2:0] demand_state;

    // ====================================================
    // LATCHED CPU REQUEST
    // ====================================================

    reg [5:0]  req_addr;
    reg [15:0] req_data;

    // ====================================================
    // CACHE
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
    
    reg [5:0] pending_current_addr;

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
    // RAM
    // ====================================================

    reg         ram_en;
    reg         ram_we;
    reg  [5:0]  ram_addr;
    reg  [15:0] ram_data_in;

    wire [15:0] ram_data_out;
    wire        ram_data_valid;

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
    // STRIDE PREDICTOR
    // ====================================================

    reg         predictor_access_valid;
    reg  [5:0]  predictor_access_addr;

    wire [5:0] candidate_addr;
    wire       candidate_valid;

    wire signed [6:0] current_stride;
    wire              stride_match;
    wire              history_valid;

    stride_candidate predictor_inst (
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
    // FEATURE GENERATOR
    // ====================================================

    reg feature_request;

    reg recent_cache_miss;
    reg previous_prefetch_useful;
    reg recent_accuracy_high;

    wire [7:0] feature_vector;
    wire       features_valid;

    feature_generator feature_inst (
        .clk                      (clk),
        .rst                      (rst),

        .feature_valid            (feature_request),

        .current_addr             (pending_current_addr),
        .candidate_addr           (candidate_addr),

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

    reg        infer_valid;
    reg [7:0]  infer_features;

    wire       decision_valid;
    wire       prefetch_decision;
    wire signed [11:0] perceptron_score;

    wire       tracker_train_valid;
    wire [7:0] tracker_train_features;
    wire       tracker_train_target;

    perceptron perceptron_inst (
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

    prefetch_tracker tracker_inst (
        .clk                    (clk),
        .rst                    (rst),

        .prefetch_issued        (tracker_prefetch_issued),
        .prefetch_addr          (tracker_prefetch_addr),
        .prefetch_features      (tracker_prefetch_features),

        .demand_access_valid    (demand_access_event),
        .demand_addr            (demand_access_addr),

        .tracker_busy           (tracker_busy),

        .train_valid            (tracker_train_valid),
        .train_features         (tracker_train_features),
        .train_target           (tracker_train_target),

        .prefetch_useful_event  (prefetch_useful_event),
        .prefetch_useless_event (prefetch_useless_event)
    );

    // ====================================================
    // PREFETCH STATE
    // ====================================================

    localparam P_IDLE     = 2'd0;
    localparam P_RAM_REQ  = 2'd1;
    localparam P_RAM_WAIT = 2'd2;
    localparam P_FILL     = 2'd3;

    reg [1:0] prefetch_state;

    reg [5:0] prefetch_addr_reg;
    reg [7:0] prefetch_features_reg;

    reg [3:0] bootstrap_counter;

    assign bootstrap_count = bootstrap_counter;

    // ====================================================
    // FEATURE / INFERENCE PIPELINE
    // ====================================================

    reg [5:0] pending_candidate;

    // Candidate must survive across registered stages.
    reg candidate_pending;

    // ====================================================
    // SIMPLE RECENT ACCURACY
    //
    // Four-bit history:
    // 1 = useful
    // 0 = useless
    //
    // accuracy_high = at least 2 useful results out of
    // last 4 evaluated outcomes.
    // ====================================================

    reg [3:0] outcome_history;
    reg [2:0] outcome_count;

    always @(*) begin

        if (outcome_count < 2)
            recent_accuracy_high = 1'b0;
        else if (
            outcome_history[0] +
            outcome_history[1] +
            outcome_history[2] +
            outcome_history[3] >= 2
        )
            recent_accuracy_high = 1'b1;
        else
            recent_accuracy_high = 1'b0;

    end

    // ====================================================
    // MAIN SEQUENTIAL CONTROL
    // ====================================================

    always @(posedge clk) begin

        if (rst) begin

            demand_state   <= D_IDLE;
            prefetch_state <= P_IDLE;

            req_addr <= 0;
            req_data <= 0;

            data_out   <= 0;
            data_valid <= 0;
            busy       <= 0;

            cache_hit_event  <= 0;
            cache_miss_event <= 0;

            cache_lookup_en   <= 0;
            cache_lookup_addr <= 0;

            cache_fill_en   <= 0;
            cache_fill_addr <= 0;
            cache_fill_data <= 0;

            cache_update_en   <= 0;
            cache_update_addr <= 0;
            cache_update_data <= 0;
            
            pending_current_addr <= 6'd0;

            ram_en      <= 0;
            ram_we      <= 0;
            ram_addr    <= 0;
            ram_data_in <= 0;

            predictor_access_valid <= 0;
            predictor_access_addr  <= 0;

            feature_request <= 0;

            infer_valid    <= 0;
            infer_features <= 0;

            tracker_prefetch_issued   <= 0;
            tracker_prefetch_addr     <= 0;
            tracker_prefetch_features <= 0;

            demand_access_event <= 0;
            demand_access_addr  <= 0;

            prefetch_addr_reg     <= 0;
            prefetch_features_reg <= 0;

            pending_candidate <= 0;
            candidate_pending <= 0;

            bootstrap_counter <= 0;

            recent_cache_miss        <= 0;
            previous_prefetch_useful <= 0;

            outcome_history <= 0;
            outcome_count   <= 0;

            prefetch_start_event <= 0;

        end

        else begin

            // ============================================
            // DEFAULT ONE-CYCLE SIGNALS
            // ============================================

            data_valid <= 0;

            cache_hit_event  <= 0;
            cache_miss_event <= 0;

            cache_fill_en   <= 0;
            cache_update_en <= 0;

            ram_en <= 0;

            predictor_access_valid <= 0;

            feature_request <= 0;
            infer_valid     <= 0;

            tracker_prefetch_issued <= 0;

            demand_access_event <= 0;

            prefetch_start_event <= 0;

            // ============================================
            // TRACK PREFETCH OUTCOMES
            // ============================================

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

            // ============================================
            // CPU DEMAND CONTROLLER
            // ============================================

            case (demand_state)

                D_IDLE: begin

                    busy            <= 0;
                    cache_lookup_en <= 0;

                    if (req) begin

                        req_addr <= addr;
                        req_data <= data_in;

                        busy <= 1;

                        // Every accepted CPU access is
                        // visible to tracker.
                        demand_access_event <= 1;
                        demand_access_addr  <= addr;

                        // Only reads are used to learn
                        // access patterns for prefetching.
                        if (!we) begin

                            predictor_access_valid <= 1;
                            predictor_access_addr  <= addr;

                            cache_lookup_en   <= 1;
                            cache_lookup_addr <= addr;

                            demand_state <= D_LOOKUP;

                        end

                        else begin

                            demand_state <= D_WRITE;

                        end

                    end

                end

                // ----------------------------------------
                // CACHE LOOKUP
                // ----------------------------------------

                D_LOOKUP: begin

                    cache_lookup_en <= 0;

                    if (cache_hit) begin

                        data_out   <= cache_lookup_data;
                        data_valid <= 1;

                        cache_hit_event <= 1;
                        recent_cache_miss <= 0;

                        busy <= 0;
                        demand_state <= D_IDLE;

                    end

                    else begin

                        cache_miss_event <= 1;
                        recent_cache_miss <= 1;

                        demand_state <= D_RAM_REQ;

                    end

                end

                // ----------------------------------------
                // REQUEST DEMAND RAM READ
                // ----------------------------------------

                D_RAM_REQ: begin

                    // Demand always gets priority.
                    //
                    // Wait until no speculative RAM
                    // transaction is active.
                    if (prefetch_state == P_IDLE) begin

                        ram_en   <= 1'b1;
                        ram_we   <= 1'b0;
                        ram_addr <= req_addr;

                        demand_state <= D_RAM_WAIT;

                    end

                end

                // ----------------------------------------
                // WAIT FOR DEMAND RAM
                // ----------------------------------------

                D_RAM_WAIT: begin
                
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

                // ----------------------------------------
                // DEMAND CACHE FILL COMPLETE
                // ----------------------------------------

                D_FILL: begin

                    busy <= 0;
                    demand_state <= D_IDLE;

                end

                // ----------------------------------------
                // WRITE THROUGH
                // ----------------------------------------

                D_WRITE: begin

                    // Do not collide with speculative RAM.
                    if (prefetch_state == P_IDLE) begin

                        ram_en      <= 1;
                        ram_we      <= 1;
                        ram_addr    <= req_addr;
                        ram_data_in <= req_data;

                        cache_update_en   <= 1;
                        cache_update_addr <= req_addr;
                        cache_update_data <= req_data;
                        
                        demand_state <= D_WRITE_DONE;

                    end

                end
                
                D_WRITE_DONE: begin

                    ram_en <= 1'b0;
                    ram_we <= 1'b0;
                
                    busy <= 1'b0;
                
                    demand_state <= D_IDLE;
                
                end

                default:
                    demand_state <= D_IDLE;

            endcase

            // ============================================
            // CANDIDATE → FEATURE PIPELINE
            // ============================================

            if (candidate_valid && !candidate_pending) begin

                pending_candidate <= candidate_addr;
                pending_current_addr <= predictor_access_addr;
                
                candidate_pending <= 1;

                feature_request <= 1;

            end

            // ============================================
            // FEATURES → PERCEPTRON
            // ============================================

            if (features_valid && candidate_pending) begin

                infer_features <= feature_vector;
                infer_valid    <= 1;

            end

            // ============================================
            // ML DECISION → PREFETCH REQUEST
            // ============================================

            if (decision_valid && candidate_pending) begin

                // Eligible only if nothing else is
                // currently being tracked/prefetched.
                if (
                    !tracker_busy &&
                    prefetch_state == P_IDLE
                ) begin

                    // First 8 opportunities form bootstrap.
                    if (
                        bootstrap_counter < 8 ||
                        prefetch_decision
                    ) begin

                        prefetch_addr_reg     <= pending_candidate;
                        prefetch_features_reg <= infer_features;

                        prefetch_state <= P_RAM_REQ;

                        prefetch_start_event <= 1;

                        if (bootstrap_counter < 8)
                            bootstrap_counter <=
                                bootstrap_counter + 1'b1;

                    end

                end

                candidate_pending <= 0;

            end

            // ============================================
            // PREFETCH ENGINE
            // ============================================

            case (prefetch_state)

                P_IDLE: begin
                    // Nothing to do.
                end

                // ----------------------------------------
                // ISSUE PREFETCH RAM READ
                // ----------------------------------------

                P_RAM_REQ: begin

                    // Never use RAM while demand path
                    // requires it.
                    if (
                        demand_state == D_IDLE ||
                        demand_state == D_LOOKUP
                    ) begin

                        ram_en   <= 1;
                        ram_we   <= 0;
                        ram_addr <= prefetch_addr_reg;

                        prefetch_state <= P_RAM_WAIT;

                    end

                end

                // ----------------------------------------
                // WAIT FOR PREFETCH DATA
                // ----------------------------------------

                P_RAM_WAIT: begin

                    ram_en   <= 1'b1;
                    ram_we   <= 1'b0;
                    ram_addr <= prefetch_addr_reg;

                    if (ram_data_valid) begin

                        cache_fill_en   <= 1;
                        cache_fill_addr <= prefetch_addr_reg;
                        cache_fill_data <= ram_data_out;

                        ram_en <= 1'b0;

                        prefetch_state <= P_FILL;

                    end

                end

                // ----------------------------------------
                // PREFETCH IS NOW IN CACHE
                // ----------------------------------------

                P_FILL: begin

                    tracker_prefetch_issued   <= 1;
                    tracker_prefetch_addr     <= prefetch_addr_reg;
                    tracker_prefetch_features <=
                        prefetch_features_reg;

                    prefetch_state <= P_IDLE;

                end

                default:
                    prefetch_state <= P_IDLE;

            endcase

        end

    end

endmodule