`timescale 1ns/1ps
// Data-only URAM ring plus a FIFO of one complete identity per frame.
// Arbitrary frame identifiers are preserved; backpressure is legal.
module t10_output_buffer #(parameter integer FRAME_BEATS=334080,DEPTH=65536,AW=$clog2(DEPTH),RESPONSE_DEPTH=64)(
 input logic clk,rst,poison,
 input logic s_valid,output logic s_ready,input logic [127:0] s_data,
 input logic [31:0] s_frame,s_generation,s_beat,input logic s_last,
 output logic m_valid,input logic m_ready,output logic [224:0] m_record,
 output logic [31:0] occupancy,high_water,outstanding_high_water,
 output logic [63:0] accepted,issued,returned,consumed,output logic fault,output logic [7:0] first_error
);
 logic [AW-1:0] wp,rp;logic [1:0] rv;logic [31:0] input_beat,input_frame,input_gen,output_beat;
 wire halted=poison||fault;wire hr,hv,hbusy,he,qr,qv,qbusy,qe;wire [63:0] hd;wire [127:0] rd,qd;
 wire [63:0] outstanding=issued-consumed;
 assign s_ready=!rst&&!halted&&occupancy<DEPTH&&(input_beat!=0||hr)&&!hbusy;
 wire wf=s_valid&&s_ready;
 wire valid_input=s_beat==input_beat&&s_beat<FRAME_BEATS&&s_last==(s_beat==FRAME_BEATS-1)&&
                   (input_beat==0||(s_frame==input_frame&&s_generation==input_gen));
 wire read_command=!rst&&!halted&&occupancy!=0&&outstanding<RESPONSE_DEPTH&&qr&&!qbusy;
 wire collision=wf&&read_command&&wp==rp;
 assign m_valid=!rst&&!halted&&qv&&hv;wire pop=m_valid&&m_ready;wire last=output_beat==FRAME_BEATS-1;
 assign m_record={hd[63:32],hd[31:0],output_beat,last,qd};
 t03_uram_frame_bank #(.DEPTH_BEATS(DEPTH),.ADDR_WIDTH(AW)) storage(.clk(clk),.rst(rst),.wr_en(wf&&valid_input&&!collision),.wr_addr(wp),.wr_data(s_data),.rd_en(read_command&&!collision),.rd_addr(rp),.rd_data(rd));
 t07_sync_fifo #(.WIDTH(64),.DEPTH(32)) headers(.clk(clk),.rst(rst),.s_valid(wf&&valid_input&&input_beat==0),.s_ready(hr),.s_data({s_frame,s_generation}),.m_valid(hv),.m_ready(pop&&last),.m_data(hd),.level(),.high_water(),.reset_busy(hbusy),.error_sticky(he));
 t07_sync_fifo #(.WIDTH(128),.DEPTH(RESPONSE_DEPTH)) responses(.clk(clk),.rst(rst),.s_valid(rv[1]),.s_ready(qr),.s_data(rd),.m_valid(qv),.m_ready(pop),.m_data(qd),.level(),.high_water(),.reset_busy(qbusy),.error_sticky(qe));
 logic [7:0] bad;
 always_comb begin
  bad=0;
  if(he||qe||(rv[1]&&!qr))bad=1;
  else if(wf&&!valid_input)bad=2;
  else if(collision)bad=3;
  else if(occupancy>DEPTH||consumed>returned||returned>issued||issued>accepted||outstanding>RESPONSE_DEPTH)bad=4;
 end
 always_ff @(posedge clk)begin
  if(rst)begin wp<=0;rp<=0;rv<=0;input_beat<=0;input_frame<=0;input_gen<=0;output_beat<=0;occupancy<=0;high_water<=0;accepted<=0;issued<=0;returned<=0;consumed<=0;fault<=0;first_error<=0;outstanding_high_water<=0;end
  else begin
   rv<={rv[0],read_command&&!collision};
   if(!fault&&bad!=0)begin fault<=1;first_error<=bad;end
   if(occupancy>high_water)high_water<=occupancy;
   if(outstanding>outstanding_high_water)outstanding_high_water<=outstanding;
   if(rv[1]&&qr)returned<=returned+1;
   if(!halted&&bad==0)begin
    case({wf,read_command})2'b10:occupancy<=occupancy+1;2'b01:occupancy<=occupancy-1;default:begin end endcase
    if(wf)begin wp<=wp+1'b1;accepted<=accepted+1;input_frame<=s_frame;input_gen<=s_generation;input_beat<=s_last?0:input_beat+1;end
    if(read_command)begin rp<=rp+1'b1;issued<=issued+1;end
    if(pop)begin consumed<=consumed+1;output_beat<=last?0:output_beat+1;end
   end
  end
 end
 // synthesis translate_off
 initial if(DEPTH<128||(DEPTH&(DEPTH-1))!=0||FRAME_BEATS<1)$fatal(1,"Output buffer geometry");
 // synthesis translate_on
endmodule
