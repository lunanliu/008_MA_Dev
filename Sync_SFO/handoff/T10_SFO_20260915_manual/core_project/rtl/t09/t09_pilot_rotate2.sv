// Two complex pilot rotations per accepted beat. S16 input -> S18 quotient.
// phase = angle/(pi/4), using S18/F16 coefficients {0,+/-65536,+/-46341}.
// Three globally enabled pipeline stages; output backpressure freezes every stage.
module t09_pilot_rotate2 (
 input logic clk, input logic rst,
 input logic s_valid, output logic s_ready,
 input logic [63:0] s_data, input logic [5:0] s_phase,
 input logic [1:0] s_mask, input logic [31:0] s_tag,
 output logic m_valid, input logic m_ready,
 output logic [71:0] m_data, output logic [1:0] m_mask,
 output logic [31:0] m_tag, output logic busy
);
 logic v1,v2;
 logic [31:0] tag1,tag2;
 logic [1:0] mask1,mask2,odd1;
 logic signed [17:0] pre_i[0:1],pre_q[0:1];
 logic signed [34:0] prod_i[0:1],prod_q[0:1];
 wire advance = !m_valid || m_ready;
 assign s_ready = !rst && advance;
 assign busy = v1 || v2 || m_valid;
 function automatic signed [17:0] pre_rotate(
  input logic signed [15:0] a,input logic signed [15:0] b,
  input logic [2:0] phase,input logic imaginary);
  logic signed [17:0] x,y;
  begin
   x={{2{a[15]}},a};y={{2{b[15]}},b};
   case(phase)
    3'd0: pre_rotate=imaginary ? y : x;
    3'd1: pre_rotate=imaginary ? x+y : x-y;
    3'd2: pre_rotate=imaginary ? x : -y;
    3'd3: pre_rotate=imaginary ? x-y : -(x+y);
    3'd4: pre_rotate=imaginary ? -y : -x;
    3'd5: pre_rotate=imaginary ? -(x+y) : -(x-y);
    3'd6: pre_rotate=imaginary ? -x : y;
    3'd7: pre_rotate=imaginary ? -(x-y) : x+y;
    default: pre_rotate='0;
   endcase
  end
 endfunction
 function automatic signed [34:0] scale_pre(
  input logic signed [17:0] value,input logic odd_phase);
  logic signed [34:0] extended;
  begin
   extended={{17{value[17]}},value};
   if(odd_phase) scale_pre=value * 17'sd46341;
   else scale_pre=extended <<< 16;
  end
 endfunction
 function automatic signed [17:0] rne_f16(input logic signed [34:0] value);
  logic [34:0] magnitude;logic [18:0] quotient;
  begin
   magnitude=value[34] ? (~value+35'd1) : value;
   quotient=magnitude[34:16];
   if(magnitude[15:0]>16'h8000 || (magnitude[15:0]==16'h8000 && quotient[0]))
    quotient=quotient+19'd1;
   // Range proof: odd phase magnitude <=46341; even phase <=32768.
   rne_f16=value[34] ? -$signed(quotient[17:0]) : $signed(quotient[17:0]);
  end
 endfunction
 always_ff @(posedge clk) begin
  if(rst) begin
   v1<=0;v2<=0;m_valid<=0;
   mask1<=0;mask2<=0;m_mask<=0;
   tag1<=0;tag2<=0;m_tag<=0;m_data<=0;odd1<=0;
   for(int lane=0;lane<2;lane++) begin
    pre_i[lane]<=0;pre_q[lane]<=0;prod_i[lane]<=0;prod_q[lane]<=0;
   end
  end else if(advance) begin
   v1<=s_valid;v2<=v1;m_valid<=v2;
   tag1<=s_tag;tag2<=tag1;m_tag<=tag2;
   mask1<=s_mask;mask2<=mask1;m_mask<=mask2;
   for(int lane=0;lane<2;lane++) begin
    odd1[lane]<=s_phase[lane*3];
    pre_i[lane]<=s_mask[lane] ? pre_rotate($signed(s_data[lane*32+:16]),$signed(s_data[lane*32+16+:16]),s_phase[lane*3+:3],1'b0) : 18'sd0;
    pre_q[lane]<=s_mask[lane] ? pre_rotate($signed(s_data[lane*32+:16]),$signed(s_data[lane*32+16+:16]),s_phase[lane*3+:3],1'b1) : 18'sd0;
    prod_i[lane]<=scale_pre(pre_i[lane],odd1[lane]);
    prod_q[lane]<=scale_pre(pre_q[lane],odd1[lane]);
    m_data[lane*36+:18]<=rne_f16(prod_i[lane]);
    m_data[lane*36+18+:18]<=rne_f16(prod_q[lane]);
   end
  end
 end
endmodule