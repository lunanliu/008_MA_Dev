// Two complete 2048-complex packets, 125 MHz only. One fill and one drain may overlap.
// Reserve a FREE slot before starting the front FFT; publish only after all 512 beats
// and the front stage's numerical/protocol completion have been checked.
module t09_grid_packet_queue2(
 input logic clk,input logic rst,
 input logic alloc_valid,output logic alloc_ready,input logic [70:0] alloc_identity,
 input logic s_valid,output logic s_ready,input logic [208:0] s_word,
 input logic commit_valid,output logic commit_ready,
 output logic packet_valid,output logic [70:0] packet_identity,
 output logic m_valid,input logic m_ready,output logic [208:0] m_word,
 output logic [1:0] committed_count,output logic fill_active,
 output logic [1:0] reserved_count,output logic error
);
 (* ram_style="block" *) logic [127:0] data_mem[0:1023];
 logic [70:0] identity[0:1];
 logic wr_slot,rd_slot;
 logic [9:0] fill_count,issued;
 logic raw_valid,out_valid;
 logic [127:0] raw_data,out_data;
 logic [8:0] raw_beat,out_beat;
 wire allocate=alloc_valid && alloc_ready;
 wire write_fire=s_valid && s_ready;
 wire commit=commit_valid && commit_ready;
 wire pop=m_valid && m_ready && out_beat==511;
 wire advance=!out_valid || m_ready;
 wire read_issue=packet_valid && issued<512 && advance;
 wire input_bad=s_word[208:138]!=identity[wr_slot] || s_word[137:129]!=fill_count[8:0] || s_word[128]!=(fill_count==511);
 assign reserved_count=committed_count+{1'b0,fill_active};
 assign alloc_ready=!rst && !error && !fill_active && committed_count<2;
 assign s_ready=!rst && !error && fill_active && fill_count<512;
 assign commit_ready=!rst && !error && fill_active && fill_count==512;
 assign packet_valid=!rst && !error && committed_count!=0;
 assign packet_identity=identity[rd_slot];
 assign m_valid=packet_valid && out_valid;
 assign m_word={identity[rd_slot],out_beat,(out_beat==511),out_data};
 always_ff @(posedge clk)begin
  if(write_fire && !input_bad)data_mem[{wr_slot,fill_count[8:0]}]<=s_word[127:0];
  if(read_issue)raw_data<=data_mem[{rd_slot,issued[8:0]}];
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   wr_slot<=0;rd_slot<=0;fill_active<=0;fill_count<=0;committed_count<=0;
   issued<=0;raw_valid<=0;out_valid<=0;raw_beat<=0;out_beat<=0;out_data<=0;error<=0;
   identity[0]<=0;identity[1]<=0;
  end else if(!error)begin
   if(allocate)begin fill_active<=1;fill_count<=0;identity[wr_slot]<=alloc_identity;end
   if(write_fire)begin
    if(input_bad)error<=1;
    else fill_count<=fill_count+1;
   end
   if(commit)begin fill_active<=0;fill_count<=0;wr_slot<=~wr_slot;end
   case({commit,pop})
    2'b10:committed_count<=committed_count+1;
    2'b01:committed_count<=committed_count-1;
    default:begin end
   endcase
   if(advance)begin
    out_valid<=raw_valid;
    if(raw_valid)begin out_data<=raw_data;out_beat<=raw_beat;end
    raw_valid<=read_issue;
    if(read_issue)begin raw_beat<=issued[8:0];issued<=issued+1;end
   end
   if(pop)begin rd_slot<=~rd_slot;issued<=0;raw_valid<=0;out_valid<=0;end
   if(reserved_count>2 || (fill_active && committed_count>=2))error<=1;
  end
 end
endmodule
