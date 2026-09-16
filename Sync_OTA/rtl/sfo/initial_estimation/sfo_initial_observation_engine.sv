`timescale 1ns / 1ps
`include "initial_observation_ip_config.svh"
// One exact T06 observation, no normalization/five sums. Frozen pair/BFP is
// instantiated unchanged. Admission reserves one of 128 final-output credits.
module sfo_initial_observation_engine (
    input  logic               clk,
    input  logic               rst,
    input  logic               s_valid,
    output logic               s_ready,
    input  logic        [31:0] s_first_iq,
    input  logic        [31:0] s_second_iq,
    input  logic        [31:0] s_tag,
    output logic               m_valid,
    input  logic               m_ready,
    output logic signed [47:0] m_phase,
    output logic signed [47:0] m_native_phase,
    output logic        [31:0] m_power_first,
    output logic        [31:0] m_power_second,
    output logic        [63:0] m_weight_numerator,
    output logic        [32:0] m_weight_denominator,
    output logic        [31:0] m_tag,
    output logic               m_zero_power,
    output logic               m_axis_mapped,
    output logic               m_error,
    output logic        [ 7:0] pending_count,
    output logic               protocol_error_sticky
);
  localparam integer SQUARE_LAT = `SFO_INITIAL_OBS_SQUARE_LATENCY;
  localparam integer WEIGHT_LAT = `SFO_INITIAL_OBS_WEIGHT_LATENCY;
  localparam integer CORDIC_LAT = 57;
  localparam integer ALIGN_LAT = CORDIC_LAT - SQUARE_LAT - 1 - WEIGHT_LAT;
  localparam logic signed [47:0] PHASE_ONE = 48'sh200000000000;
  localparam logic signed [47:0] PHASE_TWO = 48'sh400000000000;
  typedef struct packed {logic [31:0] tag, second_iq, first_iq;} input_t;
  typedef struct packed {
    logic [63:0] nw;
    logic [32:0] dw;
    logic [31:0] p1, p2;
  } weight_t;
  typedef struct packed {
    logic [31:0] tag;
    logic signed [47:0] phase, native_phase;
    logic [31:0] p1, p2;
    logic [63:0] nw;
    logic [32:0] dw;
    logic zero_power, axis_mapped, error;
  } output_t;
  input_t input_head;
  output_t output_head, output_word;
  logic input_full, input_empty, input_wr_busy, input_rd_busy, input_overflow, input_underflow;
  logic
      output_full, output_empty, output_wr_busy, output_rd_busy, output_overflow, output_underflow;
  logic accept, consume, can_admit, pair_ready, pair_valid, pair_output_ready, launch;
  logic signed [32:0] pair_re, pair_im;
  logic signed [47:0] pair_bfp_re, pair_bfp_im;
  logic [5:0] pair_shift, pair_pending;
  logic pair_zero, pair_error, pair_protocol;
  logic [31:0] pair_tag;
  logic [95:0] cordic_cartesian, cordic_result;
  logic cordic_valid, output_write;
  logic [CORDIC_LAT-1:0] observation_valid, zero_pipe, axis_pipe, error_pipe;
  logic [31:0] tag_pipe[0:CORDIC_LAT-1];
  logic [SQUARE_LAT-1:0] square_valid;
  logic [31:0] squares[0:3];
  logic [32:0] power1_sum, power2_sum;
  logic [31:0] power1_reg, power2_reg;
  logic [32:0] denominator_reg;
  logic power_valid;
  logic [63:0] weight_product;
  logic [WEIGHT_LAT-1:0] product_valid;
  logic [96:0] power_meta[0:WEIGHT_LAT-1];
  weight_t aligned_weight[0:ALIGN_LAT-1];
  logic [ALIGN_LAT-1:0] aligned_valid;
  integer stage;

  assign m_valid = !rst && !output_rd_busy && !output_empty;
  assign consume = m_valid && m_ready;
  assign can_admit = !rst && !protocol_error_sticky && !input_full && !input_wr_busy &&
      !input_rd_busy && !output_wr_busy && !output_rd_busy && (pending_count < 128);
  assign s_ready = can_admit && pair_ready;
  assign accept = s_valid && s_ready;
  sfo_initial_pair_phasor_bfp pair_bfp (
      .clk                  (clk),
      .rst                  (rst),
      .s_valid              (s_valid && can_admit),
      .s_ready              (pair_ready),
      .s_first_iq           (s_first_iq),
      .s_second_iq          (s_second_iq),
      .s_tag                (s_tag),
      .m_valid              (pair_valid),
      .m_ready              (pair_output_ready),
      .m_phasor_re          (pair_re),
      .m_phasor_im          (pair_im),
      .m_bfp_re             (pair_bfp_re),
      .m_bfp_im             (pair_bfp_im),
      .m_shift              (pair_shift),
      .m_zero               (pair_zero),
      .m_error              (pair_error),
      .m_tag                (pair_tag),
      .pending_count        (pair_pending),
      .protocol_error_sticky(pair_protocol)
  );
  assign pair_output_ready = !rst && !input_empty && !input_rd_busy && !output_wr_busy;
  assign launch = pair_valid && pair_output_ready;
  sfo_initial_observation_engine_fifo #(
      .WIDTH($bits(input_t)),
      .DEPTH(32)
  ) input_fifo (
      .clk      (clk),
      .rst      (rst),
      .wr_en    (accept),
      .rd_en    (launch),
      .din      ({s_tag, s_second_iq, s_first_iq}),
      .dout     (input_head),
      .full     (input_full),
      .empty    (input_empty),
      .wr_busy  (input_wr_busy),
      .rd_busy  (input_rd_busy),
      .overflow (input_overflow),
      .underflow(input_underflow)
  );
  // Dummy Cartesian is private to the vendor adapter, not the BFP node.
  assign cordic_cartesian = pair_zero ? {48'd0, 48'h200000000000} : {pair_bfp_im, pair_bfp_re};
  t06_cordic_translate48_parallel translate (
      .aclk                   (clk),
      .aresetn                (!rst),
      .s_axis_cartesian_tvalid(launch),
      .s_axis_cartesian_tdata (cordic_cartesian),
      .m_axis_dout_tvalid     (cordic_valid),
      .m_axis_dout_tdata      (cordic_result)
  );
  t06_observation_engine_square square_i1 (
      .CLK(clk),
      .A  (input_head.first_iq[15:0]),
      .B  (input_head.first_iq[15:0]),
      .P  (squares[0])
  );
  t06_observation_engine_square square_q1 (
      .CLK(clk),
      .A  (input_head.first_iq[31:16]),
      .B  (input_head.first_iq[31:16]),
      .P  (squares[1])
  );
  t06_observation_engine_square square_i2 (
      .CLK(clk),
      .A  (input_head.second_iq[15:0]),
      .B  (input_head.second_iq[15:0]),
      .P  (squares[2])
  );
  t06_observation_engine_square square_q2 (
      .CLK(clk),
      .A  (input_head.second_iq[31:16]),
      .B  (input_head.second_iq[31:16]),
      .P  (squares[3])
  );
  assign power1_sum = {1'b0, squares[0]} + {1'b0, squares[1]};
  assign power2_sum = {1'b0, squares[2]} + {1'b0, squares[3]};
  t06_observation_engine_weight_product product (
      .CLK(clk),
      .A  (power1_reg),
      .B  (power2_reg),
      .P  (weight_product)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      pending_count <= 0;
      protocol_error_sticky <= 0;
      observation_valid <= '0;
      zero_pipe <= '0;
      axis_pipe <= '0;
      error_pipe <= '0;
      square_valid <= '0;
      power_valid <= 0;
      product_valid <= '0;
      aligned_valid <= '0;
      power1_reg <= 0;
      power2_reg <= 0;
      denominator_reg <= 0;
      for (stage = 0; stage < CORDIC_LAT; stage = stage + 1) tag_pipe[stage] <= 0;
      for (stage = 0; stage < WEIGHT_LAT; stage = stage + 1) power_meta[stage] <= 0;
      for (stage = 0; stage < ALIGN_LAT; stage = stage + 1) aligned_weight[stage] <= '0;
    end else begin
      case ({
        accept, consume
      })
        2'b10:   pending_count <= pending_count + 8'd1;
        2'b01:   pending_count <= pending_count - 8'd1;
        default: pending_count <= pending_count;
      endcase
      observation_valid <= {observation_valid[CORDIC_LAT-2:0], launch};
      zero_pipe <= {zero_pipe[CORDIC_LAT-2:0], pair_zero};
      axis_pipe <= {axis_pipe[CORDIC_LAT-2:0], (pair_re < 0 && pair_im == 0 && !pair_zero)};
      error_pipe <= {error_pipe[CORDIC_LAT-2:0], pair_error};
      tag_pipe[0] <= pair_tag;
      for (stage = 1; stage < CORDIC_LAT; stage = stage + 1) tag_pipe[stage] <= tag_pipe[stage-1];
      square_valid <= {square_valid[SQUARE_LAT-2:0], launch};
      power_valid <= square_valid[SQUARE_LAT-1];
      power1_reg <= power1_sum[31:0];
      power2_reg <= power2_sum[31:0];
      denominator_reg <= power1_sum + power2_sum;
      product_valid <= {product_valid[WEIGHT_LAT-2:0], power_valid};
      power_meta[0] <= {denominator_reg, power1_reg, power2_reg};
      for (stage = 1; stage < WEIGHT_LAT; stage = stage + 1)
      power_meta[stage] <= power_meta[stage-1];
      aligned_valid <= {aligned_valid[ALIGN_LAT-2:0], product_valid[WEIGHT_LAT-1]};
      aligned_weight[0] <= {weight_product, power_meta[WEIGHT_LAT-1]};
      for (stage = 1; stage < ALIGN_LAT; stage = stage + 1)
      aligned_weight[stage] <= aligned_weight[stage-1];
      if (pair_protocol || input_overflow || input_underflow || output_overflow || output_underflow
          || (launch && (pair_tag != input_head.tag || pair_zero !=
                         ((input_head.first_iq == 0) || (input_head.second_iq == 0)))) ||
          (cordic_valid != observation_valid[CORDIC_LAT-1]) ||
          (aligned_valid[ALIGN_LAT-1] != observation_valid[CORDIC_LAT-1]))
        protocol_error_sticky <= 1;
    end
  end
  always_comb begin
    output_word = '0;
    output_word.tag = tag_pipe[CORDIC_LAT-1];
    output_word.native_phase = $signed(cordic_result[95:48]);
    output_word.phase = output_word.native_phase;
    if (output_word.native_phase >= PHASE_ONE)
      output_word.phase = output_word.native_phase - PHASE_TWO;
    else if (output_word.native_phase < -PHASE_ONE)
      output_word.phase = output_word.native_phase + PHASE_TWO;
    output_word.zero_power  = zero_pipe[CORDIC_LAT-1];
    output_word.axis_mapped = axis_pipe[CORDIC_LAT-1];
    if (output_word.zero_power) output_word.phase = 0;
    else if (output_word.axis_mapped) output_word.phase = -PHASE_ONE;
    output_word.p1 = aligned_weight[ALIGN_LAT-1].p1;
    output_word.p2 = aligned_weight[ALIGN_LAT-1].p2;
    output_word.nw = aligned_weight[ALIGN_LAT-1].nw;
    output_word.dw = aligned_weight[ALIGN_LAT-1].dw;
    output_word.error = error_pipe[CORDIC_LAT-1] || output_word.phase < -PHASE_ONE ||
        output_word.phase >= PHASE_ONE;
  end
  assign output_write = !rst && !output_wr_busy && observation_valid[CORDIC_LAT-1] && cordic_valid;
  sfo_initial_observation_engine_fifo #(
      .WIDTH($bits(output_t)),
      .DEPTH(128)
  ) result_fifo (
      .clk      (clk),
      .rst      (rst),
      .wr_en    (output_write),
      .rd_en    (consume),
      .din      (output_word),
      .dout     (output_head),
      .full     (output_full),
      .empty    (output_empty),
      .wr_busy  (output_wr_busy),
      .rd_busy  (output_rd_busy),
      .overflow (output_overflow),
      .underflow(output_underflow)
  );
  assign m_phase = output_head.phase;
  assign m_native_phase = output_head.native_phase;
  assign m_power_first = output_head.p1;
  assign m_power_second = output_head.p2;
  assign m_weight_numerator = output_head.nw;
  assign m_weight_denominator = output_head.dw;
  assign m_tag = output_head.tag;
  assign m_zero_power = output_head.zero_power;
  assign m_axis_mapped = output_head.axis_mapped;
  assign m_error = output_head.error;
