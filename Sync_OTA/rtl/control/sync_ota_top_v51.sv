`timescale 1ns/1ps
// V5.1 production candidate: input replay segments -> autonomous complete
// synchronization -> unconditional final output. All intermediate IQ is on chip.
module sync_ota_top(
 input wire clk125,clk150,clk500,reset_request,cancel,
 input wire stream_valid,output wire stream_ready,input wire [127:0] stream_data,
 input wire stream_first,stream_last,read_done,
 output wire output_valid,output wire [127:0] output_data,
 output wire [31:0] output_frame,output_generation,output_beat,output wire output_last,
 output wire busy125,output logic fault125,output logic [7:0] error125,
 output wire [2:0] ingress_stage125,output wire [63:0] accepted_words125,
 output wire [31:0] frames_created125,segments_started125,segments_completed125,
 output logic frame_done125,output logic [31:0] done_frame125,done_generation125,completed_frames125,
 output logic [31:0] frontend_candidates125,frontend_rejected125,frontend_dropped125,frontend_confirmed125,
 output logic [15:0] frontend_error125,output wire [7:0] sfo_error125,sfo_error150,context_error150,cfo_error150,
 output wire [31:0] coarse_beats150,final_beats150,coarse_saturations150,final_saturations150,
 output wire [12:0] cfo_window_words150,output wire [6:0] cfo_windows150,
 output wire [498:0] cfo_result150,output wire [255:0] sfo_diagnostic150
);
 wire rst125,rst150;
 sfo_domain_reset reset_a(.clk(clk125),.reset_request(reset_request),.reset_active(rst125));
 sfo_domain_reset reset_b(.clk(clk150),.reset_request(reset_request),.reset_active(rst150));
 wire poison125=fault125||cancel;
 wire poison150;
 logic local_fault150;logic [7:0] held_context_error150;
 wire local_stop150=poison150||local_fault150;
 wire [7:0] live_context_error150;
 assign context_error150=held_context_error150;
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) poison_sync(
  .src_clk(clk125),.src_in(poison125),.dest_clk(clk150),.dest_out(poison150));
 wire raw_v,raw_r,fe_v,fe_r,fe_start,fe_end,fe_quiet,fe_mv,fe_mr,retention_v;
 wire [127:0] raw_data,fe_data;wire [287:0] fe_record;
 wire [31:0] fe_epoch,retention_epoch;wire [63:0] retention_samples;
 wire event_v,event_r;wire [208:0] event_record;
 wire ingress_idle;
 wire [15:0] live_frontend_error;
 wire [31:0] live_candidates,live_rejected,live_dropped,live_confirmed;
 wire frontend_fatal=|(live_frontend_error&16'h006f);
 // Mirror diagnostics while healthy; poison resets the frontend internals but
 // must not erase the cause or counters before the Host can read them.
 always_ff @(posedge clk125)begin
  if(rst125)begin frontend_error125<=0;frontend_candidates125<=0;frontend_rejected125<=0;frontend_dropped125<=0;frontend_confirmed125<=0;end
  else if(!poison125)begin
   frontend_error125<=live_frontend_error;frontend_candidates125<=live_candidates;
   frontend_rejected125<=live_rejected;frontend_dropped125<=live_dropped;frontend_confirmed125<=live_confirmed;
  end
 end
 wire ingress_fault;wire [7:0] ingress_error;
 ota_stream_ingress ingress(
  .clk(clk125),.rst(rst125),.poison(poison125),
  .s_valid(stream_valid),.s_ready(stream_ready),.s_data(stream_data),.s_first(stream_first),.s_last(stream_last),.read_done(read_done),
  .raw_valid(raw_v),.raw_ready(raw_r),.raw_data(raw_data),.fe_valid(fe_v),.fe_ready(fe_r),.fe_data(fe_data),
  .fe_start(fe_start),.fe_segment_end(fe_end),.fe_quiescent(fe_quiet),.fe_epoch(fe_epoch),
  .fe_result_valid(fe_mv),.fe_result_ready(fe_mr),.fe_result(fe_record),
  .retention_valid(retention_v),.retention_epoch(retention_epoch),.retention_samples(retention_samples),
  .event_valid(event_v),.event_ready(event_r),.event_record(event_record),
  .forwarded_words(accepted_words125),.frames_created(frames_created125),.segments_started(segments_started125),.segments_completed(segments_completed125),
  .input_idle(ingress_idle),.fault(ingress_fault),.error_code(ingress_error),.stage(ingress_stage125));
 sync_frontend_top #(.STREAM_BOUNDARIES(1)) frontend(
  .clk(clk125),.reset_n(!rst125),.session_start(fe_start),.session_abort(poison125),.stream_gap(1'b0),
  .segment_end(fe_end),.segment_quiescent(fe_quiet),.s_valid(fe_v),.s_ready(fe_r),.s_data(fe_data),
  .m_valid(fe_mv),.m_ready(fe_mr),.m_result(fe_record),.accepted_samples(),.epoch(fe_epoch),
  .candidate_count(live_candidates),.rejected_count(live_rejected),.capture_drop_count(live_dropped),.duplicate_count(),.confirmed_count(live_confirmed),
  .snapshot_occupancy(),.snapshot_peak(),.max_history_age(),.error_sticky(live_frontend_error),
  .retention_valid(retention_v),.retention_epoch(retention_epoch),.retention_floor_samples(retention_samples));
 wire first_v,first_r,second_v,second_r;
 wire [223:0] first_record,second_record;
 wire sfo_v,sfo_r,sfo_reset,sfo_fault,sfo_output_fault;
 wire [224:0] sfo_record;
 wire meta_sv,meta_sr,meta_mv,meta_mr,meta_we,meta_re;wire [149:0] meta_sd,meta_md;
 sync_sfo_top #(.SHARED_RAW_INPUT(1),.REQUIRE_CONTEXT_ACK(1),.PROCESSING_LIMIT_CYCLES(400896),.OUTPUT_CLOCK_MHZ(150)) sfo(
  .clk125(clk125),.clk150(clk150),.clk500(clk500),.reset_request(reset_request),.abort125(poison125),.abort150(local_stop150),
  .s_valid(raw_v),.s_ready(raw_r),.s_data(raw_data),.s_frame_id(32'd0),.s_absolute_index(32'sd0),.s_lane_valid(4'hf),
  .raw_event_valid(event_v),.raw_event_ready(event_r),.raw_event_record(event_record),
  .metadata_valid(meta_sv),.metadata_ready(meta_sr),.metadata_record(meta_sd),
  .frame_valid(1'b0),.frame_ready(),.frame_record(188'd0),.cfo_valid(1'b0),.cfo_ready(),.cfo_record(96'd0),
  .fine_valid(1'b0),.fine_ready(),.fine_record(96'd0),
  .first_context_valid(first_v),.first_context_ready(first_r),.first_context_record(first_record),
  .second_context_valid(second_v),.second_context_ready(second_r),.second_context_record(second_record),
  .m_valid(sfo_v),.m_ready(sfo_r),.m_record(sfo_record),.m_reset(sfo_reset),.m_fault(sfo_output_fault),
  .fault(sfo_fault),.error_code125(sfo_error125),.error_code150(sfo_error150),.diagnostic(sfo_diagnostic150),
  .residual_point_valid(),.residual_point_record(),.debug125(),.debug150(),.debug_e1_valid(),.debug_e1_data(),.debug_e1_beat(),.debug_e1_last());
 // This queue accepts metadata before E1 exists. Its ready cannot depend on
 // either SFO context; T06 completion is gated until metadata has been queued.
 sfo_record_cdc_fifo #(.WIDTH(150),.DEPTH(32)) metadata(
  .wr_clk(clk125),.rd_clk(clk150),.reset_request(reset_request),
  .s_valid(meta_sv),.s_ready(meta_sr),.s_data(meta_sd),.m_valid(meta_mv),.m_ready(meta_mr),.m_data(meta_md),
  .wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),.wr_reset_active(),.rd_reset_active(),.wr_error(meta_we),.rd_error(meta_re));
 wire context_v,context_r;wire [213:0] context_data;
 ota_sfo_context_join context_join(
  .clk(clk150),.rst(rst150),.cancel(local_stop150),.meta_valid(meta_mv),.meta_ready(meta_mr),
  .meta_frame(meta_md[149:118]),.meta_generation(meta_md[117:86]),.meta_coarse_hz_q8(meta_md[85:54]),.meta_raw_origin_q28(meta_md[53:0]),
  .first_valid(first_v),.first_ready(first_r),.first_frame(first_record[223:192]),.first_generation(first_record[191:160]),.first_step_q28(first_record[159:128]),
  .second_valid(second_v),.second_ready(second_r),.second_frame(second_record[223:192]),.second_generation(second_record[191:160]),.second_step_q28(second_record[159:128]),
  .m_valid(context_v),.m_ready(context_r),.m_context(context_data),.error_code(live_context_error150));
 wire cfo_busy,cfo_fault,cfo_done;wire [224:0] output_record;wire [31:0] cfo_done_frame,cfo_done_generation;
 ota_cfo_chain_onchip cfo(
  .clk150(clk150),.clk500(clk500),.reset_request(reset_request),.cancel150(local_stop150),
  .context_valid(context_v),.context_ready(context_r),.context_record(context_data),
  .s_valid(sfo_v),.s_ready(sfo_r),.s_record(sfo_record),.m_valid(output_valid),.m_record(output_record),.done(cfo_done),.done_frame(cfo_done_frame),.done_generation(cfo_done_generation),
  .busy(cfo_busy),.fault(cfo_fault),.error_code(cfo_error150),.completed_frames(),
  .coarse_beats(coarse_beats150),.final_beats(final_beats150),.coarse_saturations(coarse_saturations150),.final_saturations(final_saturations150),
  .window_buffered_words(cfo_window_words150),.observation_windows(cfo_windows150),.estimator_result(cfo_result150));
 assign {output_frame,output_generation,output_beat,output_last,output_data}=output_record;
 wire completion_r,completion_v,completion_we,completion_re;wire [63:0] completion_record;
 sfo_record_cdc_fifo #(.WIDTH(64),.DEPTH(32)) completions(
  .wr_clk(clk150),.rd_clk(clk125),.reset_request(reset_request),
  .s_valid(cfo_done),.s_ready(completion_r),.s_data({cfo_done_frame,cfo_done_generation}),
  .m_valid(completion_v),.m_ready(1'b1),.m_data(completion_record),
  .wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),.wr_reset_active(),.rd_reset_active(),.wr_error(completion_we),.rd_error(completion_re));
 // No Host acknowledgement can stall final IQ. Completion is automatically
 // consumed each125 cycle; even peak frame events are 334080150 cycles apart.
 logic completion_fault150;wire remote_fault125,cfo_busy125;
 always_ff @(posedge clk150)begin
  if(rst150)completion_fault150<=0;
  else if((cfo_done&&!completion_r)||completion_we)completion_fault150<=1;
 end
 wire remote_fault150=cfo_fault||sfo_output_fault||live_context_error150!=0||meta_re||completion_fault150;
 always_ff @(posedge clk150)begin
  if(rst150)begin local_fault150<=0;held_context_error150<=0;end
  else begin
   if(remote_fault150||poison150)local_fault150<=1;
   if(live_context_error150!=0&&held_context_error150==0)held_context_error150<=live_context_error150;
  end
 end
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) remote_fault_sync(
  .src_clk(clk150),.src_in(local_fault150),.dest_clk(clk125),.dest_out(remote_fault125));
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) cfo_busy_sync(
  .src_clk(clk150),.src_in(cfo_busy),.dest_clk(clk125),.dest_out(cfo_busy125));
 assign busy125=!ingress_idle||frames_created125!=completed_frames125||cfo_busy125;
 always_ff @(posedge clk125)begin
  if(rst125)begin fault125<=0;error125<=0;frame_done125<=0;done_frame125<=0;done_generation125<=0;completed_frames125<=0;end
  else begin
   frame_done125<=completion_v&&!fault125&&!cancel&&!ingress_fault&&!frontend_fatal&&!sfo_fault&&!meta_we&&!completion_re&&!remote_fault125;
   if(completion_v)begin {done_frame125,done_generation125}<=completion_record;completed_frames125<=completed_frames125+1'b1;end
   if(!fault125)begin
    if(cancel)begin fault125<=1;error125<=8'h01;end
    else if(ingress_fault)begin fault125<=1;error125<=ingress_error;end
    else if(frontend_fatal)begin fault125<=1;error125<=8'h30;end
    else if(sfo_fault)begin fault125<=1;error125<=8'h40;end
    else if(meta_we||completion_re)begin fault125<=1;error125<=8'h60;end
    else if(remote_fault125)begin fault125<=1;error125<=8'h80;end
   end
  end
 end
endmodule
