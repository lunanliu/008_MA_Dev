// Four signed I16/Q16 pairs to four exact unsigned 32-bit powers.
// Two globally enabled stages; all metadata and data hold under backpressure.
module t09_power4(
 input logic clk,input logic rst,
 input logic s_valid,output logic s_ready,input logic [127:0] s_data,input logic [41:0] s_meta,
 output logic m_valid,input logic m_ready,output logic [127:0] m_power,output logic [41:0] m_meta,
 output logic busy
);
 logic stage_valid;
 logic [41:0] stage_meta;
 (* use_dsp="yes" *) logic signed [31:0] sq_i[0:3],sq_q[0:3];
 wire advance=!m_valid || m_ready;
 assign s_ready=!rst && advance;
 assign busy=stage_valid || m_valid;
 always_ff @(posedge clk)begin
  if(rst)begin
   stage_valid<=0;stage_meta<=0;m_valid<=0;m_power<=0;m_meta<=0;
   for(integer l=0;l<4;l=l+1)begin sq_i[l]<=0;sq_q[l]<=0;end
  end else if(advance)begin
   stage_valid<=s_valid;stage_meta<=s_meta;
   for(integer l=0;l<4;l=l+1)begin
    sq_i[l]<=$signed(s_data[l*32+:16])*$signed(s_data[l*32+:16]);
    sq_q[l]<=$signed(s_data[l*32+16+:16])*$signed(s_data[l*32+16+:16]);
    m_power[l*32+:32]<={1'b0,sq_i[l]}+{1'b0,sq_q[l]};
   end
   m_valid<=stage_valid;m_meta<=stage_meta;
  end
 end
endmodule