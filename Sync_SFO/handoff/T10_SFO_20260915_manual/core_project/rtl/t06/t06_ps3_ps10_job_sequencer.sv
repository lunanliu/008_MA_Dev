`timescale 1ns/1ps

// Logical sample/phase scheduling only. A separate bank adapter must realign
// unaligned physical words; this module never rounds an absolute address.
module t06_ps3_ps10_job_sequencer (
  input  logic clk,
  input  logic rst_n,
  input  logic start_valid,
  output logic start_ready,
  input  logic [31:0] start_frame_id,
  input  logic signed [31:0] start_fine_start,
  input  logic signed [31:0] start_phase_increment,
  output logic read_req_valid,
  input  logic read_req_ready,
  output logic [31:0] read_req_frame_id,
  output logic signed [31:0] read_req_lane0_abs_sample,
  output logic [3:0] read_req_ps_symbol,
  output logic [8:0] read_req_beat_index,
  output logic [127:0] read_req_phase_codes,
  output logic read_req_transaction_end,
  output logic busy,
  output logic done_pulse,
  output logic range_error_pulse
);
  logic [31:0] phase [0:3];
  logic [31:0] phase_step_4;
  logic [31:0] phase_step_516;
  logic signed [32:0] proposed_first;
  logic signed [32:0] proposed_last;
  logic proposed_range_error;

  always_comb begin
    proposed_first = $signed({start_fine_start[31],start_fine_start}) + 33'sd5632;
    proposed_last = $signed({start_fine_start[31],start_fine_start}) + 33'sd25599;
    proposed_range_error = proposed_first < -33'sd2147483648 ||
                           proposed_last > 33'sd2147483647;
    start_ready = rst_n && !busy;
    read_req_valid = rst_n && busy;
    read_req_transaction_end = read_req_beat_index == 9'd511;
    for (int lane=0; lane<4; lane++)
      read_req_phase_codes[32*lane +: 32] = phase[lane];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      busy <= 1'b0;
      done_pulse <= 1'b0;
      range_error_pulse <= 1'b0;
      read_req_frame_id <= '0;
      read_req_lane0_abs_sample <= '0;
      read_req_ps_symbol <= '0;
      read_req_beat_index <= '0;
      phase_step_4 <= '0;
      phase_step_516 <= '0;
      for (int lane=0; lane<4; lane++) phase[lane] <= '0;
    end else begin
      done_pulse <= 1'b0;
      range_error_pulse <= 1'b0;
      if (start_valid && start_ready) begin
        // Constant shifts/additions only. All phase additions intentionally
        // retain the low 32 bits of the modulo-2^32 DDS phase accumulator.
        read_req_frame_id <= start_frame_id;
        read_req_lane0_abs_sample <= proposed_first[31:0];
        read_req_ps_symbol <= 4'd3;
        read_req_beat_index <= 9'd0;
        phase[0] <= 32'd0;
        phase[1] <= start_phase_increment;
        phase[2] <= start_phase_increment << 1;
        phase[3] <= (start_phase_increment << 1) + start_phase_increment;
        phase_step_4 <= start_phase_increment << 2;
        phase_step_516 <= (start_phase_increment << 9) + (start_phase_increment << 2);
        if (proposed_range_error) begin
          busy <= 1'b0;
          range_error_pulse <= 1'b1;
          done_pulse <= 1'b1;
        end else begin
          busy <= 1'b1;
        end
      end else if (read_req_valid && read_req_ready) begin
        if (read_req_beat_index == 9'd511) begin
          if (read_req_ps_symbol == 4'd10) begin
            busy <= 1'b0;
            done_pulse <= 1'b1;
          end else begin
            read_req_ps_symbol <= read_req_ps_symbol + 1'b1;
            read_req_beat_index <= 9'd0;
            read_req_lane0_abs_sample <= read_req_lane0_abs_sample + 32'sd516;
            for (int lane=0; lane<4; lane++) phase[lane] <= phase[lane] + phase_step_516;
          end
        end else begin
          read_req_beat_index <= read_req_beat_index + 1'b1;
          read_req_lane0_abs_sample <= read_req_lane0_abs_sample + 32'sd4;
          for (int lane=0; lane<4; lane++) phase[lane] <= phase[lane] + phase_step_4;
        end
      end
    end
  end
endmodule
