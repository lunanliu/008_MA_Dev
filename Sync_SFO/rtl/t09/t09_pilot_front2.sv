// One selector register followed by the unchanged three-stage two-lane rotator.
// Slot/beat/error advance with the rotator's exact global enable; tag stays opaque.
module t09_pilot_front2 #(
 parameter PHASE_ROM_FILE="t09_pilot_phase.mem"
)(
 input logic clk,input logic rst,
 input logic s_valid,output logic s_ready,
 input logic [127:0] s_data,input logic [6:0] s_symbol_slot,
 input logic [8:0] s_fft_beat,input logic [31:0] s_tag,
 output logic m_valid,input logic m_ready,
 output logic [71:0] m_data,output logic [1:0] m_mask,output logic m_error,
 output logic [6:0] m_symbol_slot,output logic [8:0] m_fft_beat,
 output logic [31:0] m_tag,output logic busy
);
 logic selected_valid,selected_ready,selected_busy,rotate_busy;
 logic [63:0] selected_data;
 logic [5:0] selected_phase;
 logic [1:0] selected_mask;
 logic selected_error;
 logic [6:0] selected_slot;
 logic [8:0] selected_beat;
 logic [31:0] selected_tag;
 logic [16:0] meta1,meta2,meta3;
 wire rotate_advance=!m_valid || m_ready;
 t09_pilot_select_phase4 #(.PHASE_ROM_FILE(PHASE_ROM_FILE)) selector(
  .clk(clk),.rst(rst),.s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),
  .s_symbol_slot(s_symbol_slot),.s_fft_beat(s_fft_beat),.s_tag(s_tag),
  .m_valid(selected_valid),.m_ready(selected_ready),.m_data(selected_data),
  .m_phase(selected_phase),.m_mask(selected_mask),.m_error(selected_error),
  .m_symbol_slot(selected_slot),.m_fft_beat(selected_beat),.m_tag(selected_tag),.busy(selected_busy));
 t09_pilot_rotate2 rotator(
  .clk(clk),.rst(rst),.s_valid(selected_valid),.s_ready(selected_ready),
  .s_data(selected_data),.s_phase(selected_phase),.s_mask(selected_mask),.s_tag(selected_tag),
  .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_mask(m_mask),.m_tag(m_tag),.busy(rotate_busy));
 assign {m_symbol_slot,m_fft_beat,m_error}=meta3;
 assign busy=selected_busy || rotate_busy;
 always_ff @(posedge clk) begin
  if(rst)begin meta1<=0;meta2<=0;meta3<=0;end
  else if(rotate_advance)begin
   meta1<={selected_slot,selected_beat,selected_error};meta2<=meta1;meta3<=meta2;
  end
 end
endmodule
