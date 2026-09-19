`timescale 1ns/1ps
// Complete 74-point CORDIC + unwrap + OLS phase path of the frozen estimator.
// Spectrum quality, FFT fallback and final CFO validity are later composition.
module cfo_phase74_core #(parameter ATAN_FILE="phase74_atan_q31.mem")(
 input logic clk,rst,abort_sync,
 input logic s_valid,output logic s_ready,
 input logic [31:0] s_frame,s_generation,input logic [6:0] s_index,input logic s_last,
 input logic signed [37:0] s_i,s_q,
 output logic m_valid,input logic m_ready,
 output logic [31:0] m_frame,m_generation,output logic m_nonzero,m_phase_linear,
 output logic [3:0] m_error,output logic signed [31:0] m_frequency_q16,
 output logic signed [55:0] m_weighted_sum,output logic [63:0] m_max_centered,
 output logic [11:0] m_cordic_saturations,
 // Unbackpressured observation ports for exact internal-node verification.
 output logic phase_audit_valid,output logic [6:0] phase_audit_index,
 output logic signed [31:0] phase_audit_angle,output logic signed [39:0] phase_audit_unwrapped,
 output logic pred_audit_valid,output logic [6:0] pred_audit_index,
 output logic signed [39:0] pred_audit_value,output logic signed [55:0] pred_audit_residual,
 output logic center_audit_valid,output logic [6:0] center_audit_index,output logic signed [63:0] center_audit_value
);
 typedef enum logic [4:0] {ACCEPT_Z,CORDIC_SHIFT,CORDIC,STORE_OFFSET,STORE_PHASE,STORE_DOT,STORE_ACCUM,FREQ_START,FREQ_MULT,FREQ_REQ,FREQ_WAIT,PRED_LOAD,PRED_START,PRED_WAIT,PRED_STORE,CENTER_LOAD,CENTER_PAIR,CENTER_SUM,CENTER_ABS,CENTER_EVAL,RESULT} state_t;
 state_t state;
 (* rom_style="distributed" *) logic signed [31:0] atan_rom[0:23];
 initial $readmemh(ATAN_FILE,atan_rom);
 (* ram_style="distributed" *) logic signed [39:0] unwrapped_ram[0:73];
 (* ram_style="distributed" *) logic signed [55:0] residual_ram[0:73];
 logic [6:0] observation,work_index;logic [4:0] iteration;
 logic signed [39:0] x,y,unwrap_offset;
 logic signed [31:0] angle,previous_angle,phase_code;
 logic signed [55:0] dot_sum,residual_sum;
 logic signed [39:0] unwrapped_read,pred_product;
 logic signed [55:0] residual_read;
 logic [63:0] max_centered;
 logic [11:0] saturations;
 logic any_nonzero;
 wire clear=rst||abort_sync;
 assign s_ready=!clear && state==ACCEPT_Z;
 assign m_valid=!clear && state==RESULT;
 wire signed [39:0] sx={{2{s_i[37]}},s_i},sy={{2{s_q[37]}},s_q};
 logic signed [39:0] shifted_x,shifted_y,held_unwrapped,held_prediction;
 logic signed [48:0] held_dot;
 logic signed [55:0] held_residual;
 logic signed [63:0] center_left,center_right,center_value;
 logic [63:0] center_magnitude;
 logic signed [71:0] frequency_acc,frequency_shift;
 logic [15:0] frequency_factor;logic [4:0] frequency_remaining;
 logic signed [63:0] frequency_numerator;
 wire signed [71:0] frequency_sum=frequency_acc+(frequency_factor[0]?frequency_shift:72'sd0);
 wire signed [40:0] x_wide=y[39]?($signed({x[39],x})-$signed({shifted_y[39],shifted_y})):($signed({x[39],x})+$signed({shifted_y[39],shifted_y}));
 wire signed [40:0] y_wide=y[39]?($signed({y[39],y})+$signed({shifted_x[39],shifted_x})):($signed({y[39],y})-$signed({shifted_x[39],shifted_x}));
 wire x_clip=x_wide>41'sd549755813887 || x_wide< -41'sd549755813888;
 wire y_clip=y_wide>41'sd549755813887 || y_wide< -41'sd549755813888;
 wire signed [39:0] x_next=x_wide>41'sd549755813887 ? 40'sh7fffffffff:(x_wide< -41'sd549755813888 ? 40'sh8000000000:x_wide[39:0]);
 wire signed [39:0] y_next=y_wide>41'sd549755813887 ? 40'sh7fffffffff:(y_wide< -41'sd549755813888 ? 40'sh8000000000:y_wide[39:0]);
 wire signed [31:0] angle_next=y[39]?angle-atan_rom[iteration]:angle+atan_rom[iteration];
 wire signed [32:0] difference=$signed({angle[31],angle})-$signed({previous_angle[31],previous_angle});
 wire signed [39:0] offset_next=observation==0 ? 40'sd0:(difference>33'sd1073741824 ? unwrap_offset-40'sd2147483648:(difference< -33'sd1073741824 ? unwrap_offset+40'sd2147483648:unwrap_offset));
 wire signed [39:0] unwrapped_next=$signed({{8{angle[31]}},angle})+unwrap_offset;
 wire signed [8:0] weight=($signed({2'b0,observation})<<<1)-9'sd73;
 wire signed [48:0] dot_term=held_unwrapped*weight;
 wire signed [55:0] dot_next=dot_sum+$signed({{7{held_dot[48]}},held_dot});
 wire dot_bad=dot_sum>=56'sd562949953421312 || dot_sum<= -56'sd562949953421312;
 wire signed [63:0] pred_extended={{24{pred_product[39]}},pred_product};
 wire signed [63:0] pred_numerator=(pred_extended<<<19)-(pred_extended<<<16);
 wire divide_input_valid=!clear && ((state==FREQ_REQ)||state==PRED_START);
 wire divide_input_ready,divide_valid,divide_error;
 wire signed [63:0] divide_numerator=state==FREQ_REQ?frequency_numerator:pred_numerator;
 wire [31:0] divide_denominator=state==FREQ_REQ?32'd1239089152:32'd390625;
 wire signed [63:0] divide_quotient;
 cfo_divide_rne64 divider(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(divide_input_valid),.s_ready(divide_input_ready),.s_numerator(divide_numerator),.s_denominator(divide_denominator),.m_valid(divide_valid),.m_ready(1'b1),.m_quotient(divide_quotient),.m_error(divide_error));
 wire signed [63:0] residual_next=$signed({{24{unwrapped_read[39]}},unwrapped_read})-divide_quotient;
 wire signed [63:0] res_extended={{8{residual_read[55]}},residual_read};
 wire [63:0] maximum_next=center_magnitude>max_centered?center_magnitude:max_centered;
 // Compare both inputs in parallel instead of max-select followed by compare.
 wire linear_next=center_magnitude<=64'd7945689497 && max_centered<=64'd7945689497 && saturations==0 && any_nonzero;
 task automatic fail_result(input logic [3:0] code);
  begin
   m_error<=code;m_nonzero<=0;m_phase_linear<=0;m_frequency_q16<=0;
   m_weighted_sum<=0;m_max_centered<=0;m_cordic_saturations<=0;state<=RESULT;
  end
 endtask
 always_ff @(posedge clk)begin
  if(clear)begin
   state<=ACCEPT_Z;observation<=0;work_index<=0;iteration<=0;x<=0;y<=0;angle<=0;previous_angle<=0;unwrap_offset<=0;
   phase_code<=0;dot_sum<=0;residual_sum<=0;unwrapped_read<=0;pred_product<=0;residual_read<=0;max_centered<=0;saturations<=0;any_nonzero<=0;
   shifted_x<=0;shifted_y<=0;held_unwrapped<=0;held_prediction<=0;held_dot<=0;held_residual<=0;
   center_left<=0;center_right<=0;center_value<=0;center_magnitude<=0;
   frequency_acc<=0;frequency_shift<=0;frequency_factor<=0;frequency_remaining<=0;frequency_numerator<=0;
   m_frame<=0;m_generation<=0;m_nonzero<=0;m_phase_linear<=0;m_error<=0;m_frequency_q16<=0;m_weighted_sum<=0;m_max_centered<=0;m_cordic_saturations<=0;
   phase_audit_valid<=0;phase_audit_index<=0;phase_audit_angle<=0;phase_audit_unwrapped<=0;
   pred_audit_valid<=0;pred_audit_index<=0;pred_audit_value<=0;pred_audit_residual<=0;
   center_audit_valid<=0;center_audit_index<=0;center_audit_value<=0;
  end else begin
   phase_audit_valid<=0;pred_audit_valid<=0;center_audit_valid<=0;
   case(state)
    ACCEPT_Z:if(s_valid)begin
     if(observation==0)begin
      m_frame<=s_frame;m_generation<=s_generation;m_nonzero<=0;m_phase_linear<=0;m_error<=0;m_frequency_q16<=0;m_weighted_sum<=0;m_max_centered<=0;m_cordic_saturations<=0;
      dot_sum<=0;residual_sum<=0;unwrap_offset<=0;previous_angle<=0;saturations<=0;max_centered<=0;
     end
     if(observation!=0 && (s_frame!=m_frame || s_generation!=m_generation))fail_result(4'd1);
     else if(s_index!=observation || s_last!=(observation==73))fail_result(4'd2);
     else if(s_i==38'sh2000000000 || s_q==38'sh2000000000)fail_result(4'd3);
     else begin
      any_nonzero<=(observation==0)?(s_i!=0 || s_q!=0):(any_nonzero || s_i!=0 || s_q!=0);
      x<=sx[39]?-sx:sx;y<=sx[39]?-sy:sy;
      angle<=sx[39]?(sy[39]?-32'sd1073741824:32'sd1073741824):32'sd0;
      iteration<=0;state<=CORDIC_SHIFT;
     end
    end
    CORDIC_SHIFT:begin shifted_x<=x>>>iteration;shifted_y<=y>>>iteration;state<=CORDIC;end
    CORDIC:begin
     x<=x_next;y<=y_next;angle<=angle_next;saturations<=saturations+{{11{1'b0}},x_clip}+{{11{1'b0}},y_clip};
     if(iteration==23)state<=STORE_OFFSET;else begin iteration<=iteration+1'b1;state<=CORDIC_SHIFT;end
    end
    STORE_OFFSET:begin unwrap_offset<=offset_next;previous_angle<=angle;state<=STORE_PHASE;end
    STORE_PHASE:begin
     unwrapped_ram[observation]<=unwrapped_next;held_unwrapped<=unwrapped_next;
     phase_audit_valid<=1;phase_audit_index<=observation;phase_audit_angle<=angle;phase_audit_unwrapped<=unwrapped_next;
     state<=STORE_DOT;
    end
    STORE_DOT:begin held_dot<=dot_term;state<=STORE_ACCUM;end
    STORE_ACCUM:begin
     dot_sum<=dot_next;
     if(observation==73)state<=FREQ_START;
     else begin observation<=observation+1'b1;state<=ACCEPT_Z;end
    end
    FREQ_START:if(dot_bad)fail_result(4'd4);else begin
     frequency_acc<=0;frequency_shift<={{16{dot_sum[55]}},dot_sum};
     frequency_factor<=16'd15625;frequency_remaining<=16;state<=FREQ_MULT;
    end
    FREQ_MULT:begin
     frequency_acc<=frequency_sum;frequency_shift<=frequency_shift<<<1;
     frequency_factor<=frequency_factor>>1;frequency_remaining<=frequency_remaining-1'b1;
     if(frequency_remaining==1)begin frequency_numerator<=frequency_sum[63:0];state<=FREQ_REQ;end
    end
    FREQ_REQ:if(divide_input_ready)state<=FREQ_WAIT;
    FREQ_WAIT:if(divide_valid)begin
     if(divide_error || divide_quotient>64'sd2147483647 || divide_quotient< -64'sd2147483647)fail_result(4'd4);
     else begin
      phase_code<=divide_quotient[31:0];m_frequency_q16<=divide_quotient[31:0];m_weighted_sum<=dot_sum;
      work_index<=0;residual_sum<=0;state<=PRED_LOAD;
     end
    end
    PRED_LOAD:begin
     unwrapped_read<=unwrapped_ram[work_index];pred_product<=phase_code*$signed({1'b0,work_index});state<=PRED_START;
    end
    PRED_START:if(divide_input_ready)state<=PRED_WAIT;
    PRED_WAIT:if(divide_valid)begin
     if(divide_error || divide_quotient>64'sd549755813887 || divide_quotient< -64'sd549755813888 || residual_next>64'sd36028797018963967 || residual_next< -64'sd36028797018963968)fail_result(4'd4);
     else begin
      held_residual<=residual_next[55:0];held_prediction<=divide_quotient[39:0];state<=PRED_STORE;
     end
    end
    PRED_STORE:begin
     residual_ram[work_index]<=held_residual;residual_sum<=residual_sum+held_residual;
     pred_audit_valid<=1;pred_audit_index<=work_index;pred_audit_value<=held_prediction;pred_audit_residual<=held_residual;
     if(work_index==73)begin work_index<=0;max_centered<=0;state<=CENTER_LOAD;end
     else begin work_index<=work_index+1'b1;state<=PRED_LOAD;end
    end
    CENTER_LOAD:begin residual_read<=residual_ram[work_index];state<=CENTER_PAIR;end
    CENTER_PAIR:begin
     center_left<=(res_extended<<<6)+(res_extended<<<3);
     center_right<=(res_extended<<<1)-$signed({{8{residual_sum[55]}},residual_sum});state<=CENTER_SUM;
    end
    CENTER_SUM:begin center_value<=center_left+center_right;state<=CENTER_ABS;end
    CENTER_ABS:begin center_magnitude<=center_value[63]?64'd0-center_value:center_value;state<=CENTER_EVAL;end
    CENTER_EVAL:begin
     max_centered<=maximum_next;center_audit_valid<=1;center_audit_index<=work_index;center_audit_value<=center_value;
     if(work_index==73)begin
      m_max_centered<=maximum_next;m_phase_linear<=linear_next;m_nonzero<=any_nonzero;m_cordic_saturations<=saturations;state<=RESULT;
     end else begin work_index<=work_index+1'b1;state<=CENTER_LOAD;end
    end
    RESULT:if(m_ready)begin observation<=0;state<=ACCEPT_Z;end
    default:state<=ACCEPT_Z;
   endcase
  end
 end
endmodule
