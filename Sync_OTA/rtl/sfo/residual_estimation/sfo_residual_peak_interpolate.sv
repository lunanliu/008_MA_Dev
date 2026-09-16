// Scalar three-point power interpolation and per-symbol quality.
// U32 powers; signed delta-bin Q16 and signed sample-delay Q16.
// Single transaction; original divider retains its accepted 80-step arithmetic.
module sfo_residual_peak_interpolate (
    input  logic               clk,
    input  logic               rst,
    input  logic               abort,
    input  logic               s_valid,
    output logic               s_ready,
    input  logic        [31:0] s_tag,
    input  logic        [ 6:0] s_symbol_slot,
    input  logic        [ 3:0] s_error,
    input  logic        [10:0] s_peak_bin,
    input  logic        [31:0] s_prev_power,
    input  logic        [31:0] s_peak_power,
    input  logic        [31:0] s_next_power,
    input  logic        [31:0] s_competing_power,
    output logic               m_valid,
    input  logic               m_ready,
    output logic        [31:0] m_tag,
    output logic        [ 6:0] m_symbol_slot,
    output logic        [ 3:0] m_error,
    output logic        [10:0] m_peak_bin,
    output logic signed [17:0] m_delta_bin_q16,
    output logic signed [23:0] m_delay_q16,
    output logic        [ 3:0] m_quality_flags,
    output logic               m_quality_valid,
    output logic               busy
);
  localparam [2:0] IDLE = 0, MATH = 1, DREQ = 2, DWAIT = 3, FINALIZE = 4, DONE = 5;
  localparam [24:0] QUALITY_RATIO_Q24 = 25'd33474947;
  logic [2:0] state;
  logic [31:0] a, b, c, competitor;
  logic [56:0] ratio_left, ratio_right;
  logic interpolate_ok, negative_delta;
  logic [79:0] numerator;
  logic [48:0] denominator;
  logic div_ready, div_valid, div_zero, div_busy;
  logic [79:0] div_quotient;
  logic [48:0] div_remainder;
  logic [80:0] div_rne;
  logic [31:0] div_tag;
  wire signed [33:0] curvature = $signed(
      {2'b00, a}
  ) - $signed(
      {1'b0, b, 1'b0}
  ) + $signed(
      {2'b00, c}
  );
  wire [33:0] minus_curvature = -curvature;
  wire [32:0] abs_difference = (a >= c) ? {1'b0, a} - {1'b0, c} : {1'b0, c} - {1'b0, a};
  wire can_interpolate = (curvature < 0) && abs_difference <= minus_curvature;
  wire signed [11:0] peak_offset = m_peak_bin[10] ? $signed(
      {1'b0, m_peak_bin}
  ) - 12'sd2048 : $signed(
      {1'b0, m_peak_bin}
  );
  wire interior = (peak_offset > -12'sd48 && peak_offset < 12'sd48);
  wire ratio_ok = (b != 0) && ratio_left >= ratio_right;
  wire signed [31:0] total_delay_twice_q16 = ($signed(
      {{20{peak_offset[11]}}, peak_offset}
  ) <<< 16) + $signed(
      {{14{m_delta_bin_q16[17]}}, m_delta_bin_q16}
  );
  function automatic signed [23:0] half_rne(input logic signed [31:0] value);
    logic [31:0] magnitude, quotient;
    begin
      magnitude = value[31] ? -value : value;
      quotient  = magnitude >> 1;
      if (magnitude[0] && quotient[0]) quotient = quotient + 1;
      half_rne = value[31] ? -$signed(quotient[23:0]) : $signed(quotient[23:0]);
    end
  endfunction
  assign s_ready = !rst && !abort && state == IDLE;
  assign m_valid = !rst && state == DONE;
  assign busy = state != IDLE;
  sfo_residual_div_u80_u49_rne divider (
      .clk             (clk),
      .rst             (rst || abort || state == IDLE || state == DONE),
      .s_valid         (state == DREQ && !abort),
      .s_ready         (div_ready),
      .s_numerator     (numerator),
      .s_denominator   (denominator),
      .s_tag           (m_tag),
      .m_valid         (div_valid),
      .m_ready         (state == DWAIT && !abort),
      .m_quotient      (div_quotient),
      .m_remainder     (div_remainder),
      .m_rne           (div_rne),
      .m_tag           (div_tag),
      .m_divide_by_zero(div_zero),
      .busy            (div_busy)
  );
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      m_tag <= 0;
      m_symbol_slot <= 0;
      m_error <= 0;
      m_peak_bin <= 0;
      m_delta_bin_q16 <= 0;
      m_delay_q16 <= 0;
      m_quality_flags <= 0;
      m_quality_valid <= 0;
      a <= 0;
      b <= 0;
      c <= 0;
      competitor <= 0;
      ratio_left <= 0;
      ratio_right <= 0;
      interpolate_ok <= 0;
      negative_delta <= 0;
      numerator <= 0;
      denominator <= 0;
    end else if (state == DONE) begin
      if (m_ready) state <= IDLE;
    end else if (state == IDLE) begin
      if (s_valid && s_ready) begin
        m_tag <= s_tag;
        m_symbol_slot <= s_symbol_slot;
        m_peak_bin <= s_peak_bin;
        a <= s_prev_power;
        b <= s_peak_power;
        c <= s_next_power;
        competitor <= s_competing_power;
        m_delta_bin_q16 <= 0;
        m_delay_q16 <= 0;
        m_quality_flags <= 0;
        m_quality_valid <= 0;
        m_error <= 0;
        interpolate_ok <= 0;
        if (s_error != 0) begin
          m_error <= s_error;
          state   <= DONE;
        end else if (s_symbol_slot >= 74 || (s_peak_bin > 48 && s_peak_bin < 2000)) begin
          m_error <= 7;
          state   <= DONE;
        end else state <= MATH;
      end
    end else if (abort) begin
      m_error <= 4;
      m_delta_bin_q16 <= 0;
      m_delay_q16 <= 0;
      m_quality_flags <= 0;
      m_quality_valid <= 0;
      state <= DONE;
    end else
      case (state)
        MATH: begin
          ratio_left <= {1'b0, b, 24'd0};
          ratio_right <= competitor * QUALITY_RATIO_Q24;
          interpolate_ok <= can_interpolate;
          negative_delta <= a > c;
          numerator <= {31'd0, abs_difference, 16'd0};
          denominator <= {14'd0, minus_curvature, 1'b0};
          state <= can_interpolate ? DREQ : FINALIZE;
        end
        DREQ: if (div_ready) state <= DWAIT;
        DWAIT:
        if (div_valid) begin
          if (div_zero || div_tag != m_tag || div_rne > 81'd32768) begin
            m_error <= 8;
            m_delta_bin_q16 <= 0;
            m_delay_q16 <= 0;
            m_quality_flags <= 0;
            m_quality_valid <= 0;
            state <= DONE;
          end else begin
            m_delta_bin_q16 <= negative_delta ? -$signed(div_rne[17:0]) : $signed(div_rne[17:0]);
            state <= FINALIZE;
          end
        end
        FINALIZE: begin
          m_delay_q16 <= half_rne(total_delay_twice_q16);
          m_quality_flags <= {(b != 0), ratio_ok, interior, interpolate_ok};
          m_quality_valid <= ratio_ok && interior && interpolate_ok;
          state <= DONE;
        end
        default: begin
          m_error <= 8;
          m_quality_flags <= 0;
          m_quality_valid <= 0;
          state <= DONE;
        end
      endcase
  end
endmodule
