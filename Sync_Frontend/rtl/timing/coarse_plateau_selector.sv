`timescale 1ns/1ps

module coarse_plateau_selector #(
  parameter int unsigned SEARCH_POINTS = 257,
  parameter int unsigned MINIMUM_RUN_BEATS = 4
) (
  input  logic clk,
  input  logic rst_n,

  input  logic metric_valid,
  input  logic [8:0] metric_index,
  input  logic metric_qualified,
  input  logic metric_last,

  output logic selection_done,
  output logic selection_found,
  output logic selection_ambiguity,
  output logic signed [31:0] selected_start_sample,
  output logic [8:0] selected_plateau_beats,
  output logic signed [10:0] safe_first_trace_index,
  output logic signed [10:0] safe_last_trace_index,
  output logic protocol_error_sticky
);
  logic run_active;
  logic [8:0] current_run_start;
  logic [8:0] current_run_length;
  logic first_run_found;
  logic [8:0] first_run_start;
  logic [8:0] first_run_end;
  logic [8:0] first_run_length;
  logic ambiguity_state;
  logic [8:0] expected_metric_index;

  logic close_run;
  logic close_eligible;
  logic [8:0] close_start;
  logic [8:0] close_end;
  logic [8:0] close_length;
  logic effective_first_found;
  logic [8:0] effective_first_start;
  logic [8:0] effective_first_end;
  logic [8:0] effective_first_length;
  logic effective_ambiguity;

  initial begin
    if (SEARCH_POINTS != 257)
      $error("The frozen T04 search contains exactly 257 metric points");
    if (MINIMUM_RUN_BEATS != 4)
      $error("The frozen T04 plateau requires exactly four beats");
  end

  function automatic logic signed [10:0] selected_beat_from_run(
      input logic [8:0] run_start,
      input logic [8:0] run_end);
    logic signed [10:0] z;
    logic signed [10:0] magnitude;
    begin
      z = $signed({1'b0, run_start}) +
          $signed({1'b0, run_end}) - 11'sd256;
      if (z >= 0)
        selected_beat_from_run = (z + 1) >>> 1;
      else begin
        magnitude = -z;
        selected_beat_from_run = -((magnitude + 1) >>> 1);
      end
    end
  endfunction

  always_comb begin
    close_run = 1'b0;
    close_start = '0;
    close_end = '0;
    close_length = '0;

    if (metric_valid) begin
      if (metric_qualified && metric_last) begin
        close_run = 1'b1;
        close_start = run_active ? current_run_start : metric_index;
        close_end = metric_index;
        close_length = run_active ?
            (current_run_length + 1'b1) : 9'd1;
      end else if (!metric_qualified && run_active) begin
        close_run = 1'b1;
        close_start = current_run_start;
        close_end = metric_index - 1'b1;
        close_length = current_run_length;
      end
    end

    close_eligible = close_run &&
        (close_length >= MINIMUM_RUN_BEATS);
    effective_first_found = first_run_found || close_eligible;
    effective_first_start = first_run_found ?
        first_run_start : close_start;
    effective_first_end = first_run_found ?
        first_run_end : close_end;
    effective_first_length = first_run_found ?
        first_run_length : close_length;
    effective_ambiguity = ambiguity_state ||
        (close_eligible && first_run_found);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      run_active <= 1'b0;
      current_run_start <= '0;
      current_run_length <= '0;
      first_run_found <= 1'b0;
      first_run_start <= '0;
      first_run_end <= '0;
      first_run_length <= '0;
      ambiguity_state <= 1'b0;
      expected_metric_index <= '0;
      selection_done <= 1'b0;
      selection_found <= 1'b0;
      selection_ambiguity <= 1'b0;
      selected_start_sample <= '0;
      selected_plateau_beats <= '0;
      safe_first_trace_index <= '0;
      safe_last_trace_index <= '0;
      protocol_error_sticky <= 1'b0;
    end else begin
      selection_done <= 1'b0;

      if (metric_valid) begin
        if (metric_index != expected_metric_index)
          protocol_error_sticky <= 1'b1;
        if (metric_last != (metric_index == SEARCH_POINTS-1))
          protocol_error_sticky <= 1'b1;

        if (metric_qualified) begin
          if (run_active) begin
            current_run_length <= current_run_length + 1'b1;
          end else begin
            run_active <= 1'b1;
            current_run_start <= metric_index;
            current_run_length <= 9'd1;
          end
        end else if (run_active) begin
          run_active <= 1'b0;
          current_run_length <= '0;
        end

        if (close_eligible) begin
          if (!first_run_found) begin
            first_run_found <= 1'b1;
            first_run_start <= close_start;
            first_run_end <= close_end;
            first_run_length <= close_length;
          end else begin
            ambiguity_state <= 1'b1;
          end
        end

        if (metric_last) begin
          logic signed [10:0] selected_beat;
          selection_done <= 1'b1;
          selection_found <= effective_first_found;
          selection_ambiguity <= effective_ambiguity;
          if (effective_first_found) begin
            selected_beat = selected_beat_from_run(
                effective_first_start, effective_first_end);
            selected_start_sample <=
                $signed(selected_beat) <<< 2;
            selected_plateau_beats <= effective_first_length;
            safe_first_trace_index <= selected_beat + 11'sd144;
            safe_last_trace_index <= selected_beat + 11'sd160;
          end else begin
            selected_start_sample <= '0;
            selected_plateau_beats <= '0;
            safe_first_trace_index <= '0;
            safe_last_trace_index <= '0;
          end

          run_active <= 1'b0;
          current_run_start <= '0;
          current_run_length <= '0;
          first_run_found <= 1'b0;
          first_run_start <= '0;
          first_run_end <= '0;
          first_run_length <= '0;
          ambiguity_state <= 1'b0;
          expected_metric_index <= '0;
        end else begin
          expected_metric_index <= expected_metric_index + 1'b1;
        end
      end
    end
  end
endmodule
