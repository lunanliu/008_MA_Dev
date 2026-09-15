// Stateless beat descriptor -> two selected pilots and production phase opcodes.
// Slot j corresponds to payload symbol 7*j. Beat b contains natural FFT bins4*b..4*b+3.
module t09_pilot_select_phase4 #(
 parameter PHASE_ROM_FILE="t09_pilot_phase.mem"
)(
 input logic clk,input logic rst,
 input logic s_valid,output logic s_ready,
 input logic [127:0] s_data,input logic [6:0] s_symbol_slot,
 input logic [8:0] s_fft_beat,input logic [31:0] s_tag,
 output logic m_valid,input logic m_ready,
 output logic [63:0] m_data,output logic [5:0] m_phase,
 output logic [1:0] m_mask,output logic m_error,
 output logic [6:0] m_symbol_slot,output logic [8:0] m_fft_beat,
 output logic [31:0] m_tag,output logic busy
);
 (* rom_style="block" *) logic [5:0] phase_rom[0:37887];
 initial $readmemh(PHASE_ROM_FILE,phase_rom);
 wire slot_ok=s_symbol_slot<7'd74;
 wire [15:0] rom_address={s_symbol_slot,s_fft_beat};
 wire [1:0] select_mask;
 assign select_mask[0]=slot_ok && ((s_fft_beat>=9'd1 && s_fft_beat<=9'd205) || s_fft_beat>=9'd307);
 assign select_mask[1]=slot_ok && (s_fft_beat<=9'd204 || s_fft_beat>=9'd307);
 wire advance=!m_valid || m_ready;
 assign s_ready=!rst && advance;
 assign busy=m_valid;
 always_ff @(posedge clk) begin
  if(rst) begin
   m_valid<=0;m_data<=0;m_phase<=0;m_mask<=0;m_error<=0;
   m_symbol_slot<=0;m_fft_beat<=0;m_tag<=0;
  end else if(advance) begin
   m_valid<=s_valid;m_tag<=s_tag;m_symbol_slot<=s_symbol_slot;m_fft_beat<=s_fft_beat;
   m_mask<=select_mask;m_error<=!slot_ok;
   m_data[31:0]<=select_mask[0] ? s_data[31:0] : 32'd0;
   m_data[63:32]<=select_mask[1] ? s_data[95:64] : 32'd0;
   // Invalid descriptors never index outside the 74*512 ROM.
   if(slot_ok) m_phase<=phase_rom[rom_address];
   else m_phase<=0;
  end
 end
endmodule