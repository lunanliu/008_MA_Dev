`timescale 1ns/1ps
// Raw IQ and ordered lease/floor events enter at125; shared RAM and E1 run150.
// T06 training has one outstanding job and an explicit identity-bearing release.
// No E1 lease is released until that frame's T06 release token is queued.
module ota_raw_training_hub #(
 parameter integer DEPTH=393216,FRAME_WORDS=334215,TRAIN_WORDS=5172
)(
 input wire clk125,clk150,reset_request,poison125,poison150,
 input wire s_valid,output wire s_ready,input wire [127:0] s_data,
 input wire event_valid,output wire event_ready,input wire [208:0] event_record,
 output wire train_cfg_valid,input wire train_cfg_ready,output wire [207:0] train_cfg_record,
 output wire train_data_valid,input wire train_data_ready,output wire [224:0] train_data_record,
 input wire train_release_valid,output wire train_release_ready,input wire [63:0] train_release_record,
 input wire frame_valid,output wire frame_ready,input wire [63:0] frame_first,
 input wire [31:0] frame_id,frame_generation,
 output wire m_valid,input wire m_ready,output wire [127:0] m_data,
 output wire [31:0] m_frame,m_generation,m_beat,output wire m_last,
 output wire [63:0] accepted_words,written_words,retired_words,
 output wire [31:0] high_water,
 output wire fault125,output logic fault150,output logic [7:0] error150
);
 wire rst125,rst150;
 sfo_domain_reset reset_a(.clk(clk125),.reset_request(reset_request),.reset_active(rst125));
 sfo_domain_reset reset_b(.clk(clk150),.reset_request(reset_request),.reset_active(rst150));
 wire stopped125=rst125||poison125||fault125,stopped150=rst150||poison150||fault150;
 wire [4:0] wr_error,rd_error;
 wire raw_v,raw_r,raw_sr,ev_v,ev_r,ev_sr,tc_v,tc_r,td_v,td_r,ack_v,ack_r,ack_sr;
 wire [127:0] raw_d;wire [208:0] ev_d;wire [63:0] ack_d;
 wire [207:0] tc_d;wire [224:0] td_d;
 wire error_to125,poison_to150;
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) fault_sync(
  .src_clk(clk150),.src_in(fault150),.dest_clk(clk125),.dest_out(error_to125));
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) poison_sync(
  .src_clk(clk125),.src_in(poison125),.dest_clk(clk150),.dest_out(poison_to150));
 logic local_fault125;
 assign fault125=local_fault125||error_to125;
 wire fault125_sync;
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) local_fault_sync(
  .src_clk(clk125),.src_in(local_fault125),.dest_clk(clk150),.dest_out(fault125_sync));
 logic [1:0] raw_qcount;
 logic [127:0] raw_qhead,raw_qtail;
 wire raw_qv=!rst125&&raw_qcount!=0;
 wire raw_qpush=s_valid&&s_ready,raw_qpop=raw_qv&&raw_sr;
 assign s_ready=!stopped125&&raw_qcount<2;
 assign event_ready=!stopped125&&ev_sr;
 always_ff @(posedge clk125)begin
  if(stopped125)raw_qcount<=0;
  else case({raw_qpush,raw_qpop})
   2'b10:raw_qcount<=raw_qcount+1'b1;
   2'b01:raw_qcount<=raw_qcount-1'b1;
   default:begin end
  endcase
  if(raw_qpush)begin
   if(raw_qcount==0||(raw_qcount==1&&raw_qpop))raw_qhead<=s_data;
   else raw_qtail<=s_data;
  end
  if(raw_qpop&&raw_qcount==2)raw_qhead<=raw_qtail;
 end
 assign train_release_ready=!stopped125&&ack_sr;
 sfo_record_cdc_fifo #(.WIDTH(128),.DEPTH(1024)) raw_cdc(
  .wr_clk(clk125),.rd_clk(clk150),.reset_request(reset_request),
  .s_valid(raw_qv),.s_ready(raw_sr),.s_data(raw_qhead),
  .m_valid(raw_v),.m_ready(raw_r),.m_data(raw_d),.wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),
  .wr_reset_active(),.rd_reset_active(),.wr_error(wr_error[0]),.rd_error(rd_error[0]));
 sfo_record_cdc_fifo #(.WIDTH(209),.DEPTH(32)) events_cdc(
  .wr_clk(clk125),.rd_clk(clk150),.reset_request(reset_request),
  .s_valid(event_valid&&!stopped125),.s_ready(ev_sr),.s_data(event_record),
  .m_valid(ev_v),.m_ready(ev_r),.m_data(ev_d),.wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),
  .wr_reset_active(),.rd_reset_active(),.wr_error(wr_error[1]),.rd_error(rd_error[1]));
 wire cfg_out_v,data_out_v;
 assign train_cfg_valid=cfg_out_v&&!stopped125;assign train_data_valid=data_out_v&&!stopped125;
 sfo_record_cdc_fifo #(.WIDTH(208),.DEPTH(32)) training_configuration(
  .wr_clk(clk150),.rd_clk(clk125),.reset_request(reset_request),
  .s_valid(tc_v),.s_ready(tc_r),.s_data(tc_d),
  .m_valid(cfg_out_v),.m_ready(train_cfg_ready&&!stopped125),.m_data(train_cfg_record),.wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),
  .wr_reset_active(),.rd_reset_active(),.wr_error(wr_error[2]),.rd_error(rd_error[2]));
 sfo_record_cdc_fifo #(.WIDTH(225),.DEPTH(1024)) training_data(
  .wr_clk(clk150),.rd_clk(clk125),.reset_request(reset_request),
  .s_valid(td_v),.s_ready(td_r),.s_data(td_d),
  .m_valid(data_out_v),.m_ready(train_data_ready&&!stopped125),.m_data(train_data_record),.wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),
  .wr_reset_active(),.rd_reset_active(),.wr_error(wr_error[3]),.rd_error(rd_error[3]));
 sfo_record_cdc_fifo #(.WIDTH(64),.DEPTH(32)) training_release(
  .wr_clk(clk125),.rd_clk(clk150),.reset_request(reset_request),
  .s_valid(train_release_valid&&!stopped125),.s_ready(ack_sr),.s_data(train_release_record),
  .m_valid(ack_v),.m_ready(ack_r),.m_data(ack_d),.wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),
  .wr_reset_active(),.rd_reset_active(),.wr_error(wr_error[4]),.rd_error(rd_error[4]));
 wire lease_fault,raw_fault,floor_v,lease_match,lease_head_valid,job_v,job_r;
 // Ordered requested floors may lead data CDC visibility. Apply only the
 // already-written prefix; this breaks terminal-floor versus full-ring waits.
 logic [63:0] applied_floor;
 wire [7:0] lease_error,raw_error;wire [63:0] floor;
 always_ff @(posedge clk150)begin
  if(rst150)applied_floor<=0;
  else if(!stopped150&&floor_v)applied_floor<=floor<written_words?floor:written_words;
 end
 wire [207:0] job_record;
 wire raw_frame_ready,trained_v,trained_r,trained_sr,trained_error;
 wire [63:0] trained_record;
 wire trained_match=trained_v&&trained_record=={frame_id,frame_generation};
 wire launch=frame_valid&&frame_ready;
 assign frame_ready=!stopped150&&raw_frame_ready&&lease_match&&trained_match;
 assign trained_r=launch;
 ota_raw_lease_scheduler leases(
  .clk(clk150),.rst(rst150),.poison(stopped150),.s_valid(ev_v),.s_ready(ev_r),.s_event(ev_d),
  .floor_valid(floor_v),.retire_floor(floor),.frame_launch(launch),
  .launch_frame(frame_id),.launch_generation(frame_generation),.launch_first(frame_first),.launch_matches(lease_match),.lease_head_valid(lease_head_valid),
  .train_valid(job_v),.train_ready(job_r),.train_record(job_record),.fault(lease_fault),.error_code(lease_error));
 localparam [2:0] IDLE=0,CONFIGURE=1,REQUEST=2,TRANSFER=3,WAIT_RELEASE=4;
 logic [2:0] train_state;
 logic [207:0] train_context;
 logic [63:0] train_first;
 wire raw_train_ready;
 wire [127:0] train_iq;wire [31:0] train_f,train_g,train_b;wire train_last;
 assign job_r=!stopped150&&train_state==IDLE;
 assign tc_v=!stopped150&&train_state==CONFIGURE;assign tc_d=train_context;
 assign td_d={train_f,train_g,train_b,train_last,train_iq};
 wire ack_good=ack_d==train_context[207:144];
 assign ack_r=!stopped150&&train_state==WAIT_RELEASE&&trained_sr;
 sfo_sync_fifo #(.WIDTH(64),.DEPTH(32)) trained_frames(
  .clk(clk150),.rst(rst150),.s_valid(ack_v&&ack_r&&ack_good),.s_ready(trained_sr),.s_data(ack_d),
  .m_valid(trained_v),.m_ready(trained_r),.m_data(trained_record),.level(),.high_water(),.reset_busy(),.error_sticky(trained_error));
 ota_shared_raw_store #(.DEPTH(DEPTH),.FRAME_WORDS(FRAME_WORDS),.TRAIN_WORDS(TRAIN_WORDS)) raw_store(
  .clk(clk150),.rst(rst150),.poison(stopped150),
  .s_valid(raw_v),.s_ready(raw_r),.s_data(raw_d),.floor_valid(floor_v),.retire_floor(applied_floor),
  .frame_valid(frame_valid&&lease_match&&trained_match&&!stopped150),.frame_ready(raw_frame_ready),
  .frame_first(frame_first),.frame_id(frame_id),.frame_generation(frame_generation),
  .f_valid(m_valid),.f_ready(m_ready),.f_data(m_data),.f_frame(m_frame),.f_generation(m_generation),.f_beat(m_beat),.f_last(m_last),
  .train_valid(train_state==REQUEST&&!stopped150),.train_ready(raw_train_ready),.train_first(train_first),
  .train_frame(train_context[207:176]),.train_generation(train_context[175:144]),
  .t_valid(td_v),.t_ready(td_r),.t_data(train_iq),.t_frame(train_f),.t_generation(train_g),.t_beat(train_b),.t_last(train_last),
  .accepted_words(accepted_words),.written_words(written_words),.retired_words(retired_words),.high_water(high_water),
  .fault(raw_fault),.error_code(raw_error));
 always_ff @(posedge clk125)begin
  if(rst125)local_fault125<=0;
  else if(poison125||wr_error[0]||wr_error[1]||rd_error[2]||rd_error[3]||wr_error[4])local_fault125<=1;
 end
 always_ff @(posedge clk150)begin
  if(rst150)begin train_state<=IDLE;train_context<=0;train_first<=0;fault150<=0;error150<=0;end
  else if(!fault150)begin
   if(poison150||poison_to150||fault125_sync)begin fault150<=1;error150<=8'h01;end
   else if(rd_error[0]||rd_error[1]||wr_error[2]||wr_error[3]||rd_error[4]||trained_error)begin fault150<=1;error150<=8'h02;end
   else if(lease_fault)begin fault150<=1;error150<=8'h10|lease_error;end
   else if(raw_fault)begin fault150<=1;error150<=8'h20|raw_error;end
   else if(ack_v&&ack_r&&!ack_good)begin fault150<=1;error150<=8'h30;end
   else if(frame_valid&&lease_head_valid&&!lease_match)begin fault150<=1;error150<=8'h34;end
   else if(frame_valid&&trained_v&&!trained_match)begin fault150<=1;error150<=8'h31;end
   else if(!stopped150)case(train_state)
    IDLE:if(job_v&&job_r)begin
     train_context<=job_record;train_first<=job_record[143:80]+64'd1361;train_state<=CONFIGURE;
     if(job_record[143:80]>64'hffffffffffffffff-64'd1361)begin fault150<=1;error150<=8'h32;end
    end
    CONFIGURE:if(tc_r)train_state<=REQUEST;
    REQUEST:if(raw_train_ready)train_state<=TRANSFER;
    TRANSFER:if(td_v&&td_r&&train_last)train_state<=WAIT_RELEASE;
    WAIT_RELEASE:if(ack_v&&ack_r)train_state<=IDLE;
    default:begin fault150<=1;error150<=8'h33;end
   endcase
  end
 end
endmodule
