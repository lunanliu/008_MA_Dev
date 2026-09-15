`timescale 1ns / 1ps
`include "initial_pair_max_tracker_ip_config.svh"
// Exact rational maximum. No quotient approximation or observation storage.
module sfo_initial_pair_max_tracker_2lane (
    input  logic        clk,
    input  logic        rst,
    input  logic        pair_start_valid,
    output logic        pair_start_ready,
    input  logic [31:0] pair_start_tag,
    input  logic        s_valid,
    output logic        s_ready,
    input  logic [63:0] s_nw0,
    input  logic [63:0] s_nw1,
    input  logic [32:0] s_dw0,
    input  logic [32:0] s_dw1,
    input  logic [10:0] s_index0,
    input  logic [10:0] s_index1,
    output logic        m_valid,
    input  logic        m_ready,
    output logic [63:0] m_nm,
    output logic [32:0] m_dm,
    output logic [10:0] m_index,
    output logic [31:0] m_tag,
    output logic        m_pair_valid,
    output logic [ 7:0] m_error_code
);
  localparam integer CROSS_LAT = `SFO_INITIAL_PAIR_MAX_CROSS_LATENCY;
  typedef enum logic [2:0] {
    IDLE,
    FEED,
    DRAIN,
    MERGE_ISSUE,
    MERGE_WAIT,
    EMIT,
    OUT
  } state_t;
  typedef struct packed {
    logic [63:0] n;
    logic [32:0] d;
    logic [10:0] index;
  } candidate_t;
  typedef struct packed {
    candidate_t proposed, incumbent;
    logic [3:0] slot;
    logic merging;
  } meta_t;
  state_t state;
  candidate_t partial[0:15], best;
  candidate_t proposed[0:1], incumbent[0:1], winner[0:1];
  logic [3:0] issue_slot[0:1];
  meta_t meta[0:1][0:CROSS_LAT-1];
  logic [CROSS_LAT-1:0] pipe_valid[0:1];
  logic [1:0] issue;
  logic [96:0] lhs[0:1], rhs[0:1];
  logic [15:0] slot_busy;
  logic [9:0] beat_count;
  logic [3:0] merge_index;
  logic pair_error;
  logic [31:0] active_tag;
  logic accept;
  integer lane, stage, slot;

  assign pair_start_ready = !rst && state == IDLE;
  assign s_ready = !rst && state == FEED;
  assign accept = s_valid && s_ready;
  assign m_valid = !rst && state == OUT;

  // U97 comparisons only. Lowest index breaks ties independently of slot order.
  function automatic candidate_t choose(input meta_t entry, input logic [96:0] left_product,
                                        right_product);
    candidate_t selected;
    begin
      selected = entry.incumbent;
      if (entry.proposed.n != 0 && entry.proposed.d != 0 &&
          (entry.incumbent.n == 0 || left_product > right_product ||
           (left_product == right_product && entry.proposed.index < entry.incumbent.index)))
        selected = entry.proposed;
      choose = selected;
    end
  endfunction

  always_comb begin
    issue = 2'b00;
    issue_slot[0] = {1'b0, beat_count[2:0]};
    issue_slot[1] = {1'b1, beat_count[2:0]};
    proposed[0] = '0;
    proposed[1] = '0;
    incumbent[0] = '0;
    incumbent[1] = '0;
    if (state == FEED) begin
      issue = {2{accept}};
      proposed[0] = {s_nw0, s_dw0, s_index0};
      proposed[1] = {s_nw1, s_dw1, s_index1};
      incumbent[0] = partial[issue_slot[0]];
      incumbent[1] = partial[issue_slot[1]];
    end else if (state == MERGE_ISSUE && !rst) begin
      issue = 2'b01;
      proposed[0] = partial[merge_index];
      incumbent[0] = best;
    end
    winner[0] = choose(meta[0][CROSS_LAT-1], lhs[0], rhs[0]);
    winner[1] = choose(meta[1][CROSS_LAT-1], lhs[1], rhs[1]);
  end
  genvar g;
  generate
    for (g = 0; g < 2; g = g + 1) begin : cross_lane
      t06_pair_max_tracker_2lane_cross left_product (
          .CLK(clk),
          .A  (proposed[g].n),
          .B  (incumbent[g].d),
          .P  (lhs[g])
      );
      t06_pair_max_tracker_2lane_cross right_product (
          .CLK(clk),
          .A  (incumbent[g].n),
          .B  (proposed[g].d),
          .P  (rhs[g])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      beat_count <= 0;
      merge_index <= 0;
      pair_error <= 0;
      active_tag <= 0;
      slot_busy <= 0;
      best <= '0;
      m_nm <= 0;
      m_dm <= 0;
      m_index <= 0;
      m_tag <= 0;
      m_pair_valid <= 0;
      m_error_code <= 0;
      for (slot = 0; slot < 16; slot = slot + 1) partial[slot] <= '0;
      for (lane = 0; lane < 2; lane = lane + 1) begin
        pipe_valid[lane] <= '0;
        for (stage = 0; stage < CROSS_LAT; stage = stage + 1) meta[lane][stage] <= '0;
      end
    end else begin
      for (lane = 0; lane < 2; lane = lane + 1) begin
        pipe_valid[lane][0] <= issue[lane];
        meta[lane][0] <= {proposed[lane], incumbent[lane], issue_slot[lane], state == MERGE_ISSUE};
        for (stage = 1; stage < CROSS_LAT; stage = stage + 1) begin
          pipe_valid[lane][stage] <= pipe_valid[lane][stage-1];
          meta[lane][stage] <= meta[lane][stage-1];
        end
        if (issue[lane] && state == FEED) slot_busy[issue_slot[lane]] <= 1'b1;
        if (pipe_valid[lane][CROSS_LAT-1]) begin
          if (meta[lane][CROSS_LAT-1].merging) begin
            best <= winner[lane];
            if (merge_index == 15) state <= EMIT;
            else begin
              merge_index <= merge_index + 1'b1;
              state <= MERGE_ISSUE;
            end
          end else begin
            partial[meta[lane][CROSS_LAT-1].slot]   <= winner[lane];
            slot_busy[meta[lane][CROSS_LAT-1].slot] <= 1'b0;
          end
        end
      end
      case (state)
        IDLE:
        if (pair_start_valid) begin
          state <= FEED;
          active_tag <= pair_start_tag;
          beat_count <= 0;
          pair_error <= 0;
          best <= '0;
          merge_index <= 0;
          slot_busy <= 0;
          for (slot = 0; slot < 16; slot = slot + 1) partial[slot] <= '0;
        end
        FEED:
        if (accept) begin
          if (s_index0 != {beat_count, 1'b0} || s_index1 != {beat_count, 1'b1} ||
              (s_nw0 != 0 && s_dw0 == 0) || (s_nw1 != 0 && s_dw1 == 0))
            pair_error <= 1'b1;
          if (beat_count == 819) state <= DRAIN;
          else beat_count <= beat_count + 1'b1;
        end
        DRAIN:
        if (pipe_valid[0] == '0 && pipe_valid[1] == '0 && slot_busy == 0) begin
          state <= MERGE_ISSUE;
          merge_index <= 0;
          best <= '0;
        end
        MERGE_ISSUE: state <= MERGE_WAIT;
        MERGE_WAIT: begin
        end
        EMIT: begin
          m_tag <= active_tag;
          m_pair_valid <= !pair_error && best.n != 0;
          m_error_code <= pair_error ? 8'd7 : (best.n == 0 ? 8'd1 : 8'd0);
          m_nm <= (pair_error || best.n == 0) ? 64'd0 : best.n;
          m_dm <= (pair_error || best.n == 0) ? 33'd0 : best.d;
          m_index <= (pair_error || best.n == 0) ? 11'd0 : best.index;
          state <= OUT;
        end
        OUT: if (m_ready) state <= IDLE;
        default: state <= IDLE;
      endcase
    end
  end

  // synthesis translate_off
  initial if (CROSS_LAT != 4 || CROSS_LAT + 1 >= 8) $fatal(1, "PAIR_MAX feedback latency contract");
  always @(posedge clk)
    if (!rst) begin
      for (integer a = 0; a < 2; a = a + 1) begin
        if (issue[a] && state == FEED && slot_busy[issue_slot[a]])
          $fatal(
              1, "PAIR_MAX slot reused before previous commit lane=%0d slot=%0d", a, issue_slot[a]
          );
        if (pipe_valid[a][CROSS_LAT-1] && meta[a][CROSS_LAT-1].merging &&
            (a != 0 || state != MERGE_WAIT))
          $fatal(1, "PAIR_MAX merge metadata/state mismatch");
        if (pipe_valid[a][CROSS_LAT-1] && !meta[a][CROSS_LAT-1].merging &&
            !slot_busy[meta[a][CROSS_LAT-1].slot])
          $fatal(1, "PAIR_MAX commit has no slot credit");
      end
      if (state == MERGE_ISSUE && (slot_busy != 0 || pipe_valid[0] != '0 || pipe_valid[1] != '0))
        $fatal(1, "PAIR_MAX merge overlaps in-flight comparison");
      if ((state == IDLE || state == OUT) &&
          (pipe_valid[0] != '0 || pipe_valid[1] != '0 || slot_busy != 0))
        $fatal(1, "PAIR_MAX residual valid escaped pair boundary");
    end
  // synthesis translate_on
endmodule
