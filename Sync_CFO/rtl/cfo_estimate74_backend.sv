`timescale 1ns/1ps
// Joins actual phase and FFT-quality RTL results from the same 74 observations.
module cfo_estimate74_backend(
 input logic clk,rst,abort_sync,input logic s_valid,output logic s_ready,
 input logic [31:0] s_frame,s_generation,input logic [6:0] s_index,input logic s_last,
 input logic signed [37:0] s_i,s_q,
 output logic m_valid,input logic m_ready,
 output logic [31:0] m_frame,m_generation,output logic [3:0] m_error,
 output logic [1:0] m_mode,output logic m_estimate_valid,
 output logic signed [31:0] m_frequency_q16,m_phase_q16,m_fft_q16,
 output logic m_spectrum,m_phase_linear,m_consistent,
 output logic [196:0] m_quality,output logic [131:0] m_phase_detail,
 output logic normal_audit_valid,output logic [6:0] normal_audit_index,output logic [39:0] normal_audit_value,
 output logic fft_audit_valid,output logic [7:0] fft_audit_index,output logic [79:0] fft_audit_value
);
 wire p_ready,q_ready,p_valid,q_valid;
 wire [31:0] p_frame,p_generation,q_frame,q_generation;wire [3:0] p_error,q_error;
 wire p_nonzero,p_linear,q_nonzero,q_spectrum;
 wire signed [31:0] p_frequency,q_frequency;wire signed [55:0] p_dot;
 wire [63:0] p_maximum;wire [11:0] p_saturations;wire [196:0] q_detail;
 assign s_ready=p_ready&&q_ready;
 assign m_valid=p_valid&&q_valid;
 cfo_phase74_core phase_core(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(s_valid&&q_ready),.s_ready(p_ready),
  .s_frame(s_frame),.s_generation(s_generation),.s_index(s_index),.s_last(s_last),.s_i(s_i),.s_q(s_q),
  .m_valid(p_valid),.m_ready(m_ready&&q_valid),.m_frame(p_frame),.m_generation(p_generation),.m_nonzero(p_nonzero),.m_phase_linear(p_linear),
  .m_error(p_error),.m_frequency_q16(p_frequency),.m_weighted_sum(p_dot),.m_max_centered(p_maximum),.m_cordic_saturations(p_saturations),
  .phase_audit_valid(),.phase_audit_index(),.phase_audit_angle(),.phase_audit_unwrapped(),.pred_audit_valid(),.pred_audit_index(),.pred_audit_value(),.pred_audit_residual(),.center_audit_valid(),.center_audit_index(),.center_audit_value());
 cfo_fft74_quality quality_core(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(s_valid&&p_ready),.s_ready(q_ready),
  .s_frame(s_frame),.s_generation(s_generation),.s_index(s_index),.s_last(s_last),.s_i(s_i),.s_q(s_q),
  .m_valid(q_valid),.m_ready(m_ready&&p_valid),.m_frame(q_frame),.m_generation(q_generation),.m_error(q_error),.m_nonzero(q_nonzero),
  .m_spectrum(q_spectrum),.m_frequency_q16(q_frequency),.m_quality(q_detail),
  .normal_audit_valid(normal_audit_valid),.normal_audit_index(normal_audit_index),.normal_audit_value(normal_audit_value),
  .fft_audit_valid(fft_audit_valid),.fft_audit_index(fft_audit_index),.fft_audit_value(fft_audit_value));
 wire signed [63:0] phase64={{32{p_frequency[31]}},p_frequency},fft64={{32{q_frequency[31]}},q_frequency};
 wire signed [63:0] difference=phase64-fft64;
 wire [63:0] abs_difference=difference[63] ? -difference : difference;
 wire [63:0] abs_phase=phase64[63] ? -phase64 : phase64;
 wire [63:0] abs_fft=fft64[63] ? -fft64 : fft64;
 wire consistent=(abs_difference*64'd4587520)<=64'd32768000000000;
 always_comb begin
  m_frame=p_frame;m_generation=p_generation;m_error=0;
  if(p_error!=0)m_error=p_error;
  else if(q_error!=0)m_error=q_error;
  else if(p_valid&&q_valid&&(p_frame!=q_frame || p_generation!=q_generation || p_nonzero!=q_nonzero))m_error=5;
  m_mode=0;m_estimate_valid=0;m_frequency_q16=0;
  m_phase_q16=p_frequency;m_fft_q16=q_frequency;m_spectrum=q_spectrum;m_phase_linear=p_linear;m_consistent=consistent;
  m_quality=q_detail;m_phase_detail={p_dot,p_maximum,p_saturations};
  if(m_error!=0)begin
   m_phase_q16=0;m_fft_q16=0;m_spectrum=0;m_phase_linear=0;m_consistent=0;m_quality=0;m_phase_detail=0;
  end else if(!q_nonzero)begin
   m_mode=3;m_phase_q16=0;m_fft_q16=0;m_spectrum=0;m_phase_linear=0;m_consistent=0;m_quality=0;
  end else if(q_spectrum&&p_linear&&consistent&&abs_phase<=64'd851968000)begin
   m_mode=1;m_estimate_valid=1;m_frequency_q16=p_frequency;
  end else if(q_spectrum&&abs_fft<=64'd851968000)begin
   m_mode=2;m_estimate_valid=1;m_frequency_q16=q_frequency;
  end
 end
endmodule