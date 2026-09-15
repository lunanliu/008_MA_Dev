`timescale 1ns/1ps
module t10_full023_tb;
 import bistatic_stream_pkg::*;
 localparam integer N=1336320, RAW_BEATS=334215, E1_BEATS=334098, OUT_BEATS=334080;
 logic clk125=0,clk150=0,clk500=0,reset_request=1,abort125=0;
 always #4 clk125=~clk125;
 initial begin #1.1;forever #3.333333333 clk150=~clk150;end
 initial begin #0.3;forever #1 clk500=~clk500;end
 logic send=0;integer ni=0,n1=0,n2=0,no=0,nreq=0,nwin=0,npoint=0,nt06=0,nt09=0,ncfg=0,npub=0,ne2cfg=0,ndone=0;
 integer c125=0,c150=0,maxdiff=0,df,ef,pf,rf,phase_start=0;
 logic [127:0] raw[0:RAW_BEATS-1],ref1[0:E1_BEATS-1],ref2[0:OUT_BEATS-1];
 logic [23:0] expected_delay[0:73];logic [17:0] expected_delta[0:73];
 wire s_valid=send&&ni<RAW_BEATS;wire s_ready;
 wire [127:0] s_data=ni<RAW_BEATS?raw[ni]:128'd0;
 wire signed [31:0] s_abs=-172+4*ni;
 logic fv=0,cv=0,tv=0;wire fr,cr,tr;
 logic [187:0] descriptor={32'd6001,32'd1,64'd0,32'd0,28'd0};
 bistatic_estimator_result_t cfo_record,fine_record;
 wire mv,mreset,mfault,fault;wire [224:0] mr;wire [7:0] e125,e150;wire [255:0] diag;wire pv;wire [128:0] point;
 t10_two_pass_system #(.OUTPUT_CLOCK_MHZ(150)) dut(
 .clk125(clk125),.clk150(clk150),.clk500(clk500),.reset_request(reset_request),.abort125(abort125),
 .s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_frame_id(32'd6001),.s_absolute_index(s_abs),.s_lane_valid(4'hf),
 .frame_valid(fv),.frame_ready(fr),.frame_record(descriptor),.cfo_valid(cv),.cfo_ready(cr),.cfo_record(cfo_record),.fine_valid(tv),.fine_ready(tr),.fine_record(fine_record),
 .m_valid(mv),.m_ready(1'b1),.m_record(mr),.m_reset(mreset),.m_fault(mfault),.fault(fault),.error_code125(e125),.error_code150(e150),.diagnostic(diag),.residual_point_valid(pv),.residual_point_record(point));
 task automatic compare(input logic [127:0] a,b,input integer kind,beat);
 integer d,aa,bb;
 begin
  if($isunknown(a))$fatal(1,"FULL023 unknown IQ kind=%0d beat=%0d",kind,beat);
  for(integer j=0;j<8;j=j+1)begin
   aa=$signed(a[16*j+:16]);bb=$signed(b[16*j+:16]);d=aa-bb;if(d<0)d=-d;
   if(d>maxdiff)maxdiff=d;
   if(d>1)$fatal(1,"FULL023 IQ mismatch kind=%0d beat=%0d component=%0d actual=%0d expected=%0d difference=%0d",kind,beat,j,aa,bb,d);
  end
 end endtask
 task automatic event_row(input string kind,input integer cycle,input logic [255:0] data);
 begin $fwrite(ef,"%s,%0.0f,%0d,%064h\n",kind,$realtime*1000,cycle,data);$fflush(ef);$display("FULL023_STAGE %s cycle=%0d time_ns=%0.3f data=%h",kind,cycle,$realtime,data);end endtask
 initial begin
  df=$fopen("data.csv","w");ef=$fopen("events.csv","w");pf=$fopen("points.csv","w");
  if(df==0||ef==0||pf==0)$fatal(1,"FULL023 output file open failed");
  $fwrite(df,"Kind,Cycle,Frame,Generation,Beat,Last,Data\n");$fwrite(ef,"Kind,TimePs,Cycle,Record\n");$fwrite(pf,"Slot,TimePs,Record\n");
  $readmemh("raw.mem",raw);$readmemh("r1.mem",ref1);$readmemh("r2.mem",ref2);$readmemh("delay.mem",expected_delay);$readmemh("delta.mem",expected_delta);
  for(integer i=0;i<RAW_BEATS;i=i+1)if($isunknown(raw[i]))$fatal(1,"FULL023 raw load %0d",i);
  for(integer i=0;i<E1_BEATS;i=i+1)if($isunknown(ref1[i]))$fatal(1,"FULL023 E1 reference load %0d",i);
  for(integer i=0;i<OUT_BEATS;i=i+1)if($isunknown(ref2[i]))$fatal(1,"FULL023 E2 reference load %0d",i);
  for(integer i=0;i<74;i=i+1)if($isunknown({expected_delay[i],expected_delta[i]}))$fatal(1,"FULL023 point reference load %0d",i);
  if(raw[0]!==128'he9e21b89e51021b9fe4b04feffa40de7||raw[RAW_BEATS-1]!==128'h17670f0d09c6ff10e5f3fe10fa1bf8c8||ref1[0]!==128'hef4a0be9ec2806700466010f15f1144d||ref1[E1_BEATS-1]!==128'h0675fc79ec0bfdd30185fe23faf6fa1b||ref2[0]!==128'h0f00e8fb187703ad162306030117fdca||ref2[OUT_BEATS-1]!==128'h1163f2aaf826011cfbc4e51c18aff6cf)$fatal(1,"FULL023 fixture boundary identity");
  $display("FULL023_FIXTURES_LOADED raw=334215 r1=334098 r2=334080 points=74");
  cfo_record.value=100000;cfo_record.quality=0;cfo_record.status=16'h2800;cfo_record.frame_id=6001;
  fine_record.value=0;fine_record.quality=0;fine_record.status=16'h3800;fine_record.frame_id=6001;
  repeat(80)@(negedge clk125);reset_request=0;wait(!dut.reset125);repeat(8)@(negedge clk125);
  fv=1;do @(posedge clk125);while(!fr);@(negedge clk125);fv=0;
  cv=1;do @(posedge clk125);while(!cr);@(negedge clk125);cv=0;
  tv=1;do @(posedge clk125);while(!tr);@(negedge clk125);tv=0;
  phase_start=c125;send=1;event_row("RAW_BEGIN",c125,0);
 end
 logic raw_hold=0,win_hold=0;logic [159:0] heldraw;logic [234:0] heldwin;
 always @(posedge clk125)begin
  c125<=c125+1;
  if(!dut.reset125)begin
   if(fault)$fatal(1,"FULL023 fault e125=%h e150=%h T06stage=%h E1=%h E2=%h raw=%h banks=%h/%h",e125,e150,dut.t06err,dut.transport.e1error,dut.transport.e2error,dut.transport.raw_error,dut.transport.berror[0],dut.transport.berror[1]);
   if(raw_hold&&(!s_valid||{s_abs,s_data}!==heldraw))$fatal(1,"FULL023 input changed under backpressure");
   raw_hold<=s_valid&&!s_ready;heldraw<={s_abs,s_data};
   if(win_hold&&(!dut.qdv||dut.qdw!==heldwin))$fatal(1,"FULL023 T09 source changed under backpressure");
   win_hold<=dut.qdv&&!dut.qdr;heldwin<=dut.qdw;
   if(s_valid&&s_ready)begin
    ni<=ni+1;
    if(ni==RAW_BEATS-1)event_row("RAW_COMPLETE",c125,ni+1);
    else if(ni%32768==0)event_row("RAW_PROGRESS",c125,ni);
   end
   if(dut.t06mv&&dut.t06mr)begin
    event_row("T06_RESULT",c125,dut.t06result);
    if(nt06!=0||dut.t06result.frame_id!=6001||dut.t06result.status!=16'h4800||$signed(dut.t06result.value)!=-39303835)$fatal(1,"FULL023 T06 numeric or identity mismatch");
    if(dut.initial_estimator.fft_input_count!=4096||dut.initial_estimator.fft_output_count!=4096||dut.initial_estimator.observation_count!=6560||dut.initial_estimator.weight_count!=6560)$fatal(1,"FULL023 T06 incomplete training arithmetic");
    nt06<=nt06+1;
   end
   if(send&&c125-phase_start>70000&&nt06==0)$fatal(1,"FULL023 T06 not completed within early gate");
   if(dut.qcv&&dut.qcr)begin
    if(ncfg!=0||npub!=1||n1!=E1_BEATS||dut.qcw[221:190]!=6001||dut.qcw[189:158]!=1||dut.qcw[84:64]!=N)$fatal(1,"FULL023 T09 start requires full E1 publication");
    ncfg<=ncfg+1;event_row("T09_CONFIG",c125,dut.qcw);
   end
   if(dut.qrv&&dut.qrr)begin
    if(nreq>=74||nwin!=nreq*512||dut.qrw!=={32'd6001,32'd1,7'(nreq),21'(25984+17920*nreq),10'd512})$fatal(1,"FULL023 T09 request order or geometry");
    event_row("T09_REQUEST",c125,dut.qrw);nreq<=nreq+1;
   end
   if(dut.qdv&&dut.qdr)begin
    if(nwin>=74*512||nreq!=nwin/512+1||dut.qdw[234:203]!=6001||dut.qdw[202:171]!=1||dut.qdw[170:150]!=25984+17920*(nwin/512)+4*(nwin%512)||dut.qdw[149:141]!=nwin%512||dut.qdw[140:137]!=15||dut.qdw[136]!=(nwin%512==511)||dut.qdw[135:128]!=0)$fatal(1,"FULL023 T09 source metadata");
    compare(dut.qdw[127:0],ref1[9+6496+4480*(nwin/512)+nwin%512],3,nwin);
    $fwrite(df,"T09,%0d,6001,1,%0d,%0d,%032h\n",c125,nwin,dut.qdw[136],dut.qdw[127:0]);nwin<=nwin+1;
   end
   if(pv)begin
    $fwrite(pf,"%0d,%0.0f,%033h\n",npoint,$realtime*1000,point);$fflush(pf);
    if(npoint>=74||point[128:97]!=6001||point[96:65]!=1||point[64:58]!=npoint||!point[0])$fatal(1,"FULL023 residual point invalid or wrong identity");
    // Record all point numerics. Same final Q28 step is required below for reuse of the full saved E2 reference.
    npoint<=npoint+1;
   end
   if(dut.qmv&&dut.qmr)begin
    event_row("T09_RESULT",c125,dut.qmw);
    if(nt09!=0||nreq!=74||nwin!=37888||npoint!=74||dut.qmw[159:128]!=6001||dut.qmw[127:96]!=1||dut.qmw[95:89]!=74||dut.qmw[88:82]!=74||dut.qmw[81:70]!=0||!dut.qmw[0])$fatal(1,"FULL023 residual estimator incomplete/invalid");
    if($signed(dut.qmw[69:38])!=-12945||dut.qmw[37:6]!=268435443)$fatal(1,"FULL023 T09 differs from frozen same-input numeric reference; E2 reference applicability requires review");
    nt09<=nt09+1;
   end
  end else begin raw_hold<=0;win_hold<=0;end
 end
 always @(posedge clk150)begin
  c150<=c150+1;
  if(!mreset)begin
   if(mfault)$fatal(1,"FULL023 output-domain fault code=%h",e150);
   if(dut.transport.cr)begin
    if(ni!=RAW_BEATS||nt06!=1||dut.transport.ctxppm!=32'hfda84565)$fatal(1,"FULL023 E1 started before inputs complete");
    event_row("E1_CONFIG",c150,dut.transport.cw);
   end
   if(dut.transport.e1mv&&dut.transport.e1mr)begin
    if(n1>=E1_BEATS||dut.transport.e1of!=6001||dut.transport.e1og!=1||dut.transport.e1ob!=n1||dut.transport.e1last!=(n1==E1_BEATS-1))$fatal(1,"FULL023 E1 output metadata");
    compare(dut.transport.e1data,ref1[n1],1,n1);$fwrite(df,"E1,%0d,6001,1,%0d,%0d,%032h\n",c150,n1,dut.transport.e1last,dut.transport.e1data);
    if(n1%32768==0)event_row("E1_PROGRESS",c150,n1);n1<=n1+1;
   end
   if(dut.transport.publish)begin
    if(npub!=0||n1!=E1_BEATS||!dut.transport.e1ok||dut.transport.first_pass.diagnostic_step!=268395209)$fatal(1,"FULL023 E1 completion");
    npub<=npub+1;event_row("E1_PUBLISH",c150,dut.transport.e1cycles);
   end
   if(dut.transport.resr)begin
    if(ne2cfg!=0||nt09!=1||npoint!=74)$fatal(1,"FULL023 E2 configuration ordering");
    ne2cfg<=ne2cfg+1;event_row("E2_CONFIG",c150,dut.transport.resw);
   end
   if(dut.transport.e2mv&&dut.transport.e2mr)begin
    if(n2>=OUT_BEATS||dut.transport.e2of!=6001||dut.transport.e2og!=1||dut.transport.e2ob!=n2||dut.transport.e2last!=(n2==OUT_BEATS-1))$fatal(1,"FULL023 E2 output metadata");
    compare(dut.transport.e2data,ref2[n2],2,n2);$fwrite(df,"E2,%0d,6001,1,%0d,%0d,%032h\n",c150,n2,dut.transport.e2last,dut.transport.e2data);
    if(n2%32768==0)event_row("E2_PROGRESS",c150,n2);n2<=n2+1;
   end
   if(dut.transport.e2state==2&&dut.transport.e2done&&dut.transport.e2ok)begin
    if(ndone!=0||n2!=OUT_BEATS||dut.transport.second_pass.diagnostic_step!=268435443)$fatal(1,"FULL023 E2 completion");
    ndone<=ndone+1;event_row("E2_COMPLETE",c150,dut.transport.e2cycles);
   end
   if(mv)begin
    if(no>=OUT_BEATS||mr[224:193]!=6001||mr[192:161]!=1||mr[160:129]!=no||mr[128]!=(no==OUT_BEATS-1))$fatal(1,"FULL023 final output identity/order");
    compare(mr[127:0],ref2[no],4,no);$fwrite(df,"OUT,%0d,6001,1,%0d,%0d,%032h\n",c150,no,mr[128],mr[127:0]);no<=no+1;
   end
  end
 end
 initial begin
  wait(no==OUT_BEATS);repeat(160)@(negedge clk125);
  if(ni!=RAW_BEATS||n1!=E1_BEATS||n2!=OUT_BEATS||no!=OUT_BEATS||nt06!=1||nt09!=1||npoint!=74||nwin!=37888||npub!=1||ne2cfg!=1||ndone!=1||dut.transport.e1state!=0||dut.transport.e2state!=0||dut.transport.obocc!=0||dut.transport.oa!=OUT_BEATS||dut.transport.oi!=OUT_BEATS||dut.transport.orr!=OUT_BEATS||dut.transport.oc!=OUT_BEATS||fault||mfault)$fatal(1,"FULL023 complete drain gate");
  $fflush(df);$fflush(ef);$fflush(pf);$fclose(df);$fclose(ef);$fclose(pf);
  rf=$fopen("result.txt","w");$fwrite(rf,"PASS=1\nNOMINAL_SAMPLES=1336320\nRAW_BEATS=%0d\nE1_BEATS=%0d\nE2_BEATS=%0d\nOUTPUT_BEATS=%0d\nT06_RESULTS=%0d\nT09_RESULTS=%0d\nT09_WINDOWS=%0d\nT09_POINTS=%0d\nMAX_LSB=%0d\nCYCLES125=%0d\nCYCLES150=%0d\nT06_T09_RESULTS_INJECTED=0\nPRODUCTION_CAPACITY_SIMULATED=1\nOUTPUT_CLOCK_MHZ=150\n",ni,n1,n2,no,nt06,nt09,nreq,npoint,maxdiff,c125,c150);$fclose(rf);
  $display("T10_FULL023_PASS full_frame=1336320 real_T06=1 real_T09=1 max_lsb=%0d",maxdiff);$finish;
 end
 initial begin repeat(2000000)@(posedge clk125);$fatal(1,"FULL023 global16ms simulation watchdog");end
 initial begin #1999;forever begin $fflush(df);$fflush(ef);$fflush(pf);#2000;end end

 integer xf;
 initial begin xf=$fopen("xpm_trace.csv","w");if(xf==0)$fatal(1,"FIFO trace open");$fwrite(xf,"Fifo,Domain,TimePs,Rst,WrBusy,RdBusy,WrEn,RdEn,Full,Empty,Sleep,Overflow,Underflow\n");end
 task automatic fifo_row(input string identity,input integer domain,input real time_ps,input logic[9:0] v);
 begin $fwrite(xf,"%s,%0d,%0.0f,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b\n",identity,domain,time_ps,v[9],v[8],v[7],v[6],v[5],v[4],v[3],v[2],v[1],v[0]);$fflush(xf);end endtask
 initial begin #1999;forever begin $fflush(xf);#2000;end end
endmodule
