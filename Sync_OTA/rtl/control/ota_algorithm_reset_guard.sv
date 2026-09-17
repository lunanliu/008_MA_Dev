`timescale 1ns/1ps
// Fixed, running 125/150/500MHz domain contract. The caller blocks data
// immediately on cancel and waits reset_stable before completing cancellation.
module ota_algorithm_reset_guard (
 input wire clk125,global_reset,request_reset,
 output logic reset_active,
 output wire reset_stable
);
 localparam integer ASSERT_CYCLES=16;
 localparam integer RELEASE_CYCLES=128;
 logic [7:0] age;
 wire interval_done=reset_active?(age>=ASSERT_CYCLES-1):(age>=RELEASE_CYCLES-1);
 assign reset_stable=!global_reset&&(reset_active==request_reset)&&interval_done;
 always_ff @(posedge clk125 or posedge global_reset)begin
  if(global_reset)begin reset_active<=1'b1;age<=0;end
  else if(request_reset!=reset_active&&interval_done)begin
   reset_active<=request_reset;age<=0;
  end else if(!interval_done)age<=age+1'b1;
 end
endmodule
