`timescale 1ns / 1ps

module tb_benchmark;

    // ====================================================
    // CONFIGURATION
    //
    // 0 = No prefetch
    // 1 = Conventional stride prefetch
    // 2 = ML-assisted prefetch
    // ====================================================

    parameter PREFETCH_MODE = 2;

    parameter NUM_READS = 128;


    // ====================================================
    // DUT SIGNALS
    // ====================================================

    reg clk;
    reg rst;

    reg         req;
    reg         we;
    reg  [5:0]  addr;
    reg  [15:0] data_in;

    wire [15:0] data_out;
    wire        data_valid;
    wire        busy;

    wire cache_hit_event;
    wire cache_miss_event;

    wire [5:0] predicted_addr;
    wire       prediction_valid;

    wire signed [11:0] ml_score;
    wire               ml_decision;

    wire prefetch_start_event;
    wire prefetch_useful_event;
    wire prefetch_useless_event;

    wire [3:0] bootstrap_count;

    wire demand_ram_read_event;
    wire prefetch_ram_read_event;

    wire ml_accept_event;
    wire ml_reject_event;


    // ====================================================
    // DUT
    // ====================================================

    ai_memory_top #(
        .PREFETCH_MODE(PREFETCH_MODE),
    
        .ADDR_WIDTH(6),
        .DATA_WIDTH(16),
    
        .CACHE_ENTRIES(4),
    
        .TRACKER_ENTRIES(4),
        .PREFETCH_LIFETIME(8),
    
        .PREFETCH_DISTANCE(2),
    
        .REGION_BITS(4),
    
        .FEATURE_WIDTH(8)
    ) dut (
        .clk                     (clk),
        .rst                     (rst),

        .req                     (req),
        .we                      (we),
        .addr                    (addr),
        .data_in                 (data_in),

        .data_out                (data_out),
        .data_valid              (data_valid),
        .busy                    (busy),

        .cache_hit_event         (cache_hit_event),
        .cache_miss_event        (cache_miss_event),

        .predicted_addr          (predicted_addr),
        .prediction_valid        (prediction_valid),

        .ml_score                (ml_score),
        .ml_decision             (ml_decision),

        .prefetch_start_event    (prefetch_start_event),

        .prefetch_useful_event   (prefetch_useful_event),
        .prefetch_useless_event  (prefetch_useless_event),

        .bootstrap_count         (bootstrap_count),

        .demand_ram_read_event   (demand_ram_read_event),
        .prefetch_ram_read_event (prefetch_ram_read_event),

        .ml_accept_event         (ml_accept_event),
        .ml_reject_event         (ml_reject_event)
    );


    // ====================================================
    // CLOCK
    // ====================================================

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    // ====================================================
    // GLOBAL CLOCK COUNTER
    // ====================================================

    integer global_cycle;

    always @(posedge clk) begin

        if (rst)
            global_cycle <= 0;
        else
            global_cycle <= global_cycle + 1;

    end


    // ====================================================
    // BENCHMARK COUNTERS
    // ====================================================

    integer hits;
    integer misses;

    integer prefetches;
    integer useful;
    integer useless;

    integer demand_ram_reads;
    integer prefetch_ram_reads;

    integer ml_accepts;
    integer ml_rejects;

    integer completed_reads;

    integer total_latency;
    integer min_latency;
    integer max_latency;

    integer workload_start_cycle;
    integer workload_end_cycle;
    integer workload_cycles;

    integer errors;


    // ====================================================
    // EVENT COUNTERS
    // ====================================================

    always @(posedge clk) begin

        if (!rst) begin

            if (cache_hit_event)
                hits = hits + 1;

            if (cache_miss_event)
                misses = misses + 1;

            if (prefetch_start_event)
                prefetches = prefetches + 1;

            if (prefetch_useful_event)
                useful = useful + 1;

            if (prefetch_useless_event)
                useless = useless + 1;

            if (demand_ram_read_event)
                demand_ram_reads = demand_ram_reads + 1;

            if (prefetch_ram_read_event)
                prefetch_ram_reads = prefetch_ram_reads + 1;

            if (ml_accept_event)
                ml_accepts = ml_accepts + 1;

            if (ml_reject_event)
                ml_rejects = ml_rejects + 1;

        end

    end


    // ====================================================
    // RESET METRICS
    // ====================================================

    task clear_metrics;

        begin

            hits = 0;
            misses = 0;

            prefetches = 0;
            useful = 0;
            useless = 0;

            demand_ram_reads = 0;
            prefetch_ram_reads = 0;

            ml_accepts = 0;
            ml_rejects = 0;

            completed_reads = 0;

            total_latency = 0;
            min_latency = 999999;
            max_latency = 0;

            workload_start_cycle = 0;
            workload_end_cycle = 0;
            workload_cycles = 0;

            errors = 0;

        end

    endtask


    // ====================================================
    // RESET DUT
    // ====================================================

    task reset_dut;

        begin

            req     = 1'b0;
            we      = 1'b0;
            addr    = 6'd0;
            data_in = 16'd0;

            rst = 1'b1;

            repeat (3)
                @(posedge clk);

            @(negedge clk);
            rst = 1'b0;

            repeat (2)
                @(posedge clk);

        end

    endtask


    // ====================================================
    // WRITE MEMORY
    // ====================================================

    task write_mem;

        input [5:0]  a;
        input [15:0] d;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req     = 1'b1;
            we      = 1'b1;
            addr    = a;
            data_in = d;

            @(negedge clk);

            req = 1'b0;
            we  = 1'b0;

            while (busy)
                @(negedge clk);

        end

    endtask


    // ====================================================
    // INITIALIZE ENTIRE RAM
    //
    // RAM[x] = 0x1000 + x
    // ====================================================

    integer init_i;

    task initialize_ram;

        begin

            for (init_i = 0; init_i < 64; init_i = init_i + 1) begin

                write_mem(
                    init_i[5:0],
                    16'h1000 + init_i
                );

            end

        end

    endtask


    // ====================================================
    // READ MEMORY AND MEASURE LATENCY
    // ====================================================

    task benchmark_read;

        input [5:0] a;

        integer request_cycle;
        integer response_cycle;
        integer latency;

        reg [15:0] expected_data;

        begin

            while (busy)
                @(negedge clk);

            @(negedge clk);

            req  = 1'b1;
            we   = 1'b0;
            addr = a;

            request_cycle = global_cycle;

            @(negedge clk);

            req = 1'b0;


            // Wait for response.
            while (!data_valid)
                @(negedge clk);


            response_cycle = global_cycle;

            latency = response_cycle - request_cycle;

            completed_reads = completed_reads + 1;
            total_latency   = total_latency + latency;


            if (latency < min_latency)
                min_latency = latency;

            if (latency > max_latency)
                max_latency = latency;


            // --------------------------------------------
            // DATA CORRECTNESS CHECK
            // --------------------------------------------

            expected_data = 16'h1000 + a;

            if (data_out !== expected_data) begin

                errors = errors + 1;

                $display(
                    "ERROR: addr=%0d expected=%h received=%h",
                    a,
                    expected_data,
                    data_out
                );

            end

        end

    endtask


    // ====================================================
    // WAIT FOR CURRENT MEMORY ACTIVITY
    //
    // This does not force unresolved tracker entries to
    // timeout because timeout is demand-access based.
    // It merely lets registered event pulses settle.
    // ====================================================

    task settle_pipeline;

        begin

            while (busy)
                @(posedge clk);

            repeat (20)
                @(posedge clk);

        end

    endtask


    // ====================================================
    // RESULT PRINTER
    // ====================================================

    task print_results;

        input integer workload_id;

        real hit_rate;
        real avg_latency;
        real throughput;
        real prefetch_accuracy;

        integer evaluated_prefetches;
        integer total_ram_reads;

        begin

            workload_end_cycle = global_cycle;

            workload_cycles =
                workload_end_cycle - workload_start_cycle;

            evaluated_prefetches =
                useful + useless;

            total_ram_reads =
                demand_ram_reads + prefetch_ram_reads;


            if ((hits + misses) > 0)
                hit_rate =
                    (100.0 * hits) /
                    (hits + misses);
            else
                hit_rate = 0.0;


            if (completed_reads > 0)
                avg_latency =
                    (1.0 * total_latency) /
                    completed_reads;
            else
                avg_latency = 0.0;


            if (workload_cycles > 0)
                throughput =
                    (1.0 * completed_reads) /
                    workload_cycles;
            else
                throughput = 0.0;


            if (evaluated_prefetches > 0)
                prefetch_accuracy =
                    (100.0 * useful) /
                    evaluated_prefetches;
            else
                prefetch_accuracy = 0.0;


            $display("");
            $display("============================================================");
            $display("BENCHMARK RESULTS");
            $display("============================================================");

            $display("Prefetch mode           : %0d", PREFETCH_MODE);
            $display("Workload ID             : %0d", workload_id);

            $display("------------------------------------------------------------");

            $display("Demand reads            : %0d", completed_reads);
            $display("Workload cycles         : %0d", workload_cycles);

            $display("Average latency         : %0.3f cycles", avg_latency);
            $display("Minimum latency         : %0d cycles", min_latency);
            $display("Maximum latency         : %0d cycles", max_latency);

            $display("Throughput              : %0.6f reads/cycle", throughput);

            $display("------------------------------------------------------------");

            $display("Cache hits              : %0d", hits);
            $display("Cache misses            : %0d", misses);
            $display("Cache hit rate          : %0.2f %%", hit_rate);

            $display("------------------------------------------------------------");

            $display("Demand RAM reads        : %0d", demand_ram_reads);
            $display("Prefetch RAM reads      : %0d", prefetch_ram_reads);
            $display("Total RAM reads         : %0d", total_ram_reads);

            $display("------------------------------------------------------------");

            $display("Prefetches issued       : %0d", prefetches);
            $display("Useful prefetches       : %0d", useful);
            $display("Useless prefetches      : %0d", useless);
            $display("Evaluated prefetches    : %0d", evaluated_prefetches);
            $display("Prefetch accuracy       : %0.2f %%", prefetch_accuracy);

            $display("------------------------------------------------------------");

            $display("ML accepts              : %0d", ml_accepts);
            $display("ML rejects              : %0d", ml_rejects);
            $display("Bootstrap count         : %0d", bootstrap_count);

            $display("------------------------------------------------------------");

            $display("Data errors             : %0d", errors);

            $display("============================================================");
            $display("");

        end

    endtask


    // ====================================================
    // PREPARE A FRESH WORKLOAD
    //
    // Important:
    // Reset clears:
    //   cache
    //   predictor
    //   perceptron weights
    //   tracker
    //   bootstrap state
    //
    // RAM is then reinitialized.
    //
    // Metrics are cleared AFTER initialization so writes
    // do not affect benchmark results.
    // ====================================================

    task prepare_workload;

        begin

            reset_dut();

            initialize_ram();

            clear_metrics();

            workload_start_cycle = global_cycle;

        end

    endtask


    // ====================================================
    // WORKLOAD 1
    // SEQUENTIAL
    //
    // 0..31 repeated four times = 128 reads
    // ====================================================

    integer w1_i;

    task workload_sequential;

        begin

            prepare_workload();

            $display("");
            $display("RUNNING WORKLOAD 1: SEQUENTIAL");

            for (w1_i = 0; w1_i < NUM_READS; w1_i = w1_i + 1) begin

                benchmark_read(
                    w1_i % 32
                );

            end

            settle_pipeline();

            print_results(1);

        end

    endtask


    // ====================================================
    // WORKLOAD 2
    // FIXED STRIDE +2
    //
    // 0,2,4,...,30 repeated
    // ====================================================

    integer w2_i;
    integer w2_addr;

    task workload_stride2;

        begin

            prepare_workload();

            $display("");
            $display("RUNNING WORKLOAD 2: STRIDE +2");

            for (w2_i = 0; w2_i < NUM_READS; w2_i = w2_i + 1) begin

                w2_addr = (w2_i * 2) % 32;

                benchmark_read(
                    w2_addr[5:0]
                );

            end

            settle_pipeline();

            print_results(2);

        end

    endtask


    // ====================================================
    // WORKLOAD 3
    // REVERSE SEQUENTIAL
    //
    // 31,30,...,0 repeated
    // ====================================================

    integer w3_i;
    integer w3_addr;

    task workload_reverse;

        begin

            prepare_workload();

            $display("");
            $display("RUNNING WORKLOAD 3: REVERSE");

            for (w3_i = 0; w3_i < NUM_READS; w3_i = w3_i + 1) begin

                w3_addr =
                    31 - (w3_i % 32);

                benchmark_read(
                    w3_addr[5:0]
                );

            end

            settle_pipeline();

            print_results(3);

        end

    endtask


    // ====================================================
    // WORKLOAD 4
    // MIXED LOCALITY
    //
    // Mostly short sequential regions interrupted by
    // jumps.
    //
    // 16-address pattern repeated 8 times = 128 reads.
    // ====================================================

    reg [5:0] mixed_trace [0:15];

    integer w4_i;

    task workload_mixed;

        begin

            mixed_trace[0]  = 6'd0;
            mixed_trace[1]  = 6'd1;
            mixed_trace[2]  = 6'd2;
            mixed_trace[3]  = 6'd3;

            mixed_trace[4]  = 6'd20;

            mixed_trace[5]  = 6'd8;
            mixed_trace[6]  = 6'd9;
            mixed_trace[7]  = 6'd10;
            mixed_trace[8]  = 6'd11;

            mixed_trace[9]  = 6'd45;

            mixed_trace[10] = 6'd16;
            mixed_trace[11] = 6'd17;
            mixed_trace[12] = 6'd18;
            mixed_trace[13] = 6'd19;

            mixed_trace[14] = 6'd5;
            mixed_trace[15] = 6'd24;


            prepare_workload();

            $display("");
            $display("RUNNING WORKLOAD 4: MIXED");

            for (w4_i = 0; w4_i < NUM_READS; w4_i = w4_i + 1) begin

                benchmark_read(
                    mixed_trace[w4_i % 16]
                );

            end

            settle_pipeline();

            print_results(4);

        end

    endtask


    // ====================================================
    // WORKLOAD 5
    // DETERMINISTIC IRREGULAR / RANDOM-LIKE TRACE
    //
    // Fixed sequence for reproducibility.
    // ====================================================

    reg [5:0] random_trace [0:31];

    integer w5_i;

    task workload_random;

        begin

            random_trace[0]  = 6'd3;
            random_trace[1]  = 6'd41;
            random_trace[2]  = 6'd17;
            random_trace[3]  = 6'd52;
            random_trace[4]  = 6'd8;
            random_trace[5]  = 6'd29;
            random_trace[6]  = 6'd60;
            random_trace[7]  = 6'd1;

            random_trace[8]  = 6'd34;
            random_trace[9]  = 6'd12;
            random_trace[10] = 6'd48;
            random_trace[11] = 6'd22;
            random_trace[12] = 6'd5;
            random_trace[13] = 6'd55;
            random_trace[14] = 6'd26;
            random_trace[15] = 6'd39;

            random_trace[16] = 6'd14;
            random_trace[17] = 6'd63;
            random_trace[18] = 6'd7;
            random_trace[19] = 6'd31;
            random_trace[20] = 6'd46;
            random_trace[21] = 6'd19;
            random_trace[22] = 6'd58;
            random_trace[23] = 6'd10;

            random_trace[24] = 6'd37;
            random_trace[25] = 6'd0;
            random_trace[26] = 6'd50;
            random_trace[27] = 6'd24;
            random_trace[28] = 6'd43;
            random_trace[29] = 6'd15;
            random_trace[30] = 6'd57;
            random_trace[31] = 6'd28;


            prepare_workload();

            $display("");
            $display("RUNNING WORKLOAD 5: IRREGULAR");

            for (w5_i = 0; w5_i < NUM_READS; w5_i = w5_i + 1) begin

                benchmark_read(
                    random_trace[w5_i % 32]
                );

            end

            settle_pipeline();

            print_results(5);

        end

    endtask


    // ====================================================
    // MAIN
    // ====================================================

    initial begin

        rst     = 1'b1;

        req     = 1'b0;
        we      = 1'b0;
        addr    = 6'd0;
        data_in = 16'd0;

        global_cycle = 0;

        clear_metrics();


        $display("");
        $display("############################################################");
        $display("AI-ASSISTED MEMORY BENCHMARK");
        $display("############################################################");
        $display("PREFETCH_MODE = %0d", PREFETCH_MODE);
        $display("READS/WORKLOAD = %0d", NUM_READS);
        $display("############################################################");


        workload_sequential();

        workload_stride2();

        workload_reverse();

        workload_mixed();

        workload_random();


        $display("");
        $display("############################################################");
        $display("ALL BENCHMARKS COMPLETE");
        $display("############################################################");

        #50;

        $finish;

    end

endmodule