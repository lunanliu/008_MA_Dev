`timescale 1ns/1ps
// Natural-order 256-point complex FFT. Exact per-stage RNE /2 and S20 clamp.
// Twiddles are S18/F17, including +1 clipped to 131071.
module cfo_fft256_core(
 input logic clk,rst,abort_sync,
 input logic s_valid, output logic s_ready,
 input logic [31:0] s_frame,s_generation,
 input logic [7:0] s_index,input logic s_last,
 input logic signed [19:0] s_i,s_q,
 output logic m_valid,input logic m_ready,
 output logic [31:0] m_frame,m_generation,
 output logic [7:0] m_index,output logic m_last,
 output logic signed [19:0] m_i,m_q,
 output logic [12:0] m_saturations,output logic [3:0] m_error,
 output logic butterfly_audit_valid,
 output logic [2:0] butterfly_audit_stage,
 output logic [6:0] butterfly_audit_index,
 output logic [82:0] butterfly_audit_value
);
 localparam [3:0] LOAD=0,F_READ=1,F_MULT=2,F_ADD=3,F_ROUND=4,F_WRITE=5,O_READ=6,O_HOLD=7,E_HOLD=8;
 logic [3:0] state;
 (* ram_style="block" *) logic [39:0] bank0[0:127],bank1[0:127];
 (* rom_style="distributed" *) logic [35:0] twiddle_rom[0:127];
 initial $readmemh("fft256_twiddle.mem",twiddle_rom);
 logic [7:0] input_index,output_index,addr_a,addr_b;
 logic [2:0] stage_index;
 logic [6:0] butterfly_index,twiddle_index;
 logic [8:0] half_span,offset_in_group,base_address;
 logic [39:0] a_reg,raw0,raw1,a_word,b_word;
 logic butterfly_bank,output_bank;
 logic [7:0] load_address;
 logic rd0,rd1,we0,we1;
 logic [6:0] ra0,ra1,wa0,wa1;
 logic [39:0] wd0,wd1;
 logic signed [17:0] wr,wi;
 logic signed [37:0] rr,ii,ri,ir;
 logic signed [38:0] product_i,product_q;
 logic signed [21:0] rounded_i,rounded_q;
 logic signed [22:0] add_i,add_q,sub_i,sub_q;
 logic signed [21:0] half_ai,half_aq,half_bi,half_bq;
 logic signed [19:0] next_ai,next_aq,next_bi,next_bq;
 logic [2:0] new_saturations;
 function automatic [7:0] reverse8(input [7:0] x);
  integer j;begin for(j=0;j<8;j=j+1)reverse8[j]=x[7-j];end
 endfunction
 function automatic signed [21:0] rne17(input logic signed [38:0] x);
  logic signed [38:0] q;begin
   q=x>>>17;
   if(x[16] && ((|x[15:0]) || q[0]))q=q+39'sd1;
   rne17=q[21:0];
  end
 endfunction
 function automatic signed [21:0] rne1(input logic signed [22:0] x);
  logic signed [22:0] q;begin
   q=x>>>1;if(x[0] && q[0])q=q+23'sd1;rne1=q[21:0];
  end
 endfunction
 function automatic signed [19:0] clamp20(input logic signed [21:0] x);
  begin
   if(x>22'sd524287)clamp20=20'sh7ffff;
   else if(x< -22'sd524288)clamp20=20'sh80000;
   else clamp20=x[19:0];
  end
 endfunction
 function automatic clipped20(input logic signed [21:0] x);
  begin clipped20=(x>22'sd524287 || x< -22'sd524288);end
 endfunction
 always_comb begin
  load_address=reverse8(input_index);
  a_word=butterfly_bank ? raw1 : raw0;b_word=butterfly_bank ? raw0 : raw1;
  {m_i,m_q}=(state==E_HOLD) ? 40'd0 : (output_bank ? raw1 : raw0);
  half_span=9'd1<<stage_index;
  offset_in_group={2'b0,butterfly_index}&(half_span-9'd1);
  base_address=({2'b0,butterfly_index}>>stage_index)<<(stage_index+1);
  addr_a=base_address+offset_in_group;addr_b=base_address+offset_in_group+half_span;
  twiddle_index=offset_in_group<<(7-stage_index);
  add_i=$signed({{3{a_reg[39]}},a_reg[39:20]})+$signed({rounded_i[21],rounded_i});
  add_q=$signed({{3{a_reg[19]}},a_reg[19:0]})+$signed({rounded_q[21],rounded_q});
  sub_i=$signed({{3{a_reg[39]}},a_reg[39:20]})-$signed({rounded_i[21],rounded_i});
  sub_q=$signed({{3{a_reg[19]}},a_reg[19:0]})-$signed({rounded_q[21],rounded_q});
  half_ai=rne1(add_i);half_aq=rne1(add_q);half_bi=rne1(sub_i);half_bq=rne1(sub_q);
  next_ai=clamp20(half_ai);next_aq=clamp20(half_aq);next_bi=clamp20(half_bi);next_bq=clamp20(half_bq);
  new_saturations={2'b0,clipped20(half_ai)}+{2'b0,clipped20(half_aq)}+{2'b0,clipped20(half_bi)}+{2'b0,clipped20(half_bq)};
  s_ready=(state==LOAD) && !rst && !abort_sync;
  m_valid=(state==O_HOLD || state==E_HOLD) && !rst && !abort_sync;
 end
 // Two SDP banks: exactly one synchronous read destination per bank.
 // Parity differs for every butterfly pair, including stage 7 (equal rows).
 always_comb begin
  rd0=0;rd1=0;we0=0;we1=0;ra0=0;ra1=0;wa0=0;wa1=0;wd0=0;wd1=0;
  if(!rst && !abort_sync)begin
   // Malformed LOAD data is private and discarded by E_HOLD, never transformed.
   if(state==LOAD && s_valid)begin
    if(^load_address)begin we1=1;wa1=load_address[6:0];wd1={s_i,s_q};end
    else begin we0=1;wa0=load_address[6:0];wd0={s_i,s_q};end
   end
   if(state==F_READ)begin
    rd0=1;rd1=1;
    ra0=(^addr_a) ? addr_b[6:0] : addr_a[6:0];
    ra1=(^addr_a) ? addr_a[6:0] : addr_b[6:0];
   end
   if(state==F_WRITE)begin
    we0=1;we1=1;
    wa0=butterfly_bank ? addr_b[6:0] : addr_a[6:0];
    wa1=butterfly_bank ? addr_a[6:0] : addr_b[6:0];
    wd0=butterfly_bank ? {next_bi,next_bq} : {next_ai,next_aq};
    wd1=butterfly_bank ? {next_ai,next_aq} : {next_bi,next_bq};
   end
   if(state==O_READ)begin
    if(^output_index)begin rd1=1;ra1=output_index[6:0];end
    else begin rd0=1;ra0=output_index[6:0];end
   end
  end
 end
 always_ff @(posedge clk)begin
  if(we0)bank0[wa0]<=wd0;
  if(we1)bank1[wa1]<=wd1;
  if(rd0)raw0<=bank0[ra0];
  if(rd1)raw1<=bank1[ra1];
 end
 always_ff @(posedge clk)begin
  butterfly_audit_valid<=0;
  if(rst || abort_sync)begin
   state<=LOAD;input_index<=0;output_index<=0;stage_index<=0;butterfly_index<=0;butterfly_bank<=0;output_bank<=0;
   m_frame<=0;m_generation<=0;m_index<=0;m_last<=0;m_error<=0;m_saturations<=0;
   butterfly_audit_stage<=0;butterfly_audit_index<=0;butterfly_audit_value<=0;
  end else case(state)
   LOAD:if(s_valid)begin
    if(input_index==0)begin
     m_frame<=s_frame;m_generation<=s_generation;m_error<=0;m_saturations<=0;
    end
    if((input_index!=0) && (s_frame!=m_frame || s_generation!=m_generation))begin
     state<=E_HOLD;m_error<=1;m_index<=0;m_last<=1;m_saturations<=0;
    end else if(s_index!=input_index || s_last!=(input_index==8'd255))begin
     state<=E_HOLD;m_error<=2;m_index<=0;m_last<=1;m_saturations<=0;
    end else begin
     if(input_index==8'd255)begin stage_index<=0;butterfly_index<=0;state<=F_READ;end
     else input_index<=input_index+8'd1;
    end
   end
   F_READ:begin
    butterfly_bank<=^addr_a;{wr,wi}<=twiddle_rom[twiddle_index];state<=F_MULT;
   end
   F_MULT:begin
    a_reg<=a_word;
    rr<=$signed(b_word[39:20])*wr;ii<=$signed(b_word[19:0])*wi;
    ri<=$signed(b_word[39:20])*wi;ir<=$signed(b_word[19:0])*wr;state<=F_ADD;
   end
   F_ADD:begin
    product_i<=$signed({rr[37],rr})-$signed({ii[37],ii});
    product_q<=$signed({ri[37],ri})+$signed({ir[37],ir});state<=F_ROUND;
   end
   F_ROUND:begin rounded_i<=rne17(product_i);rounded_q<=rne17(product_q);state<=F_WRITE;end
   F_WRITE:begin
    m_saturations<=m_saturations+new_saturations;
    butterfly_audit_valid<=1;butterfly_audit_stage<=stage_index;butterfly_audit_index<=butterfly_index;
    butterfly_audit_value<={next_ai,next_aq,next_bi,next_bq,new_saturations};
    if(butterfly_index==7'd127)begin
     butterfly_index<=0;
     if(stage_index==3'd7)begin output_index<=0;state<=O_READ;end
     else begin stage_index<=stage_index+3'd1;state<=F_READ;end
    end else begin butterfly_index<=butterfly_index+7'd1;state<=F_READ;end
   end
   O_READ:begin output_bank<=^output_index;m_index<=output_index;m_last<=(output_index==8'd255);state<=O_HOLD;end
   O_HOLD:if(m_ready)begin
    if(output_index==8'd255)begin state<=LOAD;input_index<=0;end
    else begin output_index<=output_index+8'd1;state<=O_READ;end
   end
   E_HOLD:if(m_ready)begin state<=LOAD;input_index<=0;end
   default:begin state<=LOAD;input_index<=0;end
  endcase
 end
endmodule
