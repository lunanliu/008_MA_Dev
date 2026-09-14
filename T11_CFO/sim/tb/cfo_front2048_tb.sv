`timescale 1ns/1ps
module cfo_front2048_tb;
 `include "front2048_config.svh"
 logic clk=0;always #1 clk=~clk;
 logic rst=1,abort_sync=0,s_valid=0,s_ready,s_last=0,m_valid,m_ready=0;
 logic [31:0] s_frame=0,s_generation=0;logic [6:0] s_window=0;logic [10:0] s_index=0;logic signed [25:0] s_i=0,s_q=0;
 wire [31:0] m_frame,m_generation;wire [6:0] m_window;wire signed [37:0] m_z_i,m_z_q;wire [9:0] m_pilot_count;wire [15:0] m_fft_saturations;wire [3:0] m_error;
 wire pilot_audit_valid;wire [9:0] pilot_audit_index;wire [143:0] pilot_audit_value;
 wire fft_butterfly_audit_valid;wire [3:0] fft_butterfly_audit_stage;wire [9:0] fft_butterfly_audit_index;
 wire [176:0] result_word={m_frame,m_generation,m_window,m_z_i,m_z_q,m_pilot_count,m_fft_saturations,m_error};
 logic [51:0] input_memory[0:FRONT_CASES*2048-1];logic [143:0] pilot_memory[0:FRONT_CASES*820-1];logic [176:0] result_memory[0:FRONT_CASES-1];logic [70:0] metadata_memory[0:FRONT_CASES-1];
 integer cycle=0,run_id=-1,active_case=0,b_count=0,p_count=0,file_handle,i,j;
 integer first_cycle,last_input_cycle,run_stalls,input_gaps,completed=0,errors=0,reset_discards=0,abort_discards=0,total_stalls=0,max_tail=0,max_total=0,max_adjusted=0,previous_p_cycle=-1;
 logic monitor_active=0;
 cfo_front2048_window dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>3000000)$fatal(1,"FRONT2048_CYCLE_TIMEOUT");
  #0.1;
  if(!rst && !abort_sync)begin
   if(!monitor_active && (fft_butterfly_audit_valid || pilot_audit_valid || m_valid))$fatal(1,"FRONT2048_STALE_RESULT");
   if(fft_butterfly_audit_valid)begin
    if(b_count>=11264 || fft_butterfly_audit_stage!=(b_count/1024) || fft_butterfly_audit_index!=(b_count%1024))$fatal(1,"FRONT2048_FFT_SEQUENCE");
    if(b_count==0)$display("CFO_FRONT2048_PROGRESS run=%0d case=%0d stage=FFT accepted_in=2048 pilots=0 cycle=%0d simtime=%0t",run_id,active_case,cycle,$time);
    b_count=b_count+1;
   end
   if(pilot_audit_valid)begin
    if(p_count>=820 || b_count!=11264 || pilot_audit_index!=p_count || pilot_audit_value!==pilot_memory[active_case*820+p_count])$fatal(1,"FRONT2048_PILOT case=%0d point=%0d actual=%h wanted=%h",active_case,p_count,pilot_audit_value,pilot_memory[active_case*820+p_count]);
    if(p_count>0 && cycle-previous_p_cycle!=((p_count==410)?408:2))$fatal(1,"FRONT2048_PILOT_SPACING");
    if(p_count==0 || p_count==819)$display("CFO_FRONT2048_PROGRESS run=%0d case=%0d stage=PILOT accepted_in=2048 pilots=%0d cycle=%0d simtime=%0t",run_id,active_case,p_count+1,cycle,$time);
    $fdisplay(file_handle,"P %0d %0d %0d %036h",run_id,active_case,p_count,pilot_audit_value);p_count=p_count+1;previous_p_cycle=cycle;
   end
  end
 end
 task automatic begin_case(input integer k);
  begin
   @(negedge clk);if(!s_ready || m_valid)$fatal(1,"FRONT2048_NOT_READY");
   active_case=k;run_id=run_id+1;b_count=0;p_count=0;monitor_active=1;first_cycle=cycle;last_input_cycle=cycle;run_stalls=0;input_gaps=0;previous_p_cycle=-1;
  end
 endtask
 task automatic drive_sample(input integer k,input integer n,input integer corruption);
  begin
   {s_frame,s_generation,s_window}=metadata_memory[k];s_index=n;s_last=(n==2047);{s_i,s_q}=input_memory[k*2048+n];
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
   @(negedge clk);drive_sample(k,n,corruption);if(!s_ready)$fatal(1,"FRONT2048_INPUT_NOT_READY");
   @(posedge clk);#0.1;last_input_cycle=cycle;@(negedge clk);s_valid=0;
  end
 endtask
 task automatic collect_input(input integer k);
  integer n;begin
   for(n=0;n<2048;n=n+1)begin
    @(negedge clk);drive_sample(k,n,0);if(!s_ready)$fatal(1,"FRONT2048_CONTIGUOUS_INPUT_STALL");
    @(posedge clk);#0.1;last_input_cycle=cycle;
    if(k%3!=0 && n<2047)begin @(negedge clk);s_valid=0;input_gaps=input_gaps+1;end
   end
   @(negedge clk);s_valid=0;
  end
 endtask
 task automatic await_result;
  begin
   while(!m_valid)begin if(cycle-last_input_cycle>13500)$fatal(1,"FRONT2048_RESULT_TIMEOUT");@(negedge clk);end
  end
 endtask
 task automatic finish_case(input integer k,input integer extra);
  integer t,tail,total,adjusted;logic [176:0] held;
  begin
   await_result();tail=cycle-last_input_cycle;held=result_word;
   if(held!==result_memory[k] || b_count!=11264 || p_count!=820)$fatal(1,"FRONT2048_RESULT case=%0d actual=%h wanted=%h",k,held,result_memory[k]);
   run_stalls=k%5+extra;
   for(t=0;t<run_stalls;t=t+1)begin @(posedge clk);#0.1;if(!m_valid || result_word!==held || s_ready)$fatal(1,"FRONT2048_BACKPRESSURE");@(negedge clk);end
   m_ready=1;@(posedge clk);if(!m_valid || result_word!==held)$fatal(1,"FRONT2048_HANDSHAKE");#0.1;
   @(negedge clk);m_ready=0;total=cycle-first_cycle;adjusted=total-input_gaps-run_stalls;
   if(tail>13500 || adjusted>15600 || total>19000)$fatal(1,"FRONT2048_TRANSACTION_LIMIT tail=%0d total=%0d adjusted=%0d",tail,total,adjusted);
   if(tail>max_tail)max_tail=tail;if(total>max_total)max_total=total;if(adjusted>max_adjusted)max_adjusted=adjusted;
   total_stalls=total_stalls+run_stalls;completed=completed+1;
   $fdisplay(file_handle,"Z %0d %0d %045h %0d %0d %0d %0d %0d",run_id,k,held,tail,total,run_stalls,input_gaps,adjusted);monitor_active=0;
  end
 endtask
 task automatic drop_case(input integer k,input integer where,input integer use_abort);
  integer n,save_b,save_p;
  begin
   begin_case(k);
   if(where==0)begin for(n=0;n<19;n=n+1)one_input(k,n,0);end
   else begin
    collect_input(k);
    if(where==1)begin while(b_count<1401)@(negedge clk);end
    else if(where==2)begin while(p_count<13)@(negedge clk);end
    else begin await_result();repeat(3)@(negedge clk);end
   end
   @(negedge clk);save_b=b_count;save_p=p_count;
   if(use_abort!=0)abort_sync=1;else rst=1;s_valid=0;m_ready=0;
   @(posedge clk);#0.1;if(m_valid || fft_butterfly_audit_valid || pilot_audit_valid)$fatal(1,"FRONT2048_CLEAR_NOT_EFFECTIVE");
   @(negedge clk);rst=0;abort_sync=0;monitor_active=0;
   $fdisplay(file_handle,"D %0d %0d %0d %0d %0d %0d",run_id,k,use_abort,where,save_b,save_p);
   if(use_abort!=0)abort_discards=abort_discards+1;else reset_discards=reset_discards+1;repeat(4)@(negedge clk);
  end
 endtask
 task automatic error_case(input integer kind,input integer expected_error);
  logic [176:0] wanted,held;logic [70:0] meta;
  begin
   begin_case(0);meta=metadata_memory[0];
   if(kind==5)one_input(0,0,2);
   else if(kind==7)begin one_input(0,0,7);meta[6:0]=74;end
   else begin one_input(0,0,0);one_input(0,1,kind);end
   @(negedge clk);await_result();wanted={meta,76'd0,10'd0,16'd0,expected_error[3:0]};held=result_word;
   if(held!==wanted || b_count!=0 || p_count!=0)$fatal(1,"FRONT2048_ERROR_RESULT");
   repeat(3)begin @(posedge clk);#0.1;if(!m_valid || result_word!==held)$fatal(1,"FRONT2048_ERROR_HOLD");@(negedge clk);end
   m_ready=1;@(posedge clk);$fdisplay(file_handle,"E %0d 0 %0d %045h",run_id,expected_error,result_word);#0.1;
   @(negedge clk);m_ready=0;monitor_active=0;errors=errors+1;
  end
 endtask
 initial begin
  $readmemh("front2048_input.mem",input_memory);$readmemh("front2048_pilot.mem",pilot_memory);$readmemh("front2048_result.mem",result_memory);$readmemh("front2048_metadata.mem",metadata_memory);
  for(j=0;j<FRONT_CASES*2048;j=j+1)if(^input_memory[j]===1'bx)$fatal(1,"FRONT2048_VECTOR_LOAD_IQ");
  for(j=0;j<FRONT_CASES*820;j=j+1)if(^pilot_memory[j]===1'bx)$fatal(1,"FRONT2048_VECTOR_LOAD_P");
  for(j=0;j<FRONT_CASES;j=j+1)if((^result_memory[j]===1'bx) || (^metadata_memory[j]===1'bx))$fatal(1,"FRONT2048_VECTOR_LOAD_METADATA");
  file_handle=$fopen("front2048_actual.txt","w");if(file_handle==0)$fatal(1,"FRONT2048_OUTPUT_OPEN");
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<FRONT_CASES;i=i+1)begin begin_case(i);collect_input(i);finish_case(i,0);end
  for(i=0;i<8;i=i+1)begin drop_case(2*i,i/2,i%2);begin_case(2*i+1);collect_input(2*i+1);finish_case(2*i+1,7);end
  error_case(1,1);error_case(2,2);error_case(3,2);error_case(4,1);error_case(5,2);error_case(6,1);error_case(7,3);
  repeat(8)@(negedge clk);
  if(completed!=98 || errors!=7 || reset_discards!=4 || abort_discards!=4 || total_stalls!=250)$fatal(1,"FRONT2048_COUNTS");
  $fclose(file_handle);
  $display("CFO_FRONT2048_PASS unique=%0d completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d max_adjusted=%0d stalled_cycles=%0d reset_discards=%0d abort_discards=%0d",FRONT_CASES,completed,errors,max_tail,max_total,max_adjusted,total_stalls,reset_discards,abort_discards);$finish;
 end
endmodule