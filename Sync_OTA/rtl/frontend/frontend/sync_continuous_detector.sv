`timescale 1ns/1ps
// No frame labels. All positions count accepted raw samples within an epoch.
module sync_continuous_detector (
    input logic clk, rst_n, sample_fire,
    input logic [127:0] sample_data,
    output logic candidate_valid,
    output logic [63:0] candidate_anchor,
    output logic [31:0] rejected_plateaus,
    output logic arithmetic_error,
    output logic metric_valid,
    output logic metric_qualified,
    output logic [63:0] metric_position,
    output logic signed [42:0] metric_p_re, metric_p_im,
    output logic [41:0] metric_energy
);
    logic [7:0] lag_pointer;
    logic [8:0] lag_fill;
    logic [127:0] previous_beat, current_beat;
    logic lag_valid, pair_eligible, pair_first;
    logic aggregate_valid, aggregate_first;
    logic signed [34:0] aggregate_p_re, aggregate_p_im;
    logic [33:0] aggregate_energy;
    logic corr_error, corr_ip_error, sum_error;
    logic sum_valid;
    logic signed [42:0] sum_re, sum_im;
    logic [41:0] sum_energy;
    logic run_active;
    logic [11:0] run_length;
    logic [63:0] run_first;
    logic [63:0] midpoint;
    assign arithmetic_error = corr_error || corr_ip_error || sum_error;
    assign midpoint = (run_first + metric_position - 64'd4) >> 1;
    sync_beat_ram #(.ADDR_BITS(8), .READ_LATENCY(1)) lag_history (
        .clk(clk), .rst_n(rst_n), .wr_valid(sample_fire), .wr_addr(lag_pointer),
        .wr_data(sample_data), .rd_valid(sample_fire), .rd_addr(lag_pointer),
        .rsp_valid(lag_valid), .rsp_data(previous_beat)
    );
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lag_pointer <= 0; lag_fill <= 0; current_beat <= 0;
            pair_eligible <= 0; pair_first <= 0;
        end else if (sample_fire) begin
            lag_pointer <= lag_pointer+1'b1;
            if (lag_fill < 257) lag_fill <= lag_fill+1'b1;
            pair_eligible <= lag_fill >= 256;
            pair_first <= lag_fill == 256;
            current_beat <= sample_data;
        end
    end
    coarse_corr_energy_4lane correlation (
        .clk(clk), .rst_n(rst_n), .pair_valid(lag_valid && pair_eligible),
        .pair_first(pair_first), .pair_last(1'b0), .pair_current_data(current_beat),
        .pair_delayed_data(previous_beat), .pair_frame_id(32'd0),
        .pair_current_base_sample_index(32'd0), .pair_context_valid(1'b1),
        .aggregate_valid(aggregate_valid), .aggregate_first(aggregate_first),
        .aggregate_last(), .aggregate_p_re(aggregate_p_re), .aggregate_p_im(aggregate_p_im),
        .aggregate_energy(aggregate_energy), .aggregate_frame_id(),
        .aggregate_current_base_sample_index(), .aggregate_context_valid(),
        .arithmetic_overflow_sticky(corr_error), .ip_protocol_error_sticky(corr_ip_error)
    );
    sync_rolling_metric rolling (
        .clk(clk), .rst_n(rst_n), .aggregate_valid(aggregate_valid),
        .aggregate_first(aggregate_first), .aggregate_p_re(aggregate_p_re),
        .aggregate_p_im(aggregate_p_im), .aggregate_energy(aggregate_energy),
        .metric_valid(sum_valid), .rolling_p_re(sum_re), .rolling_p_im(sum_im),
        .rolling_energy(sum_energy), .arithmetic_overflow_sticky(sum_error)
    );
    coarse_metric_threshold threshold (
        .clk(clk), .rst_n(rst_n), .metric_in_valid(sum_valid),
        .metric_in_last(1'b0), .metric_in_index(9'd0), .metric_in_p_re(sum_re),
        .metric_in_p_im(sum_im), .metric_in_energy(sum_energy),
        .metric_out_valid(metric_valid), .metric_out_last(), .metric_out_index(),
        .metric_out_p_re(metric_p_re), .metric_out_p_im(metric_p_im),
        .metric_out_energy(metric_energy), .metric_out_qualified(metric_qualified),
        .metric_out_p_magnitude_squared(), .metric_out_energy_squared(),
        .metric_out_threshold_lhs(), .metric_out_threshold_rhs()
    );
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            metric_position <= 0; run_active <= 0; run_length <= 0;
            run_first <= 0; candidate_valid <= 0; candidate_anchor <= 0;
            rejected_plateaus <= 0;
        end else begin
            candidate_valid <= 0;
            if (metric_valid) begin
                metric_position <= metric_position+64'd4;
                if (metric_qualified) begin
                    if (!run_active) begin
                        run_active <= 1; run_first <= metric_position; run_length <= 1;
                    end else if (run_length < 1025) run_length <= run_length+1'b1;
                end else if (run_active) begin
                    run_active <= 0;
                    if (run_length >= 4 && run_length <= 1024 && midpoint >= 512 && !arithmetic_error) begin
                        candidate_valid <= 1;
                        candidate_anchor <= (midpoint-64'd256) & ~64'd3;
                    end else rejected_plateaus <= rejected_plateaus+1'b1;
                    run_length <= 0;
                end
            end
        end
    end
endmodule
