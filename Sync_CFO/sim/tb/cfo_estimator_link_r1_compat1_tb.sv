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
 // LINK010R1 passive reset audit. No stimulus or numerical trace is changed.
 // Q packed bits: 31 common,30 reset_async,29 abort_async,28 rst_fast,
 // 27 rst_slow,26 fifo_reset,25 wr_busy,24 rd_busy,23 fb,22 rb,21 empty,
 // 20 seen,19 done,18 done_slow,17 slow_ready,16 ready_fast,15 write_fire,
 // 14 read_fire,13 s_valid,12 s_ready,11 m_valid,10 m_ready,9 closed_fast,
 // 8 done_toggle,7 done_sync,6 done_seen,5 backend_input_valid,4 b_valid,
 // 3 b_ready,2 full,1 overflow,0 underflow. Binary text preserves X/Z.
 wire [31:0] reset_audit_bits={
  dut.common_reset,reset_async,abort_async,dut.rst_fast,dut.rst_slow,
  dut.fifo_reset,dut.wr_busy,dut.rd_busy,fb,rb,empty,
  dut.fifo_reset_seen,dut.fifo_reset_done,dut.fifo_reset_done_slow,
  dut.slow_reset_ready,dut.slow_reset_ready_fast,dut.write_fire,dut.read_fire,
  s_valid,s_ready,m_valid,m_ready,dut.closed_fast,
  dut.done_toggle,dut.done_sync,dut.done_seen,dut.backend_input_valid,
  dut.b_valid,dut.b_ready,full,overflow,underflow};
 integer reset_audit_fd=0,reset_audit_epoch=0,reset_audit_rows=0;
 integer reset_audit_assertions=1,reset_audit_fifo_assertions=0;
 integer reset_audit_fifo_deassertions=0,reset_audit_recoveries=0;
 integer reset_audit_fast_samples=0,reset_audit_slow_samples=0;
 integer reset_audit_fast_tail=16,reset_audit_slow_tail=16;
 integer reset_audit_recovered_epoch=-1;
 integer reset_audit_ep_assert[0:8],reset_audit_ep_deassert[0:8];
 integer reset_audit_ep_recovery[0:8];
 bit reset_audit_enabled=0;
 logic reset_audit_previous_fifo=1'b1;
 longint reset_audit_last_fast_ps=-1,reset_audit_last_fifo_ps=-1,reset_audit_common_change_ps=-1;
 function automatic longint reset_audit_ps();
  reset_audit_ps=longint'($realtime / 1ps);
 endfunction
 task automatic reset_audit_fail(input string reason);
  begin
   $fdisplay(reset_audit_fd,"X %0d %0d %s",reset_audit_ps(),reset_audit_epoch,reason);
   $fflush(reset_audit_fd);
   $fatal(1,"LINK010R1 reset audit: %s",reason);
  end
 endtask
 task automatic reset_audit_check_async();
  begin
   if(dut.common_reset!==1'b1 || s_ready!==1'b0 || dut.write_fire!==1'b0 ||
      dut.read_fire!==1'b0 || m_valid!==1'b0)
    reset_audit_fail("Common reset did not block all IO within 10 ps");
  end
 endtask
 task automatic reset_audit_sample(input longint edge_ps,input longint sample_ps,
  input integer epoch,input string domain_name,input string phase_name,
  input bit common_changed,input logic [31:0] bits);
  begin
   $fdisplay(reset_audit_fd,"Q %0d %0d %0d %s %s %0d %032b",
    edge_ps,sample_ps,epoch,domain_name,phase_name,common_changed,bits);
   reset_audit_rows=reset_audit_rows+1;
  end
 endtask
 // #1step samples before the clock event, including when an asynchronous
 // request happens at that same timestamp. Never read these in Active region.
 clocking reset_audit_fast_cb @(posedge clk_fast);
  default input #1step;
  input reset_audit_bits;
  input reset_audit_epoch;
 endclocking
 clocking reset_audit_slow_cb @(posedge clk_slow);
  default input #1step;
  input reset_audit_bits;
  input reset_audit_epoch;
 endclocking
 always @(posedge clk_fast)reset_audit_last_fast_ps=reset_audit_ps();
 always @(dut.common_reset)reset_audit_common_change_ps=reset_audit_ps();
 initial begin : reset_audit_initial
  integer n;
  for(n=0;n<9;n=n+1)begin
   reset_audit_ep_assert[n]=0;reset_audit_ep_deassert[n]=0;reset_audit_ep_recovery[n]=0;
  end
  reset_audit_fd=$fopen("link010r1_reset_audit.txt","w");
  if(reset_audit_fd==0)$fatal(1,"Cannot open LINK010R1 reset audit");
  $fdisplay(reset_audit_fd,"# LINK010R1_RESET_AUDIT_V1 times=integer_ps bits=MSB31_to_LSB0");
  $fdisplay(reset_audit_fd,"# Q edge_ps sample_ps epoch domain phase common_change_window bits32");
  $fdisplay(reset_audit_fd,"# A trigger_ps check_ps epoch bits32; T edge_ps epoch value fast_edge_ps");
  $fdisplay(reset_audit_fd,"# C check_ps epoch bits32; Z assertions fifo_assertions fifo_deassertions recoveries fast_samples slow_samples q_rows");
  #0.010;
  if(dut.fifo_reset!==1'b1)reset_audit_fail("FIFO reset must initialize asserted");
  reset_audit_check_async();
  reset_audit_previous_fifo=1'b1;reset_audit_enabled=1;
  $fdisplay(reset_audit_fd,"A 0 %0d 0 %032b",reset_audit_ps(),reset_audit_bits);
 end
 always @(posedge dut.common_reset)begin : reset_audit_request
  longint trigger_ps;
  if(reset_audit_enabled)begin
   trigger_ps=reset_audit_ps();
   reset_audit_epoch=reset_audit_epoch+1;
   reset_audit_assertions=reset_audit_assertions+1;
   if(reset_audit_epoch>8 || reset_audit_recovered_epoch!=reset_audit_epoch-1)
    reset_audit_fail("Unexpected reset count or new request before recovery");
   #0.010;
   reset_audit_check_async();
   $fdisplay(reset_audit_fd,"A %0d %0d %0d %032b",
    trigger_ps,reset_audit_ps(),reset_audit_epoch,reset_audit_bits);
  end
 end
 always @(dut.fifo_reset)begin : reset_audit_fifo_transition
  longint transition_ps,fast_edge_ps;
  logic value;
  integer epoch;
  if(reset_audit_enabled)begin
   transition_ps=reset_audit_ps();fast_edge_ps=reset_audit_last_fast_ps;
   value=dut.fifo_reset;epoch=reset_audit_epoch;
   if(value!==1'b0 && value!==1'b1)reset_audit_fail("FIFO reset became X/Z");
   if(transition_ps!=fast_edge_ps)reset_audit_fail("FIFO reset changed away from fast rising edge");
   if(transition_ps==reset_audit_last_fifo_ps)reset_audit_fail("Multiple FIFO reset transitions at one fast edge");
   reset_audit_last_fifo_ps=transition_ps;
   if(value===reset_audit_previous_fifo)reset_audit_fail("Spurious FIFO reset transition");
   reset_audit_previous_fifo=value;
   if(value)begin
    reset_audit_fifo_assertions=reset_audit_fifo_assertions+1;
    reset_audit_ep_assert[epoch]=reset_audit_ep_assert[epoch]+1;
   end else begin
    reset_audit_fifo_deassertions=reset_audit_fifo_deassertions+1;
    reset_audit_ep_deassert[epoch]=reset_audit_ep_deassert[epoch]+1;
   end
   // No delay here: every transition, including an off-edge glitch, is checked.
   $fdisplay(reset_audit_fd,"T %0d %0d %0d %0d",transition_ps,epoch,value,fast_edge_ps);
  end
 end
 always @(reset_audit_fast_cb)begin : reset_audit_fast_monitor
  logic [31:0] pre,post;
  longint edge_ps;
  integer pre_epoch;
  bit changed,capture;
  if(reset_audit_enabled)begin
   pre=reset_audit_fast_cb.reset_audit_bits;pre_epoch=reset_audit_fast_cb.reset_audit_epoch;
   edge_ps=reset_audit_ps();
   // These are edge-sampled values, not the values changed by this edge's NBA.
   if(pre[31]!==1'b0 || pre[28]!==1'b0 || pre[26]!==1'b0 ||
      pre[25]!==1'b0 || pre[24]!==1'b0 || pre[23]!==1'b0)
    if(pre[15]!==1'b0 || pre[12]!==1'b0)
     reset_audit_fail("Write enable/source ready active at reset/busy sampling edge");
   #0.010;
   post=reset_audit_bits;
   changed=(pre[31:29]!==post[31:29] ||
    (reset_audit_common_change_ps>=edge_ps && reset_audit_common_change_ps<=reset_audit_ps()));
   // A request in this 10 ps window has its own request+10 ps check. Do not
   // mistake its still-settling asynchronous clear for a clock-NBA violation.
   if(!changed)begin
   if(post[19]===1'b1 && (post[20]!==1'b1 || post[26]!==1'b0 || post[25]!==1'b0))
    reset_audit_fail("FIFO reset completion preceded the full writer reset sequence");
   if(post[23]===1'b0 && (post[31]!==1'b0 || post[28]!==1'b0 ||
      post[26]!==1'b0 || post[25]!==1'b0 || post[24]!==1'b0 ||
      post[22]!==1'b0 || post[19]!==1'b1 || post[16]!==1'b1))
    reset_audit_fail("Fast side released before FIFO/slow reset completion");
   end
   capture=(changed || pre[23]!==1'b0 || pre[22]!==1'b0 || post[23]!==1'b0 ||
            post[22]!==1'b0 || reset_audit_fast_tail>0);
   if(changed || pre[23]!==1'b0 || pre[22]!==1'b0 || post[23]!==1'b0 || post[22]!==1'b0)
    reset_audit_fast_tail=16;
   else if(reset_audit_fast_tail>0)reset_audit_fast_tail=reset_audit_fast_tail-1;
   if(capture)begin
    reset_audit_sample(edge_ps,edge_ps-1,pre_epoch,"F","P",changed,pre);
    reset_audit_sample(edge_ps,reset_audit_ps(),reset_audit_epoch,"F","A",changed,post);
    reset_audit_fast_samples=reset_audit_fast_samples+1;
   end
   if(!changed && reset_audit_recovered_epoch!=reset_audit_epoch && post[23]===1'b0 && post[22]===1'b0)begin
    if(post[21]!==1'b1 || post[20]!==1'b1 || post[19]!==1'b1 ||
       post[18]!==1'b1 || post[17]!==1'b1 || post[16]!==1'b1 ||
       post[8:6]!==3'b000 || post[15]!==1'b0 || post[14]!==1'b0 || post[11]!==1'b0)
     reset_audit_fail("Recovery left nonempty FIFO, stale credit or active IO");
    reset_audit_recovered_epoch=reset_audit_epoch;
    reset_audit_recoveries=reset_audit_recoveries+1;
    reset_audit_ep_recovery[reset_audit_epoch]=reset_audit_ep_recovery[reset_audit_epoch]+1;
    $fdisplay(reset_audit_fd,"C %0d %0d %032b",reset_audit_ps(),reset_audit_epoch,post);
   end
  end
 end
 always @(reset_audit_slow_cb)begin : reset_audit_slow_monitor
  logic [31:0] pre,post;
  longint edge_ps;
  integer pre_epoch;
  bit changed,capture;
  if(reset_audit_enabled)begin
   pre=reset_audit_slow_cb.reset_audit_bits;pre_epoch=reset_audit_slow_cb.reset_audit_epoch;
   edge_ps=reset_audit_ps();
   if(pre[31]!==1'b0 || pre[27]!==1'b0 || pre[26]!==1'b0 ||
      pre[25]!==1'b0 || pre[24]!==1'b0 || pre[22]!==1'b0)
    if(pre[14]!==1'b0 || pre[5]!==1'b0 || pre[11]!==1'b0)
     reset_audit_fail("Reader/backend/output active at reset/busy sampling edge");
   #0.010;
   post=reset_audit_bits;
   changed=(pre[31:29]!==post[31:29] ||
    (reset_audit_common_change_ps>=edge_ps && reset_audit_common_change_ps<=reset_audit_ps()));
   // A request in this 10 ps window has its own request+10 ps check. Do not
   // mistake its still-settling asynchronous clear for a clock-NBA violation.
   if(!changed)begin
   if(post[17]===1'b1 && (post[18]!==1'b1 || post[24]!==1'b0))
    reset_audit_fail("Slow reset ready preceded FIFO reset completion");
   if(post[22]===1'b0 && (post[31]!==1'b0 || post[27]!==1'b0 ||
      post[26]!==1'b0 || post[25]!==1'b0 || post[24]!==1'b0 ||
      post[18]!==1'b1 || post[17]!==1'b1))
    reset_audit_fail("Slow side released in FIFO reset/busy gap");
   if(post[22]===1'b1 && post[8]!==1'b0)
    reset_audit_fail("Frame credit advanced during slow reset");
   end
   capture=(changed || pre[23]!==1'b0 || pre[22]!==1'b0 || post[23]!==1'b0 ||
            post[22]!==1'b0 || reset_audit_slow_tail>0);
   if(changed || pre[23]!==1'b0 || pre[22]!==1'b0 || post[23]!==1'b0 || post[22]!==1'b0)
    reset_audit_slow_tail=16;
   else if(reset_audit_slow_tail>0)reset_audit_slow_tail=reset_audit_slow_tail-1;
   if(capture)begin
    reset_audit_sample(edge_ps,edge_ps-1,pre_epoch,"S","P",changed,pre);
    reset_audit_sample(edge_ps,reset_audit_ps(),reset_audit_epoch,"S","A",changed,post);
    reset_audit_slow_samples=reset_audit_slow_samples+1;
   end
  end
 end
 task automatic reset_audit_finish();
  integer n;
  begin
   if(reset_audit_assertions!=9 || reset_audit_fifo_assertions!=8 ||
      reset_audit_fifo_deassertions!=9 || reset_audit_recoveries!=9 ||
      reset_audit_recovered_epoch!=8 || reset_audit_fast_tail!=0 || reset_audit_slow_tail!=0)
    reset_audit_fail("Reset audit aggregate coverage incomplete");
   for(n=0;n<9;n=n+1)
    if(reset_audit_ep_assert[n]!=(n==0 ? 0 : 1) ||
       reset_audit_ep_deassert[n]!=1 || reset_audit_ep_recovery[n]!=1)
     reset_audit_fail("Per-epoch FIFO reset/recovery coverage incomplete");
   if(reset_audit_rows!=2*(reset_audit_fast_samples+reset_audit_slow_samples))
    reset_audit_fail("Reset audit sample pairing mismatch");
   $fdisplay(reset_audit_fd,"Z %0d %0d %0d %0d %0d %0d %0d",
    reset_audit_assertions,reset_audit_fifo_assertions,reset_audit_fifo_deassertions,
    reset_audit_recoveries,reset_audit_fast_samples,reset_audit_slow_samples,reset_audit_rows);
   reset_audit_enabled=0;
   $fclose(reset_audit_fd);
   $display("CFO_LINK010R1_RESET_AUDIT_PASS reset_epochs=9 common_assertions=9 fifo_assertions=8 fifo_deassertions=9 recoveries=9 fast_samples=%0d slow_samples=%0d q_rows=%0d",
    reset_audit_fast_samples,reset_audit_slow_samples,reset_audit_rows);
  end
 endtask
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
  reset_audit_finish();
  $fclose(fd);
  $display("CFO_LINK010_PASS unique=4 completed=%0d protocol_errors=%0d max_tail=%0d max_total=%0d source_stalls=%0d full_runs=%0d reset_discards=4 abort_discards=4",completed,errors,max_tail,max_total,total_stalls,full_runs);$finish;
 end
endmodule