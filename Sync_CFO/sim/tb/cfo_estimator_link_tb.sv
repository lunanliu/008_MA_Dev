`timescale 1ns/1ps
module cfo_estimator_link_tb;
 `include "link010_config.svh"
 logic clk_fast=0,clk_slow=0,reset_async=1,abort_async=0;
 always #1 clk_fast=~clk_fast;
 initial begin #0.417;forever #3.333 clk_slow=~clk_slow;end
 logic s_valid=0,m_ready=0;wire s_ready,m_valid;
 logic [176:0] source_word=0;
 wire [498:0] backend_word;wire [3:0] link_error,front_error;wire [22:0] sat_sum;
 wire [529:0] result_word={backend_word,link_error,front_error,sat_sum};
 wire [4:0] wc,rc;wire full,empty,overflow,underflow,fb,rb,rv,nv,fv;
 wire [170:0] rw;wire [6:0] ni;wire [7:0] fi;
 cfo_estimator_link dut(
 .clk_fast(clk_fast),.clk_slow(clk_slow),.reset_async(reset_async),.abort_async(abort_async),
 .s_valid(s_valid),.s_ready(s_ready),.s_frame(source_word[176:145]),.s_generation(source_word[144:113]),.s_window(source_word[112:106]),
 .s_z_i(source_word[105:68]),.s_z_q(source_word[67:30]),.s_pilot_count(source_word[29:20]),.s_fft_saturations(source_word[19:4]),.s_front_error(source_word[3:0]),
 .m_valid(m_valid),.m_ready(m_ready),.m_backend_word(backend_word),.m_link_error(link_error),.m_front_error(front_error),.m_fft_saturation_sum(sat_sum),
 .fifo_write_count(wc),.fifo_read_count(rc),.fifo_full(full),.fifo_empty(empty),.fifo_overflow(overflow),.fifo_underflow(underflow),.fast_reset_busy(fb),.slow_reset_busy(rb),
 .read_audit_valid(rv),.read_audit_word(rw),.normal_audit_valid(nv),.normal_audit_index(ni),.fft_audit_valid(fv),.fft_audit_index(fi));
 logic [176:0] inputs[0:LINK_CASES*74-1],error_inputs[0:LINK_ERRORS-1];
 logic [170:0] reads[0:LINK_CASES*74-1],error_reads[0:LINK_ERRORS-1];
 logic [529:0] results[0:LINK_CASES-1],error_results[0:LINK_ERRORS-1];
 integer fd,fc=0,sc=0,rid=-1,ci=0,kind=0,bad_index=0;
 integer nw=0,nr=0,source_stalls=0,first_fc=0,last_read_sc=0,result_fc=0,result_sc=0,highwater=0;
 integer output_fires=0;
 integer completed=0,errors=0,discards=0,max_tail=0,max_total=0,full_runs=0,total_stalls=0;
 integer i,j,k,hold_cycles,tail,total;
 bit active=0,result_seen=0,full_seen=0,output_held=0,input_held=0,fft13_seen=0;
 logic [529:0] held_result;logic [176:0] held_input;
 function automatic [176:0] expected_input(input integer n);
  if(kind!=0 && n==bad_index)expected_input=error_inputs[kind-1];else expected_input=inputs[ci*74+n];
 endfunction
 function automatic [170:0] expected_read(input integer n);
  if(kind!=0 && n==bad_index)expected_read=error_reads[kind-1];else expected_read=reads[ci*74+n];
 endfunction
 function automatic [529:0] expected_result();
  if(kind!=0)expected_result=error_results[kind-1];else expected_result=results[ci];
 endfunction
 always @(posedge clk_fast)begin
  fc=fc+1;
  if(fc>4000000)$fatal(1,"LINK010 overall cycle timeout");
  if(!fb && !reset_async && !abort_async)begin
   if(overflow!==1'b0)$fatal(1,"FIFO overflow or unknown");
   if(wc>18)$fatal(1,"FIFO write count above FWFT capacity");
   if(active)begin
    if(wc>highwater)highwater=wc;
    if(full)full_seen=1;
    if(input_held && (!s_valid || source_word!==held_input))$fatal(1,"Source changed during backpressure");
    input_held=s_valid&&!s_ready;if(input_held)held_input=source_word;
    if(s_valid && !s_ready)source_stalls=source_stalls+1;
    if(s_valid && s_ready)begin
     if(nw>=74 || source_word!==expected_input(nw))$fatal(1,"Input word mismatch run=%0d index=%0d",rid,nw);
     if(nw==0)first_fc=fc;
     $fdisplay(fd,"W %0d %0d %0d %045h",rid,ci,nw,source_word);nw=nw+1;
    end
   end
  end else input_held=0;
 end
 always @(posedge clk_slow)begin
  if(!rb && !reset_async && !abort_async)begin
   if(output_held && (!m_valid || result_word!==held_result))$fatal(1,"Held result changed at retirement edge");
   if(m_valid && m_ready)begin
    if(!active || result_word!==expected_result() || output_fires!=0)$fatal(1,"Invalid or duplicate output retirement");
    output_fires=output_fires+1;$fdisplay(fd,"H %0d %0d %0133h",rid,ci,result_word);
   end
  end
  sc=sc+1;#0.010;
  if(!rb && !reset_async && !abort_async)begin
   if(underflow!==1'b0)$fatal(1,"FIFO underflow or unknown");
   if(active)begin
    if(rv)begin
     if(nr>=nw || nr>=74 || rw!==expected_read(nr))$fatal(1,"CDC packet mismatch run=%0d index=%0d got=%043h expected=%043h",rid,nr,rw,expected_read(nr));
     $fdisplay(fd,"R %0d %0d %0d %043h",rid,ci,nr,rw);nr=nr+1;last_read_sc=sc;
    end
    if(fv && fi==13)fft13_seen=1;
    if(output_held && !m_ready && !m_valid)$fatal(1,"Result withdrawn under backpressure");
    if(output_held && m_valid && result_word!==held_result)$fatal(1,"Result changed under backpressure");
    if(m_valid)begin
     if(result_word!==expected_result())$fatal(1,"Result mismatch run=%0d got=%0133h expected=%0133h",rid,result_word,expected_result());
     if(s_ready)$fatal(1,"Producer admitted second frame before result release");
     if(!result_seen)begin result_seen=1;result_fc=fc;result_sc=sc;end
    end
    output_held=m_valid&&!m_ready;if(output_held)held_result=result_word;
   end else if(m_valid)$fatal(1,"Unexpected stale output outside active frame");
  end else output_held=0;
 end
 task automatic begin_run(input integer c,input integer e);
  begin
   @(negedge clk_fast);while(!s_ready || rb)@(negedge clk_fast);
   if(m_valid)$fatal(1,"Output present at frame start");
   rid=rid+1;ci=c;kind=e;bad_index=(e==4 || e==5)?0:6;
   nw=0;nr=0;output_fires=0;source_stalls=0;first_fc=0;last_read_sc=0;result_seen=0;full_seen=0;highwater=0;fft13_seen=0;output_held=0;input_held=0;active=1;
  end
 endtask
 task automatic send_word(input integer n);
  begin
   @(negedge clk_fast);source_word=expected_input(n);s_valid=1;
   @(posedge clk_fast);while(!s_ready)@(posedge clk_fast);
   @(negedge clk_fast);s_valid=0;
  end
 endtask
 task automatic send_count(input integer n,input integer interval_cycles);
  integer a,deadline;
  begin
   deadline=fc;
   for(a=0;a<n;a=a+1)begin
    if(interval_cycles!=0)while(fc<deadline)@(negedge clk_fast);
    send_word(a);deadline=first_fc+(a+1)*interval_cycles-1;
   end
  end
 endtask
 task automatic finish_run(input integer pacing);
  integer h,t,u,limit;
  begin
   @(negedge clk_slow);while(!m_valid)@(negedge clk_slow);
   h=5+(rid%4);
   repeat(h)begin @(negedge clk_slow);if(!m_valid || result_word!==expected_result())$fatal(1,"Hold failed");end
   t=result_sc-last_read_sc;u=result_fc-first_fc;
   if(kind==0)begin
    if(nw!=74 || nr!=74 || t<1 || t>7800)$fatal(1,"Normal counts/tail failed");
    limit=pacing?1170000:45000;if(u<1 || u>limit)$fatal(1,"Total service failed %0d",u);
    if(pacing && source_stalls!=0)$fatal(1,"Paced input unexpectedly backpressured");
    if(!pacing && (!full_seen || source_stalls==0))$fatal(1,"Burst case failed to exercise FIFO backpressure");
    $fdisplay(fd,"F %0d %0d %0133h %0d %0d %0d %0d %0d %0d %0d",rid,ci,result_word,t,u,source_stalls,full_seen,highwater,h,pacing);
    if(t>max_tail)max_tail=t;if(u>max_total)max_total=u;
    if(full_seen)full_runs=full_runs+1;total_stalls=total_stalls+source_stalls;
   end else begin
    if(nw!=bad_index+1 || nr!=bad_index+1 || t<0 || t>4)$fatal(1,"Error counts/tail failed");
    $fdisplay(fd,"E %0d %0d %0d %0133h %0d %0d %0d",rid,ci,kind,result_word,nw,nr,h);
   end
   m_ready=1;@(negedge clk_slow);m_ready=0;
   if(output_fires!=1)$fatal(1,"Result was not retired");
   if(kind==0)completed=completed+1;else errors=errors+1;
   active=0;output_held=0;
   repeat(4)@(negedge clk_fast);
  end
 endtask
 task automatic cancel_run(input integer how,input integer where_at);
  begin
   #0.231;
   if(how==0)reset_async=1;else abort_async=1;
   s_valid=0;m_ready=0;
   $fdisplay(fd,"D %0d %0d %0d %0d %0d %0d",rid,ci,how,where_at,nw,nr);discards=discards+1;
   active=0;input_held=0;output_held=0;
   #50.117;reset_async=0;abort_async=0;
   @(negedge clk_fast);while(fb || rb)@(negedge clk_fast);
   repeat(8)@(negedge clk_slow);
   if(m_valid || !empty)$fatal(1,"Cancel left stale packet/result");
  end
 endtask
 initial begin
  $readmemh("link010_input.mem",inputs);$readmemh("link010_read.mem",reads);$readmemh("link010_result.mem",results);
  $readmemh("link010_error_input.mem",error_inputs);$readmemh("link010_error_read.mem",error_reads);$readmemh("link010_error_result.mem",error_results);
  fd=$fopen("link010_actual.txt","w");if(fd==0)$fatal(1,"Cannot open trace");
  #200.231;reset_async=0;
  for(i=0;i<LINK_CASES;i=i+1)begin begin_run(i,0);send_count(74,(i==0)?15448:0);finish_run(i==0);end
  for(i=0;i<8;i=i+1)begin
   begin_run(0,0);
   case(i/2)
    0:begin send_count(24,0);if(nw<=nr)$fatal(1,"Queue cancel must have queued packets");end
    1:begin send_count(13,0);@(negedge clk_slow);while(nr<13)@(negedge clk_slow);if(!empty)$fatal(1,"Partial backend cancel must drain FIFO");end
    2:begin send_count(74,0);@(negedge clk_slow);while(!fft13_seen)@(negedge clk_slow);end
    3:begin send_count(74,0);@(negedge clk_slow);while(!m_valid)@(negedge clk_slow);repeat(5)@(negedge clk_slow);end
   endcase
   cancel_run(i%2,i/2);
   begin_run((i+1)%LINK_CASES,0);send_count(74,0);finish_run(0);
  end
  for(i=1;i<=LINK_ERRORS;i=i+1)begin
   begin_run(0,i);send_count(bad_index+1,0);finish_run(0);
   begin_run((i-1)%LINK_CASES,0);send_count(74,0);finish_run(0);
  end
  if(completed!=22 || errors!=10 || discards!=8 || full_runs!=21 || total_stalls==0)$fatal(1,"Coverage incomplete");
  $fclose(fd);
  $display("CFO_LINK010_PASS unique=4 completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d source_stalls=%0d full_runs=%0d reset_discards=4 abort_discards=4",completed,errors,max_tail,max_total,total_stalls,full_runs);$finish;
 end
endmodule