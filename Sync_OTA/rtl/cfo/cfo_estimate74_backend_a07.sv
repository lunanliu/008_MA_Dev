`timescale 1ns/1ps
// A07: join the two actual 74-observation results into one held output register.
// Neither downstream ready nor the decision arithmetic crosses the result boundary.
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
 logic result_valid;
 wire result_space=!result_valid&&!rst&&!abort_sync;
 wire join_accept=result_space&&p_valid&&q_valid;
 assign m_valid=result_valid&&!rst&&!abort_sync;
 logic [31:0] next_frame,next_generation;
 logic [3:0] next_error;
 logic [1:0] next_mode;
 logic next_estimate_valid,next_spectrum,next_phase_linear,next_consistent;
 logic signed [31:0] next_frequency_q16,next_phase_q16,next_fft_q16;
 logic [196:0] next_quality;
 logic [131:0] next_phase_detail;
 cfo_phase74_core phase_core(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(s_valid&&q_ready),.s_ready(p_ready),
  .s_frame(s_frame),.s_generation(s_generation),.s_index(s_index),.s_last(s_last),.s_i(s_i),.s_q(s_q),
  .m_valid(p_valid),.m_ready(result_space&&q_valid),.m_frame(p_frame),.m_generation(p_generation),.m_nonzero(p_nonzero),.m_phase_linear(p_linear),
  .m_error(p_error),.m_frequency_q16(p_frequency),.m_weighted_sum(p_dot),.m_max_centered(p_maximum),.m_cordic_saturations(p_saturations),
  .phase_audit_valid(),.phase_audit_index(),.phase_audit_angle(),.phase_audit_unwrapped(),.pred_audit_valid(),.pred_audit_index(),.pred_audit_value(),.pred_audit_residual(),.center_audit_valid(),.center_audit_index(),.center_audit_value());
 cfo_fft74_quality quality_core(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(s_valid&&p_ready),.s_ready(q_ready),
  .s_frame(s_frame),.s_generation(s_generation),.s_index(s_index),.s_last(s_last),.s_i(s_i),.s_q(s_q),
  .m_valid(q_valid),.m_ready(result_space&&p_valid),.m_frame(q_frame),.m_generation(q_generation),.m_error(q_error),.m_nonzero(q_nonzero),
  .m_spectrum(q_spectrum),.m_frequency_q16(q_frequency),.m_quality(q_detail),
  .normal_audit_valid(normal_audit_valid),.normal_audit_index(normal_audit_index),.normal_audit_value(normal_audit_value),
  .fft_audit_valid(fft_audit_valid),.fft_audit_index(fft_audit_index),.fft_audit_value(fft_audit_value));
 wire signed [63:0] phase64={{32{p_frequency[31]}},p_frequency},fft64={{32{q_frequency[31]}},q_frequency};
 wire signed [63:0] difference=phase64-fft64;
 wire [63:0] abs_difference=difference[63] ? -difference : difference;
 wire [63:0] abs_phase=phase64[63] ? -phase64 : phase64;
 wire [63:0] abs_fft=fft64[63] ? -fft64 : fft64;
 // abs(signed32-signed32) <= 2^32-1: the old uint64 product cannot overflow.
 // floor(32768000000000 / 4587520) = 7142857, remainder 655360.
 wire consistent=abs_difference<=64'd7142857;
 always_comb begin
  next_frame=p_frame;next_generation=p_generation;next_error=0;
  if(p_error!=0)next_error=p_error;
  else if(q_error!=0)next_error=q_error;
  else if(p_valid&&q_valid&&(p_frame!=q_frame || p_generation!=q_generation || p_nonzero!=q_nonzero))next_error=5;
  next_mode=0;next_estimate_valid=0;next_frequency_q16=0;
  next_phase_q16=p_frequency;next_fft_q16=q_frequency;next_spectrum=q_spectrum;next_phase_linear=p_linear;next_consistent=consistent;
  next_quality=q_detail;next_phase_detail={p_dot,p_maximum,p_saturations};
  if(next_error!=0)begin
   next_phase_q16=0;next_fft_q16=0;next_spectrum=0;next_phase_linear=0;next_consistent=0;next_quality=0;next_phase_detail=0;
  end else if(!q_nonzero)begin
   next_mode=3;next_phase_q16=0;next_fft_q16=0;next_spectrum=0;next_phase_linear=0;next_consistent=0;next_quality=0;
  end else if(q_spectrum&&p_linear&&consistent&&abs_phase<=64'd851968000)begin
   next_mode=1;next_estimate_valid=1;next_frequency_q16=p_frequency;
  end else if(q_spectrum&&abs_fft<=64'd851968000)begin
   next_mode=2;next_estimate_valid=1;next_frequency_q16=q_frequency;
  end
 end
 // Consume both core results together. A held output is never overwritten.
 // The deliberate one-cycle refill gap is between frame estimates, not samples.
 always_ff @(posedge clk)begin
  if(rst||abort_sync)begin
   result_valid<=0;
   {m_frame,m_generation,m_error,m_mode,m_estimate_valid,m_frequency_q16,m_phase_q16,m_fft_q16,m_spectrum,m_phase_linear,m_consistent,m_quality,m_phase_detail}<='0;
  end else begin
   if(result_valid&&m_ready)result_valid<=0;
   if(join_accept)begin
    result_valid<=1;
    {m_frame,m_generation,m_error,m_mode,m_estimate_valid,m_frequency_q16,m_phase_q16,m_fft_q16,m_spectrum,m_phase_linear,m_consistent,m_quality,m_phase_detail}<=
     {next_frame,next_generation,next_error,next_mode,next_estimate_valid,next_frequency_q16,next_phase_q16,next_fft_q16,next_spectrum,next_phase_linear,next_consistent,next_quality,next_phase_detail};
   end
  end
 end
endmodule