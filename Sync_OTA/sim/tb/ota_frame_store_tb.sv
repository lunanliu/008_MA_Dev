`timescale 1ns/1ps
module ota_frame_store_tb;
 integer result_fd; logic clk=0; always #4 clk=~clk;
 logic rst=1,cancel=0,start_valid=0,start_ready;
 logic [63:0] start_base_word=16;logic [31:0] start_capacity=8;
 logic s_valid=0,s_ready;logic [127:0] s_data=0;logic seal=0;
 logic replay_valid=0,replay_ready;logic [31:0] replay_first=0,replay_count=8;
 logic release_frame=0,m_valid,m_ready=0;logic [127:0] m_data;logic [31:0] m_index;logic m_last;
 logic cmd_valid,cmd_ready,cmd_write;logic [63:0] cmd_address,cmd_tag;logic [127:0] cmd_data;
 logic rsp_valid=0,rsp_ready;logic [63:0] rsp_tag=0;logic [127:0] rsp_data=0;logic rsp_error=0;
 logic [31:0] generation,committed_words,read_words,stall_cycles;logic sealed,busy;logic [7:0] error_code;
 ota_frame_store dut(.*);
 logic [127:0] memory[0:127];
 integer cycle=0,delay_count=0,seen=0,expected_first=0,expected_count=0;
 logic pending=0,expect_output=0,inject_tag=0,bad_sent=0;
 logic [63:0] tag_hold;logic [127:0] data_hold;
 assign cmd_ready=!pending&&!rsp_valid&&(cycle%5!=0);
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(cmd_valid&&cmd_ready)begin
   if(cmd_address>127)$fatal(1,"address outside model");
   if(pending)$fatal(1,"credit overflow");
   pending<=1;delay_count<=3;tag_hold<=cmd_tag;
   if(cmd_write)begin memory[cmd_address]<=cmd_data;data_hold<=0;end
   else data_hold<=memory[cmd_address];
  end
  if(pending&&!rsp_valid)begin
   if(delay_count!=0)delay_count<=delay_count-1;
   else begin
    rsp_valid<=1;rsp_data<=data_hold;
    rsp_tag<=(inject_tag&&!bad_sent)?(tag_hold^64'h100000000):tag_hold;
   end
  end
  if(rsp_valid&&rsp_ready)begin
   rsp_valid<=0;
   if(inject_tag&&!bad_sent)begin bad_sent<=1;delay_count<=3;end
   else pending<=0;
  end
  if(m_valid&&m_ready)begin
   if(!expect_output)$fatal(1,"unexpected/stale output");
   if(m_data!==128'(expected_first+seen+100) || m_index!==32'(seen) || m_last!==(seen==expected_count-1))
    $fatal(1,"data/order mismatch seen=%0d value=%h index=%0d last=%b",seen,m_data,m_index,m_last);
   seen<=seen+1;
  end
 end
 task automatic tick;begin @(negedge clk);end endtask
 task automatic start_capture;begin
  while(!start_ready)tick();start_valid=1;tick();start_valid=0;
 end endtask
 task automatic put(input integer v);begin
  s_data=128'(v);s_valid=1;
  do begin @(posedge clk);end while(!s_ready);
  tick();s_valid=0;
 end endtask
 task automatic replay(input integer first,input integer count);begin
  expected_first=first;expected_count=count;seen=0;expect_output=1;
  replay_first=first;replay_count=count;replay_valid=1;tick();replay_valid=0;
  while(seen<count)begin m_ready=(cycle%4!=0);release_frame=1;tick();release_frame=0;end
  m_ready=0;expect_output=0;
  while(!sealed)tick();
 end endtask
 integer k;
 logic [127:0] held_data;
 initial begin
  repeat(8)tick();rst=0;tick();start_capture();
  for(k=0;k<8;k=k+1)put(100+k);
  // Last write is still unacknowledged. seal is a commit fence.
  if(committed_words!=7)$fatal(1,"write committed before response");
  seal=1;tick();seal=0;while(!sealed)tick();
  if(committed_words!=8)$fatal(1,"bad sealed length");
  replay(0,8);replay(2,3);
  release_frame=1;tick();release_frame=0;tick();
  if(!start_ready)$fatal(1,"release failed");
  start_capture();put(777);cancel=1;tick();cancel=0;
  if(start_ready)$fatal(1,"cancel did not drain credit");
  while(!start_ready)tick();
  start_capture();put(100);seal=1;tick();seal=0;while(!sealed)tick();
  if(generation!=3 || committed_words!=1)$fatal(1,"generation/length isolation failed");
  inject_tag=1;replay_first=0;replay_count=1;replay_valid=1;tick();replay_valid=0;
  while(!bad_sent)tick();
  if(start_ready||m_valid)$fatal(1,"foreign response returned credit");
  while(!start_ready)tick();
  if(error_code!=8'h22)$fatal(1,"missing wrong-tag error");
  inject_tag=0;start_capture();seal=1;tick();seal=0;while(!sealed)tick();
  replay_first=0;replay_count=1;replay_valid=1;tick();replay_valid=0;tick();
  if(error_code!=8'h11||cmd_valid)$fatal(1,"out of range not rejected");
  release_frame=1;tick();release_frame=0;tick();
  start_base_word=64'hfffffffffffffffe;start_capacity=8;start_capture();tick();
  if(error_code!=8'h10)$fatal(1,"address wrap not rejected");
  $display("OTA001_STORE_PASS capture=8 replay=8+3 cancel_drain=1 stale_tag=1 bounds=1");result_fd=$fopen("result.txt","w");if(result_fd==0)$fatal(1,"result open");$fdisplay(result_fd,"OTA001_STORE_PASS");$fclose(result_fd);$finish;
 end
 initial begin #200000;$fatal(1,"store TB timeout");end
 // An output under backpressure must remain byte-identical through acceptance.
 logic was_stalled=0;logic [160:0] stalled_word;
 always @(posedge clk)begin
  if(was_stalled&&!cancel&&!rst&&{m_data,m_index,m_last}!==stalled_word)$fatal(1,"unstable stalled output");
  was_stalled<=m_valid&&!m_ready;
  stalled_word<={m_data,m_index,m_last};
 end
endmodule

