`timescale 1ns/1ps
module cfo_fft256_tb;
 `include "fft256_config.svh"
 logic clk=0;always #3.333 clk=~clk;
 logic rst=1,abort_sync=0,s_valid=0,s_ready,s_last=0,m_valid,m_ready=0;
 logic [31:0] s_frame=0,s_generation=0;logic [7:0] s_index=0;logic signed [19:0] s_i=0,s_q=0;
 wire [31:0] m_frame,m_generation;wire [7:0] m_index;wire m_last;wire signed [19:0] m_i,m_q;wire [12:0] m_saturations;wire [3:0] m_error;
 wire butterfly_audit_valid;wire [2:0] butterfly_audit_stage;wire [6:0] butterfly_audit_index;wire [82:0] butterfly_audit_value;
 wire [129:0] result_word={m_frame,m_generation,m_index,m_last,m_i,m_q,m_saturations,m_error};
 logic [39:0] input_memory[0:FFT_CASES*256-1],output_memory[0:FFT_CASES*256-1];
 logic [82:0] butterfly_memory[0:FFT_CASES*1024-1];logic [12:0] saturation_memory[0:FFT_CASES-1];
 integer cycle=0,run_id=-1,active_case=0,b_count=0,o_count=0,file_handle,i,j;
 integer first_cycle,last_input_cycle,tail_cycle,run_stalls,completed=0,errors=0,reset_discards=0,abort_discards=0,total_stalls=0,max_tail=0,max_total=0;
 logic monitor_active=0;
 cfo_fft256_core dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>500000)$fatal(1,"FFT256_CYCLE_TIMEOUT");
  #1;
  if(!rst && !abort_sync)begin
   if(!monitor_active && (butterfly_audit_valid || m_valid))$fatal(1,"FFT256_STALE_RESULT");
   if(butterfly_audit_valid)begin
    if(b_count>=1024 || butterfly_audit_stage!=(b_count/128) || butterfly_audit_index!=(b_count%128) || butterfly_audit_value!==butterfly_memory[active_case*1024+b_count])$fatal(1,"FFT256_BUTTERFLY case=%0d point=%0d actual=%h wanted=%h",active_case,b_count,butterfly_audit_value,butterfly_memory[active_case*1024+b_count]);
    $fdisplay(file_handle,"B %0d %0d %0d %021h",run_id,active_case,b_count,butterfly_audit_value);b_count=b_count+1;
   end
  end
 end
 task automatic begin_case(input integer k);
  begin
   @(negedge clk);if(!s_ready || m_valid)$fatal(1,"FFT256_NOT_READY");
   active_case=k;run_id=run_id+1;b_count=0;o_count=0;monitor_active=1;first_cycle=cycle;last_input_cycle=cycle;tail_cycle=-1;run_stalls=0;
  end
 endtask
 task automatic sample(input integer k,input integer n,input integer corruption);
  begin
   @(negedge clk);s_frame=32'd3000+k;s_generation=32'h67890000+k;s_index=n;s_last=(n==255);{s_i,s_q}=input_memory[k*256+n];
   case(corruption)
    1:s_frame=s_frame^32'd1;
    2:s_index=n+1;
    3:s_last=1;
    4:s_generation=s_generation^32'd1;
   endcase
   s_valid=1;
   while(!s_ready)begin if(cycle-first_cycle>8000)$fatal(1,"FFT256_INPUT_TIMEOUT");@(negedge clk);end
   @(posedge clk);#1;last_input_cycle=cycle;@(negedge clk);s_valid=0;
  end
 endtask
 task automatic collect_input(input integer k);
  integer n;begin
   if(k%3==0)begin
    for(n=0;n<256;n=n+1)begin
     @(negedge clk);s_valid=1;s_frame=32'd3000+k;s_generation=32'h67890000+k;s_index=n;s_last=(n==255);{s_i,s_q}=input_memory[k*256+n];
     if(!s_ready)$fatal(1,"FFT256_CONTIGUOUS_INPUT_STALL");
     @(posedge clk);#1;last_input_cycle=cycle;
    end
    @(negedge clk);s_valid=0;
   end else for(n=0;n<256;n=n+1)sample(k,n,0);
  end
 endtask
 task automatic output_one(input integer k,input integer n,input integer stalls);
  integer t;logic [129:0] held,wanted;
  begin
   @(negedge clk);
   while(!m_valid)begin if(cycle-last_input_cycle>7000)$fatal(1,"FFT256_OUTPUT_TIMEOUT");@(negedge clk);end
   if(n==0)tail_cycle=cycle-last_input_cycle;
   wanted={32'd3000+k,32'h67890000+k,n[7:0],(n==255),output_memory[k*256+n],saturation_memory[k],4'd0};
   held=result_word;if(held!==wanted || b_count!=1024 || n!=o_count)$fatal(1,"FFT256_OUTPUT case=%0d bin=%0d actual=%h expected=%h",k,n,held,wanted);
   for(t=0;t<stalls;t=t+1)begin
    @(posedge clk);#1;if(!m_valid || result_word!==held)$fatal(1,"FFT256_BACKPRESSURE");@(negedge clk);
   end
   run_stalls=run_stalls+stalls;m_ready=1;@(posedge clk);
   if(!m_valid || result_word!==held)$fatal(1,"FFT256_HANDSHAKE");
   $fdisplay(file_handle,"O %0d %0d %0d %033h",run_id,k,n,held);#1;o_count=o_count+1;@(negedge clk);m_ready=0;
  end
 endtask
 task automatic finish_case(input integer k,input integer extra);
  integer n,stall,total;
  begin
   for(n=0;n<256;n=n+1)begin
    stall=(n%64==0) ? (k%4) : 0;if(n==0)stall=stall+extra;output_one(k,n,stall);
   end
   total=cycle-first_cycle;
   if(tail_cycle>5200 || total>8000 || o_count!=256 || b_count!=1024)$fatal(1,"FFT256_TRANSACTION_LIMIT");
   if(tail_cycle>max_tail)max_tail=tail_cycle;if(total>max_total)max_total=total;
   total_stalls=total_stalls+run_stalls;completed=completed+1;
   $fdisplay(file_handle,"F %0d %0d %0d %0d %0d",run_id,k,tail_cycle,total,run_stalls);monitor_active=0;
  end
 endtask
 task automatic drop_case(input integer k,input integer where,input integer use_abort);
  integer n,save_b,save_o;
  begin
   begin_case(k);
   if(where==0)begin for(n=0;n<19;n=n+1)sample(k,n,0);end
   else begin
    collect_input(k);
    if(where==1)begin while(b_count<401)@(negedge clk);end
    else begin for(n=0;n<13;n=n+1)output_one(k,n,0);end
   end
   @(negedge clk);save_b=b_count;save_o=o_count;
   if(use_abort!=0)abort_sync=1;else rst=1;
   s_valid=0;m_ready=0;@(posedge clk);#1;
   if(m_valid || butterfly_audit_valid)$fatal(1,"FFT256_CLEAR_NOT_EFFECTIVE");
   @(negedge clk);rst=0;abort_sync=0;monitor_active=0;
   $fdisplay(file_handle,"D %0d %0d %0d %0d %0d",run_id,k,use_abort,save_b,save_o);
   if(use_abort!=0)abort_discards=abort_discards+1;else reset_discards=reset_discards+1;
   repeat(4)@(negedge clk);
  end
 endtask
 task automatic error_case(input integer kind,input integer expected_error);
  logic [129:0] wanted,held;
  begin
   begin_case(0);
   if(kind==5)sample(0,0,2);
   else begin sample(0,0,0);sample(0,1,kind);end
   @(negedge clk);if(!m_valid)$fatal(1,"FFT256_ERROR_MISSING");
   wanted={32'd3000,32'h67890000,8'd0,1'b1,40'd0,13'd0,expected_error[3:0]};held=result_word;
   if(held!==wanted || b_count!=0 || o_count!=0)$fatal(1,"FFT256_ERROR_RESULT");
   repeat(3)begin @(posedge clk);#1;if(!m_valid || result_word!==held)$fatal(1,"FFT256_ERROR_HOLD");@(negedge clk);end
   m_ready=1;@(posedge clk);$fdisplay(file_handle,"E %0d 0 %0d %033h",run_id,expected_error,result_word);#1;
   @(negedge clk);m_ready=0;monitor_active=0;errors=errors+1;
  end
 endtask
 initial begin
  $readmemh("fft256_input.mem",input_memory);$readmemh("fft256_output.mem",output_memory);$readmemh("fft256_butterfly.mem",butterfly_memory);$readmemh("fft256_saturation.mem",saturation_memory);
  if((^input_memory[0]===1'bx) || (^output_memory[FFT_CASES*256-1]===1'bx) || (^butterfly_memory[FFT_CASES*1024-1]===1'bx))$fatal(1,"FFT256_VECTOR_LOAD");
  file_handle=$fopen("fft256_actual.txt","w");if(file_handle==0)$fatal(1,"FFT256_OUTPUT_OPEN");
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<FFT_CASES;i=i+1)begin begin_case(i);collect_input(i);finish_case(i,0);end
  for(i=0;i<6;i=i+1)begin drop_case(2*i,i/2,i%2);begin_case(2*i+1);collect_input(2*i+1);finish_case(2*i+1,7);end
  error_case(1,1);error_case(2,2);error_case(3,2);error_case(4,1);error_case(5,2);
  repeat(8)@(negedge clk);
  if(completed!=33 || errors!=5 || reset_discards!=3 || abort_discards!=3 || total_stalls!=246)$fatal(1,"FFT256_COUNTS");
  $fclose(file_handle);
  $display("CFO_FFT256_PASS unique=%0d completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d stalled_cycles=%0d reset_discards=%0d abort_discards=%0d",FFT_CASES,completed,errors,max_tail,max_total,total_stalls,reset_discards,abort_discards);$finish;
 end
endmodule