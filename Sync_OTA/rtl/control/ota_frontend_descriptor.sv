`timescale 1ns/1ps
// One frontend record atomically owns all three independently backpressured outputs.
// Coordinates are relative to the accepted capture epoch, NOT wall clock cycles.
module ota_frontend_descriptor (
 input logic clk,rst,cancel,
 input logic s_valid,output logic s_ready,input logic [287:0] s_record,
 input logic [31:0] capture_epoch,capture_generation,
 input logic [63:0] capture_samples,
 output logic frame_valid,input logic frame_ready,output logic [187:0] frame_record,
 output logic cfo_valid,input logic cfo_ready,output logic [95:0] cfo_record,
 output logic fine_valid,input logic fine_ready,output logic [95:0] fine_record,
 output logic [63:0] replay_first_sample,nominal_absolute_sample,
 output logic [31:0] replay_sample_count,frame_id,generation,
 output logic signed [31:0] coarse_hz_q8,
 output logic signed [53:0] raw_origin_q28,
 output logic done,output logic [7:0] error_code
);
 localparam logic [31:0] RAW_COUNT=1336860;
 logic [2:0] pending;
 wire [31:0] fe_epoch=s_record[287:256],fe_frame=s_record[255:224];
 wire [63:0] fine_abs=s_record[127:64];
 wire [63:0] nominal={fine_abs[63:2],2'b00};
 wire signed [31:0] hz=$signed(s_record[63:32]);
 wire [31:0] local_to={30'd0,fine_abs[1:0]};
 wire [2:0] accepted={fine_valid&&fine_ready,cfo_valid&&cfo_ready,frame_valid&&frame_ready};
 assign s_ready=!rst&&!cancel&&pending==0&&error_code==0;
 assign frame_valid=!rst&&!cancel&&pending[0];
 assign cfo_valid=!rst&&!cancel&&pending[1];
 assign fine_valid=!rst&&!cancel&&pending[2];
 always_ff @(posedge clk) begin
  if(rst||cancel)begin
   pending<=0;frame_record<=0;cfo_record<=0;fine_record<=0;
   replay_first_sample<=0;nominal_absolute_sample<=0;replay_sample_count<=0;
   frame_id<=0;generation<=0;coarse_hz_q8<=0;raw_origin_q28<=0;done<=0;error_code<=0;
  end else begin
   done<=0;
   if(pending!=0)begin pending<=pending&~accepted;if((pending&~accepted)==0)done<=1;end
   if(s_valid&&s_ready)begin
    if(fe_epoch!=capture_epoch)error_code<=8'h31;
    else if(s_record[15:0]!=16'h3800)error_code<=8'h32;
    else if(nominal<172 || nominal-64'd172>capture_samples || capture_samples-(nominal-64'd172)<RAW_COUNT)error_code<=8'h33;
    else if(hz < -32'sd8388607 || hz > 32'sd8388607)error_code<=8'h34;
    else begin
     pending<=3'b111;frame_id<=fe_frame;generation<=capture_generation;
     nominal_absolute_sample<=nominal;replay_first_sample<=nominal-64'd172;replay_sample_count<=RAW_COUNT;
     // raw_first_word is the new SFO ring's sequence number, never a DDR address.
     frame_record<={fe_frame,capture_generation,64'd0,32'd0,28'd0};
     cfo_record<={hz,s_record[31:16],16'h2800,fe_frame};
     fine_record<={local_to,s_record[31:16],16'h3800,fe_frame};
     coarse_hz_q8<=hz<<<8;
     raw_origin_q28<=$signed({24'd0,local_to[1:0],28'd0});
    end
   end
  end
 end
endmodule
