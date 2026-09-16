`timescale 1ns/1ps
// Scheduler/ownership test only: real store+descriptor, labelled FE/SFO/CFO
// interface services. Full physical range is counted; no full algorithm run.
module ota_capture_controller_tb;
 localparam integer WORDS=334215;
 localparam [63:0] BASE=1024;
 logic clk=0;always #4 clk=~clk;
 logic rst=1,cancel=0,start=0,sv=0,done_ready=0;logic [31:0] length=8;logic [127:0] sd=0;
 wire start_ready,sr,done,busy;wire [5:0] stage;wire [7:0] error;
 wire [31:0] accepted,committed,read_words,stalls,frame,generation;wire [63:0] nominal;wire [287:0] captured;
 wire fe_start,fe_abort,fe_sv,fe_mr,sfo_reset,sfo_sv,frame_v,coarse_v,fine_v,meta_v,cfo_cancel,completion_ready;
 wire [127:0] fe_sd,sfo_sd;wire signed [31:0] sfo_abs;wire [187:0] frame_record;wire [95:0] coarse_record,fine_record;wire [213:0] meta;
 logic fe_mv=0;logic [287:0] fe_record=0;logic [31:0] epoch=0;logic sfo_sr=0,frame_r=0,coarse_r=0,fine_r=0,meta_r=0;
 logic cfo_busy=0,completion_valid=0,completion_sent=0;logic [7:0] completion_error=0;
 wire cmd_v,cmd_w,rsp_ready;wire [63:0] address,tag;wire [127:0] data;
 logic cmd_r=0,rsp_v=0;logic [63:0] rsp_tag=0;logic [127:0] rsp_data=0;
 logic pending=0,hold_response=0;integer response_delay=0;
 ota_capture_controller dut(.clk125(clk),.rst125(rst),.cancel(cancel),
  .start_valid(start),.start_ready(start_ready),.start_base_word(BASE),.start_words(length),.s_valid(sv),.s_ready(sr),.s_data(sd),
  .done(done),.done_ready(done_ready),.busy(busy),.stage(stage),.error_code(error),.accepted_words(accepted),.committed_words(committed),.read_words(read_words),.memory_stalls(stalls),
  .frame_id(frame),.generation(generation),.nominal_absolute_sample(nominal),.frontend_record(captured),
  .fe_session_start(fe_start),.fe_session_abort(fe_abort),.fe_s_valid(fe_sv),.fe_s_ready(1'b1),.fe_s_data(fe_sd),
  .fe_m_valid(fe_mv),.fe_m_ready(fe_mr),.fe_m_record(fe_record),.fe_epoch(epoch),.fe_error(16'd0),
  .sfo_reset(sfo_reset),.sfo_s_valid(sfo_sv),.sfo_s_ready(sfo_sr),.sfo_s_data(sfo_sd),.sfo_absolute_index(sfo_abs),
  .frame_valid(frame_v),.frame_ready(frame_r),.frame_record(frame_record),.coarse_valid(coarse_v),.coarse_ready(coarse_r),.coarse_record(coarse_record),
  .fine_valid(fine_v),.fine_ready(fine_r),.fine_record(fine_record),.meta_valid(meta_v),.meta_ready(meta_r),.meta_record(meta),
  .algorithm_error(1'b0),.cfo_cancel(cfo_cancel),.cfo_busy(cfo_busy),.cfo_done_valid(completion_valid),.cfo_done_ready(completion_ready),.cfo_done_error(completion_error),
  .bridge_idle(!pending&&!rsp_v),.bridge_error(8'd0),
  .cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_address(address),.cmd_tag(tag),.cmd_data(data),
  .rsp_valid(rsp_v),.rsp_ready(rsp_ready),.rsp_tag(rsp_tag),.rsp_data(rsp_data),.rsp_error(1'b0));
 function automatic [127:0] pattern(input [31:0] n);pattern={~n,n^32'h12345678,n+32'd10,n};endfunction
 integer cycles=0,writes=0,reads=0,fe_count=0,preloaded=0,npframe=0,npcoarse=0,npfine=0,npmeta=0,k,outfile;
 logic normal_case=0;
 always @(negedge clk)begin
  cmd_r=!pending&&(cycles%5!=0);sfo_sr=cycles%7<5;
  frame_r=cycles%3==0;coarse_r=cycles%5==0;fine_r=cycles%7==0;meta_r=cycles%11==0;
 end
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(!rst)begin
   if(start&&start_ready)begin
    writes<=0;reads<=0;preloaded<=0;npframe<=0;npcoarse<=0;npfine<=0;npmeta<=0;completion_sent<=0;
   end
   if(cmd_v&&cmd_r)begin
    if(pending)$fatal(1,"credit overlap");
    if(cmd_w)begin
     if(address!==BASE+writes||data!==pattern(writes))$fatal(1,"capture address/data %0d",writes);
     writes<=writes+1;
    end else begin
     if(writes!=WORDS||address!==BASE+(reads%WORDS))$fatal(1,"read before complete capture or address %0d",reads);
     reads<=reads+1;
    end
    if(normal_case&&(tag[63:32]!=2||tag[31:0]!=(writes+reads)))$fatal(1,"lease or serial identity");
    rsp_tag<=tag;rsp_data<=pattern(32'(address-BASE));pending<=1;response_delay<=1;
   end
   if(pending&&!rsp_v&&!hold_response)begin
    if(response_delay!=0)response_delay<=response_delay-1;else rsp_v<=1;
   end
   if(rsp_v&&rsp_ready)begin pending<=0;rsp_v<=0;end
   if(fe_start)begin epoch<=epoch+1;fe_count<=0;fe_mv<=0;end
   if(fe_sv)begin
    if(fe_sd!==pattern(fe_count))$fatal(1,"frontend scan data");
    fe_count<=fe_count+1;
    if(fe_count==63)begin fe_record<={epoch,32'd9,32'd4,64'd172,64'd172,-32'sd150000,16'h0040,16'h3800};fe_mv<=1;end
   end
   if(fe_mv&&fe_mr)fe_mv<=0;
   if(sfo_sv&&sfo_sr)begin
    if(sfo_reset||sfo_sd!==pattern(preloaded)||sfo_abs!==-32'sd172+32'(4*preloaded))$fatal(1,"SFO preload %0d",preloaded);
    preloaded<=preloaded+1;
   end
   if(frame_v||coarse_v||fine_v||meta_v)begin
    if(preloaded!=WORDS||pending||dut.mem_busy)$fatal(1,"descriptor published before reader/DDR lease release");
   end
   if(frame_v&&frame_r)begin
    if(frame_record!=={32'd9,32'd2,64'd0,32'd0,28'd0})$fatal(1,"frame descriptor");npframe<=npframe+1;
   end
   if(coarse_v&&coarse_r)begin
    if(coarse_record!=={-32'sd150000,16'h0040,16'h2800,32'd9})$fatal(1,"coarse descriptor");npcoarse<=npcoarse+1;
   end
   if(fine_v&&fine_r)begin
    if(fine_record!=={32'd0,16'h0040,16'h3800,32'd9})$fatal(1,"fine descriptor");npfine<=npfine+1;
   end
   if(meta_v&&meta_r)begin
    if(meta!=={BASE,32'd9,32'd2,-32'sd38400000,54'd0})$fatal(1,"context metadata");npmeta<=npmeta+1;cfo_busy<=1;
   end
   // Labelled CFO completion service; no numerical estimator is replaced in production.
   if(cfo_cancel)begin
    cfo_busy<=1;
    if(!completion_sent)begin completion_valid<=1;completion_error<=8'h01;end
   end else if(completion_sent)cfo_busy<=0;
   if(stage==15&&!completion_sent)begin
    if(npframe!=1||npcoarse!=1||npfine!=1||npmeta!=1)$fatal(1,"independent publication count");
    completion_valid<=1;completion_error<=0;
   end
   if(completion_valid&&completion_ready)begin completion_valid<=0;completion_sent<=1;end
  end
 end
 task automatic start_capture;
  begin while(!start_ready)@(negedge clk);start=1;@(negedge clk);start=0;end
 endtask
 task automatic send_word(input integer n);
  begin sd=pattern(n);sv=1;do @(posedge clk);while(!sr);@(negedge clk);sv=0;end
 endtask
 initial begin
  repeat(8)@(negedge clk);rst=0;hold_response=1;start_capture();send_word(0);
  cancel=1;@(negedge clk);cancel=0;
  repeat(24)begin @(negedge clk);if(done||start_ready)$fatal(1,"cancel returned pending credit early");end
  hold_response=0;while(!done)@(negedge clk);if(error!==8'h01)$fatal(1,"cancel error");
  done_ready=1;@(negedge clk);done_ready=0;normal_case=1;length=WORDS;
  start_capture();
  for(k=0;k<WORDS;k=k+1)send_word(k);
  while(!done)@(negedge clk);
  if(error||accepted!=WORDS||committed!=WORDS||read_words!=WORDS||preloaded!=WORDS||reads!=2*WORDS||writes!=WORDS)$fatal(1,"normal complete counters err=%h stage=%d",error,stage);
  if(frame!=9||generation!=2||nominal!=172||pending||dut.mem_busy)$fatal(1,"final ownership/identity");
  outfile=$fopen("result.txt","w");if(!outfile)$fatal(1,"result open");$fdisplay(outfile,"OTA003_CAPTURE_CONTROL_PASS");$fclose(outfile);
  $display("OTA003_CAPTURE_CONTROL_PASS captured=334215 scan_reads=334215 preload_reads=334215 cancel_pending_credit=1 descriptors_after_release=1 services_only=1");$finish;
 end
 initial begin #100000000;$fatal(1,"capture control timeout");end
endmodule
