`timescale 1ns/1ps
// V5.1: independent ordered input queues; registered identity-checked output.
// One frame can wait for E2 without blocking the next frame's E1 context.
// No downstream combinational ready path reaches either resampler launch.
module ota_sfo_context_join (
 input logic clk,rst,cancel,
 input logic meta_valid,output logic meta_ready,
 input logic [31:0] meta_frame,meta_generation,
 input logic signed [31:0] meta_coarse_hz_q8,
 input logic signed [53:0] meta_raw_origin_q28,
 input logic first_valid,output logic first_ready,
 input logic [31:0] first_frame,first_generation,first_step_q28,
 input logic second_valid,output logic second_ready,
 input logic [31:0] second_frame,second_generation,second_step_q28,
 output logic m_valid,input logic m_ready,output logic [213:0] m_context,
 output logic [7:0] error_code
);
 localparam [1:0] WAIT_HEADS=0,CHECK_IDENTITY=1,HOLD_RESULT=2;
 logic [1:0] state;
 wire active=!rst&&!cancel&&error_code==0;
 wire mr,fr,sr,mv,fv,sv,me,fe,se;
 wire [149:0] md;
 wire [95:0] fd,sd;
 logic [149:0] held_meta;
 logic [95:0] held_first,held_second;
 wire take=active&&state==WAIT_HEADS&&mv&&fv&&sv;
 assign meta_ready=active&&mr;
 assign first_ready=active&&fr;
 assign second_ready=active&&sr;
 assign m_valid=active&&state==HOLD_RESULT;
 sfo_sync_fifo #(.WIDTH(150),.DEPTH(32)) metadata_queue(
  .clk(clk),.rst(rst||cancel),.s_valid(meta_valid&&active),.s_ready(mr),
  .s_data({meta_frame,meta_generation,meta_coarse_hz_q8,meta_raw_origin_q28}),
  .m_valid(mv),.m_ready(take),.m_data(md),.level(),.high_water(),.reset_busy(),.error_sticky(me));
 sfo_sync_fifo #(.WIDTH(96),.DEPTH(32)) first_queue(
  .clk(clk),.rst(rst||cancel),.s_valid(first_valid&&active),.s_ready(fr),
  .s_data({first_frame,first_generation,first_step_q28}),
  .m_valid(fv),.m_ready(take),.m_data(fd),.level(),.high_water(),.reset_busy(),.error_sticky(fe));
 sfo_sync_fifo #(.WIDTH(96),.DEPTH(32)) second_queue(
  .clk(clk),.rst(rst||cancel),.s_valid(second_valid&&active),.s_ready(sr),
  .s_data({second_frame,second_generation,second_step_q28}),
  .m_valid(sv),.m_ready(take),.m_data(sd),.level(),.high_water(),.reset_busy(),.error_sticky(se));
 always_ff @(posedge clk) begin
  if(rst||cancel) begin
   state<=WAIT_HEADS;error_code<=0;m_context<=0;
   held_meta<=0;held_first<=0;held_second<=0;
  end else if(error_code==0) begin
   if(me||fe||se) error_code<=8'h43;
   else case(state)
    WAIT_HEADS:if(take)begin
     held_meta<=md;held_first<=fd;held_second<=sd;state<=CHECK_IDENTITY;
    end
    CHECK_IDENTITY:begin
     if(held_first[95:32]!=held_meta[149:86]||held_first[31:0]==0) error_code<=8'h41;
     else if(held_second[95:32]!=held_meta[149:86]||held_second[31:0]==0) error_code<=8'h42;
     else begin
      m_context<={held_meta[149:86],held_first[31:0],held_second[31:0],held_meta[53:0],held_meta[85:54]};
      state<=HOLD_RESULT;
     end
    end
    HOLD_RESULT:if(m_ready)state<=WAIT_HEADS;
    default:error_code<=8'h44;
   endcase
  end
 end
endmodule
