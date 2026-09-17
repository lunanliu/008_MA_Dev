`timescale 1ns/1ps

module fine_corr_cmpy_array #(
  parameter int unsigned LANES = 16,
  parameter int unsigned CMPY_LATENCY = 4
) (
  input  logic clk,
  input  logic rst_n,
  input  logic input_valid,
  input  logic [LANES-1:0][17:0] sample_i,
  input  logic [LANES-1:0][17:0] sample_q,
  input  logic [LANES-1:0][15:0] reference_i,
  input  logic [LANES-1:0][15:0] reference_q,
  input  logic signed [31:0] candidate_start,
  input  logic first_group,
  input  logic last_group,
  input  logic candidate_last,

  output logic output_valid,
  output logic [LANES*35-1:0] product_re,
  output logic [LANES*35-1:0] product_im,
  output logic signed [31:0] output_candidate_start,
  output logic output_first_group,
  output logic output_last_group,
  output logic output_candidate_last,
  output logic ip_protocol_error_sticky,
  output logic reference_conjugate_error_sticky
);
  logic [LANES-1:0] lane_output_valid;
  logic [79:0] lane_output_data [0:LANES-1];
  logic [47:0] lane_a_data [0:LANES-1];
  logic [31:0] lane_b_data [0:LANES-1];
  logic signed [16:0] negative_reference_q [0:LANES-1];
  logic [CMPY_LATENCY-1:0] tag_valid_pipe;
  logic signed [31:0] candidate_start_pipe [0:CMPY_LATENCY-1];
  logic first_pipe [0:CMPY_LATENCY-1];
  logic last_pipe [0:CMPY_LATENCY-1];
  logic candidate_last_pipe [0:CMPY_LATENCY-1];

  function automatic [47:0] pack_complex18(
      input logic signed [17:0] re,
      input logic signed [17:0] im);
    logic [47:0] packed_value;
    begin
      packed_value = '0;
      packed_value[17:0] = re;
      packed_value[23:18] = {6{re[17]}};
      packed_value[41:24] = im;
      packed_value[47:42] = {6{im[17]}};
      return packed_value;
    end
  endfunction

  function automatic [31:0] pack_complex16(
      input logic signed [15:0] re,
      input logic signed [15:0] im);
    return {im,re};
  endfunction

  initial begin
    if (LANES != 16)
      $error("T05 correlation CMPY array requires exactly 16 lanes");
    if (CMPY_LATENCY != 4)
      $error("T05 official correlation CMPY latency is frozen to four cycles");
  end

  for (genvar lane=0; lane<LANES; lane++) begin : g_cmpy
    always_comb begin
      negative_reference_q[lane] = -$signed(reference_q[lane]);
      lane_a_data[lane] = pack_complex18(
          $signed(sample_i[lane]),$signed(sample_q[lane]));
      lane_b_data[lane] = pack_complex16(
          $signed(reference_i[lane]),
          $signed(negative_reference_q[lane][15:0]));
      product_re[lane*35 +: 35] = lane_output_data[lane][34:0];
      product_im[lane*35 +: 35] = lane_output_data[lane][74:40];
    end

    t05_cmpy_corr_18x16 u_corr_cmpy (
      .aclk(clk),
      .s_axis_a_tvalid(input_valid),
      .s_axis_a_tdata(lane_a_data[lane]),
      .s_axis_b_tvalid(input_valid),
      .s_axis_b_tdata(lane_b_data[lane]),
      .m_axis_dout_tvalid(lane_output_valid[lane]),
      .m_axis_dout_tdata(lane_output_data[lane])
    );
  end

  assign output_valid = (&lane_output_valid) &&
      tag_valid_pipe[CMPY_LATENCY-1];
  assign output_candidate_start = candidate_start_pipe[CMPY_LATENCY-1];
  assign output_first_group = first_pipe[CMPY_LATENCY-1];
  assign output_last_group = last_pipe[CMPY_LATENCY-1];
  assign output_candidate_last = candidate_last_pipe[CMPY_LATENCY-1];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tag_valid_pipe <= '0;
      for (int stage=0; stage<CMPY_LATENCY; stage++) begin
        candidate_start_pipe[stage] <= '0;
        first_pipe[stage] <= 1'b0;
        last_pipe[stage] <= 1'b0;
        candidate_last_pipe[stage] <= 1'b0;
      end
      ip_protocol_error_sticky <= 1'b0;
      reference_conjugate_error_sticky <= 1'b0;
    end else begin
      for (int stage=CMPY_LATENCY-1; stage>0; stage--) begin
        tag_valid_pipe[stage] <= tag_valid_pipe[stage-1];
        candidate_start_pipe[stage] <= candidate_start_pipe[stage-1];
        first_pipe[stage] <= first_pipe[stage-1];
        last_pipe[stage] <= last_pipe[stage-1];
        candidate_last_pipe[stage] <= candidate_last_pipe[stage-1];
      end
      tag_valid_pipe[0] <= input_valid;
      if (input_valid) begin
        candidate_start_pipe[0] <= candidate_start;
        first_pipe[0] <= first_group;
        last_pipe[0] <= last_group;
        candidate_last_pipe[0] <= candidate_last;
        for (int lane=0; lane<LANES; lane++) begin
          if (negative_reference_q[lane] > 17'sd32767)
            reference_conjugate_error_sticky <= 1'b1;
        end
      end

      if ((|lane_output_valid) != (&lane_output_valid) ||
          ((&lane_output_valid) != tag_valid_pipe[CMPY_LATENCY-1]))
        ip_protocol_error_sticky <= 1'b1;
      if (&lane_output_valid) begin
        for (int lane=0; lane<LANES; lane++) begin
          if (lane_output_data[lane][39:35] !==
                  {5{lane_output_data[lane][34]}} ||
              lane_output_data[lane][79:75] !==
                  {5{lane_output_data[lane][74]}})
            ip_protocol_error_sticky <= 1'b1;
        end
      end
    end
  end
endmodule
