`timescale 1ns/1ps
// Complete window observations cross as atomic messages; one frame outstanding.
module cfo_estimator_link(
 input wire clk_fast,clk_slow,reset_async,abort_async,
 input wire s_valid,output wire s_ready,
 input wire [31:0] s_frame,s_generation,input wire [6:0] s_window,
 input wire signed [37:0] s_z_i,s_z_q,input wire [9:0] s_pilot_count,
 input wire [15:0] s_fft_saturations,input wire [3:0] s_front_error,
 output wire m_valid,input wire m_ready,
 output wire [498:0] m_backend_word,output wire [3:0] m_link_error,m_front_error,
 output wire [22:0] m_fft_saturation_sum,
 output wire [4:0] fifo_write_count,fifo_read_count,
 output wire fifo_full,fifo_empty,fifo_overflow,fifo_underflow,
 output wire fast_reset_busy,slow_reset_busy,
 output logic read_audit_valid,output logic [170:0] read_audit_word,
 output wire normal_audit_valid,output wire [6:0] normal_audit_index,
 output wire fft_audit_valid,output wire [7:0] fft_audit_index
);
 wire rst_fast,rst_slow,wr_busy,rd_busy;
 wire common_reset=reset_async||abort_async;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1)) reset_fast_sync(.src_arst(common_reset),.dest_clk(clk_fast),.dest_arst(rst_fast));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1)) reset_slow_sync(.src_arst(common_reset),.dest_clk(clk_slow),.dest_arst(rst_slow));
 assign fast_reset_busy=rst_fast||wr_busy;
 assign slow_reset_busy=rst_slow||rd_busy;
 logic closed_fast;
 logic [6:0] expected_window;
 logic [31:0] locked_frame,locked_generation;
 logic done_toggle,done_seen;
 wire done_sync;
 xpm_cdc_single #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(0),.SRC_INPUT_REG(0),.SIM_ASSERT_CHK(1)) credit_return(.src_clk(clk_slow),.src_in(done_toggle),.dest_clk(clk_fast),.dest_out(done_sync));
 logic [3:0] input_link_error;
 wire [31:0] packet_frame=(expected_window==0)?s_frame:locked_frame;
 wire [31:0] packet_generation=(expected_window==0)?s_generation:locked_generation;
 always_comb begin
  input_link_error=0;
  if(s_front_error!=0)input_link_error=4;
  else if(s_pilot_count!=10'd820)input_link_error=5;
  else if(s_window>=7'd74)input_link_error=3;
  else if(expected_window!=0 && (s_frame!=locked_frame || s_generation!=locked_generation))input_link_error=1;
  else if(s_window!=expected_window)input_link_error=2;
  else if(s_z_i=={1'b1,37'd0} || s_z_q=={1'b1,37'd0})input_link_error=6;
 end
 wire [170:0] fifo_in={packet_frame,packet_generation,s_window,s_z_i,s_z_q,s_fft_saturations,input_link_error,s_front_error};
 wire [170:0] fifo_out;
 wire write_fire=s_valid&&s_ready;
 wire read_fire;
 assign s_ready=!fast_reset_busy&&!closed_fast&&!fifo_full;
 xpm_fifo_async #(
  .FIFO_MEMORY_TYPE("distributed"),.ECC_MODE("no_ecc"),.RELATED_CLOCKS(0),.SIM_ASSERT_CHK(1),
  .FIFO_WRITE_DEPTH(16),.WRITE_DATA_WIDTH(171),.WR_DATA_COUNT_WIDTH(5),.PROG_FULL_THRESH(10),.FULL_RESET_VALUE(0),.USE_ADV_FEATURES("0707"),
  .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.READ_DATA_WIDTH(171),.RD_DATA_COUNT_WIDTH(5),.PROG_EMPTY_THRESH(10),.DOUT_RESET_VALUE("0"),.CDC_SYNC_STAGES(2)
 ) observation_fifo(
  .sleep(1'b0),.rst(rst_fast),.wr_clk(clk_fast),.wr_en(write_fire),.din(fifo_in),.full(fifo_full),.prog_full(),.wr_data_count(fifo_write_count),.overflow(fifo_overflow),.wr_rst_busy(wr_busy),.almost_full(),.wr_ack(),
  .rd_clk(clk_slow),.rd_en(read_fire),.dout(fifo_out),.empty(fifo_empty),.prog_empty(),.rd_data_count(fifo_read_count),.underflow(fifo_underflow),.rd_rst_busy(rd_busy),.almost_empty(),.data_valid(),
  .injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr()
 );
 always_ff @(posedge clk_fast or posedge rst_fast)begin
  if(rst_fast)begin closed_fast<=0;expected_window<=0;locked_frame<=0;locked_generation<=0;done_seen<=0;end
  else if(wr_busy)begin closed_fast<=0;expected_window<=0;done_seen<=done_sync;end
  else begin
   done_seen<=done_sync;
   if(done_sync!=done_seen)begin closed_fast<=0;expected_window<=0;end
   if(write_fire)begin
    if(expected_window==0)begin locked_frame<=s_frame;locked_generation<=s_generation;end
    if(input_link_error!=0 || expected_window==7'd73)closed_fast<=1;
    else expected_window<=expected_window+7'd1;
   end
  end
 end
 wire [31:0] r_frame=fifo_out[170:139],r_generation=fifo_out[138:107];
 wire [6:0] r_window=fifo_out[106:100];
 wire signed [37:0] r_i=fifo_out[99:62],r_q=fifo_out[61:24];
 wire [15:0] r_saturations=fifo_out[23:8];
 wire [3:0] r_link_error=fifo_out[7:4],r_front_error=fifo_out[3:0];
 logic error_pending,abort_backend,fatal_backend;
 logic [31:0] error_frame,error_generation;
 logic [3:0] saved_link_error,saved_front_error;
 logic [22:0] saturation_sum;
 wire b_ready,b_valid,b_estimate_valid,b_spectrum,b_linear,b_consistent;
 wire [31:0] b_frame,b_generation;wire [3:0] b_error;wire [1:0] b_mode;
 wire signed [31:0] b_frequency,b_phase,b_fft;
 wire [196:0] b_quality;wire [131:0] b_phase_detail;
 wire b_normal_valid,b_fft_valid;
 wire backend_input_valid=!slow_reset_busy&&!fatal_backend&&!error_pending&&!fifo_empty&&(r_link_error==0);
 assign read_fire=!slow_reset_busy&&!fatal_backend&&!error_pending&&!fifo_empty&&((r_link_error!=0)||b_ready);
 cfo_estimate74_backend backend(
  .clk(clk_slow),.rst(slow_reset_busy),.abort_sync(abort_backend),.s_valid(backend_input_valid),.s_ready(b_ready),
  .s_frame(r_frame),.s_generation(r_generation),.s_index(r_window),.s_last(r_window==7'd73),.s_i(r_i),.s_q(r_q),
  .m_valid(b_valid),.m_ready(m_ready&&!error_pending&&!slow_reset_busy),.m_frame(b_frame),.m_generation(b_generation),.m_error(b_error),
  .m_mode(b_mode),.m_estimate_valid(b_estimate_valid),.m_frequency_q16(b_frequency),.m_phase_q16(b_phase),.m_fft_q16(b_fft),
  .m_spectrum(b_spectrum),.m_phase_linear(b_linear),.m_consistent(b_consistent),.m_quality(b_quality),.m_phase_detail(b_phase_detail),
  .normal_audit_valid(b_normal_valid),.normal_audit_index(normal_audit_index),.normal_audit_value(),
  .fft_audit_valid(b_fft_valid),.fft_audit_index(fft_audit_index),.fft_audit_value()
 );
 assign m_valid=!slow_reset_busy&&(error_pending||b_valid);
 assign m_backend_word=error_pending ? {error_frame,error_generation,435'd0} : {b_frame,b_generation,b_error,b_mode,b_estimate_valid,b_frequency,b_phase,b_fft,b_spectrum,b_linear,b_consistent,b_quality,b_phase_detail};
 assign m_link_error=error_pending?saved_link_error:4'd0;
 assign m_front_error=error_pending?saved_front_error:4'd0;
 assign m_fft_saturation_sum=saturation_sum;
 assign normal_audit_valid=b_normal_valid&&!slow_reset_busy&&!error_pending;
 assign fft_audit_valid=b_fft_valid&&!slow_reset_busy&&!error_pending;
 always_ff @(posedge clk_slow or posedge rst_slow)begin
  if(rst_slow)begin
   done_toggle<=0;error_pending<=0;abort_backend<=0;fatal_backend<=0;saturation_sum<=0;error_frame<=0;error_generation<=0;saved_link_error<=0;saved_front_error<=0;read_audit_valid<=0;read_audit_word<=0;
  end else if(rd_busy)begin
   done_toggle<=0;error_pending<=0;abort_backend<=0;fatal_backend<=0;saturation_sum<=0;read_audit_valid<=0;
  end else begin
   abort_backend<=0;read_audit_valid<=read_fire;
   if(read_fire)begin
    read_audit_word<=fifo_out;saturation_sum<=saturation_sum+{7'd0,r_saturations};
    if(r_link_error!=0)begin
     error_pending<=1;abort_backend<=1;error_frame<=r_frame;error_generation<=r_generation;saved_link_error<=r_link_error;saved_front_error<=r_front_error;
    end
   end
   if(b_valid&&b_error!=0)fatal_backend<=1;
   if(m_valid&&m_ready)begin
    if(error_pending || b_error==0)done_toggle<=!done_toggle;
    error_pending<=0;saturation_sum<=0;
   end
  end
 end
endmodule