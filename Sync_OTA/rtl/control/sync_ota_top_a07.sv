`timescale 1ns/1ps
// A07: retained CFO FIFO diagnostics only fault an active CFO session.
// Production top: real autonomous frontend, complete two-pass SFO, two distinct
// quantized CFO rotations and the actual 74-observation residual estimator.
// NI owns clocks and the physical DDR controller. No truth-estimate inputs.
module sync_ota_top (
 input wire clk125,clk150,clk500,reset_request,
 // clk125 Host/Target control and finite raw capture.
 input wire start_valid,output wire start_ready,input wire [63:0] capture_base_word,input wire [31:0] capture_words,
 input wire cancel,input wire s_valid,output wire s_ready,input wire [127:0] s_data,
 output wire done,input wire done_ready,output wire busy,
 output wire [5:0] stage125,output wire [7:0] error125,
 output wire [31:0] accepted_words125,committed_words125,replay_words125,raw_stalls125,
 output wire [31:0] frame125,generation125,output wire [63:0] nominal_absolute125,
 output wire [287:0] frontend_record125,
 // clk125 DDR transaction bus. Tag bit64 selects raw/CFO; lower64 are lease/serial.
 output wire ddr_cmd_valid,input wire ddr_cmd_ready,output wire ddr_cmd_write,
 output wire [63:0] ddr_cmd_address,output wire [64:0] ddr_cmd_tag,output wire [127:0] ddr_cmd_data,
 input wire ddr_rsp_valid,output wire ddr_rsp_ready,input wire [64:0] ddr_rsp_tag,
 input wire [127:0] ddr_rsp_data,input wire ddr_rsp_error,
 output wire ddr_idle125,output wire [7:0] ddr_error125,
 output wire [31:0] ddr_commands125,ddr_responses125,ddr_stale125,
 output wire [5:0] ddr_request_level125,ddr_response_level125,
 // clk150 final tagged IQ: {frame32,generation32,beat32,last1,IQ128}.
 output wire m_valid,input wire m_ready,output wire [224:0] m_record,
 output wire [4:0] cfo_stage150,output wire [7:0] cfo_error150,
 output wire [31:0] coarse_beats150,final_beats150,coarse_saturations150,final_saturations150,
 output wire [6:0] observation_windows150,output wire [498:0] cfo_result150,
 output wire [31:0] cfo_committed150,cfo_read150,cfo_stalls150,
 output wire [5:0] cfo_window_fifo_level150,output wire [4:0] cfo_observation_fifo_level150,output wire [3:0] cfo_fifo_error150,
 output wire [7:0] sfo_error125,sfo_error150,context_error150,
 output wire [255:0] sfo_diagnostic150,
 output wire [511:0] sfo_monitor125,sfo_monitor150,
 output wire [31:0] first_step150,second_step150,
 output wire [63:0] frontend_accepted_samples125,
 output wire [31:0] frontend_candidates125,frontend_rejected125,frontend_drop125,frontend_duplicate125,frontend_confirmed125,
 output wire [15:0] frontend_error125
);
 wire rst125,rst150;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
 reset125(.src_arst(reset_request),.dest_clk(clk125),.dest_arst(rst125));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
 reset150(.src_arst(reset_request),.dest_clk(clk150),.dest_arst(rst150));
 wire raw_cv,raw_cr,raw_cw,raw_rv,raw_rr,raw_re;
 wire [63:0] raw_ca,raw_ct,raw_rt;wire [127:0] raw_cd,raw_rd;
 wire cfo_cv,cfo_cr,cfo_cw,cfo_rv,cfo_rr,cfo_re;
 wire [63:0] cfo_ca,cfo_ct,cfo_rt;wire [127:0] cfo_cd,cfo_rd;
 ota_ddr_bridge ddr(
  .clk125(clk125),.clk150(clk150),.reset_request(reset_request),
  .raw_cmd_valid(raw_cv),.raw_cmd_ready(raw_cr),.raw_cmd_write(raw_cw),.raw_cmd_address(raw_ca),.raw_cmd_tag(raw_ct),.raw_cmd_data(raw_cd),
  .raw_rsp_valid(raw_rv),.raw_rsp_ready(raw_rr),.raw_rsp_tag(raw_rt),.raw_rsp_data(raw_rd),.raw_rsp_error(raw_re),
  .cfo_cmd_valid(cfo_cv),.cfo_cmd_ready(cfo_cr),.cfo_cmd_write(cfo_cw),.cfo_cmd_address(cfo_ca),.cfo_cmd_tag(cfo_ct),.cfo_cmd_data(cfo_cd),
  .cfo_rsp_valid(cfo_rv),.cfo_rsp_ready(cfo_rr),.cfo_rsp_tag(cfo_rt),.cfo_rsp_data(cfo_rd),.cfo_rsp_error(cfo_re),
  .cmd_valid(ddr_cmd_valid),.cmd_ready(ddr_cmd_ready),.cmd_write(ddr_cmd_write),.cmd_address(ddr_cmd_address),.cmd_tag(ddr_cmd_tag),.cmd_data(ddr_cmd_data),
  .rsp_valid(ddr_rsp_valid),.rsp_ready(ddr_rsp_ready),.rsp_tag(ddr_rsp_tag),.rsp_data(ddr_rsp_data),.rsp_error(ddr_rsp_error),
  .idle125(ddr_idle125),.error125(ddr_error125),.commands125(ddr_commands125),.responses125(ddr_responses125),.stale_responses125(ddr_stale125),
  .request_level125(ddr_request_level125),.response_level125(ddr_response_level125));
 wire fe_start,fe_abort,fe_sv,fe_sr,fe_mv,fe_mr;wire [127:0] fe_sd;wire [287:0] fe_md;wire [31:0] fe_epoch;
 sync_frontend_top frontend(
  .clk(clk125),.reset_n(!rst125),.session_start(fe_start),.session_abort(fe_abort),.stream_gap(1'b0),
  .s_valid(fe_sv),.s_ready(fe_sr),.s_data(fe_sd),.m_valid(fe_mv),.m_ready(fe_mr),.m_result(fe_md),
  .accepted_samples(frontend_accepted_samples125),.epoch(fe_epoch),.candidate_count(frontend_candidates125),
  .rejected_count(frontend_rejected125),.capture_drop_count(frontend_drop125),.duplicate_count(frontend_duplicate125),
  .confirmed_count(frontend_confirmed125),.snapshot_occupancy(),.snapshot_peak(),.max_history_age(),.error_sticky(frontend_error125));
 wire sfo_reset125,sfo_sv,sfo_sr,frame_v,frame_r,coarse_v,coarse_r,fine_v,fine_r;
 wire [127:0] sfo_sd;wire signed [31:0] sfo_abs;wire [187:0] frame_record;wire [95:0] coarse_record,fine_record;
 wire meta_sv,meta_sr,meta_mv,meta_mr;wire [213:0] meta_sd,meta_md;
 wire cancel125,cancel150,cfo_busy150,cfo_busy125,done150,done_ready150,completion_v,completion_r;wire [7:0] completion_error;
 wire sfo_fault,sfo_mfault,algorithm_fault125,algorithm_fault150;
 wire e1v,e1r,e2v,e2r;wire [223:0] e1record,e2record;
 wire sfo_mv,sfo_mr,sfo_mreset;wire [224:0] sfo_record;
 wire context_reset150;
 // Preserve diagnostics only for an error-free normal completion.
 // Cancel/reject COMPLETE must keep reset asserted until the next session;
 // releasing it for one Host-ack cycle creates an illegal XPM reset pulse.
 wire normal_completion125=(stage125==6'd17)&&(error125==8'h00);
 wire requested_sfo_reset125=sfo_reset125&&!normal_completion125;
 wire effective_sfo_reset125,algorithm_reset_stable125;
 ota_algorithm_reset_guard algorithm_reset_guard(
  .clk125(clk125),.global_reset(reset_request||rst125),.request_reset(requested_sfo_reset125),
  .reset_active(effective_sfo_reset125),.reset_stable(algorithm_reset_stable125));
 wire [7:0] live_sfo_error125,live_sfo_error150,live_context_error150,live_cfo_error150;
 wire [255:0] live_sfo_diagnostic150;
 wire [511:0] live_sfo_monitor125,live_sfo_monitor150;
 logic [7:0] held_sfo_error125,held_sfo_error150,held_context_error150,held_cfo_error150;
 logic [255:0] held_sfo_diagnostic150;
 logic [511:0] held_sfo_monitor125,held_sfo_monitor150;
 assign cfo_error150=held_cfo_error150;
 assign sfo_error125=held_sfo_error125;assign sfo_error150=held_sfo_error150;assign context_error150=held_context_error150;
 assign sfo_diagnostic150=held_sfo_diagnostic150;
 assign sfo_monitor125=held_sfo_monitor125;assign sfo_monitor150=held_sfo_monitor150;
 always_ff @(posedge clk125)begin
  if(rst125||(start_valid&&start_ready))begin held_sfo_error125<=0;held_sfo_monitor125<=0;end
  else begin
   if(live_sfo_error125!=0&&held_sfo_error125==0)held_sfo_error125<=live_sfo_error125;
   if(!effective_sfo_reset125)held_sfo_monitor125<=live_sfo_monitor125;
  end
 end
 always_ff @(posedge clk150)begin
  if(rst150)begin held_cfo_error150<=0;held_sfo_error150<=0;held_context_error150<=0;held_sfo_monitor150<=0;held_sfo_diagnostic150<=0;end
  else begin
   if(meta_mv&&meta_mr)begin held_cfo_error150<=0;held_sfo_error150<=0;held_context_error150<=0;end
   else begin
    if(live_cfo_error150!=0&&held_cfo_error150==0)held_cfo_error150<=live_cfo_error150;
    if(live_sfo_error150!=0&&held_sfo_error150==0)held_sfo_error150<=live_sfo_error150;
    if(live_context_error150!=0&&held_context_error150==0)held_context_error150<=live_context_error150;
   end
   if(!context_reset150)begin held_sfo_monitor150<=live_sfo_monitor150;held_sfo_diagnostic150<=live_sfo_diagnostic150;end
  end
 end
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
 context_reset(.src_arst(reset_request||effective_sfo_reset125),.dest_clk(clk150),.dest_arst(context_reset150));
 // Register the binary-state decode before it can asynchronously assert a
 // destination reset. The controller already blocks ingress while cancelling.
 logic cancel_request125;
 always_ff @(posedge clk125)begin
  if(rst125)cancel_request125<=1'b0;
  else cancel_request125<=cancel125;
 end
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
 cancel_sync(.src_arst(cancel_request125),.dest_clk(clk150),.dest_arst(cancel150));
 xpm_cdc_single #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.SRC_INPUT_REG(1))
 busy_sync(.src_clk(clk150),.src_in(cfo_busy150),.dest_clk(clk125),.dest_out(cfo_busy125));
 assign algorithm_fault150=(live_context_error150!=0)||sfo_mfault||
  (cfo_busy150&&((cfo_fifo_error150!=0)||(live_cfo_error150!=0)));
 xpm_cdc_single #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.SRC_INPUT_REG(1))
 fault_sync(.src_clk(clk150),.src_in(algorithm_fault150),.dest_clk(clk125),.dest_out(algorithm_fault125));
 ota_capture_controller control(
  .clk125(clk125),.rst125(rst125),.cancel(cancel),
  .start_valid(start_valid),.start_ready(start_ready),.start_base_word(capture_base_word),.start_words(capture_words),
  .s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.done(done),.done_ready(done_ready),.busy(busy),.stage(stage125),.error_code(error125),
  .accepted_words(accepted_words125),.committed_words(committed_words125),.read_words(replay_words125),.memory_stalls(raw_stalls125),
  .frame_id(frame125),.generation(generation125),.nominal_absolute_sample(nominal_absolute125),.frontend_record(frontend_record125),
  .fe_session_start(fe_start),.fe_session_abort(fe_abort),.fe_s_valid(fe_sv),.fe_s_ready(fe_sr),.fe_s_data(fe_sd),
  .fe_m_valid(fe_mv),.fe_m_ready(fe_mr),.fe_m_record(fe_md),.fe_epoch(fe_epoch),.fe_error(frontend_error125),
  .sfo_reset(sfo_reset125),.sfo_s_valid(sfo_sv),.sfo_s_ready(sfo_sr),.sfo_s_data(sfo_sd),.sfo_absolute_index(sfo_abs),
  .frame_valid(frame_v),.frame_ready(frame_r),.frame_record(frame_record),.coarse_valid(coarse_v),.coarse_ready(coarse_r),.coarse_record(coarse_record),
  .fine_valid(fine_v),.fine_ready(fine_r),.fine_record(fine_record),.meta_valid(meta_sv),.meta_ready(meta_sr),.meta_record(meta_sd),
  .algorithm_error(sfo_fault||algorithm_fault125),.cfo_cancel(cancel125),.cfo_busy(cfo_busy125),
  .cfo_done_valid(completion_v),.cfo_done_ready(completion_r),.cfo_done_error(completion_error),.bridge_idle(ddr_idle125&&algorithm_reset_stable125),.bridge_error(ddr_error125),
  .cmd_valid(raw_cv),.cmd_ready(raw_cr),.cmd_write(raw_cw),.cmd_address(raw_ca),.cmd_tag(raw_ct),.cmd_data(raw_cd),
  .rsp_valid(raw_rv),.rsp_ready(raw_rr),.rsp_tag(raw_rt),.rsp_data(raw_rd),.rsp_error(raw_re));
 // 536870912 is an offline scheduling guard (3.58 s at150), not the old
 // 400896-cycle streaming service threshold or evidence of that qualification.
 sync_sfo_top #(.REQUIRE_CONTEXT_ACK(1),.PROCESSING_LIMIT_CYCLES(536870912),.OUTPUT_CLOCK_MHZ(150)) sfo(
  .first_context_valid(e1v),.first_context_ready(e1r),.first_context_record(e1record),
  .second_context_valid(e2v),.second_context_ready(e2r),.second_context_record(e2record),
  .clk125(clk125),.clk150(clk150),.clk500(clk500),.reset_request(reset_request||effective_sfo_reset125),.abort125(cancel125),
  .s_valid(sfo_sv),.s_ready(sfo_sr),.s_data(sfo_sd),.s_frame_id(frame125),.s_absolute_index(sfo_abs),.s_lane_valid(4'hf),
  .frame_valid(frame_v),.frame_ready(frame_r),.frame_record(frame_record),.cfo_valid(coarse_v),.cfo_ready(coarse_r),.cfo_record(coarse_record),
  .fine_valid(fine_v),.fine_ready(fine_r),.fine_record(fine_record),
  .m_valid(sfo_mv),.m_ready(sfo_mr),.m_record(sfo_record),.m_reset(sfo_mreset),.m_fault(sfo_mfault),
  .fault(sfo_fault),.error_code125(live_sfo_error125),.error_code150(live_sfo_error150),.diagnostic(live_sfo_diagnostic150),
  .residual_point_valid(),.residual_point_record(),.debug125(live_sfo_monitor125),.debug150(live_sfo_monitor150),.debug_e1_valid(),.debug_e1_data(),.debug_e1_beat(),.debug_e1_last());
 ota_async_fifo #(.WIDTH(214)) metadata(
  .wr_clk(clk125),.rd_clk(clk150),.reset_request(reset_request||effective_sfo_reset125),
  .s_valid(meta_sv),.s_ready(meta_sr),.s_data(meta_sd),.m_valid(meta_mv),.m_ready(meta_mr),.m_data(meta_md),
  .wr_busy(),.rd_busy(),.wr_count(),.rd_count(),.overflow(),.underflow());
 wire context_valid,context_ready;wire [213:0] joined_context;
 logic [63:0] cfo_base;
 logic [31:0] held_first_step,held_second_step;
 assign first_step150=held_first_step;assign second_step150=held_second_step;
 always_ff @(posedge clk150)begin
  if(rst150)begin cfo_base<=0;held_first_step<=0;held_second_step<=0;end
  else begin
   if(meta_mv&&meta_mr)begin cfo_base<=meta_md[213:150];held_first_step<=0;held_second_step<=0;end
   if(e1v&&e1r)held_first_step<=e1record[159:128];
   if(e2v&&e2r)held_second_step<=e2record[159:128];
  end
 end
 ota_sfo_context_join context_join(
  .clk(clk150),.rst(context_reset150),.cancel(cancel150),.meta_valid(meta_mv),.meta_ready(meta_mr),
  .meta_frame(meta_md[149:118]),.meta_generation(meta_md[117:86]),.meta_coarse_hz_q8(meta_md[85:54]),.meta_raw_origin_q28(meta_md[53:0]),
  .first_valid(e1v),.first_ready(e1r),.first_frame(e1record[223:192]),.first_generation(e1record[191:160]),.first_step_q28(e1record[159:128]),
  .second_valid(e2v),.second_ready(e2r),.second_frame(e2record[223:192]),.second_generation(e2record[191:160]),.second_step_q28(e2record[159:128]),
  .m_valid(context_valid),.m_ready(context_ready),.m_context(joined_context),.error_code(live_context_error150));
 ota_cfo_chain cfo(
  .clk150(clk150),.clk500(clk500),.reset_request(reset_request),.cancel150(cancel150),
  .context_valid(context_valid),.context_ready(context_ready),.context_record({cfo_base,joined_context}),
  .s_valid(sfo_mv),.s_ready(sfo_mr),.s_record(sfo_record),.m_valid(m_valid),.m_ready(m_ready),.m_record(m_record),
  .cmd_valid(cfo_cv),.cmd_ready(cfo_cr),.cmd_write(cfo_cw),.cmd_address(cfo_ca),.cmd_tag(cfo_ct),.cmd_data(cfo_cd),
  .rsp_valid(cfo_rv),.rsp_ready(cfo_rr),.rsp_tag(cfo_rt),.rsp_data(cfo_rd),.rsp_error(cfo_re),
  .busy(cfo_busy150),.done(done150),.done_ready(done_ready150),.error_code(live_cfo_error150),.stage(cfo_stage150),
  .coarse_beats(coarse_beats150),.final_beats(final_beats150),.coarse_saturations(coarse_saturations150),.final_saturations(final_saturations150),
  .observations_sent(observation_windows150),.estimator_result(cfo_result150),
  .window_fifo_level150(cfo_window_fifo_level150),.observation_fifo_level150(cfo_observation_fifo_level150),.fifo_error150(cfo_fifo_error150),
  .memory_committed(cfo_committed150),.memory_read(cfo_read150),.memory_stalls(cfo_stalls150));
 wire completion_space;
 logic completion_sent;
 always_ff @(posedge clk150)begin
  if(rst150||!done150)completion_sent<=0;
  else if(done150&&!completion_sent&&completion_space)completion_sent<=1;
 end
 assign done_ready150=completion_sent&&!cancel150;
 ota_async_fifo #(.WIDTH(8)) completion(
  .wr_clk(clk150),.rd_clk(clk125),.reset_request(reset_request),
  .s_valid(done150&&!completion_sent),.s_ready(completion_space),.s_data(live_cfo_error150),
  .m_valid(completion_v),.m_ready(completion_r),.m_data(completion_error),
  .wr_busy(),.rd_busy(),.wr_count(),.rd_count(),.overflow(),.underflow());
endmodule
