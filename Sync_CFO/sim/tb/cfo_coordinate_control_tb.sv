`timescale 1ns/1ps
module cfo_coordinate_control_tb;
 `include "coordinate_config.svh"
 logic clk=0;always #3.333 clk=~clk;
 logic rst=1,abort_sync=0,s_valid=0,s_ready,m_valid,m_ready=0;
 logic [214:0] input_word=0;
 wire [31:0] m_frame,m_generation,m_step,m_phase0;
 wire m_residual,m_ok;wire [3:0] m_error;
 wire signed [47:0] m_step48;wire [47:0] m_phase48;
 wire signed [48:0] m_origin_output_q16;
 wire [278:0] output_word={m_frame,m_generation,m_residual,m_ok,m_error,m_step,m_phase0,m_step48,m_phase48,m_origin_output_q16};
 logic [214:0] inputs[0:COORD_CASES-1];logic [278:0] expected[0:COORD_CASES-1];
 integer cycle=0,accepted_cycle=0,completed=0,max_latency=0,total_stalls=0,invalid_results=0;
 integer reset_discards=0,abort_discards=0,output_file,i;
 always @(posedge clk) begin
  cycle<=cycle+1;
  if(cycle>300000)$fatal(1,"COORD_CYCLE_TIMEOUT");
 end
 cfo_coordinate_control dut(
 .clk(clk),.rst(rst),.abort_sync(abort_sync),.s_valid(s_valid),.s_ready(s_ready),
 .s_frame(input_word[214:183]),.s_generation(input_word[182:151]),.s_residual(input_word[150]),
 .s_frequency_code(input_word[149:118]),.s_step1_q28(input_word[117:86]),.s_step2_q28(input_word[85:54]),.s_raw_origin_q28(input_word[53:0]),
 .m_valid(m_valid),.m_ready(m_ready),.m_frame(m_frame),.m_generation(m_generation),.m_residual(m_residual),
 .m_ok(m_ok),.m_error(m_error),.m_step(m_step),.m_phase0(m_phase0),.m_step48(m_step48),.m_phase48(m_phase48),.m_origin_output_q16(m_origin_output_q16));
 task automatic start_case(input integer k);
  begin
   @(negedge clk);
   if(!s_ready || m_valid)$fatal(1,"COORD_NOT_IDLE case=%0d",k);
   input_word=inputs[k];s_valid=1;accepted_cycle=cycle+1;
   @(posedge clk);#1;
   @(negedge clk);s_valid=0;
  end
 endtask
 task automatic finish_case(input integer k,input integer stalls);
  integer latency,j;logic [278:0] held;
  begin
   while(!m_valid)begin
    if(s_ready)$fatal(1,"COORD_ACCEPTED_BUSY case=%0d",k);
    if(cycle-accepted_cycle>512)$fatal(1,"COORD_LATENCY case=%0d",k);
    @(negedge clk);
   end
   latency=cycle-accepted_cycle;
   if(latency>max_latency)max_latency=latency;
   if(output_word!==expected[k])$fatal(1,"COORD_MISMATCH case=%0d actual=%070h expected=%070h",k,output_word,expected[k]);
   held=output_word;
   // Change all upstream pins during output stalls; accepted context must survive.
   input_word=~inputs[k];s_valid=1;
   for(j=0;j<stalls;j=j+1)begin
    @(negedge clk);
    if(!m_valid || s_ready || output_word!==held)$fatal(1,"COORD_STALL_CHANGED case=%0d",k);
   end
   s_valid=0;
   $fdisplay(output_file,"%0d %070h %0d %0d",k,output_word,latency,stalls);
   if(!m_ok)invalid_results=invalid_results+1;
   total_stalls=total_stalls+stalls;completed=completed+1;
   m_ready=1;@(posedge clk);#1;@(negedge clk);m_ready=0;
   if(m_valid || !s_ready)$fatal(1,"COORD_DUPLICATE_RESULT case=%0d",k);
  end
 endtask
 task automatic discard_case(input integer k,input integer delay_cycles,input logic use_abort,input logic wait_output);
  integer j;
  begin
   start_case(k);
   if(wait_output)begin
    while(!m_valid)@(negedge clk);
   end else repeat(delay_cycles)@(negedge clk);
   if(use_abort)abort_sync=1;else rst=1;
   #1;if(m_valid || s_ready)$fatal(1,"COORD_CLEAR_HANDSHAKE");
   repeat(2)@(negedge clk);
   if(use_abort)begin abort_sync=0;abort_discards=abort_discards+1;end
   else begin rst=0;reset_discards=reset_discards+1;end
   for(j=0;j<6;j=j+1)begin
    @(negedge clk);if(m_valid || !s_ready)$fatal(1,"COORD_STALE_AFTER_CLEAR");
   end
   start_case(k+1);finish_case(k+1,5);
  end
 endtask
 initial begin
  $readmemh("coordinate_input.mem",inputs);$readmemh("coordinate_expected.mem",expected);
  output_file=$fopen("coordinate_actual.txt","w");if(!output_file)$fatal(1,"COORD_OUTPUT_OPEN_FAILED");
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<COORD_CASES;i=i+1)begin start_case(i);finish_case(i,i%8);end
  discard_case(0,17,0,0); // ratio multiplier
  discard_case(2,78,1,0); // origin divider
  discard_case(4,200,0,0); // frequency divider
  discard_case(6,350,1,0); // phase divider
  discard_case(8,0,0,1); // pending result under backpressure
  discard_case(10,0,1,1);
  repeat(20)begin @(negedge clk);if(m_valid)$fatal(1,"COORD_LATE_STALE_RESULT");end
  $fclose(output_file);
  $display("CFO_COORD_PASS unique=%0d completed=%0d invalid=%0d max_latency=%0d stalled_cycles=%0d reset_discards=%0d abort_discards=%0d",COORD_CASES,completed,invalid_results,max_latency,total_stalls,reset_discards,abort_discards);
  $finish;
 end
endmodule