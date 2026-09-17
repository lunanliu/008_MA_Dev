`timescale 1ns/1ps
// Real complete production tree; short global-reset/capture/cancel/restart control smoke.
module sync_ota_smoke_tb;
 logic clk125=0;
 logic clk150=0;
 logic clk500=0;
 logic reset_request=0;
 logic start_valid=0;
 wire start_ready;
 logic [63:0] capture_base_word=0;
 logic [31:0] capture_words=0;
 logic cancel=0;
 logic s_valid=0;
 wire s_ready;
 logic [127:0] s_data=0;
 wire done;
 logic done_ready=0;
 wire busy;
 wire [5:0] stage125;
 wire [7:0] error125;
 wire [31:0] accepted_words125;
 wire [31:0] committed_words125;
 wire [31:0] replay_words125;
 wire [31:0] raw_stalls125;
 wire [31:0] frame125;
 wire [31:0] generation125;
 wire [63:0] nominal_absolute125;
 wire [287:0] frontend_record125;
 wire ddr_cmd_valid;
 logic ddr_cmd_ready=0;
 wire ddr_cmd_write;
 wire [63:0] ddr_cmd_address;
 wire [64:0] ddr_cmd_tag;
 wire [127:0] ddr_cmd_data;
 logic ddr_rsp_valid=0;
 wire ddr_rsp_ready;
 logic [64:0] ddr_rsp_tag=0;
 logic [127:0] ddr_rsp_data=0;
 logic ddr_rsp_error=0;
 wire ddr_idle125;
 wire [7:0] ddr_error125;
 wire [31:0] ddr_commands125;
 wire [31:0] ddr_responses125;
 wire [31:0] ddr_stale125;
 wire [5:0] ddr_request_level125;
 wire [5:0] ddr_response_level125;
 wire m_valid;
 logic m_ready=0;
 wire [224:0] m_record;
 wire [4:0] cfo_stage150;
 wire [7:0] cfo_error150;
 wire [31:0] coarse_beats150;
 wire [31:0] final_beats150;
 wire [31:0] coarse_saturations150;
 wire [31:0] final_saturations150;
 wire [6:0] observation_windows150;
 wire [498:0] cfo_result150;
 wire [31:0] cfo_committed150;
 wire [31:0] cfo_read150;
 wire [31:0] cfo_stalls150;
 wire [5:0] cfo_window_fifo_level150;
 wire [4:0] cfo_observation_fifo_level150;
 wire [3:0] cfo_fifo_error150;
 wire [7:0] sfo_error125;
 wire [7:0] sfo_error150;
 wire [7:0] context_error150;
 wire [255:0] sfo_diagnostic150;
 wire [511:0] sfo_monitor125,sfo_monitor150;
 wire [31:0] first_step150;
 wire [31:0] second_step150;
 wire [63:0] frontend_accepted_samples125;
 wire [31:0] frontend_candidates125;
 wire [31:0] frontend_rejected125;
 wire [31:0] frontend_drop125;
 wire [31:0] frontend_duplicate125;
 wire [31:0] frontend_confirmed125;
 wire [15:0] frontend_error125;
 always #4 clk125=~clk125;
 initial begin #0.33;forever #3.333 clk150=~clk150;end
 initial begin #0.71;forever #1 clk500=~clk500;end
 sync_ota_top dut(
  .clk125(clk125),
  .clk150(clk150),
  .clk500(clk500),
  .reset_request(reset_request),
  .start_valid(start_valid),
  .start_ready(start_ready),
  .capture_base_word(capture_base_word),
  .capture_words(capture_words),
  .cancel(cancel),
  .s_valid(s_valid),
  .s_ready(s_ready),
  .s_data(s_data),
  .done(done),
  .done_ready(done_ready),
  .busy(busy),
  .stage125(stage125),
  .error125(error125),
  .accepted_words125(accepted_words125),
  .committed_words125(committed_words125),
  .replay_words125(replay_words125),
  .raw_stalls125(raw_stalls125),
  .frame125(frame125),
  .generation125(generation125),
  .nominal_absolute125(nominal_absolute125),
  .frontend_record125(frontend_record125),
  .ddr_cmd_valid(ddr_cmd_valid),
  .ddr_cmd_ready(ddr_cmd_ready),
  .ddr_cmd_write(ddr_cmd_write),
  .ddr_cmd_address(ddr_cmd_address),
  .ddr_cmd_tag(ddr_cmd_tag),
  .ddr_cmd_data(ddr_cmd_data),
  .ddr_rsp_valid(ddr_rsp_valid),
  .ddr_rsp_ready(ddr_rsp_ready),
  .ddr_rsp_tag(ddr_rsp_tag),
  .ddr_rsp_data(ddr_rsp_data),
  .ddr_rsp_error(ddr_rsp_error),
  .ddr_idle125(ddr_idle125),
  .ddr_error125(ddr_error125),
  .ddr_commands125(ddr_commands125),
  .ddr_responses125(ddr_responses125),
  .ddr_stale125(ddr_stale125),
  .ddr_request_level125(ddr_request_level125),
  .ddr_response_level125(ddr_response_level125),
  .m_valid(m_valid),
  .m_ready(m_ready),
  .m_record(m_record),
  .cfo_stage150(cfo_stage150),
  .cfo_error150(cfo_error150),
  .coarse_beats150(coarse_beats150),
  .final_beats150(final_beats150),
  .coarse_saturations150(coarse_saturations150),
  .final_saturations150(final_saturations150),
  .observation_windows150(observation_windows150),
  .cfo_result150(cfo_result150),
  .cfo_committed150(cfo_committed150),
  .cfo_read150(cfo_read150),
  .cfo_stalls150(cfo_stalls150),
  .cfo_window_fifo_level150(cfo_window_fifo_level150),
  .cfo_observation_fifo_level150(cfo_observation_fifo_level150),
  .cfo_fifo_error150(cfo_fifo_error150),
  .sfo_error125(sfo_error125),
  .sfo_error150(sfo_error150),
  .context_error150(context_error150),
  .sfo_diagnostic150(sfo_diagnostic150),
  .sfo_monitor125(sfo_monitor125),.sfo_monitor150(sfo_monitor150),
  .first_step150(first_step150),
  .second_step150(second_step150),
  .frontend_accepted_samples125(frontend_accepted_samples125),
  .frontend_candidates125(frontend_candidates125),
  .frontend_rejected125(frontend_rejected125),
  .frontend_drop125(frontend_drop125),
  .frontend_duplicate125(frontend_duplicate125),
  .frontend_confirmed125(frontend_confirmed125),
  .frontend_error125(frontend_error125)
 );

 integer cycles=0,commands=0,replies=0,response_delay=0,outfile;

 logic guard_request=1;
 wire guarded_reset,guard_stable;
 logic guard_test_armed=0,guard_test_done=0;
 time guard_release_time;
 wire [3:0] probe_wr_reset,probe_rd_reset;
 ota_algorithm_reset_guard guard_probe(
  .clk125(clk125),.global_reset(reset_request),.request_reset(guard_request),
  .reset_active(guarded_reset),.reset_stable(guard_stable));
 for(genvar g=0;g<4;g=g+1)begin:reset_probes
  wire write_clock=(g<2)?clk125:clk150;
  wire read_clock=(g<2)?clk150:clk125;
  sfo_record_cdc_fifo #(.WIDTH(8),.DEPTH((g%2==0)?32:1024)) fifo_probe(
   .wr_clk(write_clock),.rd_clk(read_clock),.reset_request(guarded_reset),
   .s_valid(1'b0),.s_ready(),.s_data(8'h00),.m_valid(),.m_ready(1'b0),.m_data(),
   .wr_level(),.rd_level(),.wr_high_water(),.rd_high_water(),
   .wr_reset_active(probe_wr_reset[g]),.rd_reset_active(probe_rd_reset[g]),
   .wr_error(),.rd_error());
 end
 always @(posedge guarded_reset)begin
  if(guard_test_armed)begin
   if(($time-guard_release_time)<1024)$fatal(1,"early cancel truncated reset recovery interval");
   if(probe_wr_reset!==4'b0000||probe_rd_reset!==4'b0000)
    $fatal(1,"early cancel reasserted while representative FIFO reset busy");
  end
 end
 initial begin
  wait(reset_request===1'b1);wait(reset_request===1'b0);
  repeat(2)@(negedge clk125);guard_request=0;
  @(negedge guarded_reset);guard_release_time=$time;guard_test_armed=1;
  // Cancel at the first half-cycle after reset release.
  @(negedge clk125);guard_request=1;
  @(posedge guarded_reset);wait(guard_stable);
  guard_test_done=1;
  $display("OTA004_EARLY_CANCEL_RESET_PASS real_fifo_probes=4 clocks_both_directions=1 depths_32_1024=1 all_busy_clear_before_reassert=1");
 end

 // Real FIFO reset/flush checks for all clock directions used by OTA.
 wire [3:0] local_fifo_done;
 for(genvar h=0;h<4;h=h+1)begin:local_reset_probes
  wire wc=(h==0)?clk125:((h==3)?clk500:clk150);
  wire rc=(h==1)?clk125:((h==2)?clk500:clk150);
  logic request=1,sv=0,mr=0,finished=0;
  logic [7:0] sd=0;
  wire sr,mv,wb,rb,ov,un;
  wire [7:0] md;
  integer received=0;
  assign local_fifo_done[h]=finished;
  ota_async_fifo #(.WIDTH(8),.DEPTH(32)) fifo_local(
   .wr_clk(wc),.rd_clk(rc),.reset_request(request),
   .s_valid(sv),.s_ready(sr),.s_data(sd),.m_valid(mv),.m_ready(mr),.m_data(md),
   .wr_busy(wb),.rd_busy(rb),.wr_count(),.rd_count(),.overflow(ov),.underflow(un));
  task automatic push(input [7:0] value);
   begin
    @(negedge wc);sd=value;sv=1;
    do @(posedge wc);while(!sr);
    @(negedge wc);sv=0;
   end
  endtask
  always @(posedge rc)begin
   if(!request&&mv&&mr)begin
    if(md!==(8'h50+h*4+received))$fatal(1,"local FIFO stale, missing or reordered data probe=%0d received=%0d value=%h",h,received,md);
    received<=received+1;
   end
   if(!request&&(ov||un))$fatal(1,"local FIFO protocol error");
  end
  initial begin
   wait(reset_request===1'b1);wait(reset_request===1'b0);
   repeat(2)@(negedge wc);request=0;
   wait(!wb&&!rb);
   // Leave old-session data under read backpressure, then abort it.
   push(8'h10+h*4);push(8'h11+h*4);
   repeat(5)@(negedge rc);
   @(negedge wc);request=1;
   repeat(16)@(negedge wc);request=0;
   wait(!wb&&!rb);
   @(negedge rc);mr=1;
   push(8'h50+h*4);push(8'h51+h*4);
   wait(received==2);
   repeat(8)@(negedge rc);
   if(received!=2||mv||ov||un)$fatal(1,"local FIFO did not become empty after exactly two new records");
   finished=1;
  end
 end
 initial begin
  wait(local_fifo_done===4'b1111);
  $display("OTA004_LOCAL_RESET_FIFO_PASS real_fifo_probes=4 old_epoch_flushed=1 new_records_per_probe=2 stale_duplicate_reorder=0");
 end

 integer startup_samples=0;
 // Evidence for the vendor FPO warning at 20ns: its public reset input must
 // remain asserted throughout these four adjacent startup samples.
 always @(negedge clk125)begin
  if(startup_samples<4)begin
   startup_samples=startup_samples+1;
   if(reset_request!==1'b1||dut.frontend.estimator_rst_n!==1'b0||accepted_words125!==0)
    $fatal(1,"startup reset input not held");
   $display("OTA004_STARTUP_RESET_SAMPLE sample=%0d raw_reset=1 estimator_reset_n=0 accepted_words=0",startup_samples);
  end
  if(monitor_enable)begin
   // This short test cancels during capture and rejects length0; it never
   // authorizes SFO processing, including COMPLETE and Host acknowledgments.
   if(dut.effective_sfo_reset125!==1'b1)$fatal(1,"SFO reset released during cancel/reject completion");
  end
 end

 logic pending=0,hold_response=0,monitor_enable=0;
 logic [64:0] held_tag;logic [127:0] held_data;
 always @(negedge clk125)ddr_cmd_ready=(cycles%5<3)&&!pending;
 always @(posedge clk125)begin
  cycles<=cycles+1;
  if(!reset_request)begin
   if(ddr_cmd_valid&&ddr_cmd_ready)begin
    if(pending||!ddr_cmd_write||ddr_cmd_tag[64]||ddr_cmd_address!==64'd4096+commands)$fatal(1,"production DDR capture command");
    if(ddr_cmd_tag[63:32]!=1||ddr_cmd_tag[31:0]!=commands)$fatal(1,"production DDR lease identity");
    commands<=commands+1;held_tag<=ddr_cmd_tag;held_data<=ddr_cmd_data;pending<=1;response_delay<=3;
   end
   if(pending&&!ddr_rsp_valid&&!hold_response)begin
    if(response_delay!=0)response_delay<=response_delay-1;
    else begin ddr_rsp_valid<=1;ddr_rsp_tag<=held_tag;ddr_rsp_data<=held_data;end
   end
   if(ddr_rsp_valid&&ddr_rsp_ready)begin ddr_rsp_valid<=0;pending<=0;replies<=replies+1;end
   if(m_valid)$fatal(1,"final output before an estimated complete frame");
   if(monitor_enable&&(ddr_error125!=0||cfo_fifo_error150!=0))$fatal(1,"production protocol/FIFO fault");
  end
 end
 task automatic start_capture(input [31:0] words);
  begin
   @(negedge clk125);capture_words=words;capture_base_word=4096;
   while(!start_ready)@(negedge clk125);
   start_valid=1;@(negedge clk125);start_valid=0;
  end
 endtask
 task automatic send_beat(input integer number);
  begin
   s_data={32'(number),32'(number+1),32'(number+2),32'(number+3)};s_valid=1;
   do @(posedge clk125);while(!s_ready);
   @(negedge clk125);s_valid=0;
  end
 endtask
 initial begin
  reset_request=1;done_ready=0;m_ready=1;
  repeat(200)@(negedge clk125);reset_request=0;
  while(!start_ready)@(negedge clk125);monitor_enable=1;
  start_capture(64);send_beat(0);send_beat(1);
  while(replies!=2)@(negedge clk125);
  hold_response=1;send_beat(2);while(commands!=3)@(negedge clk125);
  cancel=1;@(negedge clk125);cancel=0;
  repeat(80)begin @(negedge clk125);if(done||start_ready)$fatal(1,"global cancel completed before pending DDR ACK");end
  hold_response=0;while(!done)@(negedge clk125);
  if(error125!==8'h01||accepted_words125!=3||commands!=3||replies!=3||!ddr_idle125)$fatal(1,"global cancel totals");
  done_ready=1;@(negedge clk125);done_ready=0;
  while(!start_ready)@(negedge clk125);
  repeat(80)@(negedge clk125);
  if(!start_ready||dut.completion_v||dut.cfo_busy150)$fatal(1,"late duplicate completion or not reusable");
  start_capture(0);while(!done)@(negedge clk125);
  if(error125!==8'h10||commands!=3||replies!=3)$fatal(1,"invalid configuration generated traffic");
  done_ready=1;@(negedge clk125);done_ready=0;
  repeat(80)@(negedge clk125);
  if(!start_ready||dut.completion_v||dut.cfo_busy150||dut.effective_sfo_reset125!==1'b1)
   $fatal(1,"invalid configuration acknowledge did not return reset-held idle");
  if(local_fifo_done!==4'b1111)$fatal(1,"local reset FIFO probes incomplete");
  if(!guard_test_done)$fatal(1,"early cancellation reset probe incomplete");
  $display("OTA004_RESET_GUARD_PASS cancel_completion=1 invalid_completion=1 both_acknowledged=1 reset_continuous=1");
  outfile=$fopen("result.txt","w");if(!outfile)$fatal(1,"result open");$fdisplay(outfile,"OTA004_REAL_TOP_SMOKE_PASS");$fclose(outfile);
  $display("OTA004_REAL_TOP_SMOKE_PASS real_algorithms_elaborated=1 pending_ddr_cancel=1 complete_once=1 reusable=1 invalid_config=1");$finish;
 end
 initial begin #200000;$fatal(1,"real top control timeout");end
endmodule
