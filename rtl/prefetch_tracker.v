`timescale 1ns / 1ps

module prefetch_tracker (
    input  wire       clk,
    input  wire       rst,

    // ----------------------------------------------------
    // REGISTER A NEW PREFETCH
    // ----------------------------------------------------

    input  wire       prefetch_issued,
    input  wire [5:0] prefetch_addr,
    input  wire [7:0] prefetch_features,

    // ----------------------------------------------------
    // DEMAND ACCESS FROM CPU
    // ----------------------------------------------------

    input  wire       demand_access_valid,
    input  wire [5:0] demand_addr,

    // ----------------------------------------------------
    // TRACKER STATUS
    // ----------------------------------------------------

    output reg        tracker_busy,

    // ----------------------------------------------------
    // TRAINING OUTPUT
    // ----------------------------------------------------

    output reg        train_valid,
    output reg [7:0]  train_features,
    output reg        train_target,

    // ----------------------------------------------------
    // FEEDBACK SIGNALS
    // ----------------------------------------------------

    output reg        prefetch_useful_event,
    output reg        prefetch_useless_event
);

    // Address being tracked
    reg [5:0] tracked_addr;

    // Feature vector that caused this prefetch
    reg [7:0] tracked_features;

    // Number of unrelated demand accesses observed
    reg [3:0] age;


    always @(posedge clk) begin

        if (rst) begin

            tracker_busy <= 1'b0;

            tracked_addr     <= 6'd0;
            tracked_features <= 8'd0;

            age <= 4'd0;

            train_valid    <= 1'b0;
            train_features <= 8'd0;
            train_target   <= 1'b0;

            prefetch_useful_event  <= 1'b0;
            prefetch_useless_event <= 1'b0;

        end

        else begin

            // Default one-cycle pulses
            train_valid             <= 1'b0;
            prefetch_useful_event   <= 1'b0;
            prefetch_useless_event  <= 1'b0;


            // ============================================
            // REGISTER NEW PREFETCH
            // ============================================

            if (prefetch_issued && !tracker_busy) begin

                tracked_addr     <= prefetch_addr;
                tracked_features <= prefetch_features;

                age <= 4'd0;

                tracker_busy <= 1'b1;

            end


            // ============================================
            // EVALUATE DEMAND ACCESSES
            // ============================================

            else if (tracker_busy && demand_access_valid) begin

                // ----------------------------------------
                // PREFETCH WAS USED
                // ----------------------------------------

                if (demand_addr == tracked_addr) begin

                    train_valid    <= 1'b1;
                    train_features <= tracked_features;
                    train_target   <= 1'b1;

                    prefetch_useful_event <= 1'b1;

                    tracker_busy <= 1'b0;
                    age          <= 4'd0;

                end


                // ----------------------------------------
                // PREFETCH NOT USED YET
                // ----------------------------------------

                else begin

                    // age represents the number of
                    // unrelated demand accesses already
                    // observed before this one.
                    //
                    // When age == 7, this access is the
                    // eighth unrelated demand access.
                    if (age == 4'd7) begin

                        train_valid    <= 1'b1;
                        train_features <= tracked_features;
                        train_target   <= 1'b0;

                        prefetch_useless_event <= 1'b1;

                        tracker_busy <= 1'b0;
                        age          <= 4'd0;

                    end

                    else begin

                        age <= age + 1'b1;

                    end

                end

            end

        end

    end

endmodule