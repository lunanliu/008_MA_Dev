`timescale 1ns/1ps
// Production closure: actual T06, two independent resamplers, actual T09,
// full-size R0/R1/output memories and explicit 125/150/500 MHz boundaries.
// Select150 explicitly for the T10-to-CFO output profile; IQ sample rate remains500MS/s.
module t10_two_pass_system #(parameter integer OUTPUT_CLOCK_MHZ=150)(
 input logic clk125,clk150,clk500,reset_request,abort125,
 input logic s_valid,output logic s_ready,input logic [127:0] s_data,
 input logic [31:0] s_frame_id,input logic signed [31:0] s_absolute_index,input logic [3:0] s_lane_valid,
 // Producer's capture descriptor: {frame32,generation32,raw_first_word64,nominal_absolute32,q0Q28}.
 input logic frame_valid,output logic frame_ready,input logic [187:0] frame_record,
 input logic cfo_valid,output logic cfo_ready,input bistatic_stream_pkg::bistatic_estimator_result_t cfo_record,
 input logic fine_valid,output logic fine_ready,input bistatic_stream_pkg::bistatic_estimator_result_t fine_record,
 // m_* belong to the selected output domain; all existing control ports retain clk125.
 output logic m_valid,input logic m_ready,output logic [224:0] m_record,
 output logic m_reset,m_fault,
 output logic fault,output logic [7:0] error_code125,error_code150,output logic [255:0] diagnostic,
 output logic residual_point_valid,output logic [128:0] residual_point_record,
 output wire [511:0] debug125,debug150,
 output wire debug_e1_valid,output wire [127:0] debug_e1_data,output wire [31:0] debug_e1_beat,output wire debug_e1_last
);
 import bistatic_stream_pkg::*;
 wire [31:0] debug_elapsed;wire [12:0] debug_fft_in,debug_fft_out,debug_obs,debug_weights;
 wire reset125,transport_fault;logic control_fault;wire system_fault=control_fault||transport_fault;
 wire ctx_sr,ctx_v,ctx_r,ctx_busy,ctx_error,fc_sr,fc_v,fc_r,fc_busy,fc_error;
 wire [187:0] ctx_data;wire [95:0] fc_data;
 wire t06fv,t06fr,t06cv,t06cr,t06mv,t06mr,t06halt;wire [7:0] t06err;
 bistatic_estimator_result_t t06result,stored_fine;
 logic context_history;logic [31:0] previous_frame;
 assign stored_fine=fc_data;
 assign frame_ready=!reset125&&!system_fault&&ctx_sr;
 t07_sync_fifo #(.WIDTH(188),.DEPTH(32)) contexts(.clk(clk125),.rst(reset125),.s_valid(frame_valid&&!system_fault&&!reset125),.s_ready(ctx_sr),.s_data(frame_record),.m_valid(ctx_v),.m_ready(ctx_r),.m_data(ctx_data),.level(),.high_water(),.reset_busy(ctx_busy),.error_sticky(ctx_error));
 // Atomic fork: T06 and the binding FIFO accept the same fine record together.
 assign fine_ready=!reset125&&!system_fault&&t06fr&&fc_sr;
 assign t06fv=fine_valid&&!reset125&&!system_fault&&fc_sr;
 t07_sync_fifo #(.WIDTH(96),.DEPTH(32)) fine_binding(.clk(clk125),.rst(reset125),.s_valid(fine_valid&&!reset125&&!system_fault&&t06fr),.s_ready(fc_sr),.s_data(fine_record),.m_valid(fc_v),.m_ready(fc_r),.m_data(fc_data),.level(),.high_water(),.reset_busy(fc_busy),.error_sticky(fc_error));
 assign cfo_ready=!reset125&&!system_fault&&t06cr;assign t06cv=cfo_valid&&!reset125&&!system_fault;
 t06_initial_sfo_standalone #(.MAX_CYCLES(65024)) initial_estimator(
 .clk_125(clk125),.clk_500(clk500),.rst(reset125),.tap_fire(s_valid&&s_ready),.tap_data(s_data),.tap_frame_id(s_frame_id),.tap_abs(s_absolute_index),.tap_lane_valid(s_lane_valid),
 .s_cfo_valid(t06cv),.s_cfo_ready(t06cr),.s_cfo(cfo_record),.s_fine_valid(t06fv),.s_fine_ready(t06fr),.s_fine(fine_record),
 .m_valid(t06mv),.m_ready(t06mr),.m_result(t06result),.m_slope(),.m_error_stage(t06err),.halted(t06halt),.elapsed_cycles(debug_elapsed),.fft_lease_wait_cycles(),.fft_input_stall_cycles(),.fft_output_stall_cycles(),.shared_gain_sample_count(),.fft_input_count(debug_fft_in),.fft_output_count(debug_fft_out),.observation_count(debug_obs),.weight_count(debug_weights),.cfo_context_occupancy(),.fine_context_occupancy(),.fft_owned(),.fft_error());
 wire [31:0] ctx_frame=ctx_data[187:156],ctx_gen=ctx_data[155:124];wire [63:0] ctx_raw=ctx_data[123:60];
 wire signed [32:0] timing_offset=$signed({stored_fine.value[31],stored_fine.value})-$signed({ctx_data[59],ctx_data[59:28]});
 wire identity_good=ctx_frame==t06result.frame_id&&ctx_frame==stored_fine.frame_id;
 // T05 fine timing carries kind 3; T06 initial SFO carries kind 4.
 wire numeric_good=t06result.status==16'h4800&&stored_fine.status==16'h3800&&timing_offset>=-33'sd101&&timing_offset<=33'sd101;
 wire joined=ctx_v&&fc_v&&t06mv;wire transport_ctx_v,transport_ctx_r;wire [235:0] transport_ctx_data;
 assign transport_ctx_v=!reset125&&!system_fault&&joined&&identity_good&&numeric_good;
 assign transport_ctx_data={ctx_frame,ctx_gen,ctx_raw,timing_offset[31:0],ctx_data[27:0],t06result.value,t06result.status};
 wire consume_join=transport_ctx_v&&transport_ctx_r;
 assign ctx_r=consume_join;assign fc_r=consume_join;assign t06mr=consume_join;
 wire qcv,qcr,qrv,qrr,qdv,qdr,qmv,qmr,qcancel,qbusy;wire [221:0] qcw;wire [101:0] qrw;wire [234:0] qdw;wire [159:0] qmw;
 t09_residual_sfo_pipeline4 residual_estimator(.clk(clk125),.clk500(clk500),.rst(reset125),.abort(system_fault||abort125),
 .cfg_valid(qcv),.cfg_ready(qcr),.cfg_descriptor(qcw),.req_valid(qrv),.req_ready(qrr),.req_word(qrw),.s_valid(qdv),.s_ready(qdr),.s_word(qdw),
 .m_valid(qmv),.m_ready(qmr),.m_result(qmw),.point_valid(residual_point_valid),.point_record(residual_point_record),.window_done_valid(),.window_done_record(),.m_diagnostic(),.cancel(qcancel),.busy(qbusy));
 t10_two_pass_transport #(.OUTPUT_CLOCK_MHZ(OUTPUT_CLOCK_MHZ)) transport(.clk125(clk125),.clk150(clk150),.reset_request(reset_request),.abort125(abort125||control_fault),
 .s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.context_valid(transport_ctx_v),.context_ready(transport_ctx_r),.context_record(transport_ctx_data),
 .t09_cfg_valid(qcv),.t09_cfg_ready(qcr),.t09_cfg_record(qcw),.t09_req_valid(qrv),.t09_req_ready(qrr),.t09_req_record(qrw),.t09_data_valid(qdv),.t09_data_ready(qdr),.t09_data_record(qdw),.t09_result_valid(qmv),.t09_result_ready(qmr),.t09_result_record(qmw),
 .m_valid(m_valid),.m_ready(m_ready),.m_record(m_record),.m_reset(m_reset),.m_fault(m_fault),.reset125(reset125),.fault125(transport_fault),.first_error150(error_code150),.diagnostic(diagnostic),.debug150(debug150),.debug_e1_valid(debug_e1_valid),.debug_e1_data(debug_e1_data),.debug_e1_beat(debug_e1_beat),.debug_e1_last(debug_e1_last));
 assign fault=!reset125&&system_fault;
 always_ff @(posedge clk125)begin
  if(reset125)begin control_fault<=0;error_code125<=0;context_history<=0;previous_frame<=0;end
  else begin
   if(frame_valid&&frame_ready)begin context_history<=1;previous_frame<=frame_record[187:156];end
   if(!control_fault)begin
    if(abort125)begin control_fault<=1;error_code125<=1;end
    else if(ctx_error||fc_error)begin control_fault<=1;error_code125<=2;end
    else if(s_valid&&s_ready&&s_lane_valid!=4'hf)begin control_fault<=1;error_code125<=3;end
    else if(frame_valid&&frame_ready&&context_history&&frame_record[187:156]<=previous_frame)begin control_fault<=1;error_code125<=4;end
    else if(joined&&!identity_good)begin control_fault<=1;error_code125<=5;end
    else if(joined&&!numeric_good)begin control_fault<=1;error_code125<=6;end
    else if(t06halt)begin control_fault<=1;error_code125<=7;end
   end
  end
 end

 logic [31:0] dbg_raw,dbg_points,dbg_requests;
 logic dbg_seen1,dbg_seen2;
 logic [95:0] dbg_first;
 logic [159:0] dbg_second;
 always_ff @(posedge clk125)begin
  if(reset125)begin dbg_raw<=0;dbg_points<=0;dbg_requests<=0;dbg_seen1<=0;dbg_seen2<=0;dbg_first<=0;dbg_second<=0;end
  else begin
   if(s_valid&&s_ready)dbg_raw<=dbg_raw+1'b1;
   if(residual_point_valid)dbg_points<=dbg_points+1'b1;
   if(qrv&&qrr)dbg_requests<=dbg_requests+1'b1;
   if(t06mv)begin dbg_first<=t06result;dbg_seen1<=1;end
   if(qmv)begin dbg_second<=qmw;dbg_seen2<=1;end
  end
 end
 assign debug125[0*32+:32]=dbg_raw;
 assign debug125[1*32+:32]={27'd0,fault,qbusy,t06halt,dbg_seen2,dbg_seen1};
 assign debug125[2*32+:32]=dbg_first[95:64];
 assign debug125[3*32+:32]=dbg_first[63:32];
 assign debug125[4*32+:32]=dbg_first[31:0];
 assign debug125[5*32+:32]=dbg_second[69:38];
 assign debug125[6*32+:32]=dbg_second[37:6];
 assign debug125[7*32+:32]=dbg_second[159:128];
 assign debug125[8*32+:32]=dbg_second[127:96];
 assign debug125[9*32+:32]=debug_elapsed;
 assign debug125[10*32+:32]={3'd0,debug_fft_out,3'd0,debug_fft_in};
 assign debug125[11*32+:32]={3'd0,debug_weights,3'd0,debug_obs};
 assign debug125[12*32+:32]=dbg_second[95:64];
 assign debug125[13*32+:32]=dbg_points;
 assign debug125[14*32+:32]=dbg_requests;
 assign debug125[15*32+:32]={10'd0,dbg_second[5:0],t06err,error_code125};
endmodule
