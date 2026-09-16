`timescale 1ns/1ps
// Continuous control; the 35/34 -> 43/42-bit arithmetic is copied from
// coarse_rolling_sc_accumulator, with the finite 512-beat frame monitor removed.
module sync_rolling_metric (
    input logic clk, rst_n, aggregate_valid, aggregate_first,
    input logic signed [34:0] aggregate_p_re, aggregate_p_im,
    input logic [33:0] aggregate_energy,
    output logic metric_valid,
    output logic signed [42:0] rolling_p_re, rolling_p_im,
    output logic [41:0] rolling_energy,
    output logic arithmetic_overflow_sticky
);
    logic [7:0] pointer;
    logic [103:0] history;
    logic history_valid, delayed_valid, delayed_first;
    logic signed [34:0] delayed_p_re, delayed_p_im;
    logic [33:0] delayed_energy;
    logic signed [34:0] old_p_re, old_p_im;
    logic [33:0] old_energy;
    logic [8:0] fill_count;
    assign old_p_re = $signed(history[103:69]);
    assign old_p_im = $signed(history[68:34]);
    assign old_energy = history[33:0];
    sync_beat_ram #(.ADDR_BITS(8), .DATA_BITS(104), .READ_LATENCY(1)) aggregate_history (
        .clk(clk), .rst_n(rst_n), .wr_valid(aggregate_valid),
        .wr_addr(pointer), .wr_data({aggregate_p_re,aggregate_p_im,aggregate_energy}),
        .rd_valid(aggregate_valid), .rd_addr(pointer),
        .rsp_valid(history_valid), .rsp_data(history)
    );
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pointer <= '0; delayed_valid <= 0; delayed_first <= 0;
            delayed_p_re <= '0; delayed_p_im <= '0; delayed_energy <= '0;
        end else begin
            delayed_valid <= aggregate_valid;
            if (aggregate_valid) begin
                pointer <= pointer+1'b1;
                delayed_first <= aggregate_first;
                delayed_p_re <= aggregate_p_re;
                delayed_p_im <= aggregate_p_im;
                delayed_energy <= aggregate_energy;
            end
        end
    end
    always_ff @(posedge clk) begin
        logic signed [43:0] next_p_re_ext, next_p_im_ext;
        logic [42:0] next_energy_ext;
        if (!rst_n) begin
            fill_count <= 0; metric_valid <= 0;
            rolling_p_re <= 0; rolling_p_im <= 0; rolling_energy <= 0;
            arithmetic_overflow_sticky <= 0;
        end else begin
            metric_valid <= 0;
            if (delayed_valid) begin
                if (delayed_first) begin
                    next_p_re_ext = {{9{delayed_p_re[34]}},delayed_p_re};
                    next_p_im_ext = {{9{delayed_p_im[34]}},delayed_p_im};
                    next_energy_ext = {{9{1'b0}},delayed_energy};
                    fill_count <= 1;
                end else if (fill_count < 256) begin
                    next_p_re_ext = {{1{rolling_p_re[42]}},rolling_p_re} + {{9{delayed_p_re[34]}},delayed_p_re};
                    next_p_im_ext = {{1{rolling_p_im[42]}},rolling_p_im} + {{9{delayed_p_im[34]}},delayed_p_im};
                    next_energy_ext = {1'b0,rolling_energy} + {{9{1'b0}},delayed_energy};
                    fill_count <= fill_count+1'b1;
                end else begin
                    next_p_re_ext = {{1{rolling_p_re[42]}},rolling_p_re} + {{9{delayed_p_re[34]}},delayed_p_re} - {{9{old_p_re[34]}},old_p_re};
                    next_p_im_ext = {{1{rolling_p_im[42]}},rolling_p_im} + {{9{delayed_p_im[34]}},delayed_p_im} - {{9{old_p_im[34]}},old_p_im};
                    next_energy_ext = {1'b0,rolling_energy} + {{9{1'b0}},delayed_energy} - {{9{1'b0}},old_energy};
                end
                if (next_p_re_ext[43] != next_p_re_ext[42] || next_p_im_ext[43] != next_p_im_ext[42] || next_energy_ext[42]) arithmetic_overflow_sticky <= 1;
                rolling_p_re <= next_p_re_ext[42:0];
                rolling_p_im <= next_p_im_ext[42:0];
                rolling_energy <= next_energy_ext[41:0];
                if (!delayed_first && fill_count >= 255) metric_valid <= 1;
            end
        end
    end
endmodule
