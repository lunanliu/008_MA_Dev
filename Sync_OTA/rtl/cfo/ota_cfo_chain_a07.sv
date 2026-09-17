`timescale 1ns/1ps
// A07: two complete ingress records cut the backward ready path to SFO RAM.
// A06 registered cancellation and A02 diagnostics are retained.
// A02 backend-failure result and FIFO diagnostics are retained.
// Complete offline CFO chain. Memory is a transactional NI-owned external region.
// All ports except the FFT service clock/reset operate at clk150.
module ota_cfo_chain (
 input wire clk150,clk500,reset_request,cancel150,
 input wire context_valid,output wire context_ready,
 input wire [277:0] context_record, // {DDR base64, frame32,gen32,step1,step2,origin54,coarseF8}
 input wire s_valid,output wire s_ready,input wire [224:0] s_record,
 output wire m_valid,input wire m_ready,output wire [224:0] m_record,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire [63:0] cmd_address,cmd_tag,output wire [127:0] cmd_data,
 input wire rsp_valid,output wire rsp_ready,input wire [63:0] rsp_tag,
 input wire [127:0] rsp_data,input wire rsp_error,
 output wire busy,output wire done,input wire done_ready,
 output logic [7:0] error_code,output logic [4:0] stage,
 output logic [31:0] coarse_beats,final_beats,coarse_saturations,final_saturations,
 output logic [6:0] observations_sent,
 output logic [498:0] estimator_result,
 output wire [5:0] window_fifo_level150,
 output wire [4:0] observation_fifo_level150,
 output logic [3:0] fifo_error150,
 output wire [31:0] memory_committed,memory_read,memory_stalls
);
 localparam [31:0] FRAME_SAMPLES=1336320,FRAME_BEATS=334080;
 localparam [4:0] IDLE=0,OPEN=1,COARSE_COORD=2,COARSE_CFG=3,INGEST=4,SEAL=5,
  WINDOW_REQUEST=6,WINDOW_STREAM=7,ESTIMATE=8,RESIDUAL_COORD=9,RESIDUAL_CFG=10,
  FINAL_REQUEST=11,FINAL_STREAM=12,FINAL_DRAIN=13,RELEASE=14,COMPLETE=15,FAIL=16,CANCEL_DRAIN=17;
 wire rst150,rst500;
 logic compute_cancel150;
 always_ff @(posedge clk150)begin
  if(rst150)compute_cancel150<=1'b0;
  else compute_cancel150<=cancel150||(stage==CANCEL_DRAIN);
 end
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
  reset150(.src_arst(reset_request),.dest_clk(clk150),.dest_arst(rst150));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
  reset500(.src_arst(reset_request||compute_cancel150),.dest_clk(clk500),.dest_arst(rst500));
 logic [31:0] frame_id,generation,step1,step2;
 logic signed [53:0] origin;
 logic signed [31:0] coarse_frequency,residual_frequency;
 logic [63:0] memory_base;
 logic [31:0] window_first;
 logic [6:0] window_number;
 logic [1:0] lane;
 wire compute_clear=rst150||cancel150||stage==CANCEL_DRAIN;
 wire coordinate_ready,coordinate_valid,coordinate_residual,coordinate_ok;
 wire [31:0] coordinate_frame,coordinate_generation,phase0,phase_step;
 wire [3:0] coordinate_error;
 wire r1_cfg_ready,r2_cfg_ready,r1_sr,r2_sr,r1_valid,r2_valid;
 wire [224:0] r1_record,r2_record;wire [7:0] sat1,sat2;
 wire r1_fault,r2_fault;wire [3:0] r1_error,r2_error;
 // Keep the public 30/31 stage codes; preserve each rotation's first cause
 // across cancellation for optional Vivado/ILA inspection, without new ports.
 (* mark_debug="true", keep="true" *) logic [3:0] first_rotation_error,second_rotation_error;
 always_ff @(posedge clk150)begin
  if(rst150||(context_valid&&context_ready))begin
   first_rotation_error<=0;second_rotation_error<=0;
  end else begin
   if(r1_fault&&first_rotation_error==0)first_rotation_error<=r1_error;
   if(r2_fault&&second_rotation_error==0)second_rotation_error<=r2_error;
  end
 end
 wire memory_start_ready,memory_replay_ready,memory_sealed,memory_busy,memory_sv,memory_sr;
 wire memory_mv,memory_mr,memory_last;wire [127:0] memory_data;wire [31:0] memory_index,memory_generation;
 wire [7:0] memory_error;
 wire [31:0] replay_first=(stage==FINAL_REQUEST)?32'd0:window_first;
 wire [31:0] replay_count=(stage==FINAL_REQUEST)?FRAME_BEATS:32'd512;
 wire backend_bad=link_valid&&(link_error!=0||link_front_error!=0||backend_word[498:467]!=frame_id||backend_word[466:435]!=generation||backend_word[434:431]!=0||!backend_word[428]);
 // OPEN is the new lease handshake: the store clears its retained old error
 // on that edge. Any error from this start remains visible in COARSE_COORD.
 wire memory_failed=memory_error!=0&&stage!=OPEN;
 wire fail=error_code!=0||r1_fault||r2_fault||memory_failed||backend_bad;
 assign context_ready=!rst150&&!cancel150&&stage==IDLE&&!memory_busy&&!fw_busy&&!slow_busy;
 // No combinational dependency from DDR, rotation ready, or backend arithmetic
 // to upstream ready. On a fatal error, the whole frame including this queue
 // is discarded; a same-edge upstream acceptance is part of that failed frame.
 logic [1:0] ingress_count;
 logic ingress_closed;
 logic [224:0] ingress_head,ingress_tail;
 wire ingress_push=s_valid&&s_ready;
 wire ingress_pop=stage==INGEST&&!fail&&ingress_count!=0&&r1_sr;
 assign s_ready=!rst150&&!cancel150&&stage==INGEST&&!ingress_closed&&ingress_count<2;
 always_ff @(posedge clk150)begin
  if(rst150||cancel150||stage!=INGEST||fail)begin
   ingress_count<=0;ingress_closed<=0;
  end else begin
   case({ingress_push,ingress_pop})
    2'b10:ingress_count<=ingress_count+1'b1;
    2'b01:ingress_count<=ingress_count-1'b1;
    default:begin end
   endcase
   if(ingress_push)begin
    if(ingress_count==0||(ingress_count==1&&ingress_pop))ingress_head<=s_record;
    else ingress_tail<=s_record;
    if(s_record[128])ingress_closed<=1;
   end
   if(ingress_pop&&ingress_count==2)ingress_head<=ingress_tail;
  end
 end
 assign m_valid=(stage==FINAL_STREAM||stage==FINAL_DRAIN)&&!fail&&!cancel150&&r2_valid;
 assign m_record=r2_record;
 assign done=stage==COMPLETE;
 assign busy=stage!=IDLE||memory_busy;
 wire coordinate_output_ready=(stage==COARSE_CFG)?r1_cfg_ready:((stage==RESIDUAL_CFG)?r2_cfg_ready:1'b0);
 cfo_coordinate_control coordinate(
  .clk(clk150),.rst(rst150),.abort_sync(cancel150||stage==CANCEL_DRAIN),
  .s_valid(stage==COARSE_COORD||stage==RESIDUAL_COORD),.s_ready(coordinate_ready),
  .s_frame(frame_id),.s_generation(generation),.s_residual(stage==RESIDUAL_COORD),
  .s_frequency_code(stage==RESIDUAL_COORD?residual_frequency:coarse_frequency),
  .s_step1_q28(step1),.s_step2_q28(step2),.s_raw_origin_q28(origin),
  .m_valid(coordinate_valid),.m_ready(coordinate_output_ready),.m_frame(coordinate_frame),.m_generation(coordinate_generation),
  .m_residual(coordinate_residual),.m_ok(coordinate_ok),.m_error(coordinate_error),
  .m_step(phase_step),.m_phase0(phase0),.m_step48(),.m_phase48(),.m_origin_output_q16()
 );
 cfo_rotate4 first_rotation(
  .clk(clk150),.rst(rst150),.abort_sync(cancel150||stage==CANCEL_DRAIN),
  .cfg_valid(stage==COARSE_CFG&&coordinate_valid&&coordinate_ok),.cfg_ready(r1_cfg_ready),
  .cfg_frame(frame_id),.cfg_generation(generation),.cfg_phase0(phase0),.cfg_step(phase_step),.cfg_sample_count(FRAME_SAMPLES),
  .s_valid(ingress_count!=0&&stage==INGEST&&!fail),.s_ready(r1_sr),.s_record(ingress_head),
  .m_valid(r1_valid),.m_ready(memory_sr&&stage==INGEST&&!fail),.m_record(r1_record),.m_saturation(sat1),
  .fault(r1_fault),.first_error(r1_error)
 );
 assign memory_sv=stage==INGEST&&r1_valid&&!fail;
 wire release_memory=stage==RELEASE;
 ota_frame_store coarse_store(
  .clk(clk150),.rst(rst150),.cancel(cancel150||stage==CANCEL_DRAIN),
  .start_valid(stage==OPEN),.start_ready(memory_start_ready),.start_base_word(memory_base),.start_capacity(FRAME_BEATS),
  .s_valid(memory_sv),.s_ready(memory_sr),.s_data(r1_record[127:0]),.seal(stage==SEAL),
  .replay_valid(stage==WINDOW_REQUEST||stage==FINAL_REQUEST),.replay_ready(memory_replay_ready),
  .replay_first(replay_first),.replay_count(replay_count),.release_frame(release_memory),
  .m_valid(memory_mv),.m_ready(memory_mr),.m_data(memory_data),.m_index(memory_index),.m_last(memory_last),
  .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_address(cmd_address),.cmd_tag(cmd_tag),.cmd_data(cmd_data),
  .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_tag(rsp_tag),.rsp_data(rsp_data),.rsp_error(rsp_error),
  .generation(memory_generation),.committed_words(memory_committed),.read_words(memory_read),.sealed(memory_sealed),.busy(memory_busy),
  .error_code(memory_error),.stall_cycles(memory_stalls)
 );
 wire sample_fifo_ready,sample_fifo_valid,sample_fifo_pop,fw_busy,fr_busy,fw_over,fr_under;
 wire [134:0] sample_packet;
 wire signed [15:0] sample_i=$signed(memory_data[32*lane+:16]);
 wire signed [15:0] sample_q=$signed(memory_data[32*lane+16+:16]);
 wire [134:0] input_packet={frame_id,generation,window_number,memory_index[8:0],lane,
                          (memory_last&&lane==3),{{4{sample_i[15]}},sample_i,6'd0},{{4{sample_q[15]}},sample_q,6'd0}};
 ota_async_fifo #(.WIDTH(135),.DEPTH(32)) window_samples(
  .wr_clk(clk150),.rd_clk(clk500),.reset_request(reset_request||compute_cancel150),
  .s_valid(stage==WINDOW_STREAM&&memory_mv&&!fail),.s_ready(sample_fifo_ready),.s_data(input_packet),
  .m_valid(sample_fifo_valid),.m_ready(sample_fifo_pop),.m_data(sample_packet),
  .wr_busy(fw_busy),.rd_busy(fr_busy),.wr_count(window_fifo_level150),.rd_count(),.overflow(fw_over),.underflow(fr_under)
 );
 wire [31:0] obs_frame,obs_generation;wire [6:0] obs_window;
 wire signed [37:0] obs_i,obs_q;wire [9:0] obs_pilots;wire [15:0] obs_saturations;
 wire [3:0] front_error,link_error,link_front_error;wire front_valid,front_ready,link_valid;
 wire [498:0] backend_word;wire fast_busy,slow_busy;
 wire observation_overflow,observation_underflow;
 logic [1:0] fast_fifo_errors;wire [1:0] fast_fifo_errors150;
 always_ff @(posedge clk500)begin
  if(rst500)fast_fifo_errors<=0;
  else begin
   if(fr_under)fast_fifo_errors[0]<=1;
   if(observation_overflow)fast_fifo_errors[1]<=1;
  end
 end
 xpm_cdc_array_single #(.WIDTH(2),.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.SRC_INPUT_REG(0))
 fifo_error_sync(.src_clk(clk500),.src_in(fast_fifo_errors),.dest_clk(clk150),.dest_out(fast_fifo_errors150));
 always_ff @(posedge clk150)begin
  if(rst150||(context_valid&&context_ready))fifo_error150<=0;
  else fifo_error150<=fifo_error150|{observation_underflow,fast_fifo_errors150,fw_over};
 end
 cfo_front2048_window observation_front(
  .clk(clk500),.rst(rst500||fr_busy),.abort_sync(1'b0),
  .s_valid(sample_fifo_valid),.s_ready(sample_fifo_pop),
  .s_frame(sample_packet[134:103]),.s_generation(sample_packet[102:71]),.s_window(sample_packet[70:64]),
  .s_index(sample_packet[63:53]),.s_last(sample_packet[52]),.s_i(sample_packet[51:26]),.s_q(sample_packet[25:0]),
  .m_valid(front_valid),.m_ready(front_ready),.m_frame(obs_frame),.m_generation(obs_generation),.m_window(obs_window),
  .m_z_i(obs_i),.m_z_q(obs_q),.m_pilot_count(obs_pilots),.m_fft_saturations(obs_saturations),.m_error(front_error),
  .pilot_audit_valid(),.pilot_audit_index(),.pilot_audit_value(),.fft_butterfly_audit_valid(),.fft_butterfly_audit_stage(),.fft_butterfly_audit_index()
 );
 cfo_estimator_link observation_backend(
  .clk_fast(clk500),.clk_slow(clk150),.reset_async(reset_request),.abort_async(compute_cancel150),
  .s_valid(front_valid),.s_ready(front_ready),.s_frame(obs_frame),.s_generation(obs_generation),.s_window(obs_window),
  .s_z_i(obs_i),.s_z_q(obs_q),.s_pilot_count(obs_pilots),.s_fft_saturations(obs_saturations),.s_front_error(front_error),
  .m_valid(link_valid),.m_ready(stage==ESTIMATE),.m_backend_word(backend_word),.m_link_error(link_error),.m_front_error(link_front_error),
  .m_fft_saturation_sum(),.fifo_write_count(),.fifo_read_count(observation_fifo_level150),.fifo_full(),.fifo_empty(),.fifo_overflow(observation_overflow),.fifo_underflow(observation_underflow),
  .fast_reset_busy(fast_busy),.slow_reset_busy(slow_busy),.read_audit_valid(),.read_audit_word(),.normal_audit_valid(),.normal_audit_index(),.fft_audit_valid(),.fft_audit_index()
 );
 assign memory_mr=!fail&&((stage==WINDOW_STREAM)?(sample_fifo_ready&&lane==3):((stage==FINAL_STREAM)?r2_sr:1'b0));
 wire [224:0] final_input={frame_id,generation,memory_index,memory_last,memory_data};
 cfo_rotate4 second_rotation(
  .clk(clk150),.rst(rst150),.abort_sync(cancel150||stage==CANCEL_DRAIN),
  .cfg_valid(stage==RESIDUAL_CFG&&coordinate_valid&&coordinate_ok),.cfg_ready(r2_cfg_ready),
  .cfg_frame(frame_id),.cfg_generation(generation),.cfg_phase0(phase0),.cfg_step(phase_step),.cfg_sample_count(FRAME_SAMPLES),
  .s_valid(stage==FINAL_STREAM&&memory_mv&&!fail),.s_ready(r2_sr),.s_record(final_input),
  .m_valid(r2_valid),.m_ready(m_ready&&(stage==FINAL_STREAM||stage==FINAL_DRAIN)&&!fail),.m_record(r2_record),.m_saturation(sat2),
  .fault(r2_fault),.first_error(r2_error)
 );
 function automatic [3:0] pop8(input [7:0] v);
  integer j;begin pop8=0;for(j=0;j<8;j=j+1)pop8=pop8+v[j];end
 endfunction
 always_ff @(posedge clk150)begin
  if(rst150)begin
   stage<=IDLE;error_code<=0;frame_id<=0;generation<=0;step1<=0;step2<=0;origin<=0;coarse_frequency<=0;residual_frequency<=0;
   memory_base<=0;window_first<=6496;window_number<=0;lane<=0;coarse_beats<=0;final_beats<=0;
   coarse_saturations<=0;final_saturations<=0;observations_sent<=0;estimator_result<=0;
  end else if(cancel150)begin stage<=(stage==CANCEL_DRAIN&&!memory_busy)?COMPLETE:((stage==COMPLETE)?COMPLETE:CANCEL_DRAIN);if(error_code==0)error_code<=8'h01;end
  else if(stage==CANCEL_DRAIN)begin if(!memory_busy)stage<=COMPLETE;end
  else if(fail&&stage!=COMPLETE&&stage!=IDLE)begin
   stage<=FAIL;
   if(backend_bad)estimator_result<=backend_word;
   if(error_code==0)error_code<=backend_bad?8'h60:(memory_failed?8'h20:(r1_fault?8'h30:8'h31));
  end else begin
   if(memory_sv&&memory_sr)begin coarse_beats<=coarse_beats+1'b1;coarse_saturations<=coarse_saturations+pop8(sat1);end
   if(m_valid&&m_ready)begin final_beats<=final_beats+1'b1;final_saturations<=final_saturations+pop8(sat2);end
   case(stage)
    IDLE:if(context_valid&&context_ready)begin
     {memory_base,frame_id,generation,step1,step2,origin,coarse_frequency}<=context_record;
     stage<=OPEN;error_code<=0;window_first<=6496;window_number<=0;lane<=0;
     coarse_beats<=0;final_beats<=0;coarse_saturations<=0;final_saturations<=0;observations_sent<=0;estimator_result<=0;
    end
    OPEN:if(memory_start_ready)stage<=COARSE_COORD;
    COARSE_COORD:if(coordinate_ready)stage<=COARSE_CFG;
    COARSE_CFG,RESIDUAL_CFG:if(coordinate_valid&&coordinate_output_ready)begin
     if(!coordinate_ok||coordinate_frame!=frame_id||coordinate_generation!=generation||coordinate_residual!=(stage==RESIDUAL_CFG))begin error_code<=8'h40;stage<=FAIL;end
     else stage<=stage==COARSE_CFG?INGEST:FINAL_REQUEST;
    end
    INGEST:if(memory_sv&&memory_sr&&r1_record[128])stage<=SEAL;
    SEAL:if(memory_sealed)begin
     if(memory_committed!=FRAME_BEATS)begin error_code<=8'h21;stage<=FAIL;end
     else stage<=WINDOW_REQUEST;
    end
    WINDOW_REQUEST:if(memory_replay_ready)begin lane<=0;stage<=WINDOW_STREAM;end
    WINDOW_STREAM:if(memory_mv&&sample_fifo_ready)begin
     lane<=lane+1'b1;
     if(lane==3&&memory_last)begin
      observations_sent<=observations_sent+1'b1;
      if(window_number==73)stage<=ESTIMATE;
      else begin window_number<=window_number+1'b1;window_first<=window_first+4480;stage<=WINDOW_REQUEST;end
     end
    end
    ESTIMATE:if(link_valid)begin
     estimator_result<=backend_word;
     if(link_error!=0||link_front_error!=0||backend_word[498:467]!=frame_id||backend_word[466:435]!=generation||backend_word[434:431]!=0||!backend_word[428])begin
      error_code<=8'h60;stage<=FAIL;
     end else begin residual_frequency<=backend_word[427:396];stage<=RESIDUAL_COORD;end
    end
    RESIDUAL_COORD:if(coordinate_ready)stage<=RESIDUAL_CFG;
    FINAL_REQUEST:if(memory_replay_ready)stage<=FINAL_STREAM;
    FINAL_STREAM:if(memory_mv&&memory_mr&&memory_last)stage<=FINAL_DRAIN;
    FINAL_DRAIN:if(m_valid&&m_ready&&m_record[128])stage<=RELEASE;
    RELEASE:stage<=COMPLETE;
    COMPLETE:if(done_ready)begin stage<=IDLE;error_code<=0;end
    FAIL:begin end
    default:begin error_code<=8'hff;stage<=FAIL;end
   endcase
  end
 end
endmodule



