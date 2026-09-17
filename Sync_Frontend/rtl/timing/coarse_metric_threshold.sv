`timescale 1ns/1ps

module coarse_metric_threshold #(
  parameter int unsigned MULTIPLIER_PIPE_STAGES = 6
) (
  input  logic clk,
  input  logic rst_n,

  input  logic metric_in_valid,
  input  logic metric_in_last,
  input  logic [8:0] metric_in_index,
  input  logic signed [42:0] metric_in_p_re,
  input  logic signed [42:0] metric_in_p_im,
  input  logic [41:0] metric_in_energy,

  output logic metric_out_valid,
  output logic metric_out_last,
  output logic [8:0] metric_out_index,
  output logic signed [42:0] metric_out_p_re,
  output logic signed [42:0] metric_out_p_im,
  output logic [41:0] metric_out_energy,
  output logic metric_out_qualified,

  output logic [86:0] metric_out_p_magnitude_squared,
  output logic [83:0] metric_out_energy_squared,
  output logic [93:0] metric_out_threshold_lhs,
  output logic [85:0] metric_out_threshold_rhs
);
  logic [85:0] p_re_squared;
  logic [85:0] p_im_squared;
  logic [83:0] energy_squared;

  logic [MULTIPLIER_PIPE_STAGES-1:0] valid_pipe;
  logic [MULTIPLIER_PIPE_STAGES-1:0] last_pipe;
  logic [8:0] index_pipe [0:MULTIPLIER_PIPE_STAGES-1];
  logic signed [42:0] p_re_pipe [0:MULTIPLIER_PIPE_STAGES-1];
  logic signed [42:0] p_im_pipe [0:MULTIPLIER_PIPE_STAGES-1];
  logic [41:0] energy_pipe [0:MULTIPLIER_PIPE_STAGES-1];

  logic square_stage_valid;
  logic square_stage_last;
  logic [8:0] square_stage_index;
  logic signed [42:0] square_stage_p_re;
  logic signed [42:0] square_stage_p_im;
  logic [41:0] square_stage_energy;
  logic [86:0] square_stage_p_magnitude_squared;
  logic [83:0] square_stage_energy_squared;

  logic threshold_stage_valid;
  logic threshold_stage_last;
  logic [8:0] threshold_stage_index;
  logic signed [42:0] threshold_stage_p_re;
  logic signed [42:0] threshold_stage_p_im;
  logic [41:0] threshold_stage_energy;
  logic [86:0] threshold_stage_p_magnitude_squared;
  logic [83:0] threshold_stage_energy_squared;
  logic [93:0] threshold_stage_lhs;
  logic [85:0] threshold_stage_rhs;

  initial begin
    if (MULTIPLIER_PIPE_STAGES != 6)
      $error("Production Multiplier Generator PipeStages must be six");
  end

  t04_square_s43 u_square_p_re (
    .CLK(clk),
    .A(metric_in_p_re),
    .B(metric_in_p_re),
    .P(p_re_squared)
  );

  t04_square_s43 u_square_p_im (
    .CLK(clk),
    .A(metric_in_p_im),
    .B(metric_in_p_im),
    .P(p_im_squared)
  );

  t04_square_u42 u_square_energy (
    .CLK(clk),
    .A(metric_in_energy),
    .B(metric_in_energy),
    .P(energy_squared)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_pipe <= '0;
      last_pipe <= '0;
      for (int stage = 0; stage < MULTIPLIER_PIPE_STAGES; stage++) begin
        index_pipe[stage] <= '0;
        p_re_pipe[stage] <= '0;
        p_im_pipe[stage] <= '0;
        energy_pipe[stage] <= '0;
      end
    end else begin
      valid_pipe[0] <= metric_in_valid;
      last_pipe[0] <= metric_in_last;
      index_pipe[0] <= metric_in_index;
      p_re_pipe[0] <= metric_in_p_re;
      p_im_pipe[0] <= metric_in_p_im;
      energy_pipe[0] <= metric_in_energy;
      for (int stage = 1;
           stage < MULTIPLIER_PIPE_STAGES; stage++) begin
        valid_pipe[stage] <= valid_pipe[stage-1];
        last_pipe[stage] <= last_pipe[stage-1];
        index_pipe[stage] <= index_pipe[stage-1];
        p_re_pipe[stage] <= p_re_pipe[stage-1];
        p_im_pipe[stage] <= p_im_pipe[stage-1];
        energy_pipe[stage] <= energy_pipe[stage-1];
      end
    end
  end

  always_ff @(posedge clk) begin
    logic [93:0] p_magnitude_extended;
    logic [85:0] energy_squared_extended;
    if (!rst_n) begin
      square_stage_valid <= 1'b0;
      square_stage_last <= 1'b0;
      square_stage_index <= '0;
      square_stage_p_re <= '0;
      square_stage_p_im <= '0;
      square_stage_energy <= '0;
      square_stage_p_magnitude_squared <= '0;
      square_stage_energy_squared <= '0;
      threshold_stage_valid <= 1'b0;
      threshold_stage_last <= 1'b0;
      threshold_stage_index <= '0;
      threshold_stage_p_re <= '0;
      threshold_stage_p_im <= '0;
      threshold_stage_energy <= '0;
      threshold_stage_p_magnitude_squared <= '0;
      threshold_stage_energy_squared <= '0;
      threshold_stage_lhs <= '0;
      threshold_stage_rhs <= '0;
      metric_out_valid <= 1'b0;
      metric_out_last <= 1'b0;
      metric_out_index <= '0;
      metric_out_p_re <= '0;
      metric_out_p_im <= '0;
      metric_out_energy <= '0;
      metric_out_qualified <= 1'b0;
      metric_out_p_magnitude_squared <= '0;
      metric_out_energy_squared <= '0;
      metric_out_threshold_lhs <= '0;
      metric_out_threshold_rhs <= '0;
    end else begin
      square_stage_valid <=
          valid_pipe[MULTIPLIER_PIPE_STAGES-1];
      square_stage_last <=
          last_pipe[MULTIPLIER_PIPE_STAGES-1];
      square_stage_index <=
          index_pipe[MULTIPLIER_PIPE_STAGES-1];
      square_stage_p_re <=
          p_re_pipe[MULTIPLIER_PIPE_STAGES-1];
      square_stage_p_im <=
          p_im_pipe[MULTIPLIER_PIPE_STAGES-1];
      square_stage_energy <=
          energy_pipe[MULTIPLIER_PIPE_STAGES-1];
      square_stage_p_magnitude_squared <=
          {1'b0, p_re_squared} + {1'b0, p_im_squared};
      square_stage_energy_squared <= energy_squared;

      p_magnitude_extended =
          {{7{1'b0}}, square_stage_p_magnitude_squared};
      energy_squared_extended =
          {{2{1'b0}}, square_stage_energy_squared};
      threshold_stage_valid <= square_stage_valid;
      threshold_stage_last <= square_stage_last;
      threshold_stage_index <= square_stage_index;
      threshold_stage_p_re <= square_stage_p_re;
      threshold_stage_p_im <= square_stage_p_im;
      threshold_stage_energy <= square_stage_energy;
      threshold_stage_p_magnitude_squared <=
          square_stage_p_magnitude_squared;
      threshold_stage_energy_squared <=
          square_stage_energy_squared;
      threshold_stage_lhs <=
          (p_magnitude_extended << 6) +
          (p_magnitude_extended << 5) +
          (p_magnitude_extended << 2);
      threshold_stage_rhs <=
          (energy_squared_extended << 1) +
          energy_squared_extended;

      metric_out_valid <= threshold_stage_valid;
      metric_out_last <= threshold_stage_last;
      metric_out_index <= threshold_stage_index;
      metric_out_p_re <= threshold_stage_p_re;
      metric_out_p_im <= threshold_stage_p_im;
      metric_out_energy <= threshold_stage_energy;
      metric_out_qualified <= threshold_stage_valid &&
          (threshold_stage_energy > 0) &&
          (threshold_stage_lhs >= threshold_stage_rhs);
      metric_out_p_magnitude_squared <=
          threshold_stage_p_magnitude_squared;
      metric_out_energy_squared <=
          threshold_stage_energy_squared;
      metric_out_threshold_lhs <= threshold_stage_lhs;
      metric_out_threshold_rhs <= threshold_stage_rhs;
    end
  end
endmodule
