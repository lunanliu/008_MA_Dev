`timescale 1ns/1ps
module ota_ddr_bridge_tb;
 logic clk125=0,clk150=0,reset=1;
 always #4 clk125=~clk125;initial begin #0.71;forever #3.333 clk150=~clk150;end
 logic rv=0,rw=0,rr=0,fv=0,fw=0,fr=0;wire rready,fready,rrv,frv;
 logic [63:0] ra=0,rt=0,fa=0,ft=0;logic [127:0] rd=0,fd=0;
 wire [63:0] rrt,frt;wire [127:0] rrd,frd;wire rre,fre;
 wire cv,cw,sr,idle;logic cr=0,sv=0,se=0;wire [63:0] ca;wire [64:0] ct;wire [127:0] cd;
 logic [64:0] st=0;logic [127:0] sd=0;wire [7:0] error;
 wire [31:0] commands,responses,stales;wire [5:0] ql,pl;
 ota_ddr_bridge dut(.clk125(clk125),.clk150(clk150),.reset_request(reset),
  .raw_cmd_valid(rv),.raw_cmd_ready(rready),.raw_cmd_write(rw),.raw_cmd_address(ra),.raw_cmd_tag(rt),.raw_cmd_data(rd),
  .raw_rsp_valid(rrv),.raw_rsp_ready(rr),.raw_rsp_tag(rrt),.raw_rsp_data(rrd),.raw_rsp_error(rre),
  .cfo_cmd_valid(fv),.cfo_cmd_ready(fready),.cfo_cmd_write(fw),.cfo_cmd_address(fa),.cfo_cmd_tag(ft),.cfo_cmd_data(fd),
  .cfo_rsp_valid(frv),.cfo_rsp_ready(fr),.cfo_rsp_tag(frt),.cfo_rsp_data(frd),.cfo_rsp_error(fre),
  .cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),.cmd_address(ca),.cmd_tag(ct),.cmd_data(cd),
  .rsp_valid(sv),.rsp_ready(sr),.rsp_tag(st),.rsp_data(sd),.rsp_error(se),.idle125(idle),.error125(error),
  .commands125(commands),.responses125(responses),.stale_responses125(stales),.request_level125(ql),.response_level125(pl));
 function automatic [127:0] payload(input [63:0] a);payload={a,~a};endfunction
 integer c125=0,c150=0,nraw=0,ncfo=0,external=0,delay_count=0,outfile;
 logic pending=0,stale_injected=0,stale_now=0,held=0;logic [64:0] expected_tag;logic [257:0] held_cmd;
 always @(negedge clk125)begin cr=(c125%7<3);rr=(c125%5<2);end
 always @(negedge clk150)fr=(c150%11<4);
 always @(posedge clk150)begin
  c150<=c150+1;
  if(frv&&fr)begin
   if(frt!=={32'd4,32'(ncfo)}||frd!==payload(200+ncfo)||fre)$fatal(1,"CFO routed response");ncfo<=ncfo+1;
  end
 end
 always @(posedge clk125)begin
  c125<=c125+1;
  if(!reset)begin
   if(held&&(!cv||{cw,ca,ct,cd}!==held_cmd))$fatal(1,"external command changed under backpressure");
   held<=cv&&!cr;if(cv&&!cr)held_cmd<={cw,ca,ct,cd};
   if(rrv&&rr)begin
    if(rrt!=={32'd3,32'(nraw)}||rrd!==payload(100+nraw)||rre)$fatal(1,"RAW routed response");nraw<=nraw+1;
   end
   if(cv&&cr)begin
    if(pending)$fatal(1,"more than one external credit");
    if(ct[64]?(ca!=200+ct[31:0]||ct[63:32]!=4):(ca!=100+ct[31:0]||ct[63:32]!=3))$fatal(1,"command owner/address");
    if(cd!==payload(ca)||cw!==(ct[31:0]==0))$fatal(1,"command data/opcode");
    expected_tag<=ct;sd<=payload(ca);pending<=1;delay_count<=5;external<=external+1;
   end
   if(pending&&!sv)begin
    if(delay_count!=0)delay_count<=delay_count-1;
    else begin
     sv<=1;
     if(expected_tag[64]&&!stale_injected)begin st<=expected_tag^65'h10000000000000000;stale_now<=1;stale_injected<=1;end
     else begin st<=expected_tag;stale_now<=0;end
    end
   end
   if(sv&&sr)begin
    if(stale_now)begin
     if(rrv||frv)$fatal(1,"stale reply forwarded");
     sv<=0;delay_count<=4;stale_now<=0;
    end else begin pending<=0;sv<=0;end
   end
  end
 end
 task automatic raw_client;
  integer i;begin
   for(i=0;i<2;i=i+1)begin
    @(negedge clk125);ra=100+i;rt={32'd3,32'(i)};rd=payload(ra);rw=i==0;rv=1;
    do @(posedge clk125);while(!rready);
    @(negedge clk125);rv=0;while(nraw<i+1)@(negedge clk125);
   end
  end
 endtask
 task automatic cfo_client;
  integer i;begin
   for(i=0;i<2;i=i+1)begin
    @(negedge clk150);fa=200+i;ft={32'd4,32'(i)};fd=payload(fa);fw=i==0;fv=1;
    do @(posedge clk150);while(!fready);
    @(negedge clk150);fv=0;while(ncfo<i+1)@(negedge clk150);
   end
  end
 endtask
 initial begin
  repeat(20)@(negedge clk125);reset=0;while(!idle)@(negedge clk125);
  fork raw_client();cfo_client();join
  while(!idle)@(negedge clk125);repeat(20)@(negedge clk125);
  if(nraw!=2||ncfo!=2||external!=4||commands!=4||responses!=4||stales!=1||error!==8'h71||ql!=0||pl!=0)$fatal(1,"bridge totals");
  outfile=$fopen("result.txt","w");if(!outfile)$fatal(1,"result open");$fdisplay(outfile,"OTA003_DDR_BRIDGE_PASS");$fclose(outfile);
  $display("OTA003_DDR_BRIDGE_PASS commands=4 matched=4 stale_drained=1 owners=2 independent_clocks=2");$finish;
 end
 initial begin #1000000;$fatal(1,"bridge timeout");end
endmodule
