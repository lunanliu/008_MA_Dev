`timescale 1ns/1ps
module cfo_phase74_tb;
 `include "phase74_config.svh"
 logic clk=0;always #3.333 clk=~clk;
 logic rst=1,abort_sync=0,s_valid=0,s_ready,s_last=0,m_valid,m_ready=0;
 logic [31:0] s_frame=0,s_generation=0;logic [6:0] s_index=0;logic signed [37:0] s_i=0,s_q=0;
 wire [31:0] m_frame,m_generation;wire m_nonzero,m_phase_linear;wire [3:0] m_error;
 wire signed [31:0] m_frequency_q16;wire signed [55:0] m_weighted_sum;wire [63:0] m_max_centered;wire [11:0] m_cordic_saturations;
 wire phase_audit_valid,pred_audit_valid,center_audit_valid;wire [6:0] phase_audit_index,pred_audit_index,center_audit_index;
 wire signed [31:0] phase_audit_angle;wire signed [39:0] phase_audit_unwrapped,pred_audit_value;wire signed [55:0] pred_audit_residual;wire signed [63:0] center_audit_value;
 wire [233:0] result_word={m_frame,m_generation,m_nonzero,m_phase_linear,m_error,m_frequency_q16,m_weighted_sum,m_max_centered,m_cordic_saturations};
 logic [75:0] z_memory[0:PHASE_CASES*74-1];
 logic [71:0] angle_memory[0:PHASE_CASES*74-1];logic [95:0] pred_memory[0:PHASE_CASES*74-1];logic [63:0] center_memory[0:PHASE_CASES*74-1];
 logic [233:0] result_memory[0:PHASE_CASES-1];
 integer cycle=0,run_id=-1,active_case=0,phase_count=0,pred_count=0,center_count=0,completed=0,errors=0,reset_discards=0,abort_discards=0;
 integer first_cycle,last_input_cycle,max_tail=0,max_total=0,total_stalls=0,file_handle,i,j;
 logic monitor_active=0;
 cfo_phase74_core dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(cycle>1000000)$fatal(1,"PHASE74_CYCLE_TIMEOUT");
  #1;
  if(!rst && !abort_sync)begin
   if(!monitor_active && (phase_audit_valid || pred_audit_valid || center_audit_valid || m_valid))$fatal(1,"PHASE74_STALE_OUTPUT");
   if(phase_audit_valid)begin
    if(phase_audit_index!=phase_count || {phase_audit_angle,phase_audit_unwrapped}!==angle_memory[active_case*74+phase_count])$fatal(1,"PHASE74_ANGLE case=%0d index=%0d",active_case,phase_count);
    $fdisplay(file_handle,"P %0d %0d %0d %018h",run_id,active_case,phase_count,{phase_audit_angle,phase_audit_unwrapped});phase_count=phase_count+1;
   end
   if(pred_audit_valid)begin
    if(pred_audit_index!=pred_count || {pred_audit_value,pred_audit_residual}!==pred_memory[active_case*74+pred_count])$fatal(1,"PHASE74_PRED case=%0d index=%0d",active_case,pred_count);
    $fdisplay(file_handle,"R %0d %0d %0d %024h",run_id,active_case,pred_count,{pred_audit_value,pred_audit_residual});pred_count=pred_count+1;
   end
   if(center_audit_valid)begin
    if(center_audit_index!=center_count || center_audit_value!==center_memory[active_case*74+center_count])$fatal(1,"PHASE74_CENTER case=%0d index=%0d",active_case,center_count);
    $fdisplay(file_handle,"C %0d %0d %0d %016h",run_id,active_case,center_count,center_audit_value);center_count=center_count+1;
   end
  end
 end
 task automatic begin_case(input integer k);
  begin
   @(negedge clk);if(!s_ready || m_valid)$fatal(1,"PHASE74_NOT_READY");
   active_case=k;run_id=run_id+1;phase_count=0;pred_count=0;center_count=0;monitor_active=1;
   first_cycle=cycle;last_input_cycle=cycle;
  end
 endtask
 task automatic sample(input integer k,input integer n,input integer corruption);
  begin
   @(negedge clk);
   s_frame=32'd2000+k;s_generation=32'h56780000+k;s_index=n;s_last=(n==73);
   {s_i,s_q}=z_memory[k*74+n];
   case(corruption)
    1:s_generation=s_generation^32'd1;
    2:s_index=n+1;
    3:s_last=1;
    4:s_i=38'sh2000000000;
    5:s_frame=s_frame^32'd1;
   endcase
   s_valid=1;
   while(!s_ready)begin
    if(cycle-first_cycle>11000)$fatal(1,"PHASE74_INPUT_TIMEOUT");
    @(negedge clk);
   end
   @(posedge clk);#1;last_input_cycle=cycle;
   @(negedge clk);s_valid=0;
  end
 endtask
 task automatic collect74(input integer k);
  integer n;
  begin for(n=0;n<74;n=n+1)sample(k,n,0);end
 endtask
 task automatic finish_case(input integer k,input integer stalls);
  integer tail,total,n;logic [233:0] held;
  begin
   while(!m_valid)begin
    if(cycle-last_input_cycle>6000)$fatal(1,"PHASE74_TAIL_TIMEOUT");
    @(negedge clk);
   end
   tail=cycle-last_input_cycle;total=cycle-first_cycle;
   if(tail>max_tail)max_tail=tail;if(total>max_total)max_total=total;
   if(result_word!==result_memory[k] || phase_count!=74 || pred_count!=74 || center_count!=74)$fatal(1,"PHASE74_RESULT case=%0d actual=%059h expected=%059h P=%0d R=%0d C=%0d",k,result_word,result_memory[k],phase_count,pred_count,center_count);
   held=result_word;s_valid=1;s_frame=~s_frame;s_generation=~s_generation;
   for(n=0;n<stalls;n=n+1)begin
    @(negedge clk);if(!m_valid || s_ready || result_word!==held)$fatal(1,"PHASE74_STALL_CHANGED");
   end
   s_valid=0;$fdisplay(file_handle,"F %0d %0d %059h %0d %0d %0d",run_id,k,result_word,tail,total,stalls);
   completed=completed+1;total_stalls=total_stalls+stalls;
   m_ready=1;@(posedge clk);#1;@(negedge clk);m_ready=0;monitor_active=0;
   if(m_valid || !s_ready)$fatal(1,"PHASE74_DUPLICATE_RESULT");
  end
 endtask
 task automatic discard(input integer k,input integer where_to_stop,input logic use_abort);
  begin
   begin_case(k);
   if(where_to_stop==0)begin sample(k,0,0);repeat(5)@(negedge clk);end
   else begin
    collect74(k);
    if(where_to_stop==1)repeat(150)@(negedge clk);
    else while(!m_valid)@(negedge clk);
   end
   if(use_abort)abort_sync=1;else rst=1;
   #1;if(m_valid || s_ready)$fatal(1,"PHASE74_CLEAR_HANDSHAKE");
   repeat(2)@(negedge clk);
   $fdisplay(file_handle,"D %0d %0d %0d %0d %0d %0d",run_id,k,use_abort,phase_count,pred_count,center_count);
   if(use_abort)begin abort_sync=0;abort_discards=abort_discards+1;end
   else begin rst=0;reset_discards=reset_discards+1;end
   monitor_active=0;repeat(6)@(negedge clk);
   begin_case(k+1);collect74(k+1);finish_case(k+1,7);
  end
 endtask
 task automatic bad_descriptor(input integer corruption,input integer prefix);
  logic [3:0] expected_error;logic [233:0] wanted;
  begin
   begin_case(0);if(prefix)sample(0,0,0);sample(0,prefix,corruption);
   while(!m_valid)@(negedge clk);
   expected_error=(corruption==1 || corruption==5)?4'd1:(corruption==4?4'd3:4'd2);
   wanted={32'd2000,32'h56780000,1'b0,1'b0,expected_error,32'd0,56'd0,64'd0,12'd0};
   if(result_word!==wanted)$fatal(1,"PHASE74_PROTOCOL_ERROR code=%0d",corruption);
   $fdisplay(file_handle,"E %0d 0 %0d %059h",run_id,expected_error,result_word);errors=errors+1;
   m_ready=1;@(posedge clk);#1;@(negedge clk);m_ready=0;monitor_active=0;
  end
 endtask
 initial begin
  $readmemh("phase74_z.mem",z_memory);$readmemh("phase74_angle.mem",angle_memory);$readmemh("phase74_pred.mem",pred_memory);$readmemh("phase74_center.mem",center_memory);$readmemh("phase74_result.mem",result_memory);
  file_handle=$fopen("phase74_actual.txt","w");if(!file_handle)$fatal(1,"PHASE74_FILE_OPEN");
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<PHASE_CASES;i=i+1)begin begin_case(i);collect74(i);finish_case(i,i%9);end
  discard(0,0,0);discard(2,0,1);discard(4,1,0);discard(6,1,1);discard(8,2,0);discard(10,2,1);
  bad_descriptor(1,1);bad_descriptor(2,0);bad_descriptor(3,0);bad_descriptor(4,0);bad_descriptor(5,1);
  repeat(20)@(negedge clk);
  $fclose(file_handle);
  $display("CFO_PHASE74_PASS unique=%0d completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d stalled_cycles=%0d reset_discards=%0d abort_discards=%0d",PHASE_CASES,completed,errors,max_tail,max_total,total_stalls,reset_discards,abort_discards);
  $finish;
 end
endmodule