`timescale 1ns/1ps
// Shared signed numerator / positive denominator; exact nearest-even rounding.
module cfo_divide_rne64(
 input logic clk,rst,abort_sync,input logic s_valid,output logic s_ready,
 input logic signed [63:0] s_numerator,input logic [31:0] s_denominator,
 output logic m_valid,input logic m_ready,output logic signed [63:0] m_quotient,output logic m_error
);
 typedef enum logic [1:0] {IDLE,DIVIDE,ROUND,RESULT} state_t;
 state_t state;logic negative;logic [63:0] numerator,quotient;
 logic [31:0] denominator;logic [32:0] remainder;logic [5:0] count;
 wire clear=rst||abort_sync;
 assign s_ready=!clear && state==IDLE;assign m_valid=!clear && state==RESULT;
 wire [32:0] shifted={remainder[31:0],numerator[63]};
 wire ge=shifted>={1'b0,denominator};
 wire [32:0] next_rem=ge?shifted-{1'b0,denominator}:shifted;
 wire [32:0] doubled=remainder<<1;
 wire inc=(doubled>{1'b0,denominator})||((doubled=={1'b0,denominator})&&quotient[0]);
 wire [63:0] rounded=quotient+{{63{1'b0}},inc};
 always_ff @(posedge clk)begin
  if(clear)begin state<=IDLE;negative<=0;numerator<=0;quotient<=0;denominator<=0;remainder<=0;count<=0;m_quotient<=0;m_error<=0;end
  else case(state)
   IDLE:if(s_valid)begin
    negative<=s_numerator[63];numerator<=s_numerator[63]?64'd0-s_numerator:s_numerator;
    denominator<=s_denominator;remainder<=0;quotient<=0;count<=0;m_error<=0;m_quotient<=0;
    if(s_denominator==0)begin m_error<=1;state<=RESULT;end else state<=DIVIDE;
   end
   DIVIDE:begin
    numerator<=numerator<<1;quotient<={quotient[62:0],ge};remainder<=next_rem;
    if(count==63)state<=ROUND;else count<=count+1'b1;
   end
   ROUND:begin m_quotient<=negative?64'd0-rounded:rounded;state<=RESULT;end
   RESULT:if(m_ready)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule