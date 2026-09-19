`timescale 1ns/1ps
// Shared 150 MHz raw IQ ring: one write port, one arbitrated read port.
// Upstream must install a frame lease BEFORE advancing retire_floor beyond it.
// E1 and training responses have disjoint credit-reserved queues and identities.
// Retirement follows RAM responses captured in those queues, never request issue.
module ota_shared_raw_store #(
 parameter integer DEPTH=393216, AW=$clog2(DEPTH),
 parameter integer FRAME_WORDS=334215, TRAIN_WORDS=5172, RETAIN=256,
 parameter integer RESPONSE_DEPTH=64
)(
 input wire clk,rst,poison,
 input wire s_valid,output wire s_ready,input wire [127:0] s_data,
 input wire floor_valid,input wire [63:0] retire_floor,
 input wire frame_valid,output wire frame_ready,
 input wire [63:0] frame_first,input wire [31:0] frame_id,frame_generation,
 output wire f_valid,input wire f_ready,output wire [127:0] f_data,
 output wire [31:0] f_frame,f_generation,f_beat,output wire f_last,
 input wire train_valid,output wire train_ready,
 input wire [63:0] train_first,input wire [31:0] train_frame,train_generation,
 output wire t_valid,input wire t_ready,output wire [127:0] t_data,
 output wire [31:0] t_frame,t_generation,t_beat,output wire t_last,
 output logic [63:0] accepted_words,written_words,retired_words,
 output logic [31:0] high_water,
 output logic fault,output logic [7:0] error_code
);
 localparam [1:0] IDLE=0,WAIT_DATA=1,MAP_ADDRESS=2,READ_DATA=3;
 localparam integer OCW=$clog2(DEPTH+1),CW=$clog2(RESPONSE_DEPTH+1);
 logic [1:0] ps,ts;
 logic [63:0] pfirst,tfirst,pfloor,tfloor,external_floor;
 logic [31:0] pframe,pgen,tframe,tgen,pi,pr,pc,ti,tr,tc;
 logic [AW-1:0] wp,pp,tp,p_map_wp,t_map_wp;
 logic [63:0] p_map_gap,t_map_gap;
 logic [OCW-1:0] occupancy;
 logic [CW-1:0] pout,tout;
 wire stopped=poison||fault;
 wire pqready,pqvalid,pqbusy,pqerror,tqready,tqvalid,tqbusy,tqerror;
 wire [127:0] pqdata,tqdata,ram_data;
 logic ram_we,ram_re;
 logic [AW-1:0] ram_wa,ram_ra;
 logic [127:0] ram_wd;
 logic [2:0] rv,owner;
 wire pf=frame_valid&&frame_ready,tf=train_valid&&train_ready;
 wire wf=s_valid&&s_ready;
 wire ppop=f_valid&&f_ready,tpop=t_valid&&t_ready;
 // The bounded local occupancy counter is the only capacity input to ready.
 assign s_ready=!rst&&!stopped&&occupancy<DEPTH;
 assign frame_ready=!rst&&!stopped&&ps==IDLE&&!pqvalid&&!pqbusy;
 assign train_ready=!rst&&!stopped&&ts==IDLE&&!tqvalid&&!tqbusy;
 assign f_valid=!rst&&!stopped&&ps==READ_DATA&&pqvalid;
 assign t_valid=!rst&&!stopped&&ts==READ_DATA&&tqvalid;
 assign f_data=pqdata;assign t_data=tqdata;
 assign f_frame=pframe;assign f_generation=pgen;assign f_beat=pc;assign f_last=pc==FRAME_WORDS-1;
 assign t_frame=tframe;assign t_generation=tgen;assign t_beat=tc;assign t_last=tc==TRAIN_WORDS-1;
 // One bounded training burst has priority; a blocked training response queue
 // immediately leaves the read port available to E1. No combinational ready chain.
 wire t_issue=!rst&&!stopped&&ts==READ_DATA&&ti<TRAIN_WORDS&&tout<RESPONSE_DEPTH&&tqready&&!tqbusy;
 wire p_issue=!rst&&!stopped&&!t_issue&&ps==READ_DATA&&pi<FRAME_WORDS&&pout<RESPONSE_DEPTH&&pqready&&!pqbusy;
 wire issue=t_issue||p_issue;
 wire [AW-1:0] issue_address=t_issue?tp:pp;
 wire collision=wf&&issue&&wp==issue_address;
 wire preturn=rv[2]&&!owner[2],treturn=rv[2]&&owner[2];
 // Every response already owns capacity before the RAM request is issued.
 sfo_uram_frame_bank #(.DEPTH_BEATS(DEPTH),.ADDR_WIDTH(AW)) memory(
  .clk(clk),.rst(rst),.wr_en(ram_we),.wr_addr(ram_wa),.wr_data(ram_wd),
  .rd_en(ram_re),.rd_addr(ram_ra),.rd_data(ram_data));
 sfo_sync_fifo #(.WIDTH(128),.DEPTH(RESPONSE_DEPTH)) frame_responses(
  .clk(clk),.rst(rst),.s_valid(preturn),.s_ready(pqready),.s_data(ram_data),
  .m_valid(pqvalid),.m_ready(ppop),.m_data(pqdata),.level(),.high_water(),.reset_busy(pqbusy),.error_sticky(pqerror));
 sfo_sync_fifo #(.WIDTH(128),.DEPTH(RESPONSE_DEPTH)) training_responses(
  .clk(clk),.rst(rst),.s_valid(treturn),.s_ready(tqready),.s_data(ram_data),
  .m_valid(tqvalid),.m_ready(tpop),.m_data(tqdata),.level(),.high_water(),.reset_busy(tqbusy),.error_sticky(tqerror));
 logic [63:0] retirement_candidate;
 wire [63:0] upper=external_floor<written_words?external_floor:written_words;
 wire [63:0] primary_pin=ps!=IDLE?pfloor:64'hffffffffffffffff;
 wire [63:0] training_pin=ts!=IDLE?tfloor:64'hffffffffffffffff;
 wire [63:0] reader_pin=primary_pin<training_pin?primary_pin:training_pin;
 wire [63:0] capped_floor=upper<reader_pin?upper:reader_pin;
 wire [63:0] retirement_delta=retirement_candidate>retired_words?retirement_candidate-retired_words:64'd0;
 wire [63:0] p_end=pfirst+FRAME_WORDS,t_end=tfirst+TRAIN_WORDS;
 // Accepted ordinal and wp refer to the same boundary; written_words is one
 // command register behind and is the admission watermark for memory reads.
 wire [63:0] pgap=accepted_words-pfirst,tgap=accepted_words-tfirst;
 logic [7:0] bad;
 always_comb begin
  bad=0;
  if(pqerror||tqerror||(preturn&&!pqready)||(treturn&&!tqready))bad=8'h01;
  else if(collision)bad=8'h02;
  else if(floor_valid&&(retire_floor<external_floor||retire_floor>accepted_words))bad=8'h03;
  else if(pf&&(frame_first<retired_words||frame_first<external_floor||frame_first<retirement_candidate||frame_first+FRAME_WORDS<frame_first))bad=8'h04;
  else if(tf&&(train_first<retired_words||train_first<external_floor||train_first<retirement_candidate||train_first+TRAIN_WORDS<train_first))bad=8'h05;
  else if((ps!=IDLE&&pfirst<retired_words&&pr==0)||(ts!=IDLE&&tfirst<retired_words&&tr==0))bad=8'h06;
  else if(retirement_delta>occupancy||pout>RESPONSE_DEPTH||tout>RESPONSE_DEPTH)bad=8'h07;
  else if((ps==MAP_ADDRESS&&p_map_gap>DEPTH)||(ts==MAP_ADDRESS&&t_map_gap>DEPTH))bad=8'h08;
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   ps<=IDLE;ts<=IDLE;wp<=0;pp<=0;tp<=0;p_map_wp<=0;t_map_wp<=0;p_map_gap<=0;t_map_gap<=0;pfirst<=0;tfirst<=0;
   pframe<=0;pgen<=0;tframe<=0;tgen<=0;pi<=0;pr<=0;pc<=0;ti<=0;tr<=0;tc<=0;
   pout<=0;tout<=0;occupancy<=0;accepted_words<=0;written_words<=0;retired_words<=0;
   external_floor<=0;pfloor<=0;tfloor<=0;retirement_candidate<=0;high_water<=0;
   fault<=0;error_code<=0;ram_we<=0;ram_re<=0;ram_wa<=0;ram_ra<=0;ram_wd<=0;rv<=0;owner<=0;
  end else begin
   ram_we<=wf&&!collision;ram_re<=issue&&!collision;
   ram_wa<=wp;ram_ra<=issue_address;ram_wd<=s_data;
   rv<={rv[1:0],issue&&!collision};owner<={owner[1:0],t_issue};
   if(ram_we)written_words<=written_words+1'b1;
   if(!fault&&(bad!=0||poison))begin fault<=1;error_code<=poison?8'h09:bad;end
   if(occupancy>high_water)high_water<=occupancy;
   // Already advertised handshakes are counted on a newly detected fault edge.
   if(!stopped)begin
    if(floor_valid&&bad==0)external_floor<=retire_floor;
    if(bad==0)retirement_candidate<=capped_floor;
    if(bad==0)retired_words<=retired_words+retirement_delta;
    occupancy<=occupancy+OCW'(wf)-(bad==0?OCW'(retirement_delta):OCW'(0));
    if(wf)begin accepted_words<=accepted_words+1'b1;wp<=wp==DEPTH-1?0:wp+1'b1;end
    case({p_issue&&!collision,ppop})2'b10:pout<=pout+1'b1;2'b01:pout<=pout-1'b1;default:begin end endcase
    case({t_issue&&!collision,tpop})2'b10:tout<=tout+1'b1;2'b01:tout<=tout-1'b1;default:begin end endcase
    if(pf)begin ps<=WAIT_DATA;pfirst<=frame_first;pframe<=frame_id;pgen<=frame_generation;pi<=0;pr<=0;pc<=0;pfloor<=frame_first;end
    if(tf)begin ts<=WAIT_DATA;tfirst<=train_first;tframe<=train_frame;tgen<=train_generation;ti<=0;tr<=0;tc<=0;tfloor<=train_first;end
    if(ps==WAIT_DATA&&written_words>=p_end)begin p_map_wp<=wp;p_map_gap<=pgap;ps<=MAP_ADDRESS;end
    if(ts==WAIT_DATA&&written_words>=t_end)begin t_map_wp<=wp;t_map_gap<=tgap;ts<=MAP_ADDRESS;end
    if(ps==MAP_ADDRESS)begin pp<=p_map_wp>=p_map_gap[AW-1:0]?p_map_wp-p_map_gap[AW-1:0]:p_map_wp+AW'(DEPTH)-p_map_gap[AW-1:0];ps<=READ_DATA;end
    if(ts==MAP_ADDRESS)begin tp<=t_map_wp>=t_map_gap[AW-1:0]?t_map_wp-t_map_gap[AW-1:0]:t_map_wp+AW'(DEPTH)-t_map_gap[AW-1:0];ts<=READ_DATA;end
    if(p_issue&&!collision)begin pi<=pi+1'b1;pp<=pp==DEPTH-1?0:pp+1'b1;end
    if(t_issue&&!collision)begin ti<=ti+1'b1;tp<=tp==DEPTH-1?0:tp+1'b1;end
    if(preturn)begin pr<=pr+1'b1;if(pr>=RETAIN)pfloor<=pfloor+1'b1;end
    if(treturn)begin tr<=tr+1'b1;tfloor<=tfloor+1'b1;end
    if(ppop)begin pc<=pc+1'b1;if(f_last)ps<=IDLE;end
    if(tpop)begin tc<=tc+1'b1;if(t_last)ts<=IDLE;end
   end
  end
 end
endmodule
