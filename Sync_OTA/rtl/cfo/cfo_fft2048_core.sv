`timescale 1ns/1ps
// S26 FFT2048, radix-2 DIT. Input bit reversal, natural output, RNE at each /2.
// Bank parity makes every butterfly use different memories. Each stage drains.
module cfo_fft2048_core(
 input logic clk,rst,abort_sync,
 input logic s_valid,output logic s_ready,
 input logic [31:0] s_frame,s_generation,input logic [6:0] s_window,
 input logic [10:0] s_index,input logic s_last,input logic signed [25:0] s_i,s_q,
 output logic m_valid,input logic m_ready,
 output logic [31:0] m_frame,m_generation,output logic [6:0] m_window,
 output logic [10:0] m_index,output logic m_last,output logic signed [25:0] m_i,m_q,
 output logic [15:0] m_saturations,output logic [3:0] m_error,
 output logic butterfly_audit_valid,output logic [3:0] butterfly_audit_stage,
 output logic [9:0] butterfly_audit_index,output logic [106:0] butterfly_audit_value
);
 localparam [2:0] LOAD=0,RUN=1,OUTPUT=2,ERROR_HOLD=3,START=4,ERROR_START=5;
 logic [2:0] state;
 (* ram_style="block" *) logic [51:0] bank0[0:1023],bank1[0:1023];
 (* rom_style="block" *) logic [35:0] twiddle[0:1023];
 initial $readmemh("fft2048_twiddle.mem",twiddle);
 logic [10:0] input_index,half_span,group_base;
 logic [9:0] offset_in_group,issue_index;
 // Keep the existing local address boundary; never lock the ROM output FF.
 (* dont_touch="true" *) logic [9:0] tw_index;
 logic [10:0] tw_stride;
 logic [3:0] stage_index;
 logic issued_all;
 logic [8:0] v;
 typedef struct packed {logic [3:0] stage;logic [9:0] bf;logic bank_a;logic [9:0] row_a,row_b;} tag_t;
 tag_t tag[0:8];
 logic [51:0] raw0,raw1,pipe0,pipe1;
 logic [35:0] raw_tw,pipe_tw;
 logic signed [25:0] ar2,ai2,br2,bi2,ar3,ai3,ar4,ai4,ar5,ai5;
 logic signed [17:0] wr2,wi2;
 logic signed [43:0] rr3,ii3,ri3,ir3;
 logic signed [44:0] pr4,pi4;
 logic signed [27:0] pr5,pi5;
 logic signed [28:0] add_i6,add_q6,sub_i6,sub_q6;
 logic signed [27:0] half_ai,half_aq,half_bi,half_bq;
 logic signed [25:0] next_ai,next_aq,next_bi,next_bq;
 logic [2:0] new_saturations,saturations8;
 logic signed [25:0] ai8,aq8,bi8,bq8;
 logic [10:0] addr_a,addr_b,load_address;
 logic [3:0] input_error;
 logic check_valid,bad_window_range,bad_frame,bad_generation,bad_window,bad_index,bad_last;
 logic load_bank,output_bank;
 logic load_cmd_valid,load_cmd_bank;
 logic [9:0] load_cmd_addr;
 logic [51:0] load_cmd_data;
 wire load_take=s_valid && s_ready;
 wire [10:0] input_index_next=input_index+11'd1;
 logic rd0,rd1,we0,we1;
 logic [9:0] raddr0,raddr1,waddr0,waddr1;
 logic [51:0] wdata0,wdata1;
 logic output_valid,out_ce,pf0_valid,pf1_valid,pf0_bank,pf1_bank,output_issued_all;
 logic [10:0] next_output,pf0_index,pf1_index;
 wire [10:0] output_index_next=next_output+11'd1;
 integer t;
 function automatic [10:0] reverse11(input [10:0] x);
  integer j;begin for(j=0;j<11;j=j+1)reverse11[j]=x[10-j];end
 endfunction
 function automatic signed [27:0] rne17(input logic signed [44:0] x);
  logic [27:0] q;logic inc;logic [3:0] carry_in;
  begin
   // Exact modulo-2^28 RNE; parallel carry lookahead limits each add to 7 bits.
   q=x[44:17];inc=x[16]&&((|x[15:0])||x[17]);
   carry_in={inc&&(&q[20:0]),inc&&(&q[13:0]),inc&&(&q[6:0]),inc};
   rne17[6:0]=q[6:0]+{6'd0,carry_in[0]};
   rne17[13:7]=q[13:7]+{6'd0,carry_in[1]};
   rne17[20:14]=q[20:14]+{6'd0,carry_in[2]};
   rne17[27:21]=q[27:21]+{6'd0,carry_in[3]};
  end
 endfunction
 function automatic signed [27:0] rne1(input logic signed [28:0] x);
  logic signed [28:0] q;begin q=x>>>1;if(x[0] && q[0])q=q+29'sd1;rne1=q[27:0];end
 endfunction
 function automatic signed [25:0] clamp26(input logic signed [27:0] x);
  begin
   if(x[27:25]=={3{x[25]}})clamp26=x[25:0];
   else clamp26=x[27] ? 26'sh2000000 : 26'sh1ffffff;
  end
 endfunction
 function automatic clipped26(input logic signed [27:0] x);
  begin clipped26=(x[27:25]!={3{x[25]}});end
 endfunction
 always_comb begin
  input_error=0;
  if(check_valid)begin
   if(bad_window_range)input_error=3;
   else if(bad_frame || bad_generation || bad_window)input_error=1;
   else if(bad_index || bad_last)input_error=2;
  end
  s_ready=(state==LOAD) && !rst && !abort_sync && input_error==0;
  m_valid=((state==OUTPUT && output_valid) || state==ERROR_HOLD) && !rst && !abort_sync;
  out_ce=!output_valid || m_ready;
  addr_a=group_base|{1'b0,offset_in_group};addr_b=addr_a|half_span;
  load_address=reverse11(input_index);
  next_ai=clamp26(half_ai);next_aq=clamp26(half_aq);next_bi=clamp26(half_bi);next_bq=clamp26(half_bq);
  new_saturations={2'b0,clipped26(half_ai)}+{2'b0,clipped26(half_aq)}+{2'b0,clipped26(half_bi)}+{2'b0,clipped26(half_bq)};
  // RAM address/data are disposable while the corresponding enable is low.
  // Keep reset/abort/valid/parity out of the wide payload muxes.
  raddr0=next_output[9:0];raddr1=next_output[9:0];
  waddr0=load_cmd_addr;waddr1=load_cmd_addr;
  wdata0=load_cmd_data;wdata1=load_cmd_data;
  if(state==RUN)begin
   raddr0=(^addr_a) ? addr_b[9:0] : addr_a[9:0];
   raddr1=(^addr_a) ? addr_a[9:0] : addr_b[9:0];
   waddr0=tag[8].bank_a ? tag[8].row_b : tag[8].row_a;
   waddr1=tag[8].bank_a ? tag[8].row_a : tag[8].row_b;
   wdata0=tag[8].bank_a ? {bi8,bq8} : {ai8,aq8};
   wdata1=tag[8].bank_a ? {ai8,aq8} : {bi8,bq8};
  end
  rd0=0;rd1=0;we0=0;we1=0;
  if(!rst && !abort_sync)begin
   // A malformed accepted record can touch disposable LOAD storage, but the
   // registered check prevents both another acceptance and entry into RUN.
   if(load_cmd_valid)begin
    we1=load_cmd_bank;we0=!load_cmd_bank;
   end
   if(state==RUN)begin
    rd0=!issued_all;rd1=!issued_all;
    we0=v[8];we1=v[8];
   end
   if(state==OUTPUT && out_ce && !output_issued_all)begin
    rd1=output_bank;rd0=!output_bank;
   end
  end
 end
 // Independent comparison registers terminate wide input identity logic.
 // START already provides the final-sample check cycle; healthy latency is unchanged.
 always_ff @(posedge clk)begin
  if(rst || abort_sync)begin check_valid<=0;load_cmd_valid<=0;end
  else begin check_valid<=load_take;load_cmd_valid<=load_take;end
  load_cmd_addr<=load_address[9:0];load_cmd_bank<=load_bank;load_cmd_data<={s_i,s_q};
  bad_window_range<=s_window>=7'd74;
  bad_frame<=input_index!=0 && s_frame!=m_frame;
  bad_generation<=input_index!=0 && s_generation!=m_generation;
  bad_window<=input_index!=0 && s_window!=m_window;
  bad_index<=s_index!=input_index;
  bad_last<=s_last!=(input_index==11'd2047);
 end
 // No reset or per-stage valid CE on pure arithmetic payload. The matching
 // valid bits alone authorize RAM writeback, saturation accounting and audit.
 // OUTPUT read holding registers retain their stall enable.
 always_ff @(posedge clk)begin
  // The existing START edge commits the last LOAD command before the first RUN read.
  tag[0]<={stage_index,issue_index,(^addr_a),addr_a[9:0],addr_b[9:0]};
  for(integer j=1;j<9;j=j+1)tag[j]<=tag[j-1];
  if(we0)bank0[waddr0]<=wdata0;
  if(we1)bank1[waddr1]<=wdata1;
  if(rd0)raw0<=bank0[raddr0];
  if(rd1)raw1<=bank1[raddr1];
  if(state==RUN && !issued_all && !rst && !abort_sync)raw_tw<=twiddle[tw_index];
  if(state==RUN || (state==OUTPUT && out_ce && pf0_valid))begin pipe0<=raw0;pipe1<=raw1;end
  pipe_tw<=raw_tw;
  begin
   {ar2,ai2}<=tag[1].bank_a ? pipe1 : pipe0;
   {br2,bi2}<=tag[1].bank_a ? pipe0 : pipe1;
   {wr2,wi2}<=pipe_tw;
  end
  begin
   rr3<=br2*wr2;ii3<=bi2*wi2;ri3<=br2*wi2;ir3<=bi2*wr2;ar3<=ar2;ai3<=ai2;
  end
  begin
   pr4<=$signed({rr3[43],rr3})-$signed({ii3[43],ii3});
   pi4<=$signed({ri3[43],ri3})+$signed({ir3[43],ir3});ar4<=ar3;ai4<=ai3;
  end
  begin pr5<=rne17(pr4);pi5<=rne17(pi4);ar5<=ar4;ai5<=ai4;end
  begin
   add_i6<=$signed({{3{ar5[25]}},ar5})+$signed({pr5[27],pr5});
   add_q6<=$signed({{3{ai5[25]}},ai5})+$signed({pi5[27],pi5});
   sub_i6<=$signed({{3{ar5[25]}},ar5})-$signed({pr5[27],pr5});
   sub_q6<=$signed({{3{ai5[25]}},ai5})-$signed({pi5[27],pi5});
  end
  // Independent arithmetic boundaries; all four words travel with tag/v.
  begin
   half_ai<=rne1(add_i6);half_aq<=rne1(add_q6);half_bi<=rne1(sub_i6);half_bq<=rne1(sub_q6);
  end
  begin
   ai8<=next_ai;aq8<=next_aq;bi8<=next_bi;bq8<=next_bq;saturations8<=new_saturations;
  end
 end
 always_ff @(posedge clk)begin
  butterfly_audit_valid<=0;
  if(rst || abort_sync)begin
   state<=LOAD;input_index<=0;load_bank<=0;output_bank<=0;v<=0;issued_all<=0;stage_index<=0;half_span<=1;tw_stride<=1024;offset_in_group<=0;group_base<=0;tw_index<=0;issue_index<=0;
   output_valid<=0;pf0_valid<=0;pf1_valid<=0;output_issued_all<=0;next_output<=0;pf0_index<=0;pf1_index<=0;pf0_bank<=0;pf1_bank<=0;
   m_frame<=0;m_generation<=0;m_window<=0;m_index<=0;m_last<=0;m_i<=0;m_q<=0;m_saturations<=0;m_error<=0;
   butterfly_audit_stage<=0;butterfly_audit_index<=0;butterfly_audit_value<=0;
  end else begin
   case(state)
    LOAD:if(load_take)begin
     if(input_index==0)begin m_frame<=s_frame;m_generation<=s_generation;m_window<=s_window;m_saturations<=0;m_error<=0;end
     if(input_index==11'd2047)begin
      state<=START;
     end else begin input_index<=input_index_next;load_bank<=^input_index_next;end
    end
    START:begin
     // Wide input identity/error decisions end at LOAD, not at every RUN CE.
     state<=RUN;stage_index<=0;half_span<=1;tw_stride<=1024;
     offset_in_group<=0;group_base<=0;tw_index<=0;issue_index<=0;issued_all<=0;v<=0;
    end
    RUN:begin
     v<={v[7:0],!issued_all};
     if(!issued_all)begin
      if(issue_index==10'd1023)issued_all<=1;else issue_index<=issue_index+10'd1;
      if({1'b0,offset_in_group}==half_span-11'd1)begin offset_in_group<=0;group_base<=group_base+(half_span<<1);tw_index<=0;end
      else begin offset_in_group<=offset_in_group+10'd1;tw_index<=tw_index+tw_stride[9:0];end
     end
     if(v[8])begin
      m_saturations<=m_saturations+saturations8;
      butterfly_audit_valid<=1;butterfly_audit_stage<=tag[8].stage;butterfly_audit_index<=tag[8].bf;
      butterfly_audit_value<={ai8,aq8,bi8,bq8,saturations8};
      if(tag[8].bf==10'd1023)begin
       v<=0;issued_all<=0;offset_in_group<=0;group_base<=0;tw_index<=0;issue_index<=0;
       if(stage_index==4'd10)begin
        state<=OUTPUT;next_output<=0;output_bank<=0;output_issued_all<=0;pf0_valid<=0;pf1_valid<=0;output_valid<=0;
       end else begin stage_index<=stage_index+4'd1;half_span<=half_span<<1;tw_stride<=tw_stride>>1;end
      end
     end
    end
    OUTPUT:if(out_ce)begin
     output_valid<=pf1_valid;
     if(pf1_valid)begin {m_i,m_q}<=pf1_bank ? pipe1 : pipe0;m_index<=pf1_index;m_last<=(pf1_index==11'd2047);end
     pf1_valid<=pf0_valid;if(pf0_valid)begin pf1_index<=pf0_index;pf1_bank<=pf0_bank;end
     pf0_valid<=!output_issued_all;
     if(!output_issued_all)begin
      pf0_index<=next_output;pf0_bank<=output_bank;
      if(next_output==11'd2047)output_issued_all<=1;
      else begin next_output<=output_index_next;output_bank<=^output_index_next;end
     end
     if(output_valid && m_ready && m_last)begin state<=LOAD;input_index<=0;load_bank<=0;output_valid<=0;pf0_valid<=0;pf1_valid<=0;end
    end
    ERROR_START:begin
     state<=ERROR_HOLD;m_index<=0;m_last<=1;m_i<=0;m_q<=0;m_saturations<=0;
    end
    ERROR_HOLD:if(m_ready)begin state<=LOAD;input_index<=0;load_bank<=0;end
    default:begin state<=LOAD;input_index<=0;load_bank<=0;v<=0;output_valid<=0;pf0_valid<=0;pf1_valid<=0;end
   endcase
   // Priority over START/RUN preparation. Error output is one cycle later;
   // healthy windows retain exactly the original load/RUN/output schedule.
   if(check_valid && input_error!=0)begin state<=ERROR_START;m_error<=input_error;end
  end
 end
endmodule
