`timescale 1ns/1ps
module ota_frontend_descriptor_tb;
 integer result_fd; logic clk=0;always #4 clk=~clk;
 logic rst=1,cancel=0,s_valid=0,s_ready;logic [287:0] s_record=0;
 logic [31:0] capture_epoch=7,capture_generation=9;logic [63:0] capture_samples=64'd20000000000;
 logic frame_valid,frame_ready=0,cfo_valid,cfo_ready=0,fine_valid,fine_ready=0;
 logic [187:0] frame_record;logic [95:0] cfo_record,fine_record;
 logic [63:0] replay_first_sample,nominal_absolute_sample;logic [31:0] replay_sample_count,frame_id,generation;
 logic signed [31:0] coarse_hz_q8;logic signed [53:0] raw_origin_q28;logic done;logic [7:0] error_code;
 ota_frontend_descriptor dut(.*);
 integer fc=0,cc=0,tc=0;
 always @(posedge clk)begin
  if(frame_valid&&frame_ready)fc<=fc+1;
  if(cfo_valid&&cfo_ready)cc<=cc+1;
  if(fine_valid&&fine_ready)tc<=tc+1;
 end
 task automatic tick;begin @(negedge clk);end endtask
 task automatic submit;begin s_valid=1;tick();s_valid=0;tick();end endtask
 task automatic clear_dut;begin cancel=1;tick();cancel=0;tick();end endtask
 initial begin
  repeat(6)tick();rst=0;tick();
  s_record={32'd7,32'd15,32'd99,64'd10000000100,64'd10000000103,-32'sd150000,16'h4567,16'h3800};submit();
  if(frame_record!=={32'd15,32'd9,64'd0,32'd0,28'd0} ||
     cfo_record!=={-32'sd150000,16'h4567,16'h2800,32'd15} ||
     fine_record!=={32'd3,16'h4567,16'h3800,32'd15})$fatal(1,"record mapping");
  if(replay_first_sample!=64'd9999999928 || nominal_absolute_sample!=64'd10000000100 ||
     coarse_hz_q8!=-32'sd38400000 || raw_origin_q28!=54'd805306368 || replay_sample_count!=1336860)$fatal(1,"coordinate conversion");
  frame_ready=1;repeat(3)tick();
  if(frame_valid||!cfo_valid||!fine_valid||s_ready)$fatal(1,"atomic ownership lost");
  fine_ready=1;repeat(3)tick();cfo_ready=1;tick();
  if(!done||fc!=1||cc!=1||tc!=1)$fatal(1,"duplicate/missing handshake");
  tick();clear_dut();s_record[287:256]=6;submit();if(error_code!=8'h31||frame_valid)$fatal(1,"epoch isolation");
  clear_dut();s_record[287:256]=7;s_record[15:0]=16'h3000;submit();if(error_code!=8'h32)$fatal(1,"invalid status");
  clear_dut();s_record[15:0]=16'h3800;capture_samples=100;submit();if(error_code!=8'h33)$fatal(1,"retention bound");
  clear_dut();capture_samples=20000000000;s_record[63:32]=32'd8388608;submit();if(error_code!=8'h34)$fatal(1,"Hz overflow");
  clear_dut();s_record[63:32]=0;frame_ready=0;cfo_ready=0;fine_ready=0;submit();clear_dut();
  if(frame_valid||cfo_valid||fine_valid||!s_ready)$fatal(1,"cancel stale record");
  $display("OTA001_DESCRIPTOR_PASS mapping=1 absolute64=1 independent_stalls=1 epoch=1 bounds=1 cancel=1");result_fd=$fopen("result.txt","w");if(result_fd==0)$fatal(1,"result open");$fdisplay(result_fd,"OTA001_DESCRIPTOR_PASS");$fclose(result_fd);$finish;
 end
 initial begin #20000;$fatal(1,"descriptor TB timeout");end
endmodule

