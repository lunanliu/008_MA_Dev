`timescale 1ns/1ps

module coarse_corr_energy_4lane #(
  parameter int unsigned CMPY_LATENCY = 4
) (
  input  logic clk,
  input  logic rst_n,

  input  logic pair_valid,
  input  logic pair_first,
  input  logic pair_last,
  input  logic [127:0] pair_current_data,
  input  logic [127:0] pair_delayed_data,
  input  logic [31:0] pair_frame_id,
  input  logic [31:0] pair_current_base_sample_index,
  input  logic pair_context_valid,

  output logic aggregate_valid,
  output logic aggregate_first,
  output logic aggregate_last,
  output logic signed [34:0] aggregate_p_re,
  output logic signed [34:0] aggregate_p_im,
  output logic [33:0] aggregate_energy,
  output logic [31:0] aggregate_frame_id,
  output logic [31:0] aggregate_current_base_sample_index,
  output logic aggregate_context_valid,

  output logic arithmetic_overflow_sticky,
  output logic ip_protocol_error_sticky
);
  logic signed [15:0] current_i [0:3];
  logic signed [15:0] current_q [0:3];
  logic signed [15:0] delayed_i [0:3];
  logic signed [15:0] delayed_q [0:3];
  logic signed [16:0] current_i_extended [0:3];
  logic signed [16:0] current_conjugate_q [0:3];
  logic signed [16:0] delayed_i_extended [0:3];
  logic signed [16:0] delayed_conjugate_q [0:3];

  logic [3:0] corr_valid;
  logic [3:0] energy_valid;
  logic [79:0] corr_data [0:3];
  logic [79:0] energy_data [0:3];
  logic signed [33:0] corr_re_physical [0:3];
  logic signed [33:0] corr_im_physical [0:3];
  logic signed [32:0] corr_re_logical [0:3];
  logic signed [32:0] corr_im_logical [0:3];
  logic [31:0] energy_logical [0:3];

  logic [CMPY_LATENCY-1:0] metadata_valid_pipe;
  logic [CMPY_LATENCY-1:0] first_pipe;
  logic [CMPY_LATENCY-1:0] last_pipe;
  logic [CMPY_LATENCY-1:0] context_pipe;
  logic [31:0] frame_id_pipe [0:CMPY_LATENCY-1];
  logic [31:0] base_index_pipe [0:CMPY_LATENCY-1];

  logic all_ip_valid;
  logic any_ip_valid;
  logic invariant_failure;
  logic signed [35:0] p_re_sum_extended;
  logic signed [35:0] p_im_sum_extended;
  logic [34:0] energy_sum_extended;

  function automatic logic [47:0] pack_cmpy_a(
      input logic signed [16:0] real_component,
      input logic signed [16:0] imag_component);
    begin
      pack_cmpy_a = '0;
      pack_cmpy_a[16:0] = real_component;
      pack_cmpy_a[23:17] = {7{real_component[16]}};
      pack_cmpy_a[40:24] = imag_component;
      pack_cmpy_a[47:41] = {7{imag_component[16]}};
    end
  endfunction

  function automatic logic [31:0] pack_cmpy_b(
      input logic signed [15:0] real_component,
      input logic signed [15:0] imag_component);
    begin
      pack_cmpy_b = {imag_component, real_component};
    end
  endfunction

  initial begin
    if (CMPY_LATENCY != 4)
      $error("The measured production CMPY latency is four cycles");
  end

  for (genvar lane = 0; lane < 4; lane++) begin : g_lane
    assign current_i[lane] =
        $signed(pair_current_data[lane*32 +: 16]);
    assign current_q[lane] =
        $signed(pair_current_data[lane*32+16 +: 16]);
    assign delayed_i[lane] =
        $signed(pair_delayed_data[lane*32 +: 16]);
    assign delayed_q[lane] =
        $signed(pair_delayed_data[lane*32+16 +: 16]);

    assign current_i_extended[lane] =
        {current_i[lane][15], current_i[lane]};
    assign current_conjugate_q[lane] =
        -$signed({current_q[lane][15], current_q[lane]});
    assign delayed_i_extended[lane] =
        {delayed_i[lane][15], delayed_i[lane]};
    assign delayed_conjugate_q[lane] =
        -$signed({delayed_q[lane][15], delayed_q[lane]});

    t04_cmpy_17x16 u_correlation_cmpy (
      .aclk(clk),
      .s_axis_a_tvalid(pair_valid),
      .s_axis_a_tdata(pack_cmpy_a(
          delayed_i_extended[lane], delayed_conjugate_q[lane])),
      .s_axis_b_tvalid(pair_valid),
      .s_axis_b_tdata(pack_cmpy_b(
          current_i[lane], current_q[lane])),
      .m_axis_dout_tvalid(corr_valid[lane]),
      .m_axis_dout_tdata(corr_data[lane])
    );

    t04_cmpy_17x16 u_energy_cmpy (
      .aclk(clk),
      .s_axis_a_tvalid(pair_valid),
      .s_axis_a_tdata(pack_cmpy_a(
          current_i_extended[lane], current_conjugate_q[lane])),
      .s_axis_b_tvalid(pair_valid),
      .s_axis_b_tdata(pack_cmpy_b(
          current_i[lane], current_q[lane])),
      .m_axis_dout_tvalid(energy_valid[lane]),
      .m_axis_dout_tdata(energy_data[lane])
    );

    assign corr_re_physical[lane] =
        $signed(corr_data[lane][33:0]);
    assign corr_im_physical[lane] =
        $signed(corr_data[lane][73:40]);
    assign corr_re_logical[lane] =
        $signed(corr_data[lane][32:0]);
    assign corr_im_logical[lane] =
        $signed(corr_data[lane][72:40]);
    assign energy_logical[lane] = energy_data[lane][31:0];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      metadata_valid_pipe <= '0;
      first_pipe <= '0;
      last_pipe <= '0;
      context_pipe <= '0;
      for (int stage = 0; stage < CMPY_LATENCY; stage++) begin
        frame_id_pipe[stage] <= '0;
        base_index_pipe[stage] <= '0;
      end
    end else begin
      metadata_valid_pipe[0] <= pair_valid;
      first_pipe[0] <= pair_first;
      last_pipe[0] <= pair_last;
      context_pipe[0] <= pair_context_valid;
      frame_id_pipe[0] <= pair_frame_id;
      base_index_pipe[0] <= pair_current_base_sample_index;
      for (int stage = 1; stage < CMPY_LATENCY; stage++) begin
        metadata_valid_pipe[stage] <= metadata_valid_pipe[stage-1];
        first_pipe[stage] <= first_pipe[stage-1];
        last_pipe[stage] <= last_pipe[stage-1];
        context_pipe[stage] <= context_pipe[stage-1];
        frame_id_pipe[stage] <= frame_id_pipe[stage-1];
        base_index_pipe[stage] <= base_index_pipe[stage-1];
      end
    end
  end

  always_comb begin
    p_re_sum_extended = '0;
    p_im_sum_extended = '0;
    energy_sum_extended = '0;
    invariant_failure = 1'b0;
    for (int lane = 0; lane < 4; lane++) begin
      p_re_sum_extended = p_re_sum_extended +
          {{3{corr_re_logical[lane][32]}}, corr_re_logical[lane]};
      p_im_sum_extended = p_im_sum_extended +
          {{3{corr_im_logical[lane][32]}}, corr_im_logical[lane]};
      energy_sum_extended = energy_sum_extended +
          {{3{1'b0}}, energy_logical[lane]};

      if (corr_valid[lane]) begin
        if (corr_data[lane][39:34] !=
                {6{corr_re_physical[lane][33]}} ||
            corr_data[lane][79:74] !=
                {6{corr_im_physical[lane][33]}} ||
            corr_re_physical[lane][33] !=
                corr_re_physical[lane][32] ||
            corr_im_physical[lane][33] !=
                corr_im_physical[lane][32])
          invariant_failure = 1'b1;
      end

      if (energy_valid[lane]) begin
        if (energy_data[lane][39:34] != 6'b0 ||
            energy_data[lane][79:74] !=
                {6{energy_data[lane][73]}} ||
            energy_data[lane][33:32] != 2'b0 ||
            $signed(energy_data[lane][73:40]) != 0)
          invariant_failure = 1'b1;
      end
    end
    if (p_re_sum_extended[35] != p_re_sum_extended[34] ||
        p_im_sum_extended[35] != p_im_sum_extended[34] ||
        energy_sum_extended[34])
      invariant_failure = 1'b1;
  end

  assign all_ip_valid = (&corr_valid) && (&energy_valid);
  assign any_ip_valid = (|corr_valid) || (|energy_valid);

  always_comb begin
    aggregate_valid =
        metadata_valid_pipe[CMPY_LATENCY-1] && all_ip_valid;
    aggregate_first = aggregate_valid &&
        first_pipe[CMPY_LATENCY-1];
    aggregate_last = aggregate_valid &&
        last_pipe[CMPY_LATENCY-1];
    aggregate_p_re = p_re_sum_extended[34:0];
    aggregate_p_im = p_im_sum_extended[34:0];
    aggregate_energy = energy_sum_extended[33:0];
    aggregate_frame_id = frame_id_pipe[CMPY_LATENCY-1];
    aggregate_current_base_sample_index =
        base_index_pipe[CMPY_LATENCY-1];
    aggregate_context_valid = context_pipe[CMPY_LATENCY-1];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      arithmetic_overflow_sticky <= 1'b0;
      ip_protocol_error_sticky <= 1'b0;
    end else begin
      if ((metadata_valid_pipe[CMPY_LATENCY-1] ||
           any_ip_valid) &&
          !(metadata_valid_pipe[CMPY_LATENCY-1] &&
            all_ip_valid))
        ip_protocol_error_sticky <= 1'b1;
      if (aggregate_valid && invariant_failure)
        arithmetic_overflow_sticky <= 1'b1;
    end
  end
endmodule
