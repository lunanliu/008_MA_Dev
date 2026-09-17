`timescale 1ns/1ps
// Once-per-descriptor conversion, matching the frozen MATLAB parameters() math.
// One serial 32x64 multiplier and one 112/64 divider; all rounding is ties-to-even.
module cfo_coordinate_control(
 input logic clk,rst,abort_sync,
 input logic s_valid,output logic s_ready,
 input logic [31:0] s_frame,s_generation,
 input logic s_residual,
 input logic signed [31:0] s_frequency_code,
 input logic [31:0] s_step1_q28,s_step2_q28,
 input logic signed [53:0] s_raw_origin_q28,
 output logic m_valid,input logic m_ready,
 output logic [31:0] m_frame,m_generation,
 output logic m_residual,m_ok,output logic [3:0] m_error,
 output logic [31:0] m_step,m_phase0,
 output logic signed [47:0] m_step48,output logic [47:0] m_phase48,
 output logic signed [48:0] m_origin_output_q16
);
 localparam [63:0] FS=64'd500000000, COARSE_DEN=64'd32768000000000;
 typedef enum logic [2:0] {IDLE,MULTIPLY,DIVIDE,ROUND_PRE,ROUND,OUTPUT_RESULT} state_t;
 typedef enum logic [1:0] {RATIO,STEP,PHASE} mul_kind_t;
 typedef enum logic [1:0] {ORIGIN,D_STEP,D_PHASE} div_kind_t;
 state_t state;mul_kind_t mul_kind;div_kind_t div_kind;
 logic residual,f_negative,o_negative;
 logic [31:0] f_abs;
 logic [53:0] o_abs;
 logic [63:0] ratio;
 logic [47:0] origin_mag;
 logic [31:0] mul_a;
 logic [95:0] mul_b,mul_acc;
 logic [5:0] mul_count;
 logic [111:0] div_num;
 logic [63:0] div_den;
 logic [64:0] div_rem;
 logic [47:0] div_quot;
 logic [6:0] div_count;
 wire clear=rst||abort_sync;
 assign s_ready=!clear && state==IDLE;
 assign m_valid=!clear && state==OUTPUT_RESULT;
 wire [95:0] mul_sum=mul_acc+(mul_a[0]?mul_b:96'd0);
 wire [64:0] shifted_rem={div_rem[63:0],div_num[111]};
 wire subtract_den=shifted_rem>={1'b0,div_den};
 wire [64:0] next_rem=subtract_den?shifted_rem-{1'b0,div_den}:shifted_rem;
 wire [47:0] next_quot={div_quot[46:0],subtract_den};
 // div_den < 2^62, so doubling the remainder fits in 65 bits.
 wire [64:0] twice_rem=div_rem<<1;
 wire round_up=(twice_rem>{1'b0,div_den})||((twice_rem=={1'b0,div_den})&&div_quot[0]);
 // Capture RNE only after the final divide iteration has registered its result.
 // This separates the remainder comparison / quotient increment from sign
 // restoration and conversion to the phase word in ROUND.
 logic [47:0] rounded_quot;
 wire [47:0] phase_word=(f_negative==o_negative)?48'd0-rounded_quot:rounded_quot;
 function automatic [31:0] rne_down16(input logic [47:0] magnitude);
  logic [32:0] q;
  begin
   q={1'b0,magnitude[47:16]}+{{32{1'b0}},(magnitude[15]&&((|magnitude[14:0])||magnitude[16]))};
   rne_down16=q[31:0];
  end
 endfunction
 always_ff @(posedge clk) begin
  if(clear) begin
   state<=IDLE;mul_kind<=RATIO;div_kind<=ORIGIN;
   residual<=0;f_negative<=0;o_negative<=0;f_abs<=0;o_abs<=0;ratio<=0;origin_mag<=0;
   mul_a<=0;mul_b<=0;mul_acc<=0;mul_count<=0;
   div_num<=0;div_den<=0;div_rem<=0;div_quot<=0;div_count<=0;rounded_quot<=0;
   m_frame<=0;m_generation<=0;m_residual<=0;m_ok<=0;m_error<=0;
   m_step<=0;m_phase0<=0;m_step48<=0;m_phase48<=0;m_origin_output_q16<=0;
  end else case(state)
   IDLE: if(s_valid) begin
    m_frame<=s_frame;m_generation<=s_generation;m_residual<=s_residual;
    m_ok<=0;m_error<=0;m_step<=0;m_phase0<=0;m_step48<=0;m_phase48<=0;m_origin_output_q16<=0;
    residual<=s_residual;f_negative<=s_frequency_code[31];o_negative<=s_raw_origin_q28[53];
    f_abs<=s_frequency_code[31]?(32'd0-s_frequency_code):s_frequency_code;
    o_abs<=s_raw_origin_q28[53]?(54'd0-s_raw_origin_q28):s_raw_origin_q28;
    if(s_frequency_code==32'h80000000 || s_raw_origin_q28==54'h20000000000000) begin
     m_error<=4'd1;state<=OUTPUT_RESULT;
    end else if(s_step1_q28==0 || s_step2_q28==0) begin
     m_error<=4'd2;state<=OUTPUT_RESULT;
    end else begin
     mul_a<=s_step1_q28;mul_b<={64'd0,s_step2_q28};mul_acc<=0;mul_count<=0;
     mul_kind<=RATIO;state<=MULTIPLY;
    end
   end
   MULTIPLY: begin
    mul_acc<=mul_sum;mul_a<=mul_a>>1;mul_b<=mul_b<<1;
    if(mul_count==6'd31) begin
     div_rem<=0;div_quot<=0;div_count<=0;state<=DIVIDE;
     case(mul_kind)
      RATIO: begin
       if(|mul_sum[63:62]) begin m_error<=4'd3;state<=OUTPUT_RESULT;end
       else begin
        ratio<=mul_sum[63:0];div_den<=mul_sum[63:0];
        div_num<={14'd0,o_abs,44'd0};div_kind<=ORIGIN;
       end
      end
      STEP: begin
       div_num<={16'd0,mul_sum};div_den<=residual?FS:COARSE_DEN;div_kind<=D_STEP;
      end
      PHASE: begin
       div_num<=residual?{mul_sum,16'd0}:{4'd0,mul_sum,12'd0};div_den<=FS;div_kind<=D_PHASE;
      end
      default: begin m_error<=4'd15;state<=OUTPUT_RESULT;end
     endcase
    end else mul_count<=mul_count+1'b1;
   end
   DIVIDE: begin
    div_num<=div_num<<1;div_rem<=next_rem;div_quot<=next_quot;
    if(div_count==7'd111) state<=ROUND_PRE;
    else div_count<=div_count+1'b1;
   end
   ROUND_PRE: begin
    rounded_quot<=div_quot+{{47{1'b0}},round_up};state<=ROUND;
   end
   ROUND: case(div_kind)
    ORIGIN: begin
     origin_mag<=rounded_quot;
     mul_a<=f_abs;mul_b<={32'd0,(residual?64'h0000000100000000:ratio)};
     mul_acc<=0;mul_count<=0;mul_kind<=STEP;state<=MULTIPLY;
    end
    D_STEP: begin
     if(rounded_quot[47]) begin m_error<=4'd4;state<=OUTPUT_RESULT;end
     else begin
      m_step48<=f_negative?rounded_quot:48'd0-rounded_quot;
      m_step<=f_negative?rne_down16(rounded_quot):32'd0-rne_down16(rounded_quot);
      mul_a<=f_abs;mul_b<=residual?{48'd0,origin_mag}:{42'd0,o_abs};
      mul_acc<=0;mul_count<=0;mul_kind<=PHASE;state<=MULTIPLY;
     end
    end
    D_PHASE: begin
     m_phase48<=phase_word;m_phase0<=rne_down16(phase_word);
     m_origin_output_q16<=o_negative?49'd0-{1'b0,origin_mag}:{1'b0,origin_mag};
     m_ok<=1;state<=OUTPUT_RESULT;
    end
    default: begin m_error<=4'd15;state<=OUTPUT_RESULT;end
   endcase
   OUTPUT_RESULT: if(m_ready) state<=IDLE;
   default: state<=IDLE;
  endcase
 end
endmodule