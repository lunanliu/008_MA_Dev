`timescale 1ns / 1ps
// Repack the accepted chain's 0000 x7,1000,1111...,0111 sequence to full low-lane-first words.
// Research closeout implementation; functional and physical gates still pending.
module sfo_nominal_pack4 #(
    parameter int unsigned SAMPLE_COUNT = 1_336_392
) (
    input  logic         clk,
    input  logic         rst,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_data,
    input  logic [  3:0] s_mask,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [127:0] m_data,
    output logic [ 31:0] m_beat,
    output logic         m_last,
    output logic [ 31:0] formed_beats,
    output logic [ 31:0] physical_beats,
    output logic         error_sticky
);
  logic pending_valid;
  localparam int unsigned OUTPUT_BEATS   = SAMPLE_COUNT / 4;
  localparam int unsigned PHYSICAL_BEATS = OUTPUT_BEATS + 8;
  logic [31:0] carry;
  logic carry_valid;
  logic [3:0] expected_mask;
  always_comb begin
    if (physical_beats < 7) expected_mask = 4'b0000;
    else if (physical_beats == 7) expected_mask = 4'b1000;
    else if (physical_beats == PHYSICAL_BEATS - 1) expected_mask = 4'b0111;
    else expected_mask = 4'b1111;
  end
  assign m_valid = !rst && pending_valid;
  assign s_ready = !rst && (!pending_valid || m_ready);
  always_ff @(posedge clk) begin
    if (rst) begin
      carry <= '0;
      carry_valid <= 1'b0;
      pending_valid <= 1'b0;
      m_data <= '0;
      m_beat <= '0;
      m_last <= 1'b0;
      formed_beats <= '0;
      physical_beats <= '0;
      error_sticky <= 1'b0;
    end else begin
      if (pending_valid && m_ready) pending_valid <= 1'b0;
      if (s_valid && s_ready) begin
        physical_beats <= physical_beats + 1'b1;
        if (physical_beats >= PHYSICAL_BEATS || s_mask != expected_mask) error_sticky <= 1'b1;
        case (s_mask)
          4'b0000: begin
          end
          4'b1000: begin
            if (carry_valid || formed_beats != 0) error_sticky <= 1'b1;
            carry <= s_data[127:96];
            carry_valid <= 1'b1;
          end
          4'b1111, 4'b0111: begin
            if (!carry_valid || formed_beats >= OUTPUT_BEATS) error_sticky <= 1'b1;
            m_data <= {s_data[95:0], carry};
            pending_valid <= 1'b1;
            m_beat <= formed_beats;
            m_last <= (formed_beats == OUTPUT_BEATS - 1);
            formed_beats <= formed_beats + 1'b1;
            carry <= s_data[127:96];
            carry_valid <= (s_mask == 4'b1111);
          end
          default: error_sticky <= 1'b1;
        endcase
      end
    end
  end
  // synthesis translate_off
  initial if (SAMPLE_COUNT < 4 || (SAMPLE_COUNT % 4) != 0) $fatal(1, "pack4 sample domain");
  // synthesis translate_on
endmodule
