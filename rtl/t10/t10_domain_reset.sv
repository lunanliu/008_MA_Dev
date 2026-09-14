`timescale 1ns/1ps
module t10_domain_reset(input logic clk,reset_request,output logic reset_active);
 wire synced;logic [6:0] hold_count;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(1)) sync_reset(.src_arst(reset_request),.dest_clk(clk),.dest_arst(synced));
 always_ff @(posedge clk or posedge synced)begin
  if(synced)begin hold_count<=0;reset_active<=1;end
  else if(hold_count<64)begin hold_count<=hold_count+1'b1;reset_active<=1;end
  else reset_active<=0;
 end
endmodule
