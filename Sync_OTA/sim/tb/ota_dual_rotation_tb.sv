`timescale 1ns/1ps
// Legal post-SFO two-symbol fragment; actual coordinate and rotation kernels.
module ota_dual_rotation_tb;
 `include "ota_dual_config.svh"
 logic clk=0;always #3.333 clk=~clk;
 logic rst=1,cv=0,sv=0,mr=0;wire cr1,cr2,pv1,pv2,pr1,pr2,sr,v1,r1,v2;
 wire [31:0] ps1,pi1,ps2,pi2;wire ok1,ok2,fault1,fault2;wire [3:0] ce1,ce2;
 wire [224:0] mid,final_word;logic [224:0] input_word;
 wire [7:0] sat1,sat2;
 logic [127:0] samples[0:1279],coarse[0:1279],finals[0:1279];
 integer k,ni=0,nc=0,nf=0,cycles=0,fd;logic configured1=0,configured2=0;
 cfo_coordinate_control coordinate1(.clk(clk),.rst(rst),.abort_sync(1'b0),.s_valid(cv),.s_ready(cr1),
  .s_frame(32'd71),.s_generation(32'd19),.s_residual(1'b0),.s_frequency_code(F1),.s_step1_q28(STEP1),.s_step2_q28(STEP2),.s_raw_origin_q28(ORIGIN),
  .m_valid(pv1),.m_ready(pr1),.m_frame(),.m_generation(),.m_residual(),.m_ok(ok1),.m_error(ce1),.m_step(pi1),.m_phase0(ps1),.m_step48(),.m_phase48(),.m_origin_output_q16());
 cfo_coordinate_control coordinate2(.clk(clk),.rst(rst),.abort_sync(1'b0),.s_valid(cv),.s_ready(cr2),
  .s_frame(32'd71),.s_generation(32'd19),.s_residual(1'b1),.s_frequency_code(F2),.s_step1_q28(STEP1),.s_step2_q28(STEP2),.s_raw_origin_q28(ORIGIN),
  .m_valid(pv2),.m_ready(pr2),.m_frame(),.m_generation(),.m_residual(),.m_ok(ok2),.m_error(ce2),.m_step(pi2),.m_phase0(ps2),.m_step48(),.m_phase48(),.m_origin_output_q16());
 cfo_rotate4 rotate1(.clk(clk),.rst(rst),.abort_sync(1'b0),.cfg_valid(pv1),.cfg_ready(pr1),
  .cfg_frame(32'd71),.cfg_generation(32'd19),.cfg_phase0(ps1),.cfg_step(pi1),.cfg_sample_count(32'd5120),
  .s_valid(sv),.s_ready(sr),.s_record(input_word),.m_valid(v1),.m_ready(r1),.m_record(mid),.m_saturation(sat1),.fault(fault1),.first_error());
 cfo_rotate4 rotate2(.clk(clk),.rst(rst),.abort_sync(1'b0),.cfg_valid(pv2),.cfg_ready(pr2),
  .cfg_frame(32'd71),.cfg_generation(32'd19),.cfg_phase0(ps2),.cfg_step(pi2),.cfg_sample_count(32'd5120),
  .s_valid(v1),.s_ready(r1),.s_record(mid),.m_valid(v2),.m_ready(mr),.m_record(final_word),.m_saturation(sat2),.fault(fault2),.first_error());
 always @(negedge clk)if(!rst)mr=(cycles%13<8);
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(!rst)begin
   if(pv1&&pr1)begin
    if(!ok1||ce1||ps1!==PHASE1||pi1!==INC1)$fatal(1,"coarse coordinate mismatch");configured1<=1;
   end
   if(pv2&&pr2)begin
    if(!ok2||ce2||ps2!==PHASE2||pi2!==INC2)$fatal(1,"residual coordinate mismatch");configured2<=1;
   end
   if(sv&&sr)ni<=ni+1;
   if(v1&&r1)begin
    if(nc>=1280||mid!=={32'd71,32'd19,32'(nc),(nc==1279),coarse[nc]}||sat1!==0)$fatal(1,"coarse data/tag beat=%0d",nc);nc<=nc+1;
   end
   if(v2&&mr)begin
    if(nf>=1280||final_word!=={32'd71,32'd19,32'(nf),(nf==1279),finals[nf]}||sat2!==0)$fatal(1,"final data/tag beat=%0d",nf);nf<=nf+1;
   end
   if(fault1||fault2)$fatal(1,"rotator protocol fault");
  end
 end
 initial begin
  $readmemh("ota_dual_input.mem",samples);$readmemh("ota_dual_coarse.mem",coarse);$readmemh("ota_dual_final.mem",finals);
  if($isunknown(samples[1279])||$isunknown(coarse[1279])||$isunknown(finals[1279]))$fatal(1,"vector load");
  repeat(5)@(negedge clk);rst=0;
  while(!cr1||!cr2)@(negedge clk);cv=1;@(negedge clk);cv=0;
  while(!configured1||!configured2)@(negedge clk);
  for(k=0;k<1280;k=k+1)begin
   input_word={32'd71,32'd19,32'(k),(k==1279),samples[k]};sv=1;
   do @(posedge clk);while(!sr);
   @(negedge clk);sv=0;if(k%11==0)@(negedge clk);
  end
  while(nf<1280)@(negedge clk);
  repeat(12)@(negedge clk);
  if(ni!=1280||nc!=1280||nf!=1280||v1||v2)$fatal(1,"count/late duplicate");
  fd=$fopen("result.txt","w");if(!fd)$fatal(1,"result open");$fdisplay(fd,"OTA003_DUAL_ROTATION_PASS");$fclose(fd);
  $display("OTA003_DUAL_ROTATION_PASS samples=5120 symbols=2 coarse_and_final_exact=1 nonzero_origin=1 nonunity_steps=2");$finish;
 end
 initial begin #1000000;$fatal(1,"dual rotation timeout");end
endmodule
