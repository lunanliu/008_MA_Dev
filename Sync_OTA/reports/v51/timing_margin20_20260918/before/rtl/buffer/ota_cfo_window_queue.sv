`timescale 1ns/1ps
// Capture only the 74 residual-CFO windows from coarse-rotated four-lane IQ.
// Eight complete windows live in a 4096x128 BRAM async FIFO. A separate header
// is published only after its last word is accepted; the fast serializer never
// starts a partially produced window. Whole-window space is reserved in advance.
module ota_cfo_window_queue(
 input wire clk150,clk500,reset_request,poison150,
 input wire cfg_valid,output wire cfg_ready,input wire [31:0] cfg_frame,cfg_generation,
 input wire s_valid,output wire s_ready,input wire [224:0] s_record,
 output wire m_valid,input wire m_ready,output wire [134:0] m_record,
 output wire [12:0] buffered_words150,
 output logic [6:0] windows_captured,
 output wire fault150,output logic [7:0] error150
);
 wire rst150,rst500;
 logic slow_fault,fast_fault;wire fast_fault150;
 sfo_domain_reset reset_slow(.clk(clk150),.reset_request(reset_request),.reset_active(rst150));
 sfo_domain_reset reset_fast(.clk(clk500),.reset_request(reset_request),.reset_active(rst500));
 wire poison500;
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) poison_sync(
  .src_clk(clk150),.src_in(poison150||slow_fault),.dest_clk(clk500),.dest_out(poison500));
 xpm_cdc_single #(.DEST_SYNC_FF(4),.SRC_INPUT_REG(1),.INIT_SYNC_FF(0)) fault_sync(
  .src_clk(clk500),.src_in(fast_fault),.dest_clk(clk150),.dest_out(fast_fault150));
 assign fault150=slow_fault||fast_fault150;
 wire slow_stop=rst150||poison150||fault150;
 wire fast_stop=rst500||poison500||fast_fault;
 logic active,reserved,header_pending;
 logic [31:0] frame,generation,expected_beat,next_first;
 logic [6:0] window_number;
 logic [9:0] window_word;
 logic [70:0] header_hold;
 wire dq_sr,dq_v,dq_r,hq_sr,hq_v,hq_r,dq_wbusy,dq_rbusy,hq_wbusy,hq_rbusy;
 wire dq_over,dq_under,hq_over,hq_under;
 logic [3:0] occupied_slots;
 wire return_ready,return_valid,return_over,return_under;
 wire reserve=active&&!reserved&&!header_pending&&window_number<74&&
       !dq_wbusy&&!hq_wbusy&&hq_sr&&occupied_slots<8;
 wire return_fire=return_valid&&!slow_stop;
 wire [127:0] dq_data;wire [70:0] hq_data;
 wire selected=window_word!=0||expected_beat==next_first;
 assign cfg_ready=!slow_stop&&!active&&!header_pending&&!dq_wbusy&&!hq_wbusy;
 assign s_ready=!slow_stop&&active&&(!selected||(reserved&&dq_sr));
 wire take=s_valid&&s_ready;
 wire sample_good=s_record[224:193]==frame&&s_record[192:161]==generation&&
  s_record[160:129]==expected_beat&&s_record[128]==(expected_beat==334079);
 wire write_window=take&&selected&&sample_good;
 ota_async_fifo #(.WIDTH(128),.DEPTH(4096)) packed_windows(
  .wr_clk(clk150),.rd_clk(clk500),.reset_request(reset_request),
  .s_valid(write_window),.s_ready(dq_sr),.s_data(s_record[127:0]),
  .m_valid(dq_v),.m_ready(dq_r),.m_data(dq_data),
  .wr_busy(dq_wbusy),.rd_busy(dq_rbusy),.wr_count(buffered_words150),.rd_count(),.overflow(dq_over),.underflow(dq_under));
 ota_async_fifo #(.WIDTH(71),.DEPTH(32)) complete_windows(
  .wr_clk(clk150),.rd_clk(clk500),.reset_request(reset_request),
  .s_valid(header_pending&&!slow_stop),.s_ready(hq_sr),.s_data(header_hold),
  .m_valid(hq_v),.m_ready(hq_r),.m_data(hq_data),
  .wr_busy(hq_wbusy),.rd_busy(hq_rbusy),.wr_count(),.rd_count(),.overflow(hq_over),.underflow(hq_under));
 // Header metadata and IQ are registered together in the fast output holding
 // register. The four-way lane selector ends here, not at the FFT input flops.
 logic header_active,output_valid;
 logic [70:0] fast_header;
 logic [10:0] sample_index;
 logic [134:0] output_record;
 logic [1:0] packed_count;
 logic [127:0] packed_head,packed_tail;
 wire packed_push=dq_v&&dq_r;
 wire advance=!output_valid||m_ready;
 wire issue=!fast_stop&&header_active&&packed_count!=0&&advance&&
            (sample_index!=2047||return_ready);
 wire packed_pop=issue&&sample_index[1:0]==3;
 ota_async_fifo #(.WIDTH(1),.DEPTH(32)) window_credits(
  .wr_clk(clk500),.rd_clk(clk150),.reset_request(reset_request),
  .s_valid(issue&&sample_index==2047),.s_ready(return_ready),.s_data(1'b1),
  .m_valid(return_valid),.m_ready(!slow_stop),.m_data(),
  .wr_busy(),.rd_busy(),.wr_count(),.rd_count(),.overflow(return_over),.underflow(return_under));
 wire [31:0] lane_data=packed_head[32*sample_index[1:0]+:32];
 wire signed [15:0] lane_i=lane_data[15:0],lane_q=lane_data[31:16];
 assign hq_r=!fast_stop&&!header_active;
 // Prefetch does not release a window credit. That still belongs to last IQ.
 assign dq_r=!fast_stop&&packed_count<2;
 assign m_valid=!fast_stop&&output_valid;
 assign m_record=output_record;
 always_ff @(posedge clk500)begin
  if(fast_stop)packed_count<=0;
  else begin
   case({packed_push,packed_pop})
    2'b10:packed_count<=packed_count+1'b1;
    2'b01:packed_count<=packed_count-1'b1;
    default:begin end
   endcase
   if(packed_push)begin
    if(packed_count==0||(packed_count==1&&packed_pop))packed_head<=dq_data;
    else packed_tail<=dq_data;
   end
   if(packed_pop&&packed_count==2)packed_head<=packed_tail;
  end
 end
 always_ff @(posedge clk500)begin
  if(rst500)begin header_active<=0;output_valid<=0;fast_header<=0;sample_index<=0;fast_fault<=0;end
  else if(fast_stop)begin header_active<=0;output_valid<=0;if(poison500)fast_fault<=1;end
  else begin
   if(dq_under||hq_under||return_over)fast_fault<=1;
   if(hq_v&&hq_r)begin fast_header<=hq_data;sample_index<=0;header_active<=1;end
   if(advance)begin
    output_valid<=issue;
    if(issue)begin
     output_record<={fast_header,sample_index,(sample_index==2047),
       {{4{lane_i[15]}},lane_i,6'd0},{{4{lane_q[15]}},lane_q,6'd0}};
     sample_index<=sample_index+1'b1;
     if(sample_index==2047)header_active<=0;
    end
   end
  end
 end
 always_ff @(posedge clk150)begin
  if(rst150)begin
   active<=0;reserved<=0;header_pending<=0;frame<=0;generation<=0;expected_beat<=0;
   next_first<=6496;window_number<=0;window_word<=0;header_hold<=0;
   windows_captured<=0;slow_fault<=0;error150<=0;occupied_slots<=0;
  end else if(!slow_fault)begin
   if(poison150||fast_fault150)begin slow_fault<=1;error150<=8'h01;end
   else if(dq_over||hq_over||return_under||(return_fire&&occupied_slots==0))begin slow_fault<=1;error150<=8'h02;end
   else if(take&&!sample_good)begin slow_fault<=1;error150<=8'h03;end
   else begin
    if(header_pending&&hq_sr)header_pending<=0;
    // Credits span frame boundaries and return only after the last packed
    // word is copied into a tagged local output register. wr_count is telemetry.
    if(reserve)reserved<=1;
    case({reserve,return_fire})
     2'b10:occupied_slots<=occupied_slots+1'b1;
     2'b01:occupied_slots<=occupied_slots-1'b1;
     default:begin end
    endcase
    if(cfg_valid&&cfg_ready)begin
     active<=1;reserved<=0;frame<=cfg_frame;generation<=cfg_generation;expected_beat<=0;
     next_first<=6496;window_number<=0;window_word<=0;windows_captured<=0;
    end
    if(take)begin
     expected_beat<=expected_beat+1'b1;
     if(expected_beat==334079)active<=0;
     if(selected)begin
      if(window_word==511)begin
       header_pending<=1;header_hold<={frame,generation,window_number};reserved<=0;
       window_word<=0;window_number<=window_number+1'b1;next_first<=next_first+4480;
       windows_captured<=windows_captured+1'b1;
      end else window_word<=window_word+1'b1;
     end
    end
   end
  end
 end
endmodule
