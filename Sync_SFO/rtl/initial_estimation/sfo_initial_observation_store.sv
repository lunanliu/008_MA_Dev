`timescale 1ns / 1ps
module sfo_initial_observation_store (
    input  logic               clk,
    input  logic               rst,
    input  logic               frame_start_valid,
    output logic               frame_start_ready,
    input  logic        [31:0] frame_start_id,
    input  logic               s_valid,
    output logic               s_ready,
    input  logic        [ 1:0] s_pair,
    input  logic        [10:0] s_index0,
    input  logic        [10:0] s_index1,
    input  logic signed [47:0] s_phase0,
    input  logic signed [47:0] s_phase1,
    input  logic        [63:0] s_nw0,
    input  logic        [63:0] s_nw1,
    input  logic        [32:0] s_dw0,
    input  logic        [32:0] s_dw1,
    input  logic               seal_valid,
    output logic               seal_ready,
    input  logic        [31:0] seal_frame_id,
    input  logic        [ 1:0] seal_pair,
    input  logic        [63:0] seal_nm,
    input  logic        [32:0] seal_dm,
    input  logic        [10:0] seal_max_index,
    input  logic               seal_pair_valid,
    input  logic        [ 7:0] seal_error_code,
    output logic               m_valid,
    input  logic               m_ready,
    output logic        [31:0] m_frame_id,
    output logic        [31:0] m_tag,
    output logic        [ 1:0] m_pair,
    output logic        [10:0] m_index,
    output logic signed [10:0] m_bin,
    output logic signed [47:0] m_phase,
    output logic        [63:0] m_nw,
    output logic        [63:0] m_nm,
    output logic        [32:0] m_dw,
    output logic        [32:0] m_dm,
    output logic        [10:0] m_max_index,
    output logic               m_pair_last,
    output logic               m_last,
    output logic               status_valid,
    input  logic               status_ready,
    output logic        [31:0] status_frame_id,
    output logic               status_error,
    output logic        [ 7:0] status_error_code,
    output logic        [12:0] written_count,
    output logic        [12:0] read_issued_count,
    output logic        [12:0] replayed_count,
    output logic        [ 2:0] pending_read_count,
    output logic               protocol_error_sticky
);
  typedef enum logic [1:0] {
    IDLE,
    RUN,
    END_FRAME
  } state_t;
  typedef struct packed {
    logic [1:0]  pair;
    logic [10:0] index;
  } read_meta_t;
  typedef struct packed {
    read_meta_t   meta;
    logic [144:0] data;
  } output_t;
  state_t state;
  logic [31:0] active_frame;
  logic [1:0] write_pair, read_pair;
  logic [ 9:0] write_beat;
  logic [10:0] read_index;
  logic [3:0] written_pairs, sealed_pairs;
  logic [2:0] seal_count;
  logic [63:0] pair_nm[0:3];
  logic [32:0] pair_dm[0:3];
  logic [10:0] pair_index[0:3];
  logic
      input_accept,
      seal_accept,
      input_error,
      seal_error,
      error_event,
      write_fire,
      read_issue,
      read_return,
      consume;
  logic [7:0] event_error_code;
  logic [11:0] write_address, read_address;
  logic [1:0] read_valid_pipe;
  read_meta_t read_meta_pipe[0:1];
  logic [144:0] bank_data[0:1];
  output_t output_queue[0:3], output_head;
  logic [1:0] queue_write, queue_read;
  logic [2:0] queue_count;
  integer i;
  assign frame_start_ready = !rst && state == IDLE;
  assign s_ready = !rst && state == RUN && written_count < 6560;
  assign seal_ready = !rst && state == RUN && seal_count < 4 && written_pairs[seal_count[1:0]];
  assign input_accept = s_valid && s_ready;
  assign seal_accept = seal_valid && seal_ready;
  assign input_error = input_accept &&
      (s_pair != write_pair || s_index0 != {write_beat, 1'b0} || s_index1 != {write_beat, 1'b1});
  assign seal_error = seal_accept &&
      (seal_frame_id != active_frame || seal_pair != seal_count[1:0] || !seal_pair_valid ||
       seal_error_code != 0 || seal_nm == 0 || seal_dm == 0 || seal_max_index >= 1640);
  assign error_event = input_error || seal_error;
  always_comb begin
    event_error_code = 8'd6;
    if (!input_error && seal_error) begin
      if (seal_frame_id != active_frame || seal_pair != seal_count[1:0]) event_error_code = 8'd6;
      else if (!seal_pair_valid) event_error_code = seal_error_code == 0 ? 8'd7 : seal_error_code;
      else if (seal_error_code != 0) event_error_code = 8'd6;
      else event_error_code = 8'd7;
    end
  end
  assign write_fire = input_accept && !error_event;
  assign write_address = written_count[12:1];
  assign read_address = read_issued_count[12:1];
  assign m_valid = !rst && queue_count != 0;
  assign consume = m_valid && m_ready;
  assign read_issue = !rst && state == RUN && !error_event && read_issued_count < 6560 &&
      sealed_pairs[read_pair] && ((pending_read_count < 4) || consume);
  assign read_return = !rst && read_valid_pipe[1];
  assign output_head = output_queue[queue_read];
  assign m_frame_id = active_frame;
  assign {m_pair, m_index} = output_head.meta;
  assign {m_phase, m_nw, m_dw} = output_head.data;
  assign m_tag = {19'd0, m_pair, m_index};
  assign m_bin = m_index < 820 ? $signed(
      {1'b0, m_index}
  ) + 12'sd1 : $signed(
      {1'b0, m_index}
  ) - 12'sd1640;
  assign m_nm = pair_nm[m_pair];
  assign m_dm = pair_dm[m_pair];
  assign m_max_index = pair_index[m_pair];
  assign m_pair_last = m_index == 1639;
  assign m_last = m_pair == 3 && m_pair_last;
  sfo_initial_observation_store_bank even_bank (
      .clk          (clk),
      .rst          (rst),
      .write_enable (write_fire),
      .read_enable  (read_issue && !read_index[0]),
      .write_address(write_address),
      .read_address (read_address),
      .write_data   ({s_phase0, s_nw0, s_dw0}),
      .read_data    (bank_data[0])
  );
  sfo_initial_observation_store_bank odd_bank (
      .clk          (clk),
      .rst          (rst),
      .write_enable (write_fire),
      .read_enable  (read_issue && read_index[0]),
      .write_address(write_address),
      .read_address (read_address),
      .write_data   ({s_phase1, s_nw1, s_dw1}),
      .read_data    (bank_data[1])
  );
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      active_frame <= 0;
      write_pair <= 0;
      read_pair <= 0;
      write_beat <= 0;
      read_index <= 0;
      written_pairs <= 0;
      sealed_pairs <= 0;
      seal_count <= 0;
      written_count <= 0;
      read_issued_count <= 0;
      replayed_count <= 0;
      pending_read_count <= 0;
      queue_count <= 0;
      queue_write <= 0;
      queue_read <= 0;
      read_valid_pipe <= 0;
      status_valid <= 0;
      status_frame_id <= 0;
      status_error <= 0;
      status_error_code <= 0;
      protocol_error_sticky <= 0;
      for (i = 0; i < 2; i = i + 1) read_meta_pipe[i] <= '0;
      for (i = 0; i < 4; i = i + 1) begin
        output_queue[i] <= '0;
        pair_nm[i] <= 0;
        pair_dm[i] <= 0;
        pair_index[i] <= 0;
      end
    end else begin
      read_valid_pipe   <= {read_valid_pipe[0], read_issue};
      read_meta_pipe[0] <= {read_pair, read_index};
      read_meta_pipe[1] <= read_meta_pipe[0];
      if (status_valid && status_ready) status_valid <= 0;
      case ({
        read_issue, consume
      })
        2'b10: pending_read_count <= pending_read_count + 1'b1;
        2'b01: pending_read_count <= pending_read_count - 1'b1;
        default: begin
        end
      endcase
      case ({
        read_return, consume
      })
        2'b10: queue_count <= queue_count + 1'b1;
        2'b01: queue_count <= queue_count - 1'b1;
        default: begin
        end
      endcase
      if (read_return) begin
        output_queue[queue_write] <= {read_meta_pipe[1], bank_data[read_meta_pipe[1].index[0]]};
        queue_write <= queue_write + 1'b1;
      end
      if (consume) begin
        queue_read <= queue_read + 1'b1;
        replayed_count <= replayed_count + 1'b1;
      end
      if (state == IDLE && frame_start_valid) begin
        state <= RUN;
        active_frame <= frame_start_id;
        write_pair <= 0;
        read_pair <= 0;
        write_beat <= 0;
        read_index <= 0;
        written_pairs <= 0;
        sealed_pairs <= 0;
        seal_count <= 0;
        written_count <= 0;
        read_issued_count <= 0;
        replayed_count <= 0;
        pending_read_count <= 0;
        queue_count <= 0;
        queue_write <= 0;
        queue_read <= 0;
        read_valid_pipe <= 0;
        status_valid <= 0;
        status_frame_id <= frame_start_id;
        status_error <= 0;
        status_error_code <= 0;
        protocol_error_sticky <= 0;
        for (i = 0; i < 4; i = i + 1) begin
          pair_nm[i] <= 0;
          pair_dm[i] <= 0;
          pair_index[i] <= 0;
        end
      end else if (state == RUN) begin
        if (write_fire) begin
          written_count <= written_count + 13'd2;
          if (write_beat == 819) begin
            written_pairs[write_pair] <= 1;
            write_beat <= 0;
            write_pair <= write_pair + 1'b1;
          end else write_beat <= write_beat + 1'b1;
        end
        if (seal_accept && !error_event) begin
          sealed_pairs[seal_pair] <= 1;
          pair_nm[seal_pair] <= seal_nm;
          pair_dm[seal_pair] <= seal_dm;
          pair_index[seal_pair] <= seal_max_index;
          seal_count <= seal_count + 1'b1;
        end
        if (read_issue) begin
          read_issued_count <= read_issued_count + 1'b1;
          if (read_index == 1639) begin
            read_index <= 0;
            read_pair  <= read_pair + 1'b1;
          end else read_index <= read_index + 1'b1;
        end
        if (error_event) begin
          state <= END_FRAME;
          status_valid <= 1;
          status_error <= 1;
          status_error_code <= event_error_code;
          if (event_error_code == 6) protocol_error_sticky <= 1;
        end else if (consume && m_last) begin
          state <= END_FRAME;
          status_valid <= 1;
          status_error <= 0;
          status_error_code <= 0;
        end
      end else if (state == END_FRAME && !status_valid && pending_read_count == 0) state <= IDLE;
    end
  end
  // synthesis translate_off
  always @(posedge clk)
    if (!rst) begin
      if (pending_read_count > 4 || queue_count > 4 ||
          pending_read_count != queue_count + read_valid_pipe[0] + read_valid_pipe[1])
        $fatal(
            1,
            "STORE reservation invariant pending=%0d queue=%0d pipe=%b",
            pending_read_count,
            queue_count,
            read_valid_pipe
        );
      if (read_return && queue_count == 4 && !consume) $fatal(1, "STORE unreserved BRAM return");
      if (read_issue && (!sealed_pairs[read_pair] || !written_pairs[read_pair]))
        $fatal(1, "STORE read before pair seal");
      if (consume && pending_read_count == 0) $fatal(1, "STORE unexpected output");
      if (consume && m_last && !error_event &&
          (written_count != 6560 || seal_count != 4 || replayed_count != 6559))
        $fatal(1, "STORE false normal completion");
      if (state == IDLE && (pending_read_count != 0 || read_valid_pipe != 0 || status_valid))
        $fatal(1, "STORE stale frame boundary");
    end
  // synthesis translate_on
endmodule
