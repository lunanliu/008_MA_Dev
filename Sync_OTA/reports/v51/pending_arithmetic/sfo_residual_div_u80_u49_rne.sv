`timescale 1ns / 1ps
// One transaction at a time. Unsigned magnitude arithmetic; caller owns sign restoration.
module sfo_residual_div_u80_u49_rne (
    input  logic        clk,
    input  logic        rst,
    input  logic        s_valid,
    output logic        s_ready,
    input  logic [79:0] s_numerator,
    input  logic [48:0] s_denominator,
    input  logic [31:0] s_tag,
    output logic        m_valid,
    input  logic        m_ready,
    output logic [79:0] m_quotient,
    output logic [48:0] m_remainder,
    output logic [80:0] m_rne,
    output logic [31:0] m_tag,
    output logic        m_divide_by_zero,
    output logic        busy
);
  logic [79:0] quotient_shift;
  logic [48:0] divisor;
  logic [48:0] remainder;
  logic [31:0] tag;
  logic [6:0] remaining;
  logic [49:0] trial;
  logic subtract;
  logic [49:0] next_remainder_wide;
  logic [48:0] next_remainder;
  logic [79:0] next_quotient;
  logic [49:0] twice_remainder;
  logic round_up;
  logic round_up_q;
  logic [1:0] round_phase;

  assign s_ready = !rst && !busy && (!m_valid || m_ready);
  assign trial = {remainder, quotient_shift[79]};
  assign subtract = trial >= {1'b0, divisor};
  assign next_remainder_wide = subtract ? trial - {1'b0, divisor} : trial;
  assign next_remainder = next_remainder_wide[48:0];
  assign next_quotient = {quotient_shift[78:0], subtract};
  assign twice_remainder = {remainder, 1'b0};
  assign round_up = (twice_remainder > {1'b0, divisor}) ||
      ((twice_remainder == {1'b0, divisor}) && quotient_shift[0]);

  always_ff @(posedge clk) begin
    if (rst) begin
      quotient_shift <= '0;
      divisor <= '0;
      remainder <= '0;
      tag <= '0;
      remaining <= '0;
      busy <= 0;
      round_phase <= 0; round_up_q <= 0;
      m_valid <= 0;
      m_quotient <= '0;
      m_remainder <= '0;
      m_rne <= '0;
      m_tag <= '0;
      m_divide_by_zero <= 0;
    end else begin
      if (m_valid && m_ready) m_valid <= 0;
      if (s_valid && s_ready) begin
        round_phase <= 0;
        if (s_denominator == 0) begin
          m_valid <= 1;
          m_tag <= s_tag;
          m_quotient <= '0;
          m_remainder <= '0;
          m_rne <= '0;
          m_divide_by_zero <= 1;
          busy <= 0;
        end else begin
          quotient_shift <= s_numerator;
          divisor <= s_denominator;
          remainder <= '0;
          tag <= s_tag;
          remaining <= 7'd80;
          busy <= 1;
        end
      end else if (busy) begin
        if (round_phase == 1) begin
          // Final quotient/remainder are already registered; separate their
          // RNE comparison from both the divide subtract and 81-bit increment.
          round_up_q <= round_up; round_phase <= 2;
        end else if (round_phase == 2) begin
          busy <= 0; round_phase <= 0;
          m_valid <= 1; m_tag <= tag;
          m_quotient <= quotient_shift; m_remainder <= remainder;
          m_rne <= {1'b0,quotient_shift} + {{80{1'b0}},round_up_q};
          m_divide_by_zero <= 0;
        end else begin
          quotient_shift <= next_quotient; remainder <= next_remainder;
          remaining <= remaining - 1'b1;
          if (remaining == 1) round_phase <= 1;
        end
      end
    end
  end
endmodule
