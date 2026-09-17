`timescale 1ns/1ps
// Four accepted samples per cycle. Phase advances only on input handshakes.
// Configuration contains already converted modulo-2^32 phase words; the
// descriptor-to-phase controller is a separate subsequent verification gate.
module cfo_rotate4 #(
 parameter ROM_FILE="cfo_rot_lut.mem"
)(
 input logic clk,rst,abort_sync,
 input logic cfg_valid,output logic cfg_ready,
 input logic [31:0] cfg_frame,cfg_generation,cfg_phase0,cfg_step,cfg_sample_count,
 input logic s_valid,output logic s_ready,
 input logic [224:0] s_record,
 output logic m_valid,input logic m_ready,
 output logic [224:0] m_record,output logic [7:0] m_saturation,
 output logic fault,output logic [3:0] first_error
);
 (* rom_style="block" *) logic [31:0] lut_a[0:1023];
 (* rom_style="block" *) logic [31:0] lut_b[0:1023];
 initial begin $readmemh(ROM_FILE,lut_a);$readmemh(ROM_FILE,lut_b);end
 logic active;logic [31:0] frame,generation,phase,step,step3,beat_next,beat_count;
 logic [4:0] valid_pipe;logic [96:0] tag_pipe[0:4];
 logic [127:0] data0,data1;logic [9:0] address0[0:3];logic [31:0] coef1[0:3];
 logic signed [31:0] ic2[0:3],qs2[0:3],is2[0:3],qc2[0:3];
 logic signed [32:0] sum_i3[0:3],sum_q3[0:3];logic [127:0] output4;logic [7:0] saturation4;
 wire clear=rst||abort_sync;
 wire advance=!valid_pipe[4]||m_ready;
 assign cfg_ready=!clear&&!fault&&!active&&valid_pipe==0;
 assign s_ready=!clear&&!fault&&active&&advance;
 assign m_valid=!clear&&!fault&&valid_pipe[4];
 assign m_record={tag_pipe[4],output4};assign m_saturation=saturation4;
 wire accept=s_valid&&s_ready;
 wire bad_record=s_record[224:193]!=frame||s_record[192:161]!=generation||s_record[160:129]!=beat_next||s_record[128]!=(beat_next==beat_count-1);
 function automatic [9:0] phase_address(input logic [31:0] p);
  logic [10:0] rounded;
  begin rounded={1'b0,p[31:22]}+(p[21]&&((|p[20:0])||p[22]));phase_address=rounded[9:0];end
 endfunction
 function automatic [16:0] rne_sat(input logic signed [32:0] value);
  logic signed [32:0] q;
  begin
   q=value>>>14;
   if(value[13]&&((|value[12:0])||q[0]))q=q+33'sd1;
   if(q>33'sd32767)rne_sat={1'b1,16'h7fff};
   else if(q< -33'sd32768)rne_sat={1'b1,16'h8000};
   else rne_sat={1'b0,q[15:0]};
  end
 endfunction
 integer i;
 always_ff @(posedge clk)begin
  if(clear)begin
   active<=0;frame<=0;generation<=0;phase<=0;step<=0;step3<=0;beat_next<=0;beat_count<=0;valid_pipe<=0;fault<=0;first_error<=0;
   data0<=0;data1<=0;output4<=0;saturation4<=0;
   for(i=0;i<5;i=i+1)tag_pipe[i]<=0;
   for(i=0;i<4;i=i+1)begin address0[i]<=0;coef1[i]<=0;ic2[i]<=0;qs2[i]<=0;is2[i]<=0;qc2[i]<=0;sum_i3[i]<=0;sum_q3[i]<=0;end
  end else if(!fault)begin
   if(cfg_valid&&cfg_ready)begin
    if(cfg_sample_count==0||cfg_sample_count[1:0]!=0||cfg_sample_count>1336320)begin fault<=1;first_error<=1;end
    else begin active<=1;frame<=cfg_frame;generation<=cfg_generation;phase<=cfg_phase0;step<=cfg_step;step3<=cfg_step+(cfg_step<<1);beat_next<=0;beat_count<=cfg_sample_count>>2;end
   end
   if(advance)begin
    valid_pipe<={valid_pipe[3:0],accept};
    for(i=1;i<5;i=i+1)tag_pipe[i]<=tag_pipe[i-1];
    if(accept)begin
     if(bad_record)begin fault<=1;first_error<=2;active<=0;valid_pipe<=0;end
     else begin
      tag_pipe[0]<=s_record[224:128];data0<=s_record[127:0];
      // Configuration precomputes 3*step modulo 2^32 so lane 3 does not
      // cascade two 32-bit adders before ROM-address rounding each sample.
      for(i=0;i<4;i=i+1)address0[i]<=phase_address(phase+((i==3)?step3:32'(i)*step));
      phase<=phase+(step<<2);beat_next<=beat_next+1;if(s_record[128])active<=0;
     end
    end
    data1<=data0;
    coef1[0]<=lut_a[address0[0]];coef1[1]<=lut_a[address0[1]];
    coef1[2]<=lut_b[address0[2]];coef1[3]<=lut_b[address0[3]];
    for(i=0;i<4;i=i+1)begin
     ic2[i]<=$signed(data1[32*i+:16])*$signed(coef1[i][15:0]);
     qs2[i]<=$signed(data1[32*i+16+:16])*$signed(coef1[i][31:16]);
     is2[i]<=$signed(data1[32*i+:16])*$signed(coef1[i][31:16]);
     qc2[i]<=$signed(data1[32*i+16+:16])*$signed(coef1[i][15:0]);
     sum_i3[i]<=$signed({ic2[i][31],ic2[i]})-$signed({qs2[i][31],qs2[i]});
     sum_q3[i]<=$signed({is2[i][31],is2[i]})+$signed({qc2[i][31],qc2[i]});
     {saturation4[2*i],output4[32*i+:16]}<=rne_sat(sum_i3[i]);
     {saturation4[2*i+1],output4[32*i+16+:16]}<=rne_sat(sum_q3[i]);
    end
   end
  end
 end
 // synthesis translate_off
 initial if($bits(s_record)!=225)$fatal(1,"CFO record geometry");
 // synthesis translate_on
endmodule