// One-window exact power cache and peak/neighbour/competitor extraction.
// Search order is signed offset -48..48, including earliest-offset tie breaking.
// Competitor is the maximum over all 2048 bins outside circular distance <=8.
module t09_peak_triplet4 #(parameter integer TIMEOUT_CYCLES=20000)(
 input logic clk,input logic rst,input logic abort,
 input logic cfg_valid,output logic cfg_ready,input logic [6:0] cfg_symbol_slot,input logic [31:0] cfg_tag,
 input logic s_valid,output logic s_ready,input logic [127:0] s_data,
 input logic [6:0] s_symbol_slot,input logic [8:0] s_beat,input logic [31:0] s_tag,input logic s_last,
 output logic m_valid,input logic m_ready,output logic [3:0] m_error,
 output logic [6:0] m_symbol_slot,output logic [31:0] m_tag,
 output logic [9:0] m_input_count,output logic [9:0] m_power_count,
 output logic [10:0] m_peak_bin,output logic signed [11:0] m_peak_offset,output logic m_search_interior,
 output logic [31:0] m_prev_power,output logic [31:0] m_peak_power,
 output logic [31:0] m_next_power,output logic [31:0] m_competing_power,output logic busy
);
 localparam [1:0] IDLE=0,FILL=1,SCAN=2,DONE=3;
 logic [1:0] state;
 logic [31:0] age;
 logic [9:0] issued_count;
 logic raw_valid;logic [8:0] raw_beat;
 logic [31:0] raw0,raw1,raw2,raw3;
 (* ram_style="block" *) logic [31:0] bank0[0:511],bank1[0:511],bank2[0:511],bank3[0:511];
 logic p_valid,p_ready,p_busy;logic [127:0] p_power;logic [41:0] p_meta;
 wire timing_active=(state==FILL || state==SCAN);
 wire timeout_now=timing_active && age>=TIMEOUT_CYCLES-1;
 wire field_bad=(s_symbol_slot!=m_symbol_slot || s_tag!=m_tag || s_beat!=m_input_count[8:0]);
 wire last_bad=(s_last!=(m_input_count==511));
 wire accepted=s_valid && s_ready;
 wire input_bad_accept=accepted && (field_bad || last_bad);
 wire p_meta_bad=p_meta!={m_tag,m_power_count[8:0],(m_power_count==511)};
 wire write_fire=!rst && !abort && !timeout_now && state==FILL && !input_bad_accept && p_valid && !p_meta_bad;
 wire [10:0] prev_bin=m_peak_bin-11'd1,next_bin=m_peak_bin+11'd1;
 logic [10:0] peak_bin_next,index_bin,scan_index,distance_bin;
 logic [31:0] peak_power_next,value,previous_next,following_next,competing_next,scan_value;
 function automatic signed [11:0] offset_of(input logic [10:0] bin);
  offset_of=bin[10] ? $signed({1'b0,bin})-12'sd2048 : $signed({1'b0,bin});
 endfunction
 assign m_peak_offset=offset_of(m_peak_bin);
 assign m_search_interior=(m_peak_offset>-12'sd48 && m_peak_offset<12'sd48);
 assign cfg_ready=!rst && !abort && state==IDLE;
 assign s_ready=!rst && !abort && !timeout_now && state==FILL && m_input_count<512;
 assign m_valid=!rst && state==DONE;
 assign busy=state!=IDLE;
 t09_power4 power_unit(.clk(clk),.rst(rst || state==IDLE || state==DONE),
  .s_valid(accepted && !field_bad && !last_bad),.s_ready(p_ready),.s_data(s_data),.s_meta({s_tag,s_beat,s_last}),
  .m_valid(p_valid),.m_ready(1'b1),.m_power(p_power),.m_meta(p_meta),.busy(p_busy));
 always_comb begin
  peak_bin_next=m_peak_bin;peak_power_next=m_peak_power;index_bin=0;value=0;
  for(integer l=0;l<4;l=l+1)begin
   index_bin={m_power_count[8:0],2'b00}+l;
   value=p_power[l*32+:32];
   if((index_bin<=48 || index_bin>=2000) &&
      (value>peak_power_next || (value==peak_power_next && offset_of(index_bin)<offset_of(peak_bin_next))))begin
    peak_power_next=value;peak_bin_next=index_bin;
   end
  end
 end
 always_comb begin
  previous_next=m_prev_power;following_next=m_next_power;competing_next=m_competing_power;
  scan_index=0;distance_bin=0;scan_value=0;
  for(integer l=0;l<4;l=l+1)begin
   scan_index={raw_beat,2'b00}+l;
   case(l)0:scan_value=raw0;1:scan_value=raw1;2:scan_value=raw2;default:scan_value=raw3;endcase
   if(scan_index==prev_bin)previous_next=scan_value;
   if(scan_index==next_bin)following_next=scan_value;
   distance_bin=scan_index-m_peak_bin;
   if(distance_bin>8 && distance_bin<2040 && scan_value>competing_next)competing_next=scan_value;
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;age<=0;m_error<=0;m_symbol_slot<=0;m_tag<=0;m_input_count<=0;m_power_count<=0;
   m_peak_bin<=2000;m_peak_power<=0;m_prev_power<=0;m_next_power<=0;m_competing_power<=0;
   issued_count<=0;raw_valid<=0;raw_beat<=0;raw0<=0;raw1<=0;raw2<=0;raw3<=0;
  end else begin
   if(timing_active)age<=age+1;
   if(state==DONE)begin if(m_ready)state<=IDLE;end
   else if(state==IDLE)begin
    if(cfg_valid && cfg_ready)begin
     m_symbol_slot<=cfg_symbol_slot;m_tag<=cfg_tag;m_input_count<=0;m_power_count<=0;
     m_peak_bin<=2000;m_peak_power<=0;m_prev_power<=0;m_next_power<=0;m_competing_power<=0;
     issued_count<=0;raw_valid<=0;age<=0;m_error<=0;
     if(cfg_symbol_slot>=74)begin m_error<=1;state<=DONE;end else state<=FILL;
    end
   end else if(abort)begin m_error<=4;state<=DONE;raw_valid<=0;end
   else if(timeout_now)begin m_error<=5;state<=DONE;raw_valid<=0;end
   else if(state==FILL)begin
    if(accepted)m_input_count<=m_input_count+1;
    if(input_bad_accept)begin m_error<=field_bad ? 4'd2 : 4'd3;state<=DONE;end
    else if(p_valid)begin
     if(p_meta_bad || m_power_count>=512 || !p_ready)begin m_error<=6;state<=DONE;end
     else begin
      bank0[m_power_count[8:0]]<=p_power[31:0];bank1[m_power_count[8:0]]<=p_power[63:32];
      bank2[m_power_count[8:0]]<=p_power[95:64];bank3[m_power_count[8:0]]<=p_power[127:96];
      m_power_count<=m_power_count+1;m_peak_bin<=peak_bin_next;m_peak_power<=peak_power_next;
      if(m_power_count==511)begin state<=SCAN;issued_count<=0;raw_valid<=0;end
     end
    end
   end else if(state==SCAN)begin
    raw_valid<=issued_count<512;
    if(issued_count<512)begin
     raw0<=bank0[issued_count[8:0]];raw1<=bank1[issued_count[8:0]];
     raw2<=bank2[issued_count[8:0]];raw3<=bank3[issued_count[8:0]];
     raw_beat<=issued_count[8:0];issued_count<=issued_count+1;
    end
    if(raw_valid)begin
     m_prev_power<=previous_next;m_next_power<=following_next;m_competing_power<=competing_next;
     if(raw_beat==511)begin state<=DONE;raw_valid<=0;end
    end
   end
  end
 end
endmodule