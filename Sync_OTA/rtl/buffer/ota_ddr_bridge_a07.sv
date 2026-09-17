`timescale 1ns/1ps
// A07: idle excludes a waiting RAW command; all four FIFO faults are visible.
// One external DDR credit; complete records cross 150 -> 125 -> 150.
// Algorithm cancel MUST NOT reset this bridge. Only a coordinated platform
// reset may discard a DDR transaction. Addresses count 128-bit words.
module ota_ddr_bridge (
 input wire clk125,clk150,reset_request,
 input wire raw_cmd_valid,output wire raw_cmd_ready,input wire raw_cmd_write,
 input wire [63:0] raw_cmd_address,raw_cmd_tag,input wire [127:0] raw_cmd_data,
 output wire raw_rsp_valid,input wire raw_rsp_ready,output wire [63:0] raw_rsp_tag,
 output wire [127:0] raw_rsp_data,output wire raw_rsp_error,
 input wire cfo_cmd_valid,output wire cfo_cmd_ready,input wire cfo_cmd_write,
 input wire [63:0] cfo_cmd_address,cfo_cmd_tag,input wire [127:0] cfo_cmd_data,
 output wire cfo_rsp_valid,input wire cfo_rsp_ready,output wire [63:0] cfo_rsp_tag,
 output wire [127:0] cfo_rsp_data,output wire cfo_rsp_error,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire [63:0] cmd_address,output wire [64:0] cmd_tag,output wire [127:0] cmd_data,
 input wire rsp_valid,output wire rsp_ready,input wire [64:0] rsp_tag,
 input wire [127:0] rsp_data,input wire rsp_error,
 output wire idle125,output logic [7:0] error125,
 output logic [31:0] commands125,responses125,stale_responses125,
 output wire [5:0] request_level125,response_level125
);
 wire rst125,rst150;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
 reset_sync(.src_arst(reset_request),.dest_clk(clk125),.dest_arst(rst125));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1))
 reset150_sync(.src_arst(reset_request),.dest_clk(clk150),.dest_arst(rst150));
 wire request_valid,request_ready,response_valid,response_ready;
 wire [256:0] request_word;
 wire [192:0] response_word;
 wire req_wbusy,req_rbusy,rsp_wbusy,rsp_rbusy;
 wire req_over,req_under,rsp_over,rsp_under;
 logic fifo_fault150;
 wire fifo_fault125;
 // Source-domain sticky bit survives a brief error and crosses atomically.
 always_ff @(posedge clk150)begin
  if(rst150)fifo_fault150<=1'b0;
  else if(req_over||rsp_under)fifo_fault150<=1'b1;
 end
 xpm_cdc_single #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.SRC_INPUT_REG(0))
 fifo_fault_sync(.src_clk(clk150),.src_in(fifo_fault150),.dest_clk(clk125),.dest_out(fifo_fault125));
 ota_async_fifo #(.WIDTH(257)) requests(
  .wr_clk(clk150),.rd_clk(clk125),.reset_request(reset_request),
  .s_valid(cfo_cmd_valid),.s_ready(cfo_cmd_ready),.s_data({cfo_cmd_write,cfo_cmd_address,cfo_cmd_tag,cfo_cmd_data}),
  .m_valid(request_valid),.m_ready(request_ready),.m_data(request_word),
  .wr_busy(req_wbusy),.rd_busy(req_rbusy),.wr_count(),.rd_count(request_level125),.overflow(req_over),.underflow(req_under));
 ota_async_fifo #(.WIDTH(193)) responses(
  .wr_clk(clk125),.rd_clk(clk150),.reset_request(reset_request),
  .s_valid(response_valid),.s_ready(response_ready),.s_data({rsp_tag[63:0],rsp_data,rsp_error}),
  .m_valid(cfo_rsp_valid),.m_ready(cfo_rsp_ready),.m_data(response_word),
  .wr_busy(rsp_wbusy),.rd_busy(rsp_rbusy),.wr_count(response_level125),.rd_count(),.overflow(rsp_over),.underflow(rsp_under));
 assign {cfo_rsp_tag,cfo_rsp_data,cfo_rsp_error}=response_word;
 localparam [1:0] SELECT=0,ISSUE=1,WAIT_RESPONSE=2;
 logic [1:0] state;
 logic prefer_cfo,owner;
 logic [256:0] held_command;
 wire choose_cfo=request_valid&&(!raw_cmd_valid||prefer_cfo);
 assign raw_cmd_ready=!rst125&&state==SELECT&&!choose_cfo;
 assign request_ready=!rst125&&state==SELECT&&choose_cfo;
 assign cmd_valid=!rst125&&state==ISSUE;
 assign {cmd_write,cmd_address,cmd_tag[63:0],cmd_data}=held_command;
 assign cmd_tag[64]=owner;
 wire match_tag=rsp_tag==cmd_tag;
 wire waiting=!rst125&&state==WAIT_RESPONSE;
 assign raw_rsp_valid=waiting&&rsp_valid&&match_tag&&!owner;
 assign raw_rsp_tag=rsp_tag[63:0];
 assign raw_rsp_data=rsp_data;
 assign raw_rsp_error=rsp_error;
 assign response_valid=waiting&&rsp_valid&&match_tag&&owner;
 assign rsp_ready=waiting&&(!match_tag||(owner?response_ready:raw_rsp_ready));
 assign idle125=!rst125&&state==SELECT&&!raw_cmd_valid&&!request_valid&&!req_rbusy&&!rsp_wbusy&&response_level125==0;
 always_ff @(posedge clk125)begin
  if(rst125)begin
   state<=SELECT;prefer_cfo<=0;owner<=0;held_command<=0;
   error125<=0;commands125<=0;responses125<=0;stale_responses125<=0;
  end else begin
   if((req_under||rsp_over||fifo_fault125)&&error125==0)error125<=8'h72;
   case(state)
    SELECT:if(choose_cfo)begin held_command<=request_word;owner<=1;state<=ISSUE;end
     else if(raw_cmd_valid)begin held_command<={raw_cmd_write,raw_cmd_address,raw_cmd_tag,raw_cmd_data};owner<=0;state<=ISSUE;end
    ISSUE:if(cmd_valid&&cmd_ready)begin commands125<=commands125+1'b1;state<=WAIT_RESPONSE;end
    WAIT_RESPONSE:if(rsp_valid&&rsp_ready)begin
     if(!match_tag)begin stale_responses125<=stale_responses125+1'b1;if(error125==0)error125<=8'h71;end
     else begin responses125<=responses125+1'b1;prefer_cfo<=!owner;state<=SELECT;end
    end
    default:begin state<=SELECT;if(error125==0)error125<=8'h7f;end
   endcase
  end
 end
endmodule
