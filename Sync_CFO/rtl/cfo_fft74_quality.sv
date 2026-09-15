`timescale 1ns/1ps
// 74 S38 observations -> block scaling, exact FFT256, spectrum checks and CFO.
module cfo_fft74_quality(
 input logic clk,rst,abort_sync,input logic s_valid,output logic s_ready,
 input logic [31:0] s_frame,s_generation,input logic [6:0] s_index,input logic s_last,
 input logic signed [37:0] s_i,s_q,
 output logic m_valid,input logic m_ready,output logic [31:0] m_frame,m_generation,
 output logic [3:0] m_error,output logic m_nonzero,m_spectrum,
 output logic signed [31:0] m_frequency_q16,output logic [196:0] m_quality,
 output logic normal_audit_valid,output logic [6:0] normal_audit_index,output logic [39:0] normal_audit_value,
 output logic fft_audit_valid,output logic [7:0] fft_audit_index,output logic [79:0] fft_audit_value
);
 typedef enum logic [3:0] {LOAD_Z,PREPARE,N_READ,N_SEND,F_COLLECT,S_READ,S_EVAL,MATH,D_START,D_WAIT,F_START,F_WAIT,RESULT} state_t;
 state_t state;
 (* ram_style="distributed" *) logic [75:0] z_ram[0:73];
 (* ram_style="block" *) logic [39:0] power_ram[0:255];
 logic [6:0] observation;
 logic [37:0] maximum;
 logic signed [5:0] exponent;
 logic [7:0] work_index,peak_bin,scan_index;
 logic [20:0] ni,nq;
 logic [39:0] peak,secondary,left_power,right_power,scan_power;
 logic [47:0] energy;
 logic [12:0] fft_saturations;logic [7:0] normal_saturations;
 logic coherent,unambiguous;
 logic signed [31:0] delta_q16;
 wire [37:0] abs_i=s_i[37] ? 38'd0-s_i : s_i;
 wire [37:0] abs_q=s_q[37] ? 38'd0-s_q : s_q;
 wire [37:0] input_max=abs_i>abs_q ? abs_i : abs_q;
 wire clear=rst||abort_sync;
 assign s_ready=!clear && state==LOAD_Z;assign m_valid=!clear && state==RESULT;
 assign m_quality={exponent,peak_bin,delta_q16,peak,secondary,energy,fft_saturations,normal_saturations,coherent,unambiguous};
 function automatic signed [5:0] block_exponent(input logic [37:0] x);
  integer j,highest;begin
   highest=0;for(j=0;j<37;j=j+1)if(x[j])highest=j;
   block_exponent=(x==(38'd1<<highest)) ? (16-highest) : (15-highest);
  end
 endfunction
 function automatic [20:0] normalized(input logic signed [37:0] x,input logic signed [5:0] e);
  logic signed [63:0] wide,q;integer shift;begin
   wide={{26{x[37]}},x};q=wide;
   if(e>=0)q=wide<<<e;
   else begin
    shift=-e;q=wide>>>shift;
    if(wide[shift-1] && (((wide&((64'd1<<(shift-1))-64'd1))!=0) || q[0]))q=q+64'sd1;
   end
   if(q>64'sd524287)normalized={1'b1,20'h7ffff};
   else if(q< -64'sd524288)normalized={1'b1,20'h80000};
   else normalized={1'b0,q[19:0]};
  end
 endfunction
 wire fft_s_valid=!clear && state==N_SEND;wire fft_s_ready,fft_m_valid;
 wire fft_m_ready=!clear && state==F_COLLECT;
 wire [31:0] fft_frame,fft_generation;wire [7:0] fft_index;wire fft_last;
 wire signed [19:0] fft_i,fft_q;wire [12:0] fft_sat;wire [3:0] fft_error;
 cfo_fft256_core fft_core(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(fft_s_valid),.s_ready(fft_s_ready),
  .s_frame(m_frame),.s_generation(m_generation),.s_index(work_index),.s_last(work_index==8'd255),.s_i(ni[19:0]),.s_q(nq[19:0]),
  .m_valid(fft_m_valid),.m_ready(fft_m_ready),.m_frame(fft_frame),.m_generation(fft_generation),.m_index(fft_index),.m_last(fft_last),
  .m_i(fft_i),.m_q(fft_q),.m_saturations(fft_sat),.m_error(fft_error),.butterfly_audit_valid(),.butterfly_audit_stage(),.butterfly_audit_index(),.butterfly_audit_value());
 wire signed [19:0] power_i=(state==N_SEND) ? $signed(ni[19:0]) : fft_i;
 wire signed [19:0] power_q=(state==N_SEND) ? $signed(nq[19:0]) : fft_q;
 wire signed [39:0] square_i=power_i*power_i,square_q=power_q*power_q;
 wire [39:0] point_power=$unsigned(square_i)+$unsigned(square_q);
 wire [7:0] circular_distance=scan_index-peak_bin;
 wire [63:0] peak64={24'd0,peak},secondary64={24'd0,secondary},energy64={16'd0,energy};
 wire spectrum_coherent=((peak64<<18)+(peak64<<16))>=((energy64<<6)+(energy64<<3)+(energy64<<1));
 wire spectrum_unambiguous=(secondary64<<2)<=peak64;
 wire signed [63:0] left64=$signed({24'd0,left_power}),right64=$signed({24'd0,right_power});
 wire signed [63:0] delta_denominator=$signed(peak64<<1)-left64-right64;
 wire signed [63:0] delta_numerator=(right64-left64)<<<15;
 wire signed [63:0] signed_bin=peak_bin[7] ? $signed({56'd0,peak_bin})-64'sd256 : $signed({56'd0,peak_bin});
 wire signed [63:0] fractional_bin=(signed_bin<<<16)+$signed({{32{delta_q16[31]}},delta_q16});
 wire signed [63:0] frequency_numerator=fractional_bin*64'sd500000000;
 wire div_s_valid=!clear && (state==D_START || state==F_START),div_s_ready,div_m_valid,div_error;
 wire div_m_ready=!clear && (state==D_WAIT || state==F_WAIT);wire signed [63:0] quotient;
 cfo_divide_rne64wide divider(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(div_s_valid),.s_ready(div_s_ready),
  .s_numerator((state==D_START) ? delta_numerator : frequency_numerator),.s_denominator((state==D_START) ? $unsigned(delta_denominator) : 64'd4587520),
  .m_valid(div_m_valid),.m_ready(div_m_ready),.m_quotient(quotient),.m_error(div_error));
 always_ff @(posedge clk)begin
  normal_audit_valid<=0;fft_audit_valid<=0;
  if(clear)begin
   state<=LOAD_Z;observation<=0;maximum<=0;exponent<=0;work_index<=0;scan_index<=0;peak_bin<=0;
   ni<=0;nq<=0;peak<=0;secondary<=0;left_power<=0;right_power<=0;energy<=0;fft_saturations<=0;normal_saturations<=0;
   coherent<=0;unambiguous<=0;delta_q16<=0;m_frame<=0;m_generation<=0;m_error<=0;m_nonzero<=0;m_spectrum<=0;m_frequency_q16<=0;
   normal_audit_index<=0;normal_audit_value<=0;fft_audit_index<=0;fft_audit_value<=0;
  end else case(state)
   LOAD_Z:if(s_valid)begin
    if(observation==0)begin
     m_frame<=s_frame;m_generation<=s_generation;maximum<=input_max;m_error<=0;m_frequency_q16<=0;m_nonzero<=0;m_spectrum<=0;
     exponent<=0;peak_bin<=0;delta_q16<=0;peak<=0;secondary<=0;left_power<=0;right_power<=0;energy<=0;
     fft_saturations<=0;normal_saturations<=0;coherent<=0;unambiguous<=0;
    end else if(input_max>maximum)maximum<=input_max;
    if(observation!=0 && (s_frame!=m_frame || s_generation!=m_generation))begin m_error<=1;state<=RESULT;end
    else if(s_index!=observation || s_last!=(observation==7'd73))begin m_error<=2;state<=RESULT;end
    else if(s_i==38'sh2000000000 || s_q==38'sh2000000000)begin m_error<=3;state<=RESULT;end
    else begin
     z_ram[observation]<={s_i,s_q};
     if(observation==7'd73)state<=PREPARE;else observation<=observation+7'd1;
    end
   end
   PREPARE:begin
    if(maximum==0)begin m_nonzero<=0;state<=RESULT;end
    else begin m_nonzero<=1;exponent<=block_exponent(maximum);work_index<=0;state<=N_READ;end
   end
   N_READ:begin
    if(work_index<8'd74)begin ni<=normalized($signed(z_ram[work_index][75:38]),exponent);nq<=normalized($signed(z_ram[work_index][37:0]),exponent);end
    else begin ni<=0;nq<=0;end
    state<=N_SEND;
   end
   N_SEND:if(fft_s_ready)begin
    if(work_index<8'd74)begin
     normal_audit_valid<=1;normal_audit_index<=work_index[6:0];normal_audit_value<={ni[19:0],nq[19:0]};
     energy<=energy+{8'd0,point_power};normal_saturations<=normal_saturations+{7'd0,ni[20]}+{7'd0,nq[20]};
    end
    if(work_index==8'd255)begin work_index<=0;state<=F_COLLECT;end
    else begin work_index<=work_index+8'd1;state<=N_READ;end
   end
   F_COLLECT:if(fft_m_valid)begin
    if(fft_error!=0 || fft_frame!=m_frame || fft_generation!=m_generation || fft_index!=work_index || fft_last!=(work_index==8'd255))begin m_error<=4;state<=RESULT;end
    else begin
     power_ram[work_index]<=point_power;fft_saturations<=fft_sat;
     fft_audit_valid<=1;fft_audit_index<=work_index;fft_audit_value<={fft_i,fft_q,point_power};
     if(work_index==0 || point_power>peak)begin peak<=point_power;peak_bin<=work_index;end
     if(work_index==8'd255)begin scan_index<=0;state<=S_READ;end
     else work_index<=work_index+8'd1;
    end
   end
   S_READ:begin scan_power<=power_ram[scan_index];state<=S_EVAL;end
   S_EVAL:begin
    if(circular_distance>8'd4 && circular_distance<8'd252 && scan_power>secondary)secondary<=scan_power;
    if(circular_distance==8'd255)left_power<=scan_power;
    if(circular_distance==8'd1)right_power<=scan_power;
    if(scan_index==8'd255)state<=MATH;
    else begin scan_index<=scan_index+8'd1;state<=S_READ;end
   end
   MATH:begin
    coherent<=spectrum_coherent;unambiguous<=spectrum_unambiguous;
    m_spectrum<=spectrum_coherent && spectrum_unambiguous && fft_saturations==0 && normal_saturations==0;
    if(delta_denominator>0)state<=D_START;else begin delta_q16<=0;state<=F_START;end
   end
   D_START:if(div_s_ready)state<=D_WAIT;
   D_WAIT:if(div_m_valid)begin
    if(div_error)begin m_error<=4;state<=RESULT;end
    else begin
     if(quotient>64'sd32768)delta_q16<=32'sd32768;
     else if(quotient< -64'sd32768)delta_q16<= -32'sd32768;
     else delta_q16<=quotient[31:0];state<=F_START;
    end
   end
   F_START:if(div_s_ready)state<=F_WAIT;
   F_WAIT:if(div_m_valid)begin
    if(div_error || quotient>64'sd2147483647 || quotient< -64'sd2147483648)begin m_error<=4;m_frequency_q16<=0;end
    else m_frequency_q16<=quotient[31:0];state<=RESULT;
   end
   RESULT:if(m_ready)begin state<=LOAD_Z;observation<=0;end
   default:begin state<=LOAD_Z;observation<=0;end
  endcase
 end
endmodule