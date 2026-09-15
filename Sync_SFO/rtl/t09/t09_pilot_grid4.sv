// One-window pilot cache: 512 front-end beats -> 2048 sparse IFFT samples.
// Four 512x36 banks provide one synchronous read per output lane.
// No cross-window overlap; all live pilot addresses are overwritten before drain.
module t09_pilot_grid4 #(parameter integer TIMEOUT_CYCLES=20000)(
 input logic clk,input logic rst,input logic abort,
 input logic cfg_valid,output logic cfg_ready,
 input logic [6:0] cfg_symbol_slot,input logic [31:0] cfg_tag,
 input logic s_valid,output logic s_ready,
 input logic [71:0] s_data,input logic [1:0] s_mask,input logic s_error,
 input logic [6:0] s_symbol_slot,input logic [8:0] s_fft_beat,input logic [31:0] s_tag,
 output logic m_valid,input logic m_ready,output logic [127:0] m_data,
 output logic [6:0] m_symbol_slot,output logic [8:0] m_fft_beat,
 output logic [31:0] m_tag,output logic signed [4:0] m_gain,output logic m_last,
 output logic done_valid,input logic done_ready,output logic [3:0] done_error,
 output logic [6:0] done_symbol_slot,output logic [31:0] done_tag,
 output logic signed [4:0] done_gain,
 output logic [9:0] done_input_beats,output logic [9:0] done_output_beats,
 output logic [9:0] done_pilot_count,output logic busy
);
 localparam [2:0] IDLE=0,FILL=1,GAIN=2,DRAIN=3,DONE=4;
 logic [2:0] state;
 logic [6:0] active_slot;
 logic [31:0] active_tag,age;
 logic [9:0] input_count,output_count,pilot_count,issued_count;
 logic [17:0] maximum;
 logic signed [4:0] gain_probe,gain_selected;
 logic raw_valid;
 logic [8:0] raw_beat;
 logic [35:0] raw0,raw1,raw2,raw3;
 (* ram_style="block" *) logic [35:0] bank0[0:511];
 (* ram_style="block" *) logic [35:0] bank1[0:511];
 (* ram_style="block" *) logic [35:0] bank2[0:511];
 (* ram_style="block" *) logic [35:0] bank3[0:511];
 wire [10:0] q0={1'b0,s_fft_beat,1'b0}+(s_fft_beat[8] ? 11'd1024 : 11'd0);
 wire [10:0] q1=q0+11'd1;
 function automatic logic member(input logic [10:0] q);
  member=(q>=11'd1 && q<=11'd410) || q>=11'd1638;
 endfunction
 function automatic [17:0] magnitude(input logic [17:0] value);
  magnitude=value[17] ? (~value+18'd1) : value;
 endfunction
 function automatic [30:0] positive_scale(input logic [17:0] value,input logic signed [4:0] shift);
  logic [30:0] quotient;
  logic [17:0] remainder,half;
  integer n;
  begin
   if(shift>=0)positive_scale={13'd0,value} << shift;
   else begin
    n=-shift;quotient=value >> n;
    remainder=value & ((18'd1<<n)-18'd1);half=18'd1<<(n-1);
    if(remainder>half || (remainder==half && quotient[0]))quotient=quotient+31'd1;
    positive_scale=quotient;
   end
  end
 endfunction
 function automatic [15:0] normalize(input logic [17:0] value,input logic signed [4:0] shift);
  logic [30:0] rounded;
  begin
   rounded=positive_scale(magnitude(value),shift);
   normalize=value[17] ? -$signed(rounded[15:0]) : $signed(rounded[15:0]);
  end
 endfunction
 function automatic [31:0] output_lane(input logic [35:0] value,input logic [10:0] q,input logic signed [4:0] shift);
  output_lane=member(q) ? {normalize(value[35:18],shift),normalize(value[17:0],shift)} : 32'd0;
 endfunction
 wire [1:0] expected_mask={member(q1),member(q0)};
 logic [17:0] beat_maximum;
 logic [3:0] input_error;
 always_comb begin
  beat_maximum=0;
  for(integer lane=0;lane<2;lane=lane+1)begin
   if(s_mask[lane])begin
    if(magnitude(s_data[lane*36+:18])>beat_maximum)beat_maximum=magnitude(s_data[lane*36+:18]);
    if(magnitude(s_data[lane*36+18+:18])>beat_maximum)beat_maximum=magnitude(s_data[lane*36+18+:18]);
   end
  end
  input_error=0;
  if(s_error)input_error=4;
  else if(s_symbol_slot!=active_slot || s_tag!=active_tag || s_fft_beat!=input_count[8:0])input_error=2;
  else if(s_mask!=expected_mask || (!s_mask[0] && s_data[35:0]!=0) || (!s_mask[1] && s_data[71:36]!=0))input_error=3;
  else if(beat_maximum>18'd46341)input_error=5;
 end
 wire expired=(state==FILL || state==GAIN || state==DRAIN) && age>=TIMEOUT_CYCLES-1;
 wire advance=!m_valid || m_ready;
 wire write_enable=s_valid && s_ready && input_error==0 && !expired;
 wire read_issue=state==DRAIN && advance && issued_count<10'd512 && !abort && !rst && !expired;
 assign cfg_ready=!rst && !abort && state==IDLE;
 assign s_ready=!rst && !abort && !expired && state==FILL;
 assign done_valid=state==DONE;
 assign busy=state!=IDLE;
 assign m_symbol_slot=active_slot;assign m_tag=active_tag;assign m_gain=gain_selected;
 assign m_last=m_valid && m_fft_beat==9'd511;
 assign done_symbol_slot=active_slot;assign done_tag=active_tag;assign done_gain=gain_selected;
 assign done_input_beats=input_count;assign done_output_beats=output_count;assign done_pilot_count=pilot_count;
 // Writes use adjacent banks 0/1 or 2/3. There is no reset loop over RAM.
 always_ff @(posedge clk) begin
  if(write_enable)begin
   if(!q0[1])begin
    if(s_mask[0])bank0[q0[10:2]]<=s_data[35:0];
    if(s_mask[1])bank1[q1[10:2]]<=s_data[71:36];
   end else begin
    if(s_mask[0])bank2[q0[10:2]]<=s_data[35:0];
    if(s_mask[1])bank3[q1[10:2]]<=s_data[71:36];
   end
  end
  if(read_issue)begin
   raw0<=bank0[issued_count[8:0]];raw1<=bank1[issued_count[8:0]];
   raw2<=bank2[issued_count[8:0]];raw3<=bank3[issued_count[8:0]];
  end
 end
 always_ff @(posedge clk) begin
  if(rst)begin
   state<=IDLE;active_slot<=0;active_tag<=0;age<=0;
   input_count<=0;output_count<=0;pilot_count<=0;issued_count<=0;maximum<=0;
   gain_probe<=12;gain_selected<=0;raw_valid<=0;raw_beat<=0;
   m_valid<=0;m_data<=0;m_fft_beat<=0;done_error<=0;
  end else if(state==DONE)begin
   // Published completion remains stable even if abort arrives.
   if(done_ready)state<=IDLE;
  end else if(abort && state!=IDLE)begin
   state<=DONE;done_error<=6;m_valid<=0;raw_valid<=0;
  end else if(expired)begin
   state<=DONE;done_error<=7;m_valid<=0;raw_valid<=0;
  end else begin
   if(state!=IDLE)age<=age+1;
   case(state)
    IDLE:begin
     m_valid<=0;raw_valid<=0;
     if(cfg_valid && cfg_ready)begin
      active_slot<=cfg_symbol_slot;active_tag<=cfg_tag;age<=0;
      input_count<=0;output_count<=0;pilot_count<=0;issued_count<=0;maximum<=0;
      gain_probe<=12;gain_selected<=0;done_error<=0;
      if(cfg_symbol_slot>=74)begin state<=DONE;done_error<=1;end
      else state<=FILL;
     end
    end
    FILL:if(s_valid && s_ready)begin
     input_count<=input_count+1;
     if(input_error!=0)begin state<=DONE;done_error<=input_error;end
     else begin
      pilot_count<=pilot_count+{9'd0,s_mask[0]}+{9'd0,s_mask[1]};
      if(beat_maximum>maximum)maximum<=beat_maximum;
      if(input_count==511)state<=GAIN;
     end
    end
    GAIN:begin
     if(positive_scale(maximum,gain_probe)<=31'd16383)begin
      gain_selected<=gain_probe;state<=DRAIN;
     end else if(gain_probe==-5'sd2)begin state<=DONE;done_error<=5;end
     else gain_probe<=gain_probe-5'sd1;
    end
    DRAIN:begin
     if(advance)begin
      m_valid<=raw_valid;
      if(raw_valid)begin
       m_data[31:0]<=output_lane(raw0,{raw_beat,2'b00},gain_selected);
       m_data[63:32]<=output_lane(raw1,{raw_beat,2'b01},gain_selected);
       m_data[95:64]<=output_lane(raw2,{raw_beat,2'b10},gain_selected);
       m_data[127:96]<=output_lane(raw3,{raw_beat,2'b11},gain_selected);
       m_fft_beat<=raw_beat;
      end
      raw_valid<=read_issue;
      if(read_issue)begin raw_beat<=issued_count[8:0];issued_count<=issued_count+1;end
     end
     if(m_valid && m_ready)begin
      output_count<=output_count+1;
      if(output_count==511)begin state<=DONE;m_valid<=0;raw_valid<=0;end
     end
    end
    default:begin state<=DONE;done_error<=8;m_valid<=0;raw_valid<=0;end
   endcase
  end
 end
endmodule