`timescale 1ns/1ps
module ota_backend74_tb;
 logic clk_fast=0,clk_slow=0,reset_async=1,abort_async=0;
 always #1 clk_fast=~clk_fast;
 initial begin #0.417;forever #3.333 clk_slow=~clk_slow;end
 logic s_valid=0,m_ready=0;wire s_ready,m_valid;
 logic [176:0] source_word=0;wire [498:0] backend_word;wire [3:0] link_error,front_error;wire [22:0] sat_sum;
 wire [529:0] result_word={backend_word,link_error,front_error,sat_sum};
 wire [4:0] wc,rc;wire full,empty,overflow,underflow,fb,rb,rv,nv,fv;
 wire [170:0] read_word;wire [6:0] ni;wire [7:0] fi;
 cfo_estimator_link dut(
  .clk_fast(clk_fast),.clk_slow(clk_slow),.reset_async(reset_async),.abort_async(abort_async),
  .s_valid(s_valid),.s_ready(s_ready),.s_frame(source_word[176:145]),.s_generation(source_word[144:113]),.s_window(source_word[112:106]),
  .s_z_i(source_word[105:68]),.s_z_q(source_word[67:30]),.s_pilot_count(source_word[29:20]),.s_fft_saturations(source_word[19:4]),.s_front_error(source_word[3:0]),
  .m_valid(m_valid),.m_ready(m_ready),.m_backend_word(backend_word),.m_link_error(link_error),.m_front_error(front_error),.m_fft_saturation_sum(sat_sum),
  .fifo_write_count(wc),.fifo_read_count(rc),.fifo_full(full),.fifo_empty(empty),.fifo_overflow(overflow),.fifo_underflow(underflow),
  .fast_reset_busy(fb),.slow_reset_busy(rb),.read_audit_valid(rv),.read_audit_word(read_word),.normal_audit_valid(nv),.normal_audit_index(ni),.fft_audit_valid(fv),.fft_audit_index(fi)
 );
 logic [176:0] inputs[0:295];logic [170:0] reads[0:295];logic [529:0] results[0:3];
 integer ci=0,k,nr=0,outputs=0,fd,reset_edges=0;logic check_reads=0,audit=0;
 logic [529:0] held;
 realtime last_fast=0;
 always @(posedge clk_fast)last_fast=$realtime;
 always @(dut.fifo_reset)if(audit)begin
  if(clk_fast!==1'b1||($realtime-last_fast)>0.001)$fatal(1,"backend FIFO reset not writer-synchronous");reset_edges=reset_edges+1;
 end
 always @(posedge clk_slow)begin
  if(rv&&check_reads)begin
   if(nr>=74||read_word!==reads[ci*74+nr])$fatal(1,"observation ordering/data ci=%0d index=%0d",ci,nr);
   nr<=nr+1;
  end
  if(m_valid&&m_ready)outputs<=outputs+1;
  if(!reset_async&&!abort_async&&!rb&&(overflow||underflow))$fatal(1,"backend FIFO fault");
 end
 task automatic tick;begin @(negedge clk_fast);end endtask
 task automatic send(input integer index);begin
  source_word=inputs[index];s_valid=1;
  do begin @(posedge clk_fast);end while(!s_ready);
  tick();s_valid=0;
 end endtask
 initial begin
  $readmemh("link010_input.mem",inputs);$readmemh("link010_read.mem",reads);$readmemh("link010_result.mem",results);
  if($isunknown(inputs[0])||$isunknown(inputs[295])||$isunknown(reads[295])||$isunknown(results[3]))$fatal(1,"published vector load");
  repeat(50)tick();audit=1;reset_async=0;while(fb||rb)tick();
  // Cancel a real partially accepted 74-observation sequence, then replay complete published frames.
  for(k=0;k<9;k=k+1)send(k);
  #0.417;abort_async=1;#0.010;
  if(s_ready||m_valid||dut.write_fire||dut.read_fire)$fatal(1,"asynchronous backend stop");
  repeat(50)tick();abort_async=0;while(fb||rb)tick();
  for(ci=0;ci<4;ci=ci+1)begin
   nr=0;check_reads=1;
   for(k=0;k<74;k=k+1)send(ci*74+k);
   while(!m_valid)tick();
   if(result_word!==results[ci]||nr!=74)$fatal(1,"74-point numerical result ci=%0d reads=%0d",ci,nr);
   held=result_word;repeat(15)begin tick();if(!m_valid||result_word!==held)$fatal(1,"backend stalled result changed");end
   @(negedge clk_slow);m_ready=1;@(negedge clk_slow);m_ready=0;check_reads=0;
   while(!s_ready)tick();
  end
  if(outputs!=4||reset_edges<3)$fatal(1,"result/reset count");
  fd=$fopen("result.txt","w");if(!fd)$fatal(1,"result open");$fdisplay(fd,"OTA002_BACKEND74_PASS");$fclose(fd);
  $display("OTA002_BACKEND74_PASS full_frames=4 observations=296 canceled_partial=9 outputs=4 reset_edges=%0d",reset_edges);$finish;
 end
 initial begin #2000000;$fatal(1,"backend74 timeout");end
endmodule
