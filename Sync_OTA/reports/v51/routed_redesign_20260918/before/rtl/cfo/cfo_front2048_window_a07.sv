`timescale 1ns/1ps
// A07: index decode -> registered address -> ROM read; data/tags follow valid.
// One already-coarse-corrected 2048-point window -> one S38 pilot sum.
module cfo_front2048_window(
 input logic clk,rst,abort_sync,
 input logic s_valid,output logic s_ready,
 input logic [31:0] s_frame,s_generation,input logic [6:0] s_window,
 input logic [10:0] s_index,input logic s_last,input logic signed [25:0] s_i,s_q,
 output logic m_valid,input logic m_ready,
 output logic [31:0] m_frame,m_generation,output logic [6:0] m_window,
 output logic signed [37:0] m_z_i,m_z_q,output logic [9:0] m_pilot_count,
 output logic [15:0] m_fft_saturations,output logic [3:0] m_error,
 output logic pilot_audit_valid,output logic [9:0] pilot_audit_index,
 output logic [143:0] pilot_audit_value,
 output wire fft_butterfly_audit_valid,output wire [3:0] fft_butterfly_audit_stage,
 output wire [9:0] fft_butterfly_audit_index
);
 localparam [1:0] FEED=0,WAIT_SUM=1,HOLD=2;
 logic [1:0] state;
 logic fft_s_valid,fft_s_ready,fft_m_valid,fft_m_ready;
 wire [31:0] f_frame,f_generation;wire [6:0] f_window;wire [10:0] f_index;wire f_last;
 wire signed [25:0] f_i,f_q;wire [15:0] f_saturations;wire [3:0] f_error;
 cfo_fft2048_core fft_core(
  .clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(fft_s_valid),.s_ready(fft_s_ready),
  .s_frame(s_frame),.s_generation(s_generation),.s_window(s_window),.s_index(s_index),.s_last(s_last),.s_i(s_i),.s_q(s_q),
  .m_valid(fft_m_valid),.m_ready(fft_m_ready),.m_frame(f_frame),.m_generation(f_generation),.m_window(f_window),
  .m_index(f_index),.m_last(f_last),.m_i(f_i),.m_q(f_q),.m_saturations(f_saturations),.m_error(f_error),
  .butterfly_audit_valid(fft_butterfly_audit_valid),.butterfly_audit_stage(fft_butterfly_audit_stage),.butterfly_audit_index(fft_butterfly_audit_index),.butterfly_audit_value()
 );
 (* rom_style="block" *) logic [2:0] coefficient_index_rom[0:60679];
 (* rom_style="distributed" *) logic [35:0] coefficient_table[0:7];
 initial begin $readmemh("front2048_coefficient_index.mem",coefficient_index_rom);$readmemh("front2048_coefficient_table.mem",coefficient_table);end
 logic first_pending,fft_done,sum_done;
 logic [16:0] coefficient_base,index_base;
 (* use_dsp="no" *) logic [16:0] coefficient_address;
 logic [1:0] address_valid;
 logic [9:0] index_stage,address_index;
 logic [51:0] index_iq,address_iq;
 logic [9:0] selected_index,pilot_count;
 logic selected;
 logic [2:0] coefficient_index0;
 logic [5:0] v;
 logic [9:0] index_pipe[0:5];
 logic [51:0] f_pipe[0:5];
 logic [35:0] c_pipe[1:5];
 logic signed [25:0] ar2,ai2;
 logic signed [17:0] cr2,ci2;
 logic signed [43:0] rr3,ii3,ri3,ir3;
 logic signed [44:0] pr4,pi4;
 logic signed [27:0] h_i5,h_q5;
 logic signed [37:0] sum_i,sum_q,next_sum_i,next_sum_q;
 integer data_j,control_j;
 function automatic signed [27:0] rne17(input logic signed [44:0] x);
  logic signed [44:0] q;begin
   q=x>>>17;if(x[16] && ((|x[15:0]) || q[0]))q=q+45'sd1;rne17=q[27:0];
  end
 endfunction
 always_comb begin
  fft_s_valid=s_valid && state==FEED && !rst && !abort_sync;
  s_ready=fft_s_ready && state==FEED && !rst && !abort_sync;
  fft_m_ready=state!=HOLD && !rst && !abort_sync;
  m_valid=state==HOLD && !rst && !abort_sync;
  selected=fft_m_valid && fft_m_ready && f_error==0 && !f_index[0] && ((f_index>=11'd2 && f_index<=11'd820) || (f_index>=11'd1228 && f_index<=11'd2046));
  selected_index=(f_index<=11'd820) ? f_index[10:1]-10'd1 : f_index[10:1]-10'd204;
  next_sum_i=sum_i+$signed({{10{h_i5[27]}},h_i5});next_sum_q=sum_q+$signed({{10{h_q5[27]}},h_q5});
 end
 // Every legal S26 * S18 complex product rounded by /2^17 fits S28.
 // Thus MATLAB's S28 saturation is the identity for this complete input range.
 always_ff @(posedge clk)begin
  if(selected)begin
   index_stage<=selected_index;index_base<=coefficient_base;index_iq<={f_i,f_q};
  end
  if(address_valid[0])begin
   coefficient_address<=index_base+{7'd0,index_stage};
   address_index<=index_stage;address_iq<=index_iq;
  end
  if(address_valid[1])begin
   coefficient_index0<=coefficient_index_rom[coefficient_address];f_pipe[0]<=address_iq;
  end
  for(data_j=1;data_j<6;data_j=data_j+1)if(v[data_j-1])f_pipe[data_j]<=f_pipe[data_j-1];
  if(v[0])c_pipe[1]<=coefficient_table[coefficient_index0];
  for(data_j=2;data_j<6;data_j=data_j+1)if(v[data_j-1])c_pipe[data_j]<=c_pipe[data_j-1];
  if(v[1])begin {ar2,ai2}<=f_pipe[1];{cr2,ci2}<=c_pipe[1];end
  if(v[2])begin rr3<=ar2*cr2;ii3<=ai2*ci2;ri3<=ar2*ci2;ir3<=ai2*cr2;end
  if(v[3])begin pr4<=$signed({rr3[43],rr3})-$signed({ii3[43],ii3});pi4<=$signed({ri3[43],ri3})+$signed({ir3[43],ir3});end
  if(v[4])begin h_i5<=rne17(pr4);h_q5<=rne17(pi4);end
 end
 always_ff @(posedge clk)begin
  pilot_audit_valid<=0;
  if(rst || abort_sync)begin
   state<=FEED;first_pending<=1;coefficient_base<=0;address_valid<=0;v<=0;fft_done<=0;sum_done<=0;sum_i<=0;sum_q<=0;pilot_count<=0;
   m_frame<=0;m_generation<=0;m_window<=0;m_z_i<=0;m_z_q<=0;m_pilot_count<=0;m_fft_saturations<=0;m_error<=0;
   pilot_audit_index<=0;pilot_audit_value<=0;
   for(control_j=0;control_j<6;control_j=control_j+1)index_pipe[control_j]<=0;
  end else begin
   address_valid<={address_valid[0],selected};
   v<={v[4:0],address_valid[1]};
   if(address_valid[1])index_pipe[0]<=address_index;
   for(control_j=1;control_j<6;control_j=control_j+1)if(v[control_j-1])index_pipe[control_j]<=index_pipe[control_j-1];
   if(s_valid && s_ready)begin
    if(first_pending)begin coefficient_base<=s_window*17'd820;first_pending<=0;end
    if(s_last)state<=WAIT_SUM;
   end
   if(fft_m_valid && fft_m_ready)begin
    m_frame<=f_frame;m_generation<=f_generation;m_window<=f_window;m_fft_saturations<=f_saturations;
    if(f_last)fft_done<=1;
   end
   if(v[5])begin
    sum_i<=next_sum_i;sum_q<=next_sum_q;pilot_count<=pilot_count+10'd1;
    pilot_audit_valid<=1;pilot_audit_index<=index_pipe[5];pilot_audit_value<={f_pipe[5],c_pipe[5],h_i5,h_q5};
    if(index_pipe[5]==10'd819)begin m_z_i<=next_sum_i;m_z_q<=next_sum_q;m_pilot_count<=pilot_count+10'd1;sum_done<=1;end
   end
   if(sum_done && fft_done && state==WAIT_SUM)begin state<=HOLD;m_error<=0;end
   if(fft_m_valid && fft_m_ready && f_error!=0)begin
    state<=HOLD;pilot_audit_valid<=0;m_error<=f_error;m_z_i<=0;m_z_q<=0;m_pilot_count<=0;m_fft_saturations<=0;address_valid<=0;v<=0;
   end
   if(state==HOLD && m_ready)begin
    state<=FEED;first_pending<=1;address_valid<=0;v<=0;fft_done<=0;sum_done<=0;sum_i<=0;sum_q<=0;pilot_count<=0;
   end
  end
 end
endmodule