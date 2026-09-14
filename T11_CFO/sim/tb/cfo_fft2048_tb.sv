`timescale 1ns/1ps
module cfo_fft2048_tb;
 `include "fft2048_config.svh"
 logic clk=0;always #1 clk=~clk;
 logic rst=1,abort_sync=0,s_valid=0,s_ready,s_last=0,m_valid,m_ready=0;
 logic [31:0] s_frame=0,s_generation=0;logic [6:0] s_window=0;logic [10:0] s_index=0;logic signed [25:0] s_i=0,s_q=0;
 wire [31:0] m_frame,m_generation;wire [6:0] m_window;wire [10:0] m_index;wire m_last;wire signed [25:0] m_i,m_q;wire [15:0] m_saturations;wire [3:0] m_error;
 wire butterfly_audit_valid;wire [3:0] butterfly_audit_stage;wire [9:0] butterfly_audit_index;wire [106:0] butterfly_audit_value;
 wire [154:0] result_word={m_frame,m_generation,m_window,m_index,m_last,m_i,m_q,m_saturations,m_error};
 logic [51:0] input_memory[0:FFT_CASES*2048-1],output_memory[0:FFT_CASES*2048-1];
 logic [106:0] butterfly_memory[0:FFT_CASES*11264-1];logic [15:0] saturation_memory[0:FFT_CASES-1];logic [6:0] window_memory[0:FFT_CASES-1];
 integer cycle=0,run_id=-1,active_case=0,b_count=0,o_count=0,file_handle,i,j;
 integer first_cycle,last_input_cycle,tail_cycle,run_stalls,input_gaps,completed=0,errors=0,reset_discards=0,abort_discards=0,total_stalls=0,max_tail=0,max_total=0,max_adjusted=0,previous_b_cycle=-1;
 logic monitor_active=0;
 cfo_fft2048_core dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>1000000)$fatal(1,"FFT2048_CYCLE_TIMEOUT");
  #0.1;
  if(!rst && !abort_sync)begin
   if(!monitor_active && (butterfly_audit_valid || m_valid))$fatal(1,"FFT2048_STALE_RESULT");
   if(butterfly_audit_valid)begin
    if(b_count>=11264 || butterfly_audit_stage!=(b_count/1024) || butterfly_audit_index!=(b_count%1024) || butterfly_audit_value!==butterfly_memory[active_case*11264+b_count])$fatal(1,"FFT2048_BUTTERFLY case=%0d point=%0d actual=%h wanted=%h",active_case,b_count,butterfly_audit_value,butterfly_memory[active_case*11264+b_count]);
    if(b_count%1024!=0 && cycle-previous_b_cycle!=1)$fatal(1,"FFT2048_BUTTERFLY_II_NOT_ONE");
    if(b_count>0 && b_count%1024==0 && cycle-previous_b_cycle!=8)$fatal(1,"FFT2048_STAGE_DRAIN");
    if(b_count%1024==0)$display("CFO_FFT2048_PROGRESS run=%0d case=%0d stage=%0d accepted_in=2048 accepted_out=%0d cycle=%0d simtime=%0t",run_id,active_case,b_count/1024,o_count,cycle,$time);
    $fdisplay(file_handle,"B %0d %0d %0d %027h",run_id,active_case,b_count,butterfly_audit_value);b_count=b_count+1;previous_b_cycle=cycle;
   end
  end
 end
 task automatic begin_case(input integer k);
  begin
   @(negedge clk);if(!s_ready || m_valid)$fatal(1,"FFT2048_NOT_READY");
   active_case=k;run_id=run_id+1;b_count=0;o_count=0;monitor_active=1;first_cycle=cycle;last_input_cycle=cycle;tail_cycle=-1;run_stalls=0;input_gaps=0;previous_b_cycle=-1;
  end
 endtask
 task automatic drive_sample(input integer k,input integer n,input integer corruption);
  begin
   s_frame=32'd5000+k;s_generation=32'h89ab0000+k;s_window=window_memory[k];s_index=n;s_last=(n==2047);{s_i,s_q}=input_memory[k*2048+n];
   case(corruption)
    1:s_frame=s_frame^32'd1;
    2:s_index=n+1;
    3:s_last=1;
    4:s_generation=s_generation^32'd1;
    6:s_window=s_window^7'd1;
    7:s_window=74;
   endcase
   s_valid=1;
  end
 endtask
 task automatic one_input(input integer k,input integer n,input integer corruption);
  begin
   @(negedge clk);drive_sample(k,n,corruption);if(!s_ready)$fatal(1,"FFT2048_INPUT_NOT_READY");
   @(posedge clk);#0.1;last_input_cycle=cycle;@(negedge clk);s_valid=0;
  end
 endtask
 task automatic collect_input(input integer k);
  integer n;begin
   for(n=0;n<2048;n=n+1)begin
    @(negedge clk);drive_sample(k,n,0);
    if(!s_ready)$fatal(1,"FFT2048_CONTIGUOUS_INPUT_STALL");
    @(posedge clk);#0.1;last_input_cycle=cycle;
    if(k%3!=0 && n<2047)begin @(negedge clk);s_valid=0;input_gaps=input_gaps+1;end
   end
   @(negedge clk);s_valid=0;
  end
 endtask
 task automatic output_one(input integer k,input integer n,input integer stalls);
  integer t;logic [154:0] held,wanted;
  begin
   // Caller is on a falling edge; keep accepted successive outputs one cycle apart.
   m_ready=0;
   if(n!=0 && !m_valid)$fatal(1,"FFT2048_OUTPUT_II_NOT_ONE");
   while(!m_valid)begin if(cycle-last_input_cycle>11500)$fatal(1,"FFT2048_OUTPUT_TIMEOUT");@(negedge clk);end
   if(n==0)tail_cycle=cycle-last_input_cycle;
   wanted={32'd5000+k,32'h89ab0000+k,window_memory[k],n[10:0],(n==2047),output_memory[k*2048+n],saturation_memory[k],4'd0};
   held=result_word;if(held!==wanted || b_count!=11264 || n!=o_count)$fatal(1,"FFT2048_OUTPUT case=%0d bin=%0d actual=%h wanted=%h",k,n,held,wanted);
   for(t=0;t<stalls;t=t+1)begin
    @(posedge clk);#0.1;if(!m_valid || result_word!==held)$fatal(1,"FFT2048_BACKPRESSURE");@(negedge clk);
   end
   run_stalls=run_stalls+stalls;m_ready=1;@(posedge clk);
   if(!m_valid || result_word!==held)$fatal(1,"FFT2048_HANDSHAKE");
   $fdisplay(file_handle,"O %0d %0d %0d %039h",run_id,k,n,held);#0.1;o_count=o_count+1;@(negedge clk);m_ready=0;
  end
 endtask
 task automatic finish_case(input integer k,input integer extra);
  integer n,stall,total,adjusted;
  begin
   for(n=0;n<2048;n=n+1)begin
    stall=(n%512==0) ? (k%4) : 0;if(n==0)stall=stall+extra;output_one(k,n,stall);
   end
   total=cycle-first_cycle;adjusted=total-input_gaps-run_stalls;
   if(tail_cycle>11450 || adjusted>15550 || total>19000 || o_count!=2048 || b_count!=11264)$fatal(1,"FFT2048_TRANSACTION_LIMIT tail=%0d total=%0d adjusted=%0d",tail_cycle,total,adjusted);
   if(tail_cycle>max_tail)max_tail=tail_cycle;if(total>max_total)max_total=total;if(adjusted>max_adjusted)max_adjusted=adjusted;
   total_stalls=total_stalls+run_stalls;completed=completed+1;
   $fdisplay(file_handle,"F %0d %0d %0d %0d %0d %0d %0d",run_id,k,tail_cycle,total,run_stalls,input_gaps,adjusted);monitor_active=0;
  end
 endtask
 task automatic drop_case(input integer k,input integer where,input integer use_abort);
  integer n,save_b,save_o;
  begin
   begin_case(k);
   if(where==0)begin for(n=0;n<19;n=n+1)one_input(k,n,0);end
   else begin
    collect_input(k);
    if(where==1)begin while(b_count<1401)@(negedge clk);end
    else begin for(n=0;n<13;n=n+1)output_one(k,n,0);end
   end
   @(negedge clk);save_b=b_count;save_o=o_count;
   if(use_abort!=0)abort_sync=1;else rst=1;
   s_valid=0;m_ready=0;@(posedge clk);#0.1;
   if(m_valid || butterfly_audit_valid)$fatal(1,"FFT2048_CLEAR_NOT_EFFECTIVE");
   @(negedge clk);rst=0;abort_sync=0;monitor_active=0;
   $fdisplay(file_handle,"D %0d %0d %0d %0d %0d %0d",run_id,k,use_abort,where,save_b,save_o);
   if(use_abort!=0)abort_discards=abort_discards+1;else reset_discards=reset_discards+1;
   repeat(4)@(negedge clk);
  end
 endtask
 task automatic error_case(input integer kind,input integer expected_error);
  logic [154:0] wanted,held;logic [6:0] expected_window;
  begin
   begin_case(0);expected_window=window_memory[0];
   if(kind==5)one_input(0,0,2);
   else if(kind==7)begin one_input(0,0,7);expected_window=74;end
   else begin one_input(0,0,0);one_input(0,1,kind);end
   @(negedge clk);if(!m_valid)$fatal(1,"FFT2048_ERROR_MISSING");
   wanted={32'd5000,32'h89ab0000,expected_window,11'd0,1'b1,52'd0,16'd0,expected_error[3:0]};held=result_word;
   if(held!==wanted || b_count!=0 || o_count!=0)$fatal(1,"FFT2048_ERROR_RESULT");
   repeat(3)begin @(posedge clk);#0.1;if(!m_valid || result_word!==held)$fatal(1,"FFT2048_ERROR_HOLD");@(negedge clk);end
   m_ready=1;@(posedge clk);$fdisplay(file_handle,"E %0d 0 %0d %039h",run_id,expected_error,result_word);#0.1;
   @(negedge clk);m_ready=0;monitor_active=0;errors=errors+1;
  end
 endtask
 initial begin
  $readmemh("fft2048_input.mem",input_memory);$readmemh("fft2048_output.mem",output_memory);$readmemh("fft2048_butterfly.mem",butterfly_memory);$readmemh("fft2048_saturation.mem",saturation_memory);$readmemh("fft2048_window.mem",window_memory);
  for(j=0;j<FFT_CASES*2048;j=j+1)if((^input_memory[j]===1'bx) || (^output_memory[j]===1'bx))$fatal(1,"FFT2048_VECTOR_LOAD_IQ");
  for(j=0;j<FFT_CASES*11264;j=j+1)if(^butterfly_memory[j]===1'bx)$fatal(1,"FFT2048_VECTOR_LOAD_B");
  for(j=0;j<FFT_CASES;j=j+1)if((^saturation_memory[j]===1'bx) || (^window_memory[j]===1'bx))$fatal(1,"FFT2048_VECTOR_LOAD_METADATA");
  file_handle=$fopen("fft2048_actual.txt","w");if(file_handle==0)$fatal(1,"FFT2048_OUTPUT_OPEN");
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<FFT_CASES;i=i+1)begin begin_case(i);collect_input(i);finish_case(i,0);end
  for(i=0;i<6;i=i+1)begin drop_case(2*i,i/2,i%2);begin_case(2*i+1);collect_input(2*i+1);finish_case(2*i+1,7);end
  error_case(1,1);error_case(2,2);error_case(3,2);error_case(4,1);error_case(5,2);error_case(6,1);error_case(7,3);
  repeat(8)@(negedge clk);
  if(completed!=26 || errors!=7 || reset_discards!=3 || abort_discards!=3 || total_stalls!=210)$fatal(1,"FFT2048_COUNTS");
  $fclose(file_handle);
  $display("CFO_FFT2048_PASS unique=%0d completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d max_adjusted=%0d stalled_cycles=%0d reset_discards=%0d abort_discards=%0d",FFT_CASES,completed,errors,max_tail,max_total,max_adjusted,total_stalls,reset_discards,abort_discards);$finish;
 end
endmodule