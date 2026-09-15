`timescale 1ns / 1ps
module sfo_initial_fft_pair_extractor (
    input  logic         clk,
    input  logic         rst,
    input  logic         frame_start_valid,
    output logic         frame_start_ready,
    input  logic [ 31:0] frame_start_id,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_data,
    input  logic         s_last,
    input  logic         s_fft_error,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [ 31:0] m_frame_id,
    output logic [  1:0] m_pair,
    output logic [ 10:0] m_index0,
    output logic [ 10:0] m_index1,
    output logic [ 63:0] m_first_iq,
    output logic [ 63:0] m_second_iq,
    output logic         m_pair_last,
    output logic         m_last,
    output logic         status_valid,
    input  logic         status_ready,
    output logic [ 31:0] status_frame_id,
    output logic         status_error,
    output logic [  7:0] status_error_code,
    output logic         halted,
    output logic [ 12:0] accepted_fft_beats,
    output logic [ 12:0] popped_halfwords,
    output logic [ 12:0] accepted_active_bins,
    output logic [ 11:0] accepted_second_beats,
    output logic [ 11:0] emitted_pair_beats,
    output logic [ 10:0] reserved_halfwords,
    output logic [ 10:0] max_reserved_halfwords,
    output logic [  9:0] max_fifo_write_words,
    output logic [ 10:0] discarded_halfwords,
    output logic         discarded_carry,
    output logic [ 31:0] input_stall_cycles
);
  typedef enum logic [1:0] {
    IDLE,
    RUN,
    FINISH,
    HALT
  } state_t;
  typedef struct packed {
    logic active;
    logic [1:0] pair;
    logic [10:0] index;
    logic [31:0] first_iq, second_iq;
  } bin_t;
  state_t state;
  logic [31:0] active_frame;
  logic [2:0] symbol_index;
  logic [8:0] beat_index, ram_beat;
  logic [1:0] ram_pair, next_pair;
  logic [10:0] next_index;
  logic input_done, accept, first_write, second_read, ram_valid;
  logic [127:0] ram_data, second_data;
  logic
      fifo_rst,
      fifo_full,
      fifo_empty,
      fifo_wr_busy,
      fifo_rd_busy,
      fifo_data_valid,
      fifo_overflow,
      fifo_underflow;
  logic fifo_write, fifo_pop, can_pop, slot_free;
  logic [ 9:0] fifo_wr_count;
  logic [10:0] fifo_rd_count;
  bin_t [ 3:0] fifo_input;
  bin_t [ 1:0] fifo_output;
  bin_t carry, combined[0:2];
  logic carry_valid;
  integer combined_count, lane, valid_in_half;
  logic [ 1:0] scan_pair;
  logic [10:0] scan_index;
  logic sequence_error, error_event;
  logic [ 7:0] error_code;
  logic [10:0] reserved_next;

  assign halted = state == HALT;
  assign fifo_rst = rst || halted;
  assign frame_start_ready = !rst && state == IDLE && !fifo_wr_busy && !fifo_rd_busy;
  assign s_ready = !rst && state == RUN && !input_done && !fifo_wr_busy && !fifo_rd_busy &&
      (!symbol_index[0] || (reserved_halfwords <= 1018 && !fifo_full));
  assign accept = s_valid && s_ready;
  assign slot_free = !m_valid || m_ready;
  assign can_pop = !rst && state == RUN && !fifo_rd_busy && !fifo_empty && fifo_data_valid &&
      slot_free;
  assign fifo_pop = can_pop && !error_event;
  assign first_write = accept && !symbol_index[0] && !error_event;
  assign second_read = accept && symbol_index[0] && !error_event;
  assign
      fifo_write = !rst && state == RUN && ram_valid && !error_event && !fifo_wr_busy && !fifo_full;
  assign m_pair_last = m_index1 == 1639;
  assign m_last = m_pair == 3 && m_pair_last;

  always_comb begin
    for (integer j = 0; j < 4; j = j + 1) begin
      fifo_input[j].active = ({ram_beat, 2'b00} + j >= 1 && {ram_beat, 2'b00} + j <= 820) ||
          ({ram_beat, 2'b00} + j >= 1228);
      fifo_input[j].pair = ram_pair;
      fifo_input[j].index = ({ram_beat, 2'b00} + j <= 820) ?
          ({ram_beat, 2'b00} + j - 1) : ({ram_beat, 2'b00} + j - 408);
      fifo_input[j].first_iq = ram_data[j*32+:32];
      fifo_input[j].second_iq = second_data[j*32+:32];
    end
    combined[0] = '0;
    combined[1] = '0;
    combined[2] = '0;
    combined_count = 0;
    valid_in_half = 0;
    if (carry_valid) begin
      combined[0] = carry;
      combined_count = 1;
    end
    scan_pair = next_pair;
    scan_index = next_index;
    sequence_error = 0;
    for (integer j = 0; j < 2; j = j + 1) begin
      if (fifo_output[j].active) begin
        if (fifo_output[j].pair != scan_pair || fifo_output[j].index != scan_index)
          sequence_error = 1;
        combined[combined_count] = fifo_output[j];
        combined_count = combined_count + 1;
        valid_in_half = valid_in_half + 1;
        if (scan_index == 1639) begin
          scan_index = 0;
          scan_pair  = scan_pair + 1'b1;
        end else scan_index = scan_index + 1'b1;
      end
    end
    if (combined_count >= 2 && (combined[0].pair != combined[1].pair || combined[1].index !=
                                combined[0].index + 1'b1 || combined[0].index[0]))
      sequence_error = 1;
    if (combined_count == 3 && combined[1].index == 1639) sequence_error = 1;
    error_event = 0;
    error_code  = 0;
    if (!rst && state == RUN) begin
      if (s_fft_error || fifo_overflow || fifo_underflow || reserved_halfwords > 1020 ||
          (ram_valid && (fifo_full || fifo_wr_busy)) || (can_pop && reserved_halfwords == 0)) begin
        error_event = 1;
        error_code  = 7;
      end else if ((accept && s_last != (beat_index == 511)) || (input_done && s_valid) ||
                   (can_pop && sequence_error)) begin
        error_event = 1;
        error_code  = 6;
      end
    end
    reserved_next = reserved_halfwords;
    if (second_read) reserved_next = reserved_next + 11'd2;
    if (fifo_pop) reserved_next = reserved_next - 11'd1;
  end
  sfo_initial_fft_pair_extractor_memory first_symbol (
      .clk    (clk),
      .rst    (rst),
      .wr_en  (first_write),
      .rd_en  (second_read),
      .wr_addr(beat_index),
      .rd_addr(beat_index),
      .wr_data(s_data),
      .rd_data(ram_data)
  );
  sfo_initial_fft_pair_extractor_fifo width_fifo (
      .clk       (clk),
      .rst       (fifo_rst),
      .wr_en     (fifo_write),
      .rd_en     (fifo_pop),
      .din       (fifo_input),
      .dout      (fifo_output),
      .full      (fifo_full),
      .empty     (fifo_empty),
      .wr_busy   (fifo_wr_busy),
      .rd_busy   (fifo_rd_busy),
      .data_valid(fifo_data_valid),
      .overflow  (fifo_overflow),
      .underflow (fifo_underflow),
      .wr_count  (fifo_wr_count),
      .rd_count  (fifo_rd_count)
  );
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      active_frame <= 0;
      symbol_index <= 0;
      beat_index <= 0;
      ram_beat <= 0;
      ram_pair <= 0;
      next_pair <= 0;
      next_index <= 0;
      input_done <= 0;
      ram_valid <= 0;
      second_data <= 0;
      carry <= '0;
      carry_valid <= 0;
      m_valid <= 0;
      m_frame_id <= 0;
      m_pair <= 0;
      m_index0 <= 0;
      m_index1 <= 0;
      m_first_iq <= 0;
      m_second_iq <= 0;
      status_valid <= 0;
      status_frame_id <= 0;
      status_error <= 0;
      status_error_code <= 0;
      accepted_fft_beats <= 0;
      accepted_second_beats <= 0;
      popped_halfwords <= 0;
      accepted_active_bins <= 0;
      emitted_pair_beats <= 0;
      reserved_halfwords <= 0;
      max_reserved_halfwords <= 0;
      max_fifo_write_words <= 0;
      discarded_halfwords <= 0;
      discarded_carry <= 0;
      input_stall_cycles <= 0;
    end else begin
      if (m_valid && m_ready) begin
        m_valid <= 0;
        emitted_pair_beats <= emitted_pair_beats + 1'b1;
      end
      if (status_valid && status_ready) status_valid <= 0;
      if (state == IDLE && frame_start_valid && frame_start_ready) begin
        state <= RUN;
        active_frame <= frame_start_id;
        symbol_index <= 0;
        beat_index <= 0;
        next_pair <= 0;
        next_index <= 0;
        input_done <= 0;
        ram_valid <= 0;
        carry_valid <= 0;
        status_valid <= 0;
        status_frame_id <= frame_start_id;
        status_error <= 0;
        status_error_code <= 0;
        accepted_fft_beats <= 0;
        accepted_second_beats <= 0;
        popped_halfwords <= 0;
        accepted_active_bins <= 0;
        emitted_pair_beats <= 0;
        reserved_halfwords <= 0;
        max_reserved_halfwords <= 0;
        max_fifo_write_words <= 0;
        discarded_halfwords <= 0;
        discarded_carry <= 0;
        input_stall_cycles <= 0;
      end else if (state == RUN) begin
        if (s_valid && !s_ready) input_stall_cycles <= input_stall_cycles + 1'b1;
        if (accept) accepted_fft_beats <= accepted_fft_beats + 1'b1;
        if (error_event) begin
          state <= HALT;
          status_valid <= 1;
          status_error <= 1;
          status_error_code <= error_code;
          discarded_halfwords <= reserved_halfwords + ((accept && symbol_index[0]) ? 11'd2 : 11'd0);
          discarded_carry <= carry_valid;
          reserved_halfwords <= 0;
          ram_valid <= 0;
          carry_valid <= 0;
        end else begin
          ram_valid <= second_read;
          if (second_read) begin
            second_data <= s_data;
            ram_pair <= symbol_index[2:1];
            ram_beat <= beat_index;
            accepted_second_beats <= accepted_second_beats + 1'b1;
          end
          if (accept) begin
            if (beat_index == 511) begin
              beat_index <= 0;
              if (symbol_index == 7) input_done <= 1;
              else symbol_index <= symbol_index + 1'b1;
            end else beat_index <= beat_index + 1'b1;
          end
          reserved_halfwords <= reserved_next;
          if (reserved_next > max_reserved_halfwords) max_reserved_halfwords <= reserved_next;
          if (fifo_wr_count > max_fifo_write_words) max_fifo_write_words <= fifo_wr_count;
          if (fifo_pop) begin
            popped_halfwords <= popped_halfwords + 1'b1;
            accepted_active_bins <= accepted_active_bins + valid_in_half;
            next_pair <= scan_pair;
            next_index <= scan_index;
            if (combined_count >= 2) begin
              m_valid <= 1;
              m_frame_id <= active_frame;
              m_pair <= combined[0].pair;
              m_index0 <= combined[0].index;
              m_index1 <= combined[1].index;
              m_first_iq <= {combined[1].first_iq, combined[0].first_iq};
              m_second_iq <= {combined[1].second_iq, combined[0].second_iq};
              carry_valid <= combined_count == 3;
              carry <= combined[2];
            end else begin
              carry_valid <= combined_count == 1;
              carry <= combined[0];
            end
          end
          if (m_valid && m_ready && m_last) begin
            state <= FINISH;
            status_valid <= 1;
            status_error <= 0;
            status_error_code <= 0;
          end
        end
      end else if (state == FINISH && !status_valid && !m_valid) state <= IDLE;
    end
  end
  // synthesis translate_off
  always @(posedge clk)
    if (!rst && state == RUN && !error_event) begin
      if (reserved_halfwords != 2 * accepted_second_beats - popped_halfwords)
        $fatal(1, "PAIR exact reservation mismatch");
      if (fifo_write && !ram_valid) $fatal(1, "PAIR FIFO write without RAM response");
      if (m_valid && m_ready && m_last &&
          (!input_done || accepted_fft_beats != 4096 || accepted_active_bins != 6560 ||
           emitted_pair_beats != 3279 || popped_halfwords != 4096 || reserved_halfwords != 0 ||
           carry_valid || ram_valid))
        $fatal(1, "PAIR premature frame completion");
    end
  // synthesis translate_on
endmodule
