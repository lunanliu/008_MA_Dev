`timescale 1ns/1ps
module ota_context_boundary_tb;
 logic clk=0;always #3.333 clk=~clk;
 logic fast=0;always #1 fast=~fast;
 logic rst=1,cancel=0;
 logic meta_valid=0,meta_ready,first_valid,first_ready,second_valid,second_ready;
 logic [31:0] frame=17,generation=10;
 logic d1_start=0,d1_ready,d2_start=0,d2_ready;
 wire [7:0] e1,e2;wire [31:0] f1,g1,step1,f2,g2,step2;wire signed [63:0] phase1,phase2;
 logic [159:0] residual_record;
 wire context_valid,context_ready;wire [213:0] context_word;wire [7:0] context_error;
 logic allow=0,output_ready=0;wire fifo_ready,output_valid;wire [213:0] output_word;
 wire wb,rb,ov,un;integer outputs=0,fd,i;logic [213:0] held;
 sfo_first_pass_descriptor first_descriptor(
  .clk(clk),.rst(rst),.s_valid(d1_start),.s_ready(d1_ready),.s_frame_id(frame),.s_generation(generation),
  .s_estimate_frame_id(frame),.s_estimate_generation(generation),.s_estimate_status(16'h4800),.s_ppm_q18(32'sd2621440),
  .s_to(32'sd3),.s_raw_first(-32'sd172),.s_available_first(-32'sd172),.s_available_last(32'sd1336687),
  .s_nominal_first(32'd0),.s_q0(28'd0),.s_input_count(32'd1336860),.s_nominal_count(32'd1336320),
  .m_valid(first_valid),.m_ready(first_ready),.m_error(e1),.m_frame_id(f1),.m_generation(g1),.m_step(step1),.m_phase(phase1),.m_raw_first(),.m_nominal_first()
 );
 sfo_second_pass_descriptor second_descriptor(
  .clk(clk),.rst(rst),.s_valid(d2_start),.s_ready(d2_ready),.s_frame_id(frame),.s_generation(generation),.s_t09_result(residual_record),
  .s_source_complete(1'b1),.s_source_error(8'd0),.s_available_first(-32'sd36),.s_available_last(32'sd1336355),
  .s_nominal_first(32'd0),.s_input_count(32'd1336392),.s_nominal_count(32'd1336320),
  .m_valid(second_valid),.m_ready(second_ready),.m_error(e2),.m_frame_id(f2),.m_generation(g2),.m_step(step2),.m_phase(phase2),.m_raw_first(),.m_nominal_first()
 );
 ota_sfo_context_join join_context(
  .clk(clk),.rst(rst),.cancel(cancel),.meta_valid(meta_valid),.meta_ready(meta_ready),.meta_frame(frame),.meta_generation(generation),
  .meta_coarse_hz_q8(-32'sd38400000),.meta_raw_origin_q28(54'sd805306368),
  .first_valid(first_valid),.first_ready(first_ready),.first_frame(f1),.first_generation(g1),.first_step_q28(step1),
  .second_valid(second_valid),.second_ready(second_ready),.second_frame(f2),.second_generation(g2),.second_step_q28(step2),
  .m_valid(context_valid),.m_ready(context_ready),.m_context(context_word),.error_code(context_error)
 );
 assign context_ready=allow&&fifo_ready;
 ota_async_fifo #(.WIDTH(214),.DEPTH(32)) context_fifo(
  .wr_clk(clk),.rd_clk(fast),.reset_request(rst||cancel),.s_valid(context_valid&&allow),.s_ready(fifo_ready),.s_data(context_word),
  .m_valid(output_valid),.m_ready(output_ready),.m_data(output_word),.wr_busy(wb),.rd_busy(rb),.wr_count(),.rd_count(),.overflow(ov),.underflow(un)
 );
 always @(posedge clk)if(!rst&&!cancel&&((first_valid&&e1!=0)||(second_valid&&e2!=0)||context_error!=0))$fatal(1,"descriptor/join first error");
 task automatic tick;begin @(negedge clk);end endtask
 task automatic issue;begin
  residual_record=0;residual_record[159:128]=frame;residual_record[127:96]=generation;
  residual_record[95:89]=74;residual_record[88:82]=74;residual_record[37:6]=268435456;residual_record[0]=1;
  meta_valid=1;tick();meta_valid=0;
  d1_start=1;d2_start=1;tick();d1_start=0;d2_start=0;
  while(!context_valid)tick();
  if(e1||e2||context_error)$fatal(1,"descriptor or context error %h %h %h",e1,e2,context_error);
  if(context_word!=={frame,generation,32'd268438140,32'd268435456,54'sd805306368,-32'sd38400000})$fatal(1,"actual-step context mismatch");
  held=context_word;repeat(9)begin tick();if(!context_valid||context_word!==held||second_ready)$fatal(1,"context stall instability");end
  allow=1;tick();allow=0;
 end endtask
 always @(posedge fast)if(output_valid&&output_ready)begin
  if(output_word!==held)$fatal(1,"CDC identity/data mismatch");outputs<=outputs+1;
 end
 realtime last_wr=0;logic audit=0;integer reset_edges=0;
 always @(posedge clk)last_wr=$realtime;
 always @(context_fifo.fifo_reset)if(audit)begin
  if(clk!==1'b1||($realtime-last_wr)>0.001)$fatal(1,"FIFO reset not on writer edge");reset_edges=reset_edges+1;
 end
 initial begin
  repeat(30)tick();audit=1;rst=0;while(wb||rb)tick();
  issue();while(!output_valid)tick();repeat(7)begin tick();if(output_word!==held)$fatal(1,"CDC hold mismatch");end
  output_ready=1;while(outputs!=1)tick();output_ready=0;
  // Cancel a queued old epoch; it must never appear after reset recovery.
  generation=11;issue();while(!output_valid)tick();
  #0.417;cancel=1;#0.010;if(output_valid||fifo_ready)$fatal(1,"asynchronous stop failed");
  repeat(30)tick();rst=1;tick();cancel=0;repeat(8)tick();rst=0;while(wb||rb)tick();
  if(output_valid)$fatal(1,"stale context after reset");generation=12;issue();output_ready=1;while(outputs!=2)tick();
  if(ov||un||reset_edges<3)$fatal(1,"FIFO fault/audit missing");
  fd=$fopen("result.txt","w");if(!fd)$fatal(1,"result open");$fdisplay(fd,"OTA002_CONTEXT_PASS");$fclose(fd);
  $display("OTA002_CONTEXT_PASS actual_descriptors=3 contexts_consumed=2 canceled=1 reset_edges=%0d",reset_edges);$finish;
 end
 initial begin #100000;$fatal(1,"context timeout");end
endmodule

