`timescale 1ns/1ps
module cfo_estimate74_backend_tb;
 `include "backend74_config.svh"
 `include "backend74_div_config.svh"
 logic clk=0;always #3.333 clk=~clk;
 logic rst=1,abort_sync=0,s_valid=0,s_ready,s_last=0,m_valid,m_ready=0;
 logic [31:0] s_frame=0,s_generation=0;logic [6:0] s_index=0;logic signed [37:0] s_i=0,s_q=0;
 wire [31:0] m_frame,m_generation;wire [3:0] m_error;wire [1:0] m_mode;wire m_estimate_valid,m_spectrum,m_phase_linear,m_consistent;
 wire signed [31:0] m_frequency_q16,m_phase_q16,m_fft_q16;
 wire [196:0] m_quality;wire [131:0] m_phase_detail;
 wire normal_audit_valid,fft_audit_valid;wire [6:0] normal_audit_index;wire [7:0] fft_audit_index;wire [39:0] normal_audit_value;wire [79:0] fft_audit_value;
 wire [169:0] result_word={m_frame,m_generation,m_error,m_mode,m_estimate_valid,m_frequency_q16,m_phase_q16,m_fft_q16,m_spectrum,m_phase_linear,m_consistent};
 wire [498:0] all_results={result_word,m_quality,m_phase_detail};
 logic [75:0] z_memory[0:BACKEND_CASES*74-1];logic [39:0] normal_memory[0:BACKEND_CASES*74-1];logic [79:0] fft_memory[0:BACKEND_CASES*256-1];
 logic [169:0] result_memory[0:BACKEND_CASES-1];logic [196:0] quality_memory[0:BACKEND_CASES-1];logic [131:0] phase_memory[0:BACKEND_CASES-1];
 integer cycle=0,run_id=-1,active_case=0,n_count=0,f_count=0,completed=0,errors=0,reset_discards=0,abort_discards=0;
 integer first_cycle,last_input_cycle,total_stalls=0,max_tail=0,max_total=0,file_handle,i,j;
 logic monitor_active=0;
 cfo_estimate74_backend dut(.*);
 // This is the new wider divider, not a repeat of a previous native unit.
 logic v_s_valid=0,v_s_ready,v_m_valid,v_m_ready=0,v_error;logic signed [63:0] v_numerator=0,v_quotient;logic [63:0] v_denominator=0;
 logic [127:0] div_input[0:DIV_CASES-1];logic [64:0] div_output[0:DIV_CASES-1];
 cfo_divide_rne64wide wide_probe(.clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(v_s_valid),.s_ready(v_s_ready),.s_numerator(v_numerator),.s_denominator(v_denominator),.m_valid(v_m_valid),.m_ready(v_m_ready),.m_quotient(v_quotient),.m_error(v_error));
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>750000)$fatal(1,"BACKEND74_CYCLE_TIMEOUT");#1;
  if(!rst&&!abort_sync)begin
   if(!monitor_active&&(normal_audit_valid||fft_audit_valid||m_valid))$fatal(1,"BACKEND74_STALE_OUTPUT");
   if(normal_audit_valid)begin
    if(n_count>=74 || normal_audit_index!=n_count || normal_audit_value!==normal_memory[active_case*74+n_count])$fatal(1,"BACKEND74_NORMAL case=%0d point=%0d",active_case,n_count);
    $fdisplay(file_handle,"N %0d %0d %0d %010h",run_id,active_case,n_count,normal_audit_value);n_count=n_count+1;
   end
   if(fft_audit_valid)begin
    if(f_count>=256 || fft_audit_index!=f_count || fft_audit_value!==fft_memory[active_case*256+f_count])$fatal(1,"BACKEND74_FFT case=%0d point=%0d actual=%h expected=%h",active_case,f_count,fft_audit_value,fft_memory[active_case*256+f_count]);
    $fdisplay(file_handle,"P %0d %0d %0d %020h",run_id,active_case,f_count,fft_audit_value);f_count=f_count+1;
   end
  end
 end
 task automatic begin_case(input integer k);
  begin @(negedge clk);if(!s_ready||m_valid)$fatal(1,"BACKEND74_NOT_READY");active_case=k;run_id=run_id+1;n_count=0;f_count=0;monitor_active=1;first_cycle=cycle;last_input_cycle=cycle;end
 endtask
 task automatic sample(input integer k,input integer n,input integer corruption);
  begin
   @(negedge clk);s_frame=32'd4000+k;s_generation=32'h789a0000+k;s_index=n;s_last=(n==73);{s_i,s_q}=z_memory[k*74+n];
   case(corruption)
    1:s_generation=s_generation^32'd1;2:s_index=n+1;3:s_last=1;4:s_i=38'sh2000000000;5:s_frame=s_frame^32'd1;
   endcase
   s_valid=1;while(!s_ready)begin if(cycle-first_cycle>12000)$fatal(1,"BACKEND74_INPUT_TIMEOUT");@(negedge clk);end
   @(posedge clk);#1;last_input_cycle=cycle;@(negedge clk);s_valid=0;
  end
 endtask
 task automatic collect_input(input integer k);integer n;begin for(n=0;n<74;n=n+1)sample(k,n,0);end endtask
 task automatic finish_case(input integer k,input integer stalls);
  integer tail,total,n;logic [498:0] held;
  begin
   @(negedge clk);while(!m_valid)begin if(cycle-last_input_cycle>7600)$fatal(1,"BACKEND74_TAIL_TIMEOUT case=%0d p_valid=%b q_valid=%b qstate=%0d",k,dut.p_valid,dut.q_valid,dut.quality_core.state);@(negedge clk);end
   tail=cycle-last_input_cycle;held=all_results;
   if(held!=={result_memory[k],quality_memory[k],phase_memory[k]})$fatal(1,"BACKEND74_RESULT case=%0d actual=%h expected=%h",k,held,{result_memory[k],quality_memory[k],phase_memory[k]});
   if(m_mode==3)begin if(n_count!=0||f_count!=0)$fatal(1,"BACKEND74_ZERO_AUDIT");end
   else if(n_count!=74||f_count!=256)$fatal(1,"BACKEND74_NODE_COUNTS");
   for(n=0;n<stalls;n=n+1)begin @(posedge clk);#1;if(!m_valid||all_results!==held)$fatal(1,"BACKEND74_BACKPRESSURE");@(negedge clk);end
   m_ready=1;@(posedge clk);if(!m_valid||all_results!==held)$fatal(1,"BACKEND74_HANDSHAKE");#1;
   @(negedge clk);m_ready=0;total=cycle-first_cycle;
   if(total>12000)$fatal(1,"BACKEND74_TOTAL_TIMEOUT");if(tail>max_tail)max_tail=tail;if(total>max_total)max_total=total;
   total_stalls=total_stalls+stalls;completed=completed+1;
   $fdisplay(file_handle,"F %0d %0d %0125h %0d %0d %0d",run_id,k,held,tail,total,stalls);monitor_active=0;
  end
 endtask
 task automatic drop_case(input integer k,input integer where,input integer use_abort);
  integer n,saved_n,saved_f;
  begin
   begin_case(k);
   if(where==0)begin for(n=0;n<19;n=n+1)sample(k,n,0);end
   else begin
    collect_input(k);
    if(where==1)begin while(n_count<25)@(negedge clk);end
    else if(where==2)begin while(f_count<13)@(negedge clk);end
    else if(where==3)begin while(!dut.quality_core.div_m_ready || dut.quality_core.div_m_valid)@(negedge clk);repeat(12)@(negedge clk);end
    else begin while(!m_valid)@(negedge clk);repeat(2)@(negedge clk);end
   end
   @(negedge clk);saved_n=n_count;saved_f=f_count;if(use_abort!=0)abort_sync=1;else rst=1;s_valid=0;m_ready=0;
   @(posedge clk);#1;if(m_valid||normal_audit_valid||fft_audit_valid)$fatal(1,"BACKEND74_CLEAR");
   @(negedge clk);rst=0;abort_sync=0;monitor_active=0;
   $fdisplay(file_handle,"D %0d %0d %0d %0d %0d %0d",run_id,k,use_abort,where,saved_n,saved_f);
   if(use_abort!=0)abort_discards=abort_discards+1;else reset_discards=reset_discards+1;repeat(4)@(negedge clk);
  end
 endtask
 task automatic error_case(input integer corruption,input integer expected);
  logic [498:0] held;logic [169:0] wanted;integer n;
  begin
   begin_case(0);sample(0,0,0);sample(0,1,corruption);
   @(negedge clk);while(!m_valid)begin if(cycle-first_cycle>1000)$fatal(1,"BACKEND74_ERROR_TIMEOUT");@(negedge clk);end
   wanted={32'd4000,32'h789a0000,expected[3:0],2'd0,1'b0,99'd0};held=all_results;
   if(result_word!==wanted || m_quality!==197'd0 || m_phase_detail!==132'd0 || n_count!=0||f_count!=0)$fatal(1,"BACKEND74_ERROR_DATA");
   for(n=0;n<3;n=n+1)begin @(posedge clk);#1;if(!m_valid||all_results!==held)$fatal(1,"BACKEND74_ERROR_HOLD");@(negedge clk);end
   m_ready=1;@(posedge clk);$fdisplay(file_handle,"E %0d 0 %0d %0125h",run_id,expected,all_results);#1;
   @(negedge clk);m_ready=0;monitor_active=0;errors=errors+1;
  end
 endtask
 task automatic divide_case(input integer k);
  integer start_cycle,n;logic [64:0] held;
  begin
   @(negedge clk);if(!v_s_ready)$fatal(1,"BACKEND74_DIV_READY");{v_numerator,v_denominator}=div_input[k];v_s_valid=1;
   @(posedge clk);#1;start_cycle=cycle;@(negedge clk);v_s_valid=0;
   while(!v_m_valid)begin if(cycle-start_cycle>70)$fatal(1,"BACKEND74_DIV_TIMEOUT");@(negedge clk);end
   held={v_quotient,v_error};if(held!==div_output[k])$fatal(1,"BACKEND74_DIV_VALUE case=%0d",k);
   for(n=0;n<3;n=n+1)begin @(posedge clk);#1;if(!v_m_valid||{v_quotient,v_error}!==held)$fatal(1,"BACKEND74_DIV_HOLD");@(negedge clk);end
   v_m_ready=1;@(posedge clk);$fdisplay(file_handle,"V %0d %017h",k,held);#1;@(negedge clk);v_m_ready=0;
  end
 endtask
 initial begin
  $readmemh("backend74_z.mem",z_memory);$readmemh("backend74_normal.mem",normal_memory);$readmemh("backend74_fft.mem",fft_memory);
  $readmemh("backend74_result.mem",result_memory);$readmemh("backend74_quality.mem",quality_memory);$readmemh("backend74_phase.mem",phase_memory);
  $readmemh("backend74_div_input.mem",div_input);$readmemh("backend74_div_output.mem",div_output);
  if((^z_memory[0]===1'bx)||(^result_memory[BACKEND_CASES-1]===1'bx)||(^fft_memory[BACKEND_CASES*256-1]===1'bx)||(^div_output[DIV_CASES-1]===1'bx))$fatal(1,"BACKEND74_LOAD");
  file_handle=$fopen("backend74_actual.txt","w");if(file_handle==0)$fatal(1,"BACKEND74_FILE");repeat(4)@(negedge clk);rst=0;
  for(i=0;i<DIV_CASES;i=i+1)divide_case(i);
  for(i=0;i<BACKEND_CASES;i=i+1)begin begin_case(i);collect_input(i);finish_case(i,i%7);end
  for(i=0;i<10;i=i+1)begin drop_case(2*i,i/2,i%2);begin_case(2*i+1);collect_input(2*i+1);finish_case(2*i+1,7);end
  error_case(1,1);error_case(2,2);error_case(3,2);error_case(4,3);error_case(5,1);repeat(8)@(negedge clk);
  if(completed!=38||reset_discards!=5||abort_discards!=5||errors!=5||total_stalls!=154)$fatal(1,"BACKEND74_COUNTS");$fclose(file_handle);
  $display("CFO_BACKEND74_PASS unique=%0d completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d stalled_cycles=%0d reset_discards=%0d abort_discards=%0d divider_cases=%0d",BACKEND_CASES,completed,errors,max_tail,max_total,total_stalls,reset_discards,abort_discards,DIV_CASES);$finish;
 end
endmodule