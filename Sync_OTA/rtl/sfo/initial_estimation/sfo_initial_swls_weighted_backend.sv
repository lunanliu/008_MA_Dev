`timescale 1ns / 1ps
module sfo_initial_swls_weighted_backend #(
    parameter integer MAX_CYCLES = 65024
) (
    input  logic               clk,
    input  logic               rst,
    input  logic               frame_start_valid,
    output logic               frame_start_ready,
    input  logic        [31:0] frame_start_id,
    input  logic               s_valid,
    output logic               s_ready,
    input  logic        [ 1:0] s_pair,
    input  logic        [10:0] s_index0,
    input  logic        [10:0] s_index1,
    input  logic signed [47:0] s_phase0,
    input  logic signed [47:0] s_phase1,
    input  logic        [63:0] s_nw0,
    input  logic        [63:0] s_nw1,
    input  logic        [32:0] s_dw0,
    input  logic        [32:0] s_dw1,
    output logic               m_valid,
    input  logic               m_ready,
    output logic        [31:0] m_frame_id,
    output logic signed [31:0] m_sfo_ppm,
    output logic        [15:0] m_quality,
    output logic signed [47:0] m_slope,
    output logic               m_error,
    output logic        [ 2:0] m_error_code,
    output logic        [ 7:0] m_error_stage,
    output logic        [31:0] elapsed_cycles,
    output logic        [12:0] accepted_observations,
    output logic        [12:0] weighted_observations,
    output logic        [ 2:0] sealed_pair_count
);
  typedef enum logic [2:0] {
    IDLE,
    FLUSH,
    START,
    FEED,
    TAIL,
    HOLD_RESULT
  } state_t;
  state_t state;
  logic [3:0] reset_count;
  logic core_rst, active, accept_input, atomic_start;
  logic [31:0] active_frame;
  logic [1:0] input_pair, next_max_pair;
  logic [10:0] input_index;
  logic max_active, store_done;
  logic store_start_ready, sum_start_ready;
  logic max_start_valid, max_start_ready, max_s_ready, max_m_valid, max_m_ready, max_pair_valid;
  logic [31:0] max_tag;
  logic [63:0] max_nm;
  logic [32:0] max_dm;
  logic [10:0] max_index;
  logic [ 7:0] max_error_code;
  logic store_s_ready, seal_ready, store_m_valid, store_m_ready;
  logic [31:0] store_frame, store_tag;
  logic [1:0] store_pair;
  logic [10:0] store_index, store_max_index;
  logic signed [10:0] store_bin;
  logic signed [47:0] store_phase;
  logic [63:0] store_nw, store_nm;
  logic [32:0] store_dw, store_dm;
  logic store_pair_last, store_last;
  logic store_status_valid, store_status_error;
  logic [31:0] store_status_frame;
  logic [ 7:0] store_status_code;
  logic [12:0] store_written, store_read_issued, store_replayed;
  logic [2:0] store_pending;
  logic store_protocol;
  logic pack_s_ready, pack_valid, pack_ready, pack_error, pack_zero;
  logic [ 2:0] pack_error_code;
  logic [62:0] pack_dividend;
  logic [46:0] pack_divisor;
  logic [45:0] pack_aw, pack_bw;
  logic [ 5:0] pack_shift;
  logic [31:0] pack_tag;
  logic
      meta_full,
      meta_empty,
      meta_wr_busy,
      meta_rd_busy,
      meta_overflow,
      meta_underflow,
      meta_write,
      meta_read;
  logic [79:0] meta_head;
  logic [31:0] meta_tag;
  logic signed [47:0] meta_phase;
  logic meta_available;
  logic div_s_valid, div_s_ready, div_m_valid, div_m_ready, div_error, div_zero, div_protocol;
  logic [62:0] div_n, div_q;
  logic [46:0] div_d, div_r;
  logic [31:0] div_s_tag, div_m_tag;
  logic [63:0] div_rne;
  logic [ 5:0] div_pending;
  logic sum_s_valid, sum_s_ready, sum_valid, sum_ready, sum_error;
  logic [2:0] sum_error_code;
  logic [31:0] sum_frame;
  logic [29:0] sum_s0;
  logic signed [40:0] sum_s1;
  logic [47:0] sum_s2;
  logic signed [75:0] sum_t0;
  logic signed [84:0] sum_t1;
  logic [12:0] sum_accepted, sum_accumulated;
  logic [17:0] normalized_weight;
  logic signed [10:0] regression_bin;
  logic
      tail_start_valid,
      tail_start_ready,
      tail_req_valid,
      tail_req_ready,
      tail_rsp_ready,
      tail_valid;
  logic [62:0] tail_n;
  logic [46:0] tail_d;
  logic [31:0] tail_tag, tail_frame, tail_cycles;
  logic signed [47:0] tail_slope;
  logic signed [31:0] tail_ppm;
  logic [15:0] tail_quality;
  logic tail_error;
  logic [2:0] tail_error_code;
  logic [77:0] tail_debug_d;
  logic signed [117:0] tail_debug_n;
  logic [5:0] tail_hq, tail_hs, tail_hp;
  logic all_weights_drained;
  assign active = state == FLUSH || state == START || state == FEED || state == TAIL;
  assign core_rst = rst || state == FLUSH || (state == HOLD_RESULT && m_error);
  assign frame_start_ready = !rst && state == IDLE;
  assign m_valid = !rst && state == HOLD_RESULT;
  assign atomic_start = state == START && store_start_ready && sum_start_ready;
  assign max_start_valid = state == FEED && !max_active && s_valid && sealed_pair_count < 4;
  assign s_ready = !core_rst && state == FEED && max_active && max_s_ready && store_s_ready &&
      accepted_observations < 6560;
  assign accept_input = s_valid && s_ready;
  sfo_initial_pair_max_tracker_2lane maximum (
      .clk             (clk),
      .rst             (core_rst),
      .pair_start_valid(max_start_valid),
      .pair_start_ready(max_start_ready),
      .pair_start_tag  ({30'd0, next_max_pair}),
      .s_valid         (accept_input),
      .s_ready         (max_s_ready),
      .s_nw0           (s_nw0),
      .s_nw1           (s_nw1),
      .s_dw0           (s_dw0),
      .s_dw1           (s_dw1),
      .s_index0        (s_index0),
      .s_index1        (s_index1),
      .m_valid         (max_m_valid),
      .m_ready         (max_m_ready),
      .m_nm            (max_nm),
      .m_dm            (max_dm),
      .m_index         (max_index),
      .m_tag           (max_tag),
      .m_pair_valid    (max_pair_valid),
      .m_error_code    (max_error_code)
  );
  assign max_m_ready = state == FEED && seal_ready;
  sfo_initial_observation_store storage (
      .clk                  (clk),
      .rst                  (core_rst),
      .frame_start_valid    (atomic_start),
      .frame_start_ready    (store_start_ready),
      .frame_start_id       (active_frame),
      .s_valid              (accept_input),
      .s_ready              (store_s_ready),
      .s_pair               (s_pair),
      .s_index0             (s_index0),
      .s_index1             (s_index1),
      .s_phase0             (s_phase0),
      .s_phase1             (s_phase1),
      .s_nw0                (s_nw0),
      .s_nw1                (s_nw1),
      .s_dw0                (s_dw0),
      .s_dw1                (s_dw1),
      .seal_valid           (state == FEED && max_m_valid),
      .seal_ready           (seal_ready),
      .seal_frame_id        (active_frame),
      .seal_pair            (max_tag[1:0]),
      .seal_nm              (max_nm),
      .seal_dm              (max_dm),
      .seal_max_index       (max_index),
      .seal_pair_valid      (max_pair_valid),
      .seal_error_code      (max_error_code),
      .m_valid              (store_m_valid),
      .m_ready              (store_m_ready),
      .m_frame_id           (store_frame),
      .m_tag                (store_tag),
      .m_pair               (store_pair),
      .m_index              (store_index),
      .m_bin                (store_bin),
      .m_phase              (store_phase),
      .m_nw                 (store_nw),
      .m_nm                 (store_nm),
      .m_dw                 (store_dw),
      .m_dm                 (store_dm),
      .m_max_index          (store_max_index),
      .m_pair_last          (store_pair_last),
      .m_last               (store_last),
      .status_valid         (store_status_valid),
      .status_ready         (state == FEED),
      .status_frame_id      (store_status_frame),
      .status_error         (store_status_error),
      .status_error_code    (store_status_code),
      .written_count        (store_written),
      .read_issued_count    (store_read_issued),
      .replayed_count       (store_replayed),
      .pending_read_count   (store_pending),
      .protocol_error_sticky(store_protocol)
  );
  assign meta_available = !meta_full && !meta_wr_busy && !meta_rd_busy;
  assign store_m_ready = state == FEED && pack_s_ready && meta_available;
  assign meta_write = store_m_valid && store_m_ready;
  sfo_initial_weight_pack packer (
      .clk                        (clk),
      .rst                        (core_rst),
      .s_valid                    (state == FEED && store_m_valid && meta_available),
      .s_ready                    (pack_s_ready),
      .s_n                        (store_nw),
      .s_d                        (store_dw),
      .s_n_max                    (store_nm),
      .s_d_max                    (store_dm),
      .s_tag                      (store_tag),
      .m_valid                    (pack_valid),
      .m_ready                    (pack_ready),
      .m_dividend                 (pack_dividend),
      .m_divisor                  (pack_divisor),
      .m_aw                       (pack_aw),
      .m_bw                       (pack_bw),
      .m_common_shift             (pack_shift),
      .m_tag                      (pack_tag),
      .m_zero_divisor_substitution(pack_zero),
      .m_error                    (pack_error),
      .m_error_code               (pack_error_code)
  );
  sfo_initial_unsigned_divider_service_fifo #(
      .WIDTH(80)
  ) phase_metadata (
      .clk      (clk),
      .rst      (core_rst),
      .wr_en    (meta_write),
      .rd_en    (meta_read),
      .din      ({store_phase, store_tag}),
      .dout     (meta_head),
      .full     (meta_full),
      .empty    (meta_empty),
      .wr_busy  (meta_wr_busy),
      .rd_busy  (meta_rd_busy),
      .overflow (meta_overflow),
      .underflow(meta_underflow)
  );
  assign {meta_phase, meta_tag} = meta_head;
  assign
      div_s_valid = state == FEED ? (pack_valid && !pack_error) : (state == TAIL && tail_req_valid);
  assign div_n = state == TAIL ? tail_n : pack_dividend;
  assign div_d = state == TAIL ? tail_d : pack_divisor;
  assign div_s_tag = state == TAIL ? tail_tag : pack_tag;
  assign pack_ready = state == FEED && div_s_ready;
  assign tail_req_ready = state == TAIL && div_s_ready;
  assign div_m_ready = state == FEED ?
      (sum_s_ready && !meta_empty && !meta_rd_busy) : (state == TAIL && tail_rsp_ready);
  assign meta_read = state == FEED && div_m_valid && div_m_ready;
  sfo_initial_unsigned_divider_service divider (
      .clk                  (clk),
      .rst                  (core_rst),
      .s_valid              (div_s_valid),
      .s_ready              (div_s_ready),
      .s_dividend           (div_n),
      .s_divisor            (div_d),
      .s_tag                (div_s_tag),
      .m_valid              (div_m_valid),
      .m_ready              (div_m_ready),
      .m_tag                (div_m_tag),
      .m_quotient           (div_q),
      .m_remainder          (div_r),
      .m_rne                (div_rne),
      .m_divide_by_zero     (div_zero),
      .m_error              (div_error),
      .pending_count        (div_pending),
      .protocol_error_sticky(div_protocol)
  );
  assign normalized_weight = div_rne < 64'd1 ?
      18'd1 : (div_rne > 64'd131072 ? 18'd131072 : div_rne[17:0]);
  assign regression_bin = div_m_tag[10:0] < 820 ? $signed(
      {1'b0, div_m_tag[10:0]}
  ) + 12'sd1 : $signed(
      {1'b0, div_m_tag[10:0]}
  ) - 12'sd1640;
  assign sum_s_valid = state == FEED && div_m_valid && !meta_empty && !meta_rd_busy && !div_error &&
      meta_tag == div_m_tag;
  sfo_initial_five_sum_accumulator sums (
      .clk              (clk),
      .rst              (core_rst),
      .start_valid      (atomic_start),
      .start_ready      (sum_start_ready),
      .start_frame_id   (active_frame),
      .s_valid          (sum_s_valid),
      .s_ready          (sum_s_ready),
      .s_pair           (div_m_tag[12:11]),
      .s_bin            (regression_bin),
      .s_weight         (normalized_weight),
      .s_phase          (meta_phase),
      .s_last           (div_m_tag[12:11] == 3 && div_m_tag[10:0] == 1639),
      .m_valid          (sum_valid),
      .m_ready          (sum_ready),
      .m_frame_id       (sum_frame),
      .m_s0             (sum_s0),
      .m_s1             (sum_s1),
      .m_s2             (sum_s2),
      .m_t0             (sum_t0),
      .m_t1             (sum_t1),
      .m_error          (sum_error),
      .m_error_code     (sum_error_code),
      .accepted_count   (sum_accepted),
      .accumulated_count(sum_accumulated)
  );
  assign all_weights_drained = store_done && store_pending == 0 && meta_empty && div_pending == 0 &&
      !pack_valid && accepted_observations == 6560 && weighted_observations == 6560 &&
      sealed_pair_count == 4 && sum_accumulated == 6560;
  assign tail_start_valid = state == FEED && sum_valid && !sum_error && all_weights_drained;
  assign sum_ready = tail_start_valid && tail_start_ready;
  sfo_initial_regression_tail regression (
      .clk             (clk),
      .rst             (core_rst),
      .s_valid         (tail_start_valid),
      .s_ready         (tail_start_ready),
      .s_frame_id      (sum_frame),
      .s_s0            (sum_s0),
      .s_s1            (sum_s1),
      .s_s2            (sum_s2),
      .s_t0            (sum_t0),
      .s_t1            (sum_t1),
      .div_req_valid   (tail_req_valid),
      .div_req_ready   (tail_req_ready),
      .div_req_dividend(tail_n),
      .div_req_divisor (tail_d),
      .div_req_tag     (tail_tag),
      .div_rsp_valid   (state == TAIL && div_m_valid),
      .div_rsp_ready   (tail_rsp_ready),
      .div_rsp_rne     (div_rne),
      .div_rsp_tag     (div_m_tag),
      .div_rsp_error   (div_error),
      .m_valid         (tail_valid),
      .m_ready         (state == TAIL),
      .m_frame_id      (tail_frame),
      .m_slope         (tail_slope),
      .m_sfo_ppm       (tail_ppm),
      .m_quality       (tail_quality),
      .m_error         (tail_error),
      .m_error_code    (tail_error_code),
      .debug_d         (tail_debug_d),
      .debug_n         (tail_debug_n),
      .debug_hq        (tail_hq),
      .debug_hs        (tail_hs),
      .debug_hppm      (tail_hp),
      .elapsed_cycles  (tail_cycles)
  );
  task automatic fail_frame(input logic [2:0] code, input logic [7:0] origin);
    begin
      m_error <= 1;
      m_error_code <= code;
      m_error_stage <= origin;
      m_sfo_ppm <= 0;
      m_quality <= 0;
      m_slope <= 0;
      state <= HOLD_RESULT;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      reset_count <= 0;
      active_frame <= 0;
      m_frame_id <= 0;
      input_pair <= 0;
      input_index <= 0;
      next_max_pair <= 0;
      max_active <= 0;
      store_done <= 0;
      elapsed_cycles <= 0;
      accepted_observations <= 0;
      weighted_observations <= 0;
      sealed_pair_count <= 0;
      m_sfo_ppm <= 0;
      m_quality <= 0;
      m_slope <= 0;
      m_error <= 0;
      m_error_code <= 0;
      m_error_stage <= 0;
    end else begin
      if (active) elapsed_cycles <= elapsed_cycles + 32'd1;
      case (state)
        IDLE:
        if (frame_start_valid && frame_start_ready) begin
          active_frame <= frame_start_id;
          m_frame_id <= frame_start_id;
          reset_count <= 0;
          state <= FLUSH;
          input_pair <= 0;
          input_index <= 0;
          next_max_pair <= 0;
          max_active <= 0;
          store_done <= 0;
          elapsed_cycles <= 0;
          accepted_observations <= 0;
          weighted_observations <= 0;
          sealed_pair_count <= 0;
          m_sfo_ppm <= 0;
          m_quality <= 0;
          m_slope <= 0;
          m_error <= 0;
          m_error_code <= 0;
          m_error_stage <= 0;
        end
        FLUSH:
        if (reset_count == 7) state <= START;
        else reset_count <= reset_count + 1'b1;
        START: if (atomic_start) state <= FEED;
        FEED: begin
          if (max_start_valid && max_start_ready) max_active <= 1;
          if (accept_input) begin
            accepted_observations <= accepted_observations + 13'd2;
            if (input_index == 1638) begin
              input_index <= 0;
              input_pair  <= input_pair + 1'b1;
            end else input_index <= input_index + 11'd2;
          end
          if (max_m_valid && max_m_ready) begin
            max_active <= 0;
            next_max_pair <= next_max_pair + 1'b1;
            sealed_pair_count <= sealed_pair_count + 1'b1;
          end
          if (store_status_valid && !store_status_error) store_done <= 1;
          if (sum_s_valid && sum_s_ready) weighted_observations <= weighted_observations + 13'd1;
          if (tail_start_valid && tail_start_ready) state <= TAIL;
        end
        TAIL:
        if (tail_valid) begin
          m_sfo_ppm <= tail_ppm;
          m_quality <= tail_quality;
          m_slope <= tail_slope;
          m_error <= tail_error;
          m_error_code <= tail_error_code;
          m_error_stage <= tail_error ? 8'd7 : 8'd0;
          state <= HOLD_RESULT;
        end
        HOLD_RESULT: if (m_ready) state <= IDLE;
        default: fail_frame(3'd6, 8'd255);
      endcase
      if (state == FEED || state == TAIL) begin
        if (state == FEED && accept_input &&
            (s_pair != input_pair || s_index0 != input_index || s_index1 != input_index + 11'd1 ||
             s_phase0 < -48'sd35184372088832 || s_phase0 > 48'sd35184372088831 ||
             s_phase1 < -48'sd35184372088832 || s_phase1 > 48'sd35184372088831))
          fail_frame(3'd6, 8'd1);
        else if (state == FEED && max_m_valid && (max_tag != {30'd0, next_max_pair}))
          fail_frame(3'd6, 8'd2);
        else if (state == FEED && store_status_valid &&
                 (store_status_frame != active_frame || store_status_error))
          fail_frame(
              store_status_frame != active_frame ? 3'd6 :
                  (store_status_code > 7 || store_status_code == 0 ? 3'd7 : store_status_code[2:0]),
              8'd3);
        else if (state == FEED && store_m_valid && store_frame != active_frame)
          fail_frame(3'd6, 8'd3);
        else if (state == FEED && pack_valid && pack_error) fail_frame(pack_error_code, 8'd4);
        else if (state == FEED && div_m_valid &&
                 (meta_empty || meta_rd_busy || meta_tag != div_m_tag || div_m_tag[31:13] != 0))
          fail_frame(3'd6, 8'd5);
        else if (state == FEED && div_m_valid && div_error) fail_frame(3'd7, 8'd5);
        else if (state == FEED && sum_valid && (sum_frame != active_frame || sum_error))
          fail_frame(sum_frame != active_frame ? 3'd6 : sum_error_code, 8'd6);
        else if (state == TAIL && tail_valid && tail_frame != active_frame) fail_frame(3'd6, 8'd7);
        else if (store_protocol || meta_overflow || meta_underflow || div_protocol)
          fail_frame(3'd6, 8'd8);
      end
      if (active && elapsed_cycles >= MAX_CYCLES - 1 && !(state == TAIL && tail_valid))
        fail_frame(3'd6, 8'd9);
    end
  end
endmodule
