`timescale 1ns/1ps
module ota_cfo_control_tb;
 logic clk150=0,clk500=0,reset_request=1,cancel150=0;
 always #3.333 clk150=~clk150;always #1 clk500=~clk500;
 logic context_valid=0;wire context_ready;
 logic [277:0] context_record={64'd100,32'd6001,32'd9,32'd268435456,32'd268435456,54'd0,32'd0};
 logic s_valid=0;wire s_ready;logic [224:0] s_record=0;
 wire m_valid;logic m_ready=1;wire [224:0] m_record;
 wire cmd_valid,cmd_write;logic cmd_ready;wire [63:0] cmd_address,cmd_tag;wire [127:0] cmd_data;
 logic rsp_valid=0;wire rsp_ready;logic [63:0] rsp_tag=0;logic [127:0] rsp_data=0;logic rsp_error=0;
 wire busy,done;logic done_ready=0;wire [7:0] error_code;wire [4:0] stage;
 wire [31:0] coarse_beats,final_beats,coarse_saturations,final_saturations,memory_committed,memory_read,memory_stalls;
 wire [6:0] observations_sent;wire [498:0] estimator_result;
 ota_cfo_chain dut(.*);
 integer delay_count=0,writes=0,fd,k;logic pending=0;logic [63:0] tag_hold;
 localparam [127:0] IQ=128'h7fff8000ffff00010002fffe1234abcd;
 assign cmd_ready=!pending&&!rsp_valid;
 always @(posedge clk150)begin
  if(cmd_valid&&cmd_ready)begin
   if(!cmd_write||cmd_address!==64'(100+writes)||cmd_data!==IQ)$fatal(1,"real coarse rotation/store mismatch addr=%0d data=%h",cmd_address,cmd_data);
   writes<=writes+1;pending<=1;delay_count<=7;tag_hold<=cmd_tag;
  end
  if(pending&&!rsp_valid)begin
   if(delay_count!=0)delay_count<=delay_count-1;
   else begin rsp_valid<=1;rsp_tag<=tag_hold;end
  end
  if(rsp_valid&&rsp_ready)begin rsp_valid<=0;pending<=0;end
  if(m_valid)$fatal(1,"final output before complete frame estimate");
 end
 task automatic tick;begin @(negedge clk150);end endtask
 task automatic put(input integer beat);begin
  s_record={32'd6001,32'd9,32'(beat),1'b0,IQ};s_valid=1;
  do begin @(posedge clk150);end while(!s_ready);
  tick();s_valid=0;
 end endtask
 initial begin
  repeat(80)tick();reset_request=0;while(!context_ready)tick();
  context_valid=1;tick();context_valid=0;while(!s_ready)tick();
  put(0);put(1);while(memory_committed!=2)tick();
  if(coarse_beats!=2||coarse_saturations!=0||stage!=4)$fatal(1,"coarse stage counters");
  put(2);while(writes!=3)tick();
  // A DDR credit really exists when cancel is asserted. Do not reset the bridge.
  if(!pending)$fatal(1,"cancel stimulus missed pending credit");cancel150=1;
  while(!done)tick();
  if(pending||rsp_valid||error_code!=1||final_beats!=0||observations_sent!=0)$fatal(1,"cancel did not drain/flush");
  cancel150=0;done_ready=1;tick();done_ready=0;tick();
  while(!context_ready)tick();if(busy)$fatal(1,"CFO idle recovery");
  fd=$fopen("result.txt","w");if(!fd)$fatal(1,"result open");$fdisplay(fd,"OTA002_CFO_CONTROL_PASS");$fclose(fd);
  $display("OTA002_CFO_CONTROL_PASS real_chain_elaborated=1 coarse_beats=3 cancel_pending_ddr=1 final_before_estimate=0");$finish;
 end
 initial begin #1000000;$fatal(1,"CFO control timeout");end
endmodule