`ifndef SYNTHESIS
  initial
    if (SQUARE_LAT != 3 || WEIGHT_LAT != 4 || ALIGN_LAT != 49)
      $fatal(1, "Observation IP schedule mismatch");
  always @(posedge clk)
    if (!rst) begin
      if (pending_count > 128 || (consume && pending_count == 0) || protocol_error_sticky)
        $fatal(1, "Observation credit/protocol invariant");
      if (launch && (pair_tag !== input_head.tag || pair_error ||
                     pair_zero !== ((input_head.first_iq == 0) || (input_head.second_iq == 0))))
        $fatal(1, "Observation pair/power association mismatch");
      if (square_valid[SQUARE_LAT-1] && (squares[0][31] || squares[1][31] || squares[2][31] ||
                                         squares[3][31] || power1_sum[32] || power2_sum[32]))
        $fatal(1, "Observation square/power exact range violation");
      if (cordic_valid !== observation_valid[CORDIC_LAT-1] ||
          aligned_valid[ALIGN_LAT-1] !== observation_valid[CORDIC_LAT-1])
        $fatal(1, "Observation CORDIC/power latency mismatch");
      if (output_write &&
          (output_full || output_word.error ||
           (output_word.zero_power && (output_word.nw != 0 || output_word.phase != 0))))
        $fatal(1, "Observation output invariant");
    end
`endif
endmodule
