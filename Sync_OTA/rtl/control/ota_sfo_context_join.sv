`timescale 1ns/1ps
// clk150 atomic join. E1/E2 inputs are the formal engine-config handshakes,
// never diagnostics. E2 cannot launch until the downstream CFO owns this context.
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
 logic have_meta,have_first;
 logic [31:0] frame_id,generation,step1;
 logic signed [31:0] coarse_hz;
 logic signed [53:0] origin;
 wire first_identity_matches=first_frame==frame_id&&first_generation==generation&&first_step_q28!=0;
 wire second_identity_matches=second_frame==frame_id&&second_generation==generation&&second_step_q28!=0;
 assign meta_ready=!rst&&!cancel&&error_code==0&&!have_meta;
 assign first_ready=!rst&&!cancel&&error_code==0&&have_meta&&!have_first&&first_identity_matches;
 assign m_valid=!rst&&!cancel&&error_code==0&&have_meta&&have_first&&second_valid&&second_identity_matches;
 assign second_ready=m_valid&&m_ready;
 assign m_context={frame_id,generation,step1,second_step_q28,origin,coarse_hz};
 always_ff @(posedge clk)begin
  if(rst||cancel)begin
   have_meta<=0;have_first<=0;frame_id<=0;generation<=0;step1<=0;coarse_hz<=0;origin<=0;error_code<=0;
  end else if(error_code==0)begin
   if(meta_valid&&meta_ready)begin
    have_meta<=1;frame_id<=meta_frame;generation<=meta_generation;
    coarse_hz<=meta_coarse_hz_q8;origin<=meta_raw_origin_q28;
   end
   if(first_valid&&have_meta&&!have_first&&!first_identity_matches)error_code<=8'h41;
   if(second_valid&&have_meta&&have_first&&!second_identity_matches)error_code<=8'h42;
   if(first_valid&&first_ready)begin have_first<=1;step1<=first_step_q28;end
   if(m_valid&&m_ready)begin have_meta<=0;have_first<=0;end
  end
 end
endmodule

