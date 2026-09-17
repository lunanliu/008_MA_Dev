`timescale 1ns/1ps

module fine_peak_selector #(
  parameter int unsigned METRIC_WIDTH = 97,
  parameter int unsigned MAX_CANDIDATES = 257,
  parameter int unsigned RUNNER_GUARD_SAMPLES = 8
) (
  input  logic clk,
  input  logic rst_n,

  input  logic candidate_valid,
  output logic candidate_ready,
  input  logic candidate_last,
  input  logic signed [31:0] candidate_start,
  input  logic [METRIC_WIDTH-1:0] candidate_metric,

  output logic result_valid,
  input  logic result_ready,
  output logic signed [31:0] peak_start,
  output logic [METRIC_WIDTH-1:0] peak_metric,
  output logic signed [31:0] runner_start,
  output logic [METRIC_WIDTH-1:0] runner_metric,
  output logic timing_valid,
  output logic ambiguity,
  output logic error
);
  localparam int unsigned ENTRY_WIDTH = METRIC_WIDTH+32;
  localparam int unsigned ADDR_WIDTH =
      (MAX_CANDIDATES <= 1) ? 1 : $clog2(MAX_CANDIDATES);
  localparam int unsigned COUNT_WIDTH =
      (MAX_CANDIDATES <= 1) ? 1 : $clog2(MAX_CANDIDATES+1);

  typedef enum logic [2:0] {
    ST_COLLECT,
    ST_SCAN_PRIME,
    ST_SCAN,
    ST_SCAN_DRAIN,
    ST_OUTPUT
  } state_t;

  state_t state;
  (* ram_style = "block" *) logic [ENTRY_WIDTH-1:0]
      candidate_memory [0:MAX_CANDIDATES-1];

  logic [COUNT_WIDTH-1:0] candidate_count;
  logic [ADDR_WIDTH-1:0] scan_address;
  logic [ENTRY_WIDTH-1:0] scan_entry;
  logic scan_entry_valid;

  logic peak_seen;
  logic signed [31:0] selected_peak_start;
  logic [METRIC_WIDTH-1:0] selected_peak_metric;
  logic runner_seen;
  logic signed [31:0] selected_runner_start;
  logic [METRIC_WIDTH-1:0] selected_runner_metric;
  logic exact_tie_seen;

  logic signed [31:0] scan_start;
  logic [METRIC_WIDTH-1:0] scan_metric;
  logic signed [32:0] scan_start_extended;
  logic signed [32:0] peak_start_extended;
  logic signed [32:0] signed_distance;
  logic [32:0] absolute_distance;
  logic scan_outside_guard;
  logic scan_better_runner;
  logic runner_seen_after_scan;
  logic signed [31:0] runner_start_after_scan;
  logic [METRIC_WIDTH-1:0] runner_metric_after_scan;
  logic exact_tie_after_scan;
  logic threshold_ambiguous_after_scan;
  logic ambiguity_after_scan;

  initial begin
    if (MAX_CANDIDATES == 0)
      $error("T05 peak selector MAX_CANDIDATES must be nonzero");
    if (METRIC_WIDTH == 0)
      $error("T05 peak selector METRIC_WIDTH must be nonzero");
  end

  always_comb begin
    candidate_ready = (state == ST_COLLECT);

    scan_metric = scan_entry[ENTRY_WIDTH-1:32];
    scan_start = $signed(scan_entry[31:0]);
    scan_start_extended = {scan_start[31],scan_start};
    peak_start_extended = {selected_peak_start[31],selected_peak_start};
    signed_distance = scan_start_extended-peak_start_extended;
    if (signed_distance < 0)
      absolute_distance = $unsigned(-signed_distance);
    else
      absolute_distance = $unsigned(signed_distance);
    scan_outside_guard = scan_entry_valid &&
        (absolute_distance > RUNNER_GUARD_SAMPLES);

    scan_better_runner = scan_outside_guard &&
        (!runner_seen ||
         (scan_metric > selected_runner_metric) ||
         ((scan_metric == selected_runner_metric) &&
          (scan_start < selected_runner_start)));

    runner_seen_after_scan = runner_seen;
    runner_start_after_scan = selected_runner_start;
    runner_metric_after_scan = selected_runner_metric;
    exact_tie_after_scan = exact_tie_seen;
    if (scan_better_runner) begin
      runner_seen_after_scan = 1'b1;
      runner_start_after_scan = scan_start;
      runner_metric_after_scan = scan_metric;
    end
    if (scan_entry_valid && (scan_start != selected_peak_start) &&
        (scan_metric == selected_peak_metric))
      exact_tie_after_scan = 1'b1;

    threshold_ambiguous_after_scan = runner_seen_after_scan &&
        ({runner_metric_after_scan,2'b00} >=
         {{2{1'b0}},selected_peak_metric});
    ambiguity_after_scan = exact_tie_after_scan ||
        threshold_ambiguous_after_scan;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_COLLECT;
      candidate_count <= '0;
      scan_address <= '0;
      scan_entry <= '0;
      scan_entry_valid <= 1'b0;
      peak_seen <= 1'b0;
      selected_peak_start <= '0;
      selected_peak_metric <= '0;
      runner_seen <= 1'b0;
      selected_runner_start <= '0;
      selected_runner_metric <= '0;
      exact_tie_seen <= 1'b0;
      result_valid <= 1'b0;
      peak_start <= '0;
      peak_metric <= '0;
      runner_start <= '0;
      runner_metric <= '0;
      timing_valid <= 1'b0;
      ambiguity <= 1'b0;
      error <= 1'b0;
    end else begin
      case (state)
        ST_COLLECT: begin
          if (candidate_valid && candidate_ready) begin
            candidate_memory[candidate_count[ADDR_WIDTH-1:0]] <=
                {candidate_metric,candidate_start};
            if (!peak_seen ||
                (candidate_metric > selected_peak_metric) ||
                ((candidate_metric == selected_peak_metric) &&
                 (candidate_start < selected_peak_start))) begin
              peak_seen <= 1'b1;
              selected_peak_start <= candidate_start;
              selected_peak_metric <= candidate_metric;
            end
            candidate_count <= candidate_count+1'b1;

            if (candidate_last) begin
              state <= ST_SCAN_PRIME;
            end else if (candidate_count == MAX_CANDIDATES-1) begin
              // A bounded packet must terminate on or before its last slot.
              result_valid <= 1'b1;
              peak_start <= '0;
              peak_metric <= '0;
              runner_start <= '0;
              runner_metric <= '0;
              timing_valid <= 1'b0;
              ambiguity <= 1'b0;
              error <= 1'b1;
              state <= ST_OUTPUT;
            end
          end
        end

        ST_SCAN_PRIME: begin
          scan_address <= '0;
          scan_entry_valid <= 1'b0;
          runner_seen <= 1'b0;
          selected_runner_start <= '0;
          selected_runner_metric <= '0;
          exact_tie_seen <= 1'b0;
          state <= ST_SCAN;
        end

        ST_SCAN: begin
          if (scan_entry_valid) begin
            runner_seen <= runner_seen_after_scan;
            selected_runner_start <= runner_start_after_scan;
            selected_runner_metric <= runner_metric_after_scan;
            exact_tie_seen <= exact_tie_after_scan;
          end

          scan_entry <= candidate_memory[scan_address];
          scan_entry_valid <= 1'b1;
          if (scan_address == candidate_count-1'b1) begin
            state <= ST_SCAN_DRAIN;
          end else begin
            scan_address <= scan_address+1'b1;
          end
        end

        ST_SCAN_DRAIN: begin
          peak_start <= selected_peak_start;
          peak_metric <= selected_peak_metric;
          runner_start <= runner_start_after_scan;
          runner_metric <= runner_seen_after_scan ?
              runner_metric_after_scan : '0;
          ambiguity <= peak_seen && (selected_peak_metric != '0) &&
              ambiguity_after_scan;
          error <= !peak_seen || (selected_peak_metric == '0);
          timing_valid <= peak_seen && (selected_peak_metric != '0) &&
              !ambiguity_after_scan;
          result_valid <= 1'b1;
          scan_entry_valid <= 1'b0;
          state <= ST_OUTPUT;
        end

        ST_OUTPUT: begin
          if (result_valid && result_ready) begin
            state <= ST_COLLECT;
            candidate_count <= '0;
            scan_entry_valid <= 1'b0;
            peak_seen <= 1'b0;
            selected_peak_start <= '0;
            selected_peak_metric <= '0;
            runner_seen <= 1'b0;
            selected_runner_start <= '0;
            selected_runner_metric <= '0;
            exact_tie_seen <= 1'b0;
            result_valid <= 1'b0;
            peak_start <= '0;
            peak_metric <= '0;
            runner_start <= '0;
            runner_metric <= '0;
            timing_valid <= 1'b0;
            ambiguity <= 1'b0;
            error <= 1'b0;
          end
        end

        default: begin
          state <= ST_COLLECT;
          result_valid <= 1'b0;
          timing_valid <= 1'b0;
          error <= 1'b1;
        end
      endcase
    end
  end
endmodule
