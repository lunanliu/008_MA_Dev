`timescale 1ns/1ps
module cfo_rotate4_tb;
 localparam integer B=1280;
 logic clk=0;always #3.333333 clk=~clk;
 logic rst=1,abort_sync=0,cfg_valid=0,cfg_ready;
 logic [31:0] cfg_frame=0,cfg_generation=0,cfg_phase0=0,cfg_step=0,cfg_sample_count=5120;
 logic s_valid=0,s_ready,m_valid,m_ready=0,fault;logic [3:0] first_error;
 logic [224:0] s_record=0,m_record;logic [7:0] m_saturation;
 cfo_rotate4 dut(.*);
 logic [127:0] inputs[0:B-1],expected[0:B-1];logic [7:0] sats[0:B-1];
 logic [31:0] phase_table[0:3],step_table[0:3];
 integer cycle=0,sent=0,received=0,case_id=-1,total_out=0,sat_count=0;
 integer first_in=-1,last_in=-1,first_out=-1,last_out=-1,source_stalls=0,output_stalls=0;
 integer log_fd,summary_fd,j,probe_sent=0,reset_discard=0;
 bit monitor_on=0,held_input=0,held_output=0,probe=0;
 logic [224:0] previous_input,previous_output;logic [7:0] previous_sat;
 task automatic fail(input string why);
  begin $display("CFO_FIRST_ERROR cycle=%0d time=%0t case=%0d frame=%0d sent=%0d received=%0d reason=%s",cycle,$time,case_id,cfg_frame,sent,received,why);$fatal(1,"%s",why);end
 endtask
 always @(posedge clk)begin
  cycle=cycle+1;if(cycle>100000)fail("TB hard cycle timeout");
  if(rst||abort_sync)begin held_input=0;held_output=0;end
  else begin
   if(held_output&&({m_valid,m_record,m_saturation}!=={1'b1,previous_output,previous_sat}))fail("blocked output changed");
   if(held_input&&({s_valid,s_record}!=={1'b1,previous_input}))fail("blocked input changed");
   held_input=s_valid&&!s_ready;previous_input=s_record;
   held_output=m_valid&&!m_ready;previous_output=m_record;previous_sat=m_saturation;
   if(probe&&s_valid&&s_ready)probe_sent=probe_sent+1;
   if(monitor_on)begin
    if(fault)fail("unexpected DUT fault");
    if(s_valid&&!s_ready)source_stalls=source_stalls+1;
    if(m_valid&&!m_ready)output_stalls=output_stalls+1;
    if(s_valid&&s_ready)begin
     if(sent>=B)fail("extra input");
     if(s_record!=={cfg_frame,cfg_generation,32'(sent),1'(sent==B-1),inputs[sent]})fail("input sequencing");
     if(case_id==0&&last_in>=0&&cycle!=last_in+1)fail("continuous input II not one");
     if(first_in<0)first_in=cycle;last_in=cycle;sent=sent+1;
    end
    if(m_valid&&m_ready)begin
     if(received>=B||received>=sent)fail("extra or premature output");
     if(m_record!=={cfg_frame,cfg_generation,32'(received),1'(received==B-1),expected[received]}||m_saturation!==sats[received])begin
      $display("ACTUAL=%057h SAT=%02h EXPECTED=%057h SAT=%02h",m_record,m_saturation,{cfg_frame,cfg_generation,32'(received),1'(received==B-1),expected[received]},sats[received]);fail("output arithmetic or metadata mismatch");
     end
     if(case_id==0&&last_out>=0&&cycle!=last_out+1)fail("continuous output II not one");
     if(first_out<0)first_out=cycle;last_out=cycle;
     for(j=0;j<8;j=j+1)if(m_saturation[j])sat_count=sat_count+1;
     $fdisplay(log_fd,"%0d,%0d,%0d,%057h,%02h",case_id,cycle,received,m_record,m_saturation);
     received=received+1;total_out=total_out+1;
     if(received%256==0)$display("CFO_PROGRESS cycle=%0d time=%0t case=%0d accepted_in=%0d accepted_out=%0d",cycle,$time,case_id,sent,received);
    end
   end else if(m_valid&&m_ready)fail("stale output outside frame");
  end
 end
 task automatic read_vectors(input integer c);
  integer a,b,d,n,ra,rb,rd;reg [127:0] extra_a,extra_b;reg [7:0] extra_d;
  begin
   a=$fopen($sformatf("rot_case%0d_input.mem",c),"r");b=$fopen($sformatf("rot_case%0d_expected.mem",c),"r");d=$fopen($sformatf("rot_case%0d_sat.mem",c),"r");
   if(a==0||b==0||d==0)fail("vector open failed");
   for(n=0;n<B;n=n+1)begin
    ra=$fscanf(a,"%h",inputs[n]);rb=$fscanf(b,"%h",expected[n]);rd=$fscanf(d,"%h",sats[n]);
    if(ra!=1||rb!=1||rd!=1||$isunknown({inputs[n],expected[n],sats[n]}))fail($sformatf("vector length/unknown at %0d",n));
   end
   ra=$fscanf(a,"%h",extra_a);rb=$fscanf(b,"%h",extra_b);rd=$fscanf(d,"%h",extra_d);
   if(ra==1||rb==1||rd==1)fail("vector longer than frozen count");
   $fclose(a);$fclose(b);$fclose(d);
   $display("CFO_LOADED case=%0d count=%0d first=%032h last=%032h first_expected=%032h last_expected=%032h phase0=%08h step=%08h",c,B,inputs[0],inputs[B-1],expected[0],expected[B-1],phase_table[c],step_table[c]);
  end
 endtask
 task automatic configure(input integer c,input integer gen);
  begin
   @(negedge clk);cfg_frame=100+c;cfg_generation=gen;cfg_phase0=phase_table[c];cfg_step=step_table[c];cfg_sample_count=5120;cfg_valid=1;
   do @(posedge clk);while(!cfg_ready);
   @(negedge clk);cfg_valid=0;
  end
 endtask
 task automatic run_case(input integer c);
  begin
   @(negedge clk);case_id=c;read_vectors(c);sent=0;received=0;sat_count=0;source_stalls=0;output_stalls=0;first_in=-1;last_in=-1;first_out=-1;last_out=-1;
   configure(c,20+c);monitor_on=1;
   while(received<B)begin
    m_ready=(c==0)||(c==1?(cycle%19<13):(cycle%31<17));
    if(!held_input)begin
     s_valid=(sent<B)&&((c==0)||cycle%7!=0);
     if(s_valid)s_record={cfg_frame,cfg_generation,32'(sent),1'(sent==B-1),inputs[sent]};
    end
    @(negedge clk);
   end
   s_valid=0;m_ready=1;monitor_on=0;
   if(sent!=B)fail("accepted count conservation");
   if((c==2&&sat_count!=5040)||(c!=2&&sat_count!=0))fail("saturation count");
   $fdisplay(summary_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",c,sent,received,sat_count,source_stalls,output_stalls,first_in,last_in,first_out,last_out);
   repeat(7)@(negedge clk);
  end
 endtask
 task automatic flush_probe(input bit use_abort);
  begin
   case_id=-1;configure(0,use_abort?8:7);m_ready=0;probe_sent=0;probe=1;
   while(probe_sent<4)begin s_valid=1;s_record={cfg_frame,cfg_generation,32'(probe_sent),1'b0,128'h12345678};@(negedge clk);end
   s_valid=0;probe=0;repeat(3)@(negedge clk);
   if(!m_valid)fail("reset probe did not fill pipeline");
   if(use_abort)abort_sync=1;else rst=1;
   repeat(2)@(negedge clk);abort_sync=0;rst=0;m_ready=1;reset_discard=reset_discard+probe_sent;
   repeat(8)@(negedge clk);if(m_valid||fault||!cfg_ready)fail("flush did not release context");
   $display("CFO_FLUSH_PROBE abort=%0d discarded=%0d",use_abort,probe_sent);
  end
 endtask
 initial begin
  `include "rotator_configs.svh"
  log_fd=$fopen("rotator_actual.csv","w");summary_fd=$fopen("rotator_summary.csv","w");if(!log_fd||!summary_fd)fail("report open");
  $fdisplay(log_fd,"case,cycle,beat,record_hex,saturation_hex");$fdisplay(summary_fd,"case,input_beats,output_beats,saturated_components,input_stall_cycles,output_stall_cycles,first_input_cycle,last_input_cycle,first_output_cycle,last_output_cycle");
  repeat(5)@(negedge clk);for(j=0;j<1024;j=j+1)if($isunknown({dut.lut_a[j],dut.lut_b[j]})||dut.lut_a[j]!==dut.lut_b[j])fail("ROM missing or inconsistent");rst=0;m_ready=1;
  flush_probe(0);run_case(0);flush_probe(1);run_case(1);run_case(2);run_case(3);
  configure(0,99);s_valid=1;s_record={cfg_frame,cfg_generation,32'd1,1'b0,128'd0};
  @(posedge clk);@(negedge clk);s_valid=0;
  if(!fault||first_error!=2||m_valid||s_ready||cfg_ready)fail("metadata fault handling");
  rst=1;repeat(2)@(negedge clk);rst=0;
  cfg_sample_count=3;cfg_valid=1;@(posedge clk);@(negedge clk);cfg_valid=0;
  if(!fault||first_error!=1||m_valid)fail("invalid configuration handling");
  $fclose(log_fd);$fclose(summary_fd);
  $display("CFO_ROTATOR_PASS cases=4 accepted_output_beats=%0d complex_samples=%0d flush_discarded_beats=%0d cycles=%0d",total_out,total_out*4,reset_discard,cycle);
  if(total_out!=5120||reset_discard!=8)fail("final count");
  $finish;
 end
endmodule