// Real connection of power/peak -> interpolation -> all-74 LS.
// Accepts already-computed DTP windows; source FFT/window-memory access is a later boundary.
module sfo_residual_delay_backend4 #(parameter integer ALLOW_SOURCE_WAIT=0) (
    input  logic                clk,
    input  logic                rst,
    input  logic                abort,
    input wire source_wait,
    input  logic                frame_valid,
    output logic                frame_ready,
    input  logic        [ 31:0] frame_tag,
    input  logic                window_valid,
    output logic                window_ready,
    input  logic        [  6:0] window_slot,
    input  logic        [ 31:0] window_tag,
    input  logic                s_valid,
    output logic                s_ready,
    input  logic        [127:0] s_data,
    input  logic        [  6:0] s_symbol_slot,
    input  logic        [  8:0] s_beat,
    input  logic        [ 31:0] s_tag,
    input  logic                s_last,
    input  logic        [  3:0] s_error,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [ 31:0] m_tag,
    output logic        [  6:0] m_count,
    output logic        [  6:0] m_window_count,
    output logic        [ 15:0] m_data_count,
    output logic        [  3:0] m_error,
    output logic        [  3:0] m_detail,
    output logic signed [ 31:0] m_ppm_q18,
    output logic        [ 31:0] m_step_q28,
    output logic        [  4:0] m_quality_flags,
    output logic                m_estimate_valid,
    output logic                busy,
    output logic                point_event,
    output logic        [ 31:0] point_tag,
    output logic        [  6:0] point_slot,
    output logic        [ 10:0] point_peak_bin,
    output logic signed [ 17:0] point_delta_q16,
    output logic signed [ 23:0] point_delay_q16,
    output logic        [  3:0] point_quality_flags,
    output logic                point_quality_valid
);
  localparam [2:0] IDLE = 0,
      ARM = 1, WAIT_WINDOW = 2, START_PEAK = 3, ACTIVE = 4, WAIT_FINAL = 5, DONE = 6;
  logic [2:0] state;
  logic [6:0] active_slot;
  wire child_reset = rst || state == IDLE || state == DONE;
  logic pk_cfg_ready, pk_s_ready, pk_valid, pk_ready, pk_busy;
  logic [ 3:0] pk_error;
  logic [ 6:0] pk_slot;
  logic [31:0] pk_tag;
  logic [9:0] pk_input_count, pk_power_count;
  logic [10:0] pk_bin;
  logic signed [11:0] pk_offset;
  logic pk_interior;
  logic [31:0] pk_prev, pk_power, pk_next, pk_comp;
  logic ip_ready, ip_valid, ip_busy;
  logic [3:0] ip_error;
  logic ls_cfg_ready, ls_s_ready, ls_valid, ls_busy;
  logic [31:0] ls_tag;
  logic [ 6:0] ls_count;
  logic [3:0] ls_error, ls_upstream_error;
  logic signed [31:0] ls_ppm;
  logic [31:0] ls_step;
  logic [4:0] ls_flags;
  logic ls_estimate_valid;
  wire active_frame = (state != IDLE && state != DONE);
  wire ip_identity_bad = (point_tag != m_tag || point_slot != active_slot || point_slot != m_count);
  wire peak_transfer = (state == ACTIVE && pk_valid && pk_error == 0 && !abort && !ls_valid);
  wire delay_transfer = (state == ACTIVE && ip_valid && ip_error == 0 && !ip_identity_bad &&
                         !abort && !ls_valid);
  assign frame_ready = !rst && !abort && state == IDLE;
  assign window_ready = !rst && !abort && state == WAIT_WINDOW && ls_s_ready && !ls_valid;
  assign s_ready = !rst && !abort && state == ACTIVE && pk_s_ready && !ls_valid;
  assign m_valid = !rst && state == DONE;
  assign busy = state != IDLE;
  assign pk_ready = state == ACTIVE && ip_ready && pk_error == 0 && !abort && !ls_valid;
  assign point_event = !rst && delay_transfer && ls_s_ready;
  sfo_residual_peak_triplet4 peak (
      .clk              (clk),
      .rst              (child_reset),
      .abort            (abort),
      .cfg_valid        (state == START_PEAK && !abort && !ls_valid),
      .cfg_ready        (pk_cfg_ready),
      .cfg_symbol_slot  (active_slot),
      .cfg_tag          (m_tag),
      .s_valid          (state == ACTIVE && s_valid && s_error == 0 && !abort && !ls_valid),
      .s_ready          (pk_s_ready),
      .s_data           (s_data),
      .s_symbol_slot    (s_symbol_slot),
      .s_beat           (s_beat),
      .s_tag            (s_tag),
      .s_last           (s_last),
      .m_valid          (pk_valid),
      .m_ready          (pk_ready),
      .m_error          (pk_error),
      .m_symbol_slot    (pk_slot),
      .m_tag            (pk_tag),
      .m_input_count    (pk_input_count),
      .m_power_count    (pk_power_count),
      .m_peak_bin       (pk_bin),
      .m_peak_offset    (pk_offset),
      .m_search_interior(pk_interior),
      .m_prev_power     (pk_prev),
      .m_peak_power     (pk_power),
      .m_next_power     (pk_next),
      .m_competing_power(pk_comp),
      .busy             (pk_busy)
  );
  sfo_residual_peak_interpolate interpolate (
      .clk(clk),
      .rst(child_reset),
      .abort(abort),
      .s_valid(peak_transfer),
      .s_ready(ip_ready),
      .s_tag(pk_tag),
      .s_symbol_slot(pk_slot),
      .s_error(pk_error),
      .s_peak_bin(pk_bin),
      .s_prev_power(pk_prev),
      .s_peak_power(pk_power),
      .s_next_power(pk_next),
      .s_competing_power(pk_comp),
      .m_valid(ip_valid),
      .m_ready(state == ACTIVE && ls_s_ready && ip_error == 0 && !ip_identity_bad && !abort &&
               !ls_valid),
      .m_tag(point_tag),
      .m_symbol_slot(point_slot),
      .m_error(ip_error),
      .m_peak_bin(point_peak_bin),
      .m_delta_bin_q16(point_delta_q16),
      .m_delay_q16(point_delay_q16),
      .m_quality_flags(point_quality_flags),
      .m_quality_valid(point_quality_valid),
      .busy(ip_busy)
  );
  sfo_residual_ls74 #(.ALLOW_SOURCE_WAIT(ALLOW_SOURCE_WAIT)) regression (
      .clk             (clk),
      .rst             (child_reset),
      .source_wait(ALLOW_SOURCE_WAIT&&source_wait),
      .abort           (abort),
      .cfg_valid       (state == ARM && !abort),
      .cfg_ready       (ls_cfg_ready),
      .cfg_tag         (m_tag),
      .s_valid         (delay_transfer),
      .s_ready         (ls_s_ready),
      .s_tag           (point_tag),
      .s_index         (point_slot),
      .s_delay_q16     (point_delay_q16),
      .s_quality_valid (point_quality_valid),
      .s_error         (4'd0),
      .m_valid         (ls_valid),
      .m_ready         (active_frame && !abort),
      .m_tag           (ls_tag),
      .m_count         (ls_count),
      .m_error         (ls_error),
      .m_upstream_error(ls_upstream_error),
      .m_ppm_q18       (ls_ppm),
      .m_step_q28      (ls_step),
      .m_quality_flags (ls_flags),
      .m_estimate_valid(ls_estimate_valid),
      .busy            (ls_busy)
  );
  task automatic fail_frame(input logic [3:0] code, input logic [3:0] detail);
    begin
      m_error <= code;
      m_detail <= detail;
      m_ppm_q18 <= 0;
      m_step_q28 <= 32'd268435456;
      m_quality_flags <= 0;
      m_estimate_valid <= 0;
      state <= DONE;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      active_slot <= 0;
      m_tag <= 0;
      m_count <= 0;
      m_window_count <= 0;
      m_data_count <= 0;
      m_error <= 0;
      m_detail <= 0;
      m_ppm_q18 <= 0;
      m_step_q28 <= 32'd268435456;
      m_quality_flags <= 0;
      m_estimate_valid <= 0;
    end else if (state == DONE) begin
      if (m_ready) state <= IDLE;
    end else if (state == IDLE) begin
      if (frame_valid && frame_ready) begin
        m_tag <= frame_tag;
        m_count <= 0;
        m_window_count <= 0;
        m_data_count <= 0;
        active_slot <= 0;
        m_error <= 0;
        m_detail <= 0;
        m_ppm_q18 <= 0;
        m_step_q28 <= 32'd268435456;
        m_quality_flags <= 0;
        m_estimate_valid <= 0;
        state <= ARM;
      end
    end else if (abort) fail_frame(5, 0);
    else if (ls_valid) begin
      if (ls_error != 0) fail_frame(4, ls_error);
      else if (ls_tag != m_tag || ls_count != m_count || ls_count != 74 || state != WAIT_FINAL)
        fail_frame(4, 8);
      else begin
        m_ppm_q18 <= ls_ppm;
        m_step_q28 <= ls_step;
        m_quality_flags <= ls_flags;
        m_estimate_valid <= ls_estimate_valid;
        state <= DONE;
      end
    end else
      case (state)
        ARM: if (ls_cfg_ready) state <= WAIT_WINDOW;
        WAIT_WINDOW:
        if (window_valid && window_ready) begin
          m_window_count <= m_window_count + 1;
          if (window_tag != m_tag) fail_frame(1, 2);
          else if (window_slot != m_count || window_slot >= 74) fail_frame(1, 1);
          else begin
            active_slot <= window_slot;
            state <= START_PEAK;
          end
        end
        START_PEAK: if (pk_cfg_ready) state <= ACTIVE;
        ACTIVE: begin
          if (s_valid && s_ready) m_data_count <= m_data_count + 1;
          if (s_valid && s_ready && s_error != 0) fail_frame(6, s_error);
          else if (pk_valid && pk_error != 0) fail_frame(2, pk_error);
          else if (ip_valid && (ip_error != 0 || ip_identity_bad))
            fail_frame(3, ip_error != 0 ? ip_error : 4'd8);
          else if (point_event) begin
            m_count <= m_count + 1;
            state   <= (point_slot == 73) ? WAIT_FINAL : WAIT_WINDOW;
          end
        end
        WAIT_FINAL: begin
        end
        default: fail_frame(4, 8);
      endcase
  end
endmodule
