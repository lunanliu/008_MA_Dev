`timescale 1ns / 1ps
// T06 ppm S32/F18 -> positive R28 step -> unique raw-coordinate phase.
// Configuration arithmetic only. Never accepts an externally precomputed phase.
module sfo_first_pass_descriptor #(
    parameter integer NOMINAL_SAMPLES = 1336320
) (
    input  logic               clk,
    input  logic               rst,
    input  logic               s_valid,
    output logic               s_ready,
    input  logic        [31:0] s_frame_id,
    input  logic        [31:0] s_generation,
    input  logic        [31:0] s_estimate_frame_id,
    input  logic        [31:0] s_estimate_generation,
    input  logic        [15:0] s_estimate_status,
    input  logic signed [31:0] s_ppm_q18,
    input  logic signed [31:0] s_to,
    input  logic signed [31:0] s_raw_first,
    input  logic signed [31:0] s_available_first,
    input  logic signed [31:0] s_available_last,
    input  logic signed [31:0] s_nominal_first,
    input  logic        [27:0] s_q0,
    input  logic        [31:0] s_input_count,
    input  logic        [31:0] s_nominal_count,
    output logic               m_valid,
    input  logic               m_ready,
    output logic        [ 7:0] m_error,
    output logic        [31:0] m_frame_id,
    output logic        [31:0] m_generation,
    output logic        [31:0] m_step,
    output logic signed [63:0] m_phase,
    output logic signed [31:0] m_raw_first,
    output logic signed [31:0] m_nominal_first
);
  localparam logic signed [63:0] Q = 64'sd268435456;
  localparam integer INPUT_COUNT = NOMINAL_SAMPLES + 540;
  localparam integer REQUEST_POINTS = 4 * (NOMINAL_SAMPLES + 104);
  // rev02: bounded configuration work. One 15-bit divide step or one
  // 64-bit address accumulator addition per cycle; no combinational divide/MAC.
  typedef enum logic [3:0] {
    IDLE,
    PREP,
    COORD,
    DIVIDE,
    ROUND_STEP,
    SET_STEP,
    START_PHASE_MUL,
    PHASE_MUL,
    SET_PHASE,
    END_MUL,
    SET_END,
    CHECK,
    HOLD
  } state_t;
  state_t state;
  logic [25:0] ppm_mag;
  logic negative_ppm;
  logic [29:0] div_numerator, div_quotient;
  logic [13:0] div_remainder;
  logic [ 5:0] bit_count;
  logic [31:0] delta;
  logic signed [63:0] phase_last, raw64, out64, to64, q064, coordinate_term, phase_bias;
  logic signed [63:0] mul_shift, mul_acc;
  logic [28:0] mul_bits;
  logic [ 7:0] input_error;
  logic signed [63:0] first_base, last_base;
  wire [14:0] divide_trial = {div_remainder, div_numerator[29]};
  wire divide_take = divide_trial >= 15'd15625;
  wire [14:0] divide_reduced = divide_trial - 15'd15625;
  wire round_up = ({div_remainder, 1'b0} > 15'd15625) ||
      (({div_remainder, 1'b0} == 15'd15625) && div_quotient[0]);
  wire signed [63:0] mul_sum = mul_acc + (mul_bits[0] ? mul_shift : 64'sd0);
  function automatic logic signed [63:0] carried_base(input logic signed [63:0] v);
    logic [8:0] mu;
    begin
      mu = {1'b0, v[27:20]} + ((v[19:0] > 20'h80000) || ((v[19:0] == 20'h80000) && v[20]));
      carried_base = (v >>> 28) + (mu == 256);
    end
  endfunction
  always_comb begin
    input_error = 0;
    if (s_frame_id != s_estimate_frame_id || s_generation != s_estimate_generation)
      input_error = 8'h10;
    else if (s_estimate_status != 16'h4800) input_error = 8'h11;
    else if (s_ppm_q18 < -32'sd39321600 || s_ppm_q18 > 32'sd39321600) input_error = 8'h12;
    else if (s_to < -101 || s_to > 101 || (s_q0 != 0 && s_q0 != 28'd134217728)) input_error = 8'h13;
    else if (s_input_count != INPUT_COUNT || s_nominal_count != NOMINAL_SAMPLES)
      input_error = 8'h14;
    else if ($signed(
            {{32{s_raw_first[31]}}, s_raw_first}
        ) != $signed(
            {{32{s_nominal_first[31]}}, s_nominal_first}
        ) - 64'sd172 || s_nominal_first < 0 || s_nominal_first > 1336320 - NOMINAL_SAMPLES)
      input_error = 8'h15;
    else if (s_available_first > s_raw_first || $signed(
            {{32{s_available_last[31]}}, s_available_last}
        ) < $signed(
            {{32{s_raw_first[31]}}, s_raw_first}
        ) + INPUT_COUNT - 1)
      input_error = 8'h16;
    first_base = carried_base(m_phase);
    last_base  = carried_base(phase_last);
  end
  assign s_ready = !rst && state == IDLE;
  assign m_valid = !rst && state == HOLD;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      m_error <= 0;
      m_frame_id <= 0;
      m_generation <= 0;
      m_step <= 0;
      m_phase <= 0;
      m_raw_first <= 0;
      m_nominal_first <= 0;
      ppm_mag <= 0;
      negative_ppm <= 0;
      div_numerator <= 0;
      div_quotient <= 0;
      div_remainder <= 0;
      bit_count <= 0;
      delta <= 0;
      phase_last <= 0;
      raw64 <= 0;
      out64 <= 0;
      to64 <= 0;
      q064 <= 0;
      coordinate_term <= 0;
      phase_bias <= 0;
      mul_shift <= 0;
      mul_acc <= 0;
      mul_bits <= 0;
    end else
      case (state)
        IDLE:
        if (s_valid && s_ready) begin
          m_frame_id <= s_frame_id;
          m_generation <= s_generation;
          m_raw_first <= s_raw_first;
          m_nominal_first <= s_nominal_first;
          negative_ppm <= s_ppm_q18 < 0;
          // Legal magnitude <=39321600 fits U26; invalid descriptors never compute.
          ppm_mag <= s_ppm_q18 < 0 ? -s_ppm_q18 : s_ppm_q18;
          raw64 <= $signed(s_raw_first);
          out64 <= $signed(s_nominal_first);
          to64 <= $signed(s_to);
          q064 <= $signed({36'd0, s_q0});
          m_error <= input_error;
          m_step <= 0;
          m_phase <= 0;
          state <= input_error != 0 ? HOLD : PREP;
        end
        PREP: begin
          div_numerator <= {ppm_mag, 4'b0};
          div_quotient <= 0;
          div_remainder <= 0;
          bit_count <= 0;
          coordinate_term <= 64'sd53 + (to64 <<< 2) - (raw64 <<< 2);
          state <= COORD;
        end
        COORD: begin
          phase_bias <= (coordinate_term <<< 28) + (q064 <<< 2);
          state <= DIVIDE;
        end
        DIVIDE: begin
          div_remainder <= divide_take ? divide_reduced[13:0] : divide_trial[13:0];
          div_quotient  <= {div_quotient[28:0], divide_take};
          div_numerator <= {div_numerator[28:0], 1'b0};
          if (bit_count == 29) state <= ROUND_STEP;
          else bit_count <= bit_count + 1'b1;
        end
        ROUND_STEP: begin
          delta <= {2'd0, div_quotient} + round_up;
          state <= SET_STEP;
        end
        SET_STEP: begin
          m_step <= negative_ppm ? 32'd268435456 - delta : 32'd268435456 + delta;
          state  <= START_PHASE_MUL;
        end
        START_PHASE_MUL: begin
          mul_shift <= (out64 <<< 2) - 64'sd215;
          mul_acc <= 0;
          mul_bits <= m_step[28:0];
          bit_count <= 0;
          state <= PHASE_MUL;
        end
        PHASE_MUL: begin
          mul_acc   <= mul_sum;
          mul_shift <= mul_shift <<< 1;
          mul_bits  <= mul_bits >> 1;
          if (bit_count == 28) state <= SET_PHASE;
          else bit_count <= bit_count + 1'b1;
        end
        SET_PHASE: begin
          m_phase <= phase_bias + mul_acc;
          mul_shift <= REQUEST_POINTS - 1;
          mul_acc <= 0;
          mul_bits <= m_step[28:0];
          bit_count <= 0;
          state <= END_MUL;
        end
        END_MUL: begin
          mul_acc   <= mul_sum;
          mul_shift <= mul_shift <<< 1;
          mul_bits  <= mul_bits >> 1;
          if (bit_count == 28) state <= SET_END;
          else bit_count <= bit_count + 1'b1;
        end
        SET_END: begin
          phase_last <= m_phase + mul_acc;
          state <= CHECK;
        end
        CHECK: begin
          if (m_step < 268395191 || m_step > 268475721 || m_phase < 0 || phase_last < m_phase ||
              first_base - 64'sd107 < 0 || last_base + 64'sd2 >= 4 * INPUT_COUNT)
            m_error <= 8'h17;
          state <= HOLD;
        end
        HOLD: if (m_valid && m_ready) state <= IDLE;
        default: begin
          m_error <= 8'h18;
          state   <= HOLD;
        end
      endcase
  end
  // synthesis translate_off
  initial
    if (NOMINAL_SAMPLES != 1336320 && NOMINAL_SAMPLES != 5120)
      $fatal(1, "T08 production or explicitly short module test only");
  // synthesis translate_on
endmodule
