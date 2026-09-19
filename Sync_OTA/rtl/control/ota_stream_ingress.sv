`timescale 1ns/1ps
// Input segment controls are transport metadata. Algorithm frames are detected
// autonomously. Raw RAM and frontend accept each IQ word atomically at125 MHz.
// A temporary valid gap changes no sample index; terminal last closes a segment.
module ota_stream_ingress(
 input wire clk,rst,poison,
 input wire s_valid,output wire s_ready,input wire [127:0] s_data,
 input wire s_first,s_last,read_done,
 output wire raw_valid,input wire raw_ready,output wire [127:0] raw_data,
 output wire fe_valid,input wire fe_ready,output wire [127:0] fe_data,
 output logic fe_start,fe_segment_end,input wire fe_quiescent,input wire [31:0] fe_epoch,
 input wire fe_result_valid,output wire fe_result_ready,input wire [287:0] fe_result,
 input wire retention_valid,input wire [31:0] retention_epoch,input wire [63:0] retention_samples,
 output wire event_valid,input wire event_ready,output wire [208:0] event_record,
 output logic [63:0] forwarded_words,
 output logic [31:0] frames_created,segments_started,segments_completed,
 output wire input_idle,output logic fault,output logic [7:0] error_code,output logic [2:0] stage
);
 localparam [2:0] IDLE=0,ARM=1,FEED=2,DRAIN=3,CLOSE=4;
 localparam [1:0] D_IDLE=0,D_MAP=1,D_PUBLISH=2;
 wire stopped=rst||poison||fault;
 logic [7:0] input_occupancy;
 wire qsr,qv,qr,qerror;wire [129:0] qdata;
 assign s_ready=!stopped&&qsr;
 sfo_sync_fifo #(.WIDTH(130),.DEPTH(128)) input_words(
  .clk(clk),.rst(rst),.s_valid(s_valid&&!stopped),.s_ready(qsr),.s_data({s_first,s_last,s_data}),
  .m_valid(qv),.m_ready(qr),.m_data(qdata),.level(),.high_water(),.reset_busy(),.error_sticky(qerror));
 assign raw_valid=!stopped&&stage==FEED&&qv&&fe_ready;
 assign fe_valid=!stopped&&stage==FEED&&qv&&raw_ready;
 assign qr=!stopped&&stage==FEED&&fe_ready&&raw_ready;
 assign raw_data=qdata[127:0];assign fe_data=qdata[127:0];
 wire word_fire=qv&&qr;
 logic first_word;
 logic [31:0] segment_generation,expected_epoch;
 logic [63:0] segment_base,required_end,candidate_floor,last_floor;
 logic [1:0] descriptor_state;
 logic [287:0] saved_result;
 logic [207:0] saved_lease;
 logic pending_event,terminal_event;
 logic [208:0] held_event;
 assign event_valid=pending_event&&!stopped;assign event_record=held_event;
 wire event_fire=event_valid&&event_ready;
 assign input_idle=stage==IDLE&&input_occupancy==0&&descriptor_state==D_IDLE&&!pending_event;
 assign fe_result_ready=!stopped&&descriptor_state==D_IDLE&&(stage==FEED||stage==DRAIN);
 wire [63:0] fine_absolute=saved_result[127:64];
 wire [63:0] nominal_word={2'd0,fine_absolute[63:2]};
 wire [63:0] mapped_first=segment_base+nominal_word-64'd43;
 wire signed [31:0] coarse_hz=$signed(saved_result[63:32]);
 always_ff @(posedge clk)begin
  if(rst)begin
   stage<=IDLE;descriptor_state<=D_IDLE;input_occupancy<=0;first_word<=1;fe_start<=0;fe_segment_end<=0;
   forwarded_words<=0;frames_created<=0;segments_started<=0;segments_completed<=0;
   segment_generation<=0;expected_epoch<=0;segment_base<=0;required_end<=0;candidate_floor<=0;last_floor<=0;
   saved_result<=0;saved_lease<=0;pending_event<=0;terminal_event<=0;held_event<=0;fault<=0;error_code<=0;
  end else begin
   fe_start<=0;fe_segment_end<=0;
   if(!fault&&(poison||qerror))begin fault<=1;error_code<=poison?8'h01:8'h02;end
   if(!stopped)begin
    case({s_valid&&s_ready,word_fire})2'b10:input_occupancy<=input_occupancy+1'b1;2'b01:input_occupancy<=input_occupancy-1'b1;default:begin end endcase
    if(retention_valid&&retention_epoch==expected_epoch)candidate_floor<=segment_base+(retention_samples>>2);
    if(event_fire)begin
     pending_event<=0;
     if(held_event[208])begin
      frames_created<=frames_created+1'b1;descriptor_state<=D_IDLE;
     end else last_floor<=held_event[63:0];
     if(terminal_event)begin stage<=IDLE;segments_completed<=segments_completed+1'b1;terminal_event<=0;end
    end
    if(fe_result_valid&&fe_result_ready)begin saved_result<=fe_result;descriptor_state<=D_MAP;end
    if(descriptor_state==D_MAP)begin
     if(saved_result[287:256]!=expected_epoch||saved_result[15:0]!=16'h3800)begin fault<=1;error_code<=8'h10;end
     else if(nominal_word<43||mapped_first<segment_base||mapped_first+334215<mapped_first)begin fault<=1;error_code<=8'h11;end
     else if(coarse_hz < -32'sd8388607||coarse_hz>32'sd8388607||frames_created==32'hffffffff)begin fault<=1;error_code<=8'h12;end
     else begin
      saved_lease<={frames_created,segment_generation,mapped_first,{30'd0,fine_absolute[1:0]},coarse_hz,saved_result[31:16]};
      if(mapped_first+334215>required_end)required_end<=mapped_first+334215;
      descriptor_state<=D_PUBLISH;
     end
    end
    // No watermark can pass a descriptor that has not yet created its lease.
    // A previous queued floor was computed while frontend still held the pin.
    if(!pending_event)begin
     if(descriptor_state==D_PUBLISH)begin pending_event<=1;held_event<={1'b1,saved_lease};terminal_event<=0;end
     else if(descriptor_state==D_IDLE&&!fe_result_valid)begin
      if(stage==CLOSE)begin pending_event<=1;held_event<={145'd0,forwarded_words};terminal_event<=1;end
      else if(stage==FEED&&retention_valid&&retention_epoch==expected_epoch&&candidate_floor>=last_floor&&candidate_floor-last_floor>=64)begin
       pending_event<=1;held_event<={145'd0,candidate_floor};terminal_event<=0;
      end
     end
    end
    case(stage)
     IDLE:if(qv)begin
      if(!qdata[129]||segments_started==32'hffffffff)begin fault<=1;error_code<=8'h20;end
      else begin
       fe_start<=1;stage<=ARM;first_word<=1;expected_epoch<=fe_epoch+1'b1;
       segment_generation<=segments_started;segments_started<=segments_started+1'b1;
       segment_base<=forwarded_words;required_end<=forwarded_words;candidate_floor<=forwarded_words;
      end
     end
     ARM:if(fe_epoch==expected_epoch&&fe_ready&&!fe_start)stage<=FEED;
     FEED:if(word_fire)begin
      forwarded_words<=forwarded_words+1'b1;first_word<=0;
      if(qdata[129]!=first_word||forwarded_words==64'hffffffffffffffff)begin fault<=1;error_code<=8'h21;end
      if(qdata[128])begin stage<=DRAIN;fe_segment_end<=1;end
     end
     DRAIN:if(fe_quiescent&&descriptor_state==D_IDLE&&!fe_result_valid&&!pending_event)begin
      if(required_end>forwarded_words)begin fault<=1;error_code<=8'h22;end
      else stage<=CLOSE;
     end
     CLOSE:begin end
     default:begin fault<=1;error_code<=8'h23;end
    endcase
   end
  end
 end
 // read_done is informational: stream_last on an accepted word owns closure.
 // A read controller may assert read_done before this input FIFO has drained.
endmodule
