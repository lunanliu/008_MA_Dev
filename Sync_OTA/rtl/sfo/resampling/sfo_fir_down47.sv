`timescale 1ns / 1ps
// Research wrapper: official FIR Compiler performs all FIR/RNE arithmetic.
// Decimator phase adapter: w[n]=x[n-1], w[0]=0. The observed official
// SSR decimator keeps (h*w)[2*k+1], which is (h*x)[2*k], the G3 contract.
// Carry state advances only on accepted input beats; no extra input beat.
// The one-entry elastic output register clips the guarded result to signed16.
module sfo_fir_down47 #(
    parameter integer IT = 8,
    OT = 4,
    parameter integer GW = 17,
    GS = 8 * ((GW + 7) / 8)
) (
    input  wire               aclk,
    input  wire               aresetn,
    input  wire               s_axis_data_tvalid,
    input  wire [  IT*32-1:0] s_axis_data_tdata,
    output wire               s_axis_data_tready,
    input  wire               m_axis_data_tready,
    output reg                m_axis_data_tvalid,
    output reg  [  OT*32-1:0] m_axis_data_tdata,
    output reg  [OT*2*GS-1:0] debug_guarded_data,
    output reg  [   OT*2-1:0] saturation
);
  reg [31:0] previous_complex_sample;
  wire [IT*32-1:0] phase_aligned_data = {s_axis_data_tdata[(IT-1)*32-1:0], previous_complex_sample};
  always @(posedge aclk) begin
    if (!aresetn) previous_complex_sample <= 32'b0;
    else if (s_axis_data_tvalid && s_axis_data_tready)
      previous_complex_sample <= s_axis_data_tdata[(IT-1)*32+:32];
  end
  wire [IT*16-1:0] i_in, q_in;
  wire [OT*GS-1:0] i_out, q_out;
  wire [OT*2*GS-1:0] packed_guarded;
  wire ri, rq, vi, vq;
  wire take_output = ~m_axis_data_tvalid | m_axis_data_tready;
  assign s_axis_data_tready = ri & rq;
  genvar lane;
  generate
    for (lane = 0; lane < IT; lane = lane + 1) begin : input_unpack
      assign i_in[lane*16+:16] = phase_aligned_data[(lane*2)*16+:16];
      assign q_in[lane*16+:16] = phase_aligned_data[(lane*2+1)*16+:16];
    end
    for (lane = 0; lane < OT; lane = lane + 1) begin : output_pack
      assign packed_guarded[(lane*2)*GS+:GS]   = i_out[lane*GS+:GS];
      assign packed_guarded[(lane*2+1)*GS+:GS] = q_out[lane*GS+:GS];
    end
  endgenerate
  t07_g3_down47 i_core (
      .aclk              (aclk),
      .aresetn           (aresetn),
      .s_axis_data_tvalid(s_axis_data_tvalid),
      .s_axis_data_tready(ri),
      .s_axis_data_tdata (i_in),
      .m_axis_data_tready(take_output),
      .m_axis_data_tvalid(vi),
      .m_axis_data_tdata (i_out)
  );
  t07_g3_down47 q_core (
      .aclk              (aclk),
      .aresetn           (aresetn),
      .s_axis_data_tvalid(s_axis_data_tvalid),
      .s_axis_data_tready(rq),
      .s_axis_data_tdata (q_in),
      .m_axis_data_tready(take_output),
      .m_axis_data_tvalid(vq),
      .m_axis_data_tdata (q_out)
  );
  function automatic [15:0] clip16(input reg signed [GW-1:0] value);
    begin
      if (value > 32767) clip16 = 16'h7fff;
      else if (value < -32768) clip16 = 16'h8000;
      else clip16 = value[15:0];
    end
  endfunction
  function automatic saturated(input reg signed [GW-1:0] value);
    saturated = (value > 32767 || value < -32768);
  endfunction
  integer component;
  always @(posedge aclk) begin
    if (!aresetn) begin
      m_axis_data_tvalid <= 0;
      m_axis_data_tdata <= 0;
      debug_guarded_data <= 0;
      saturation <= 0;
    end else if (take_output) begin
      m_axis_data_tvalid <= vi & vq;
      if (vi & vq) begin
        debug_guarded_data <= packed_guarded;
        for (component = 0; component < OT * 2; component = component + 1) begin
          m_axis_data_tdata[component*16+:16] <= clip16($signed(packed_guarded[component*GS+:GW]));
          saturation[component] <= saturated($signed(packed_guarded[component*GS+:GW]));
        end
      end
    end
  end
  // synthesis translate_off
  initial if (IT < 2 || IT != 2 * OT) $fatal(1, "Phase adapter requires decimation2");
  initial if (GW < 16 || GW > 32) $fatal(1, "Unsupported guarded width");
  always @(posedge aclk)
    if (aresetn) begin
      if (ri !== rq) $fatal(1, "I/Q ready divergence");
      if (vi !== vq) $fatal(1, "I/Q valid divergence");
    end
  // synthesis translate_on
endmodule
