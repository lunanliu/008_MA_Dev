`timescale 1ns/1ps

module cfo_coarse_estimator #(
  parameter int unsigned PHASE_SCALE_LATENCY = 6
) (
  input  logic clk,
  input  logic rst_n,

  input  logic request_valid,
  output logic request_ready,
  input  logic signed [47:0] safe_p_re,
  input  logic signed [47:0] safe_p_im,
  input  logic [46:0] safe_energy,

  output logic engine_busy,
  output logic result_valid,
  output logic result_algorithm_valid,
  output logic result_energy_or_correlation_invalid,
  output logic signed [47:0] result_phase_code_q3_45,
  output logic [47:0] result_magnitude_code_q1_47,
  output logic signed [31:0] result_cfo_hz,
  output logic [15:0] result_quality_q1_15,

  output logic arithmetic_overflow_sticky,
  output logic ip_protocol_error_sticky
);
  typedef enum logic [1:0] {
    STATE_IDLE,
    STATE_SEND_CORDIC,
    STATE_WAIT_CORDIC,
    STATE_WAIT_FINAL
  } engine_state_t;

  engine_state_t state;
  logic signed [47:0] safe_p_re_reg;
  logic signed [47:0] safe_p_im_reg;
  logic [46:0] safe_energy_reg;

  logic cordic_input_ready;
  logic cordic_output_valid;
  logic [95:0] cordic_output_data;
  // Scaled_Radians: signed Q3.45 code represents phase/pi.
  logic signed [47:0] cordic_phase_code_q3_45;
  logic [47:0] cordic_magnitude_code;

  logic signed [47:0] phase_code_q3_45_reg;
  logic [47:0] magnitude_code_reg;
  logic signed [68:0] phase_product_q3_45_x_1953125;
  logic [PHASE_SCALE_LATENCY-1:0] phase_scale_valid_pipe;
  logic cfo_done;
  logic signed [31:0] cfo_reg;

  logic divider_pending;
  logic divider_divisor_ready;
  logic divider_dividend_ready;
  logic divider_send;
  logic divider_output_valid;
  logic [0:0] divider_output_user;
  logic [111:0] divider_output_data;
  logic quality_done;
  logic [15:0] quality_reg;
  logic transaction_error;

  function automatic logic signed [31:0]
      round_q3_45_phase_product_to_hz(
      input logic signed [68:0] product);
    logic [68:0] absolute_product;
    logic [20:0] quotient;
    logic [47:0] remainder;
    logic increment;
    logic signed [31:0] signed_quotient;
    begin
      if (product[68])
        absolute_product = $unsigned(-product);
      else
        absolute_product = $unsigned(product);
      // CFO = phase_q3_45 * 1953125 / 2^48.  The 21-bit
      // magnitude plus one RNE carry is safely contained in signed 32 bits.
      quotient = absolute_product[68:48];
      remainder = absolute_product[47:0];
      increment = (remainder > 48'h8000_0000_0000) ||
          ((remainder == 48'h8000_0000_0000) && quotient[0]);
      signed_quotient = $signed({11'b0, quotient}) +
          $signed({31'b0, increment});
      if (product[68])
        round_q3_45_phase_product_to_hz = -signed_quotient;
      else
        round_q3_45_phase_product_to_hz = signed_quotient;
    end
  endfunction

  initial begin
    if (PHASE_SCALE_LATENCY != 6)
      $error("The production phase-scale Multiplier Generator latency is six");
  end

  assign request_ready = (state == STATE_IDLE);
  assign engine_busy = (state != STATE_IDLE);

  assign cordic_phase_code_q3_45 =
      $signed(cordic_output_data[95:48]);
  assign cordic_magnitude_code = cordic_output_data[47:0];

  t04_cordic_translate_48 u_phase_magnitude_cordic (
    .aclk(clk),
    .aresetn(rst_n),
    .s_axis_cartesian_tvalid(state == STATE_SEND_CORDIC),
    .s_axis_cartesian_tready(cordic_input_ready),
    .s_axis_cartesian_tdata({safe_p_im_reg, safe_p_re_reg}),
    .m_axis_dout_tvalid(cordic_output_valid),
    .m_axis_dout_tdata(cordic_output_data)
  );

  t04_phase_scale_s48_x_1953125 u_phase_to_hz_numerator (
    .CLK(clk),
    .A(cordic_phase_code_q3_45),
    .P(phase_product_q3_45_x_1953125)
  );

  assign divider_send = divider_pending &&
      divider_divisor_ready && divider_dividend_ready;

  t04_div_u63_u47 u_quality_divider (
    .aclk(clk),
    .aresetn(rst_n),
    .s_axis_divisor_tvalid(divider_send),
    .s_axis_divisor_tready(divider_divisor_ready),
    .s_axis_divisor_tdata({1'b0, safe_energy_reg}),
    .s_axis_dividend_tvalid(divider_send),
    .s_axis_dividend_tready(divider_dividend_ready),
    .s_axis_dividend_tdata(
        {1'b0, magnitude_code_reg, 15'b0}),
    .m_axis_dout_tvalid(divider_output_valid),
    .m_axis_dout_tuser(divider_output_user),
    .m_axis_dout_tdata(divider_output_data)
  );

  always_ff @(posedge clk) begin
    logic invalid_request;
    logic phase_sign_extension_invariant;
    logic divider_container_invariant;
    logic [62:0] divider_quotient;
    if (!rst_n) begin
      state <= STATE_IDLE;
      safe_p_re_reg <= '0;
      safe_p_im_reg <= '0;
      safe_energy_reg <= '0;
      phase_code_q3_45_reg <= '0;
      magnitude_code_reg <= '0;
      phase_scale_valid_pipe <= '0;
      cfo_done <= 1'b0;
      cfo_reg <= '0;
      divider_pending <= 1'b0;
      quality_done <= 1'b0;
      quality_reg <= '0;
      transaction_error <= 1'b0;
      result_valid <= 1'b0;
      result_algorithm_valid <= 1'b0;
      result_energy_or_correlation_invalid <= 1'b0;
      result_phase_code_q3_45 <= '0;
      result_magnitude_code_q1_47 <= '0;
      result_cfo_hz <= '0;
      result_quality_q1_15 <= '0;
      arithmetic_overflow_sticky <= 1'b0;
      ip_protocol_error_sticky <= 1'b0;
    end else begin
      result_valid <= 1'b0;
      result_energy_or_correlation_invalid <= 1'b0;
      phase_scale_valid_pipe <= {
          phase_scale_valid_pipe[PHASE_SCALE_LATENCY-2:0],
          cordic_output_valid};

      if (request_valid && !request_ready)
        ip_protocol_error_sticky <= 1'b1;

      if (request_valid && request_ready) begin
        invalid_request = (safe_energy == 0) ||
            ((safe_p_re == 0) && (safe_p_im == 0));
        safe_p_re_reg <= safe_p_re;
        safe_p_im_reg <= safe_p_im;
        safe_energy_reg <= safe_energy;
        cfo_done <= 1'b0;
        quality_done <= 1'b0;
        divider_pending <= 1'b0;
        transaction_error <= 1'b0;
        result_algorithm_valid <= 1'b0;
        if (invalid_request) begin
          result_valid <= 1'b1;
          result_energy_or_correlation_invalid <= 1'b1;
          result_phase_code_q3_45 <= '0;
          result_magnitude_code_q1_47 <= '0;
          result_cfo_hz <= '0;
          result_quality_q1_15 <= '0;
          state <= STATE_IDLE;
        end else begin
          state <= STATE_SEND_CORDIC;
        end
      end

      if (state == STATE_SEND_CORDIC && cordic_input_ready)
        state <= STATE_WAIT_CORDIC;

      if (cordic_output_valid) begin
        if (state != STATE_WAIT_CORDIC) begin
          ip_protocol_error_sticky <= 1'b1;
          transaction_error <= 1'b1;
        end else begin
          phase_sign_extension_invariant =
              cordic_phase_code_q3_45[47:46] ==
              {2{cordic_phase_code_q3_45[45]}};
          if (!phase_sign_extension_invariant ||
              cordic_magnitude_code[47]) begin
            arithmetic_overflow_sticky <= 1'b1;
            transaction_error <= 1'b1;
          end
          phase_code_q3_45_reg <= cordic_phase_code_q3_45;
          magnitude_code_reg <= cordic_magnitude_code;
          divider_pending <= 1'b1;
          state <= STATE_WAIT_FINAL;
        end
      end

      if (divider_pending &&
          (divider_divisor_ready != divider_dividend_ready)) begin
        ip_protocol_error_sticky <= 1'b1;
        transaction_error <= 1'b1;
      end
      if (divider_send)
        divider_pending <= 1'b0;

      if (phase_scale_valid_pipe[PHASE_SCALE_LATENCY-1]) begin
        if (state != STATE_WAIT_FINAL) begin
          ip_protocol_error_sticky <= 1'b1;
          transaction_error <= 1'b1;
        end
        cfo_reg <= round_q3_45_phase_product_to_hz(
            phase_product_q3_45_x_1953125);
        cfo_done <= 1'b1;
      end

      if (divider_output_valid) begin
        divider_container_invariant =
            !divider_output_data[111] &&
            !divider_output_data[47] &&
            !divider_output_user[0];
        if (state != STATE_WAIT_FINAL ||
            !divider_container_invariant) begin
          ip_protocol_error_sticky <= 1'b1;
          transaction_error <= 1'b1;
        end
        divider_quotient = divider_output_data[110:48];
        if (divider_quotient >= 63'd32768)
          quality_reg <= 16'd32768;
        else
          quality_reg <= divider_quotient[15:0];
        quality_done <= 1'b1;
      end

      if (state == STATE_WAIT_FINAL && cfo_done && quality_done) begin
        result_valid <= 1'b1;
        result_algorithm_valid <= !transaction_error;
        result_energy_or_correlation_invalid <= 1'b0;
        result_phase_code_q3_45 <= phase_code_q3_45_reg;
        result_magnitude_code_q1_47 <= magnitude_code_reg;
        result_cfo_hz <= transaction_error ? 32'sd0 : cfo_reg;
        result_quality_q1_15 <=
            transaction_error ? 16'd0 : quality_reg;
        cfo_done <= 1'b0;
        quality_done <= 1'b0;
        state <= STATE_IDLE;
      end

      if (cordic_output_valid && state == STATE_IDLE)
        ip_protocol_error_sticky <= 1'b1;
      if (divider_output_valid && state == STATE_IDLE)
        ip_protocol_error_sticky <= 1'b1;
    end
  end
endmodule
