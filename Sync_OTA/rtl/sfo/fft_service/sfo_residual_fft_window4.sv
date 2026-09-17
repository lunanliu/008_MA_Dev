// One nominal-window owner for the real T03 main FFT arithmetic.
// Only one window may be live until all output AND official status are observed.
module sfo_residual_fft_window4 #(
    parameter integer PROGRESSIVE_SOURCE=0,
    parameter integer TIMEOUT_CYCLES = 30000
) (
    input  logic                clk,
    input  logic                clk500,
    input  logic                rst,
    input  logic                abort,
    input logic cfg_window_granted,
    input  logic                cfg_valid,
    output logic                cfg_ready,
    input  logic        [ 31:0] cfg_frame_id,
    input  logic        [ 31:0] cfg_generation,
    input  logic        [ 31:0] cfg_source_frame_id,
    input  logic        [ 31:0] cfg_source_generation,
    input  logic                cfg_source_complete,
    input  logic        [  7:0] cfg_source_error,
    input  logic        [ 20:0] cfg_nominal_length,
    input  logic signed [ 31:0] cfg_available_first,
    input  logic signed [ 31:0] cfg_available_last,
    input  logic        [  6:0] cfg_symbol_slot,
    output logic                req_valid,
    input  logic                req_ready,
    output logic        [ 31:0] req_frame_id,
    output logic        [ 31:0] req_generation,
    output logic        [  6:0] req_symbol_slot,
    output logic        [ 20:0] req_start_index,
    output logic        [  9:0] req_beats,
    input  logic                s_valid,
    output logic                s_ready,
    input  logic        [ 31:0] s_frame_id,
    input  logic        [ 31:0] s_generation,
    input  logic        [ 20:0] s_sample_index,
    input  logic        [  8:0] s_beat,
    input  logic        [  3:0] s_lane_mask,
    input  logic                s_last,
    input  logic        [  7:0] s_error,
    input  logic        [127:0] s_data,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [ 31:0] m_frame_id,
    output logic        [ 31:0] m_generation,
    output logic        [  6:0] m_symbol_slot,
    output logic        [  8:0] m_fft_beat,
    output logic                m_last,
    output logic        [127:0] m_data,
    output logic                done_valid,
    input  logic                done_ready,
    output logic        [ 31:0] done_frame_id,
    output logic        [ 31:0] done_generation,
    output logic        [  6:0] done_symbol_slot,
    output logic        [  3:0] done_error,
    output logic        [  7:0] done_detail,
    output logic        [  7:0] done_source_error,
    output logic        [  9:0] done_source_count,
    output logic        [  9:0] done_fft_input_count,
    output logic        [  9:0] done_fft_output_count,
    output logic                done_status_seen,
    output logic                cancel,
    output logic                busy
);
  localparam [2:0] BOOT = 0, IDLE = 1, CONFIG = 2, RUN = 3, FLUSH = 4, DONE = 5, HALT = 6;
  logic [2:0] state;
  logic [4:0] reset_count;
  logic [31:0] age;
  logic [228:0] cfg_saved;
  logic saved_grant;
  logic reader_done_seen;
  wire active = state == CONFIG || state == RUN;
  wire child_reset = rst || state == BOOT || state == FLUSH || state == HALT;
  wire timeout_now = active && age >= TIMEOUT_CYCLES - 1;
  logic
      r_cfg_ready,
      r_req_valid,
      r_s_ready,
      r_m_valid,
      r_m_ready,
      r_m_last,
      r_done_valid,
      r_cancel,
      r_busy;
  logic [127:0] r_data;
  logic [31:0] r_frame, r_gen, r_done_frame, r_done_gen;
  logic [6:0] r_slot, r_done_slot;
  logic [20:0] r_index, r_done_start;
  logic [8:0] r_beat;
  logic [7:0] r_error, r_source_error;
  logic [9:0] r_input_count, r_output_count;
  logic r_requested;
  logic fft_in_ready, fft_out_valid, fft_out_last, fft_status;
  logic [127:0] fft_data;
  logic [5:0] fft_errors;
  wire poison = active &&
      (abort || timeout_now || (|fft_errors) || r_cancel || (r_done_valid && r_error != 0));
  assign cancel = child_reset || poison;
  assign cfg_ready = !rst && !abort && state == IDLE;
  assign busy = state != IDLE;
  assign req_valid = state == RUN && !cancel && r_req_valid;
  assign s_ready = state == RUN && !cancel && r_s_ready;
  assign r_m_ready = state == RUN && !cancel && fft_in_ready;
  assign m_valid = state == RUN && !cancel && fft_out_valid;
  assign m_data = fft_data;
  assign m_last = fft_out_last;
  assign m_fft_beat = done_fft_output_count[8:0];
  assign m_frame_id = done_frame_id;
  assign m_generation = done_generation;
  assign m_symbol_slot = done_symbol_slot;
  assign done_valid = !rst && state == DONE;
  sfo_residual_nominal_window_reader4 #(.PROGRESSIVE_SOURCE(PROGRESSIVE_SOURCE)) reader (
      .clk                  (clk),
      .rst                  (child_reset),
      .abort                (1'b0),
      .cfg_valid            (state == CONFIG && !cancel),
      .cfg_ready            (r_cfg_ready),
      .cfg_window_granted(saved_grant),
      .cfg_frame_id         (cfg_saved[228:197]),
      .cfg_generation       (cfg_saved[196:165]),
      .cfg_source_frame_id  (cfg_saved[164:133]),
      .cfg_source_generation(cfg_saved[132:101]),
      .cfg_source_complete  (cfg_saved[100]),
      .cfg_source_error     (cfg_saved[99:92]),
      .cfg_nominal_length   (cfg_saved[91:71]),
      .cfg_available_first  (cfg_saved[70:39]),
      .cfg_available_last   (cfg_saved[38:7]),
      .cfg_symbol_slot      (cfg_saved[6:0]),
      .req_valid            (r_req_valid),
      .req_ready            (req_ready && state == RUN && !cancel),
      .req_frame_id         (req_frame_id),
      .req_generation       (req_generation),
      .req_symbol_slot      (req_symbol_slot),
      .req_start_index      (req_start_index),
      .req_beats            (req_beats),
      .s_valid              (s_valid && state == RUN && !cancel),
      .s_ready              (r_s_ready),
      .s_frame_id           (s_frame_id),
      .s_generation         (s_generation),
      .s_sample_index       (s_sample_index),
      .s_beat               (s_beat),
      .s_lane_mask          (s_lane_mask),
      .s_last               (s_last),
      .s_error              (s_error),
      .s_data               (s_data),
      .m_valid              (r_m_valid),
      .m_ready              (r_m_ready),
      .m_frame_id           (r_frame),
      .m_generation         (r_gen),
      .m_symbol_slot        (r_slot),
      .m_sample_index       (r_index),
      .m_beat               (r_beat),
      .m_last               (r_m_last),
      .m_data               (r_data),
      .done_valid           (r_done_valid),
      .done_ready           (state == RUN && !cancel),
      .done_frame_id        (r_done_frame),
      .done_generation      (r_done_gen),
      .done_symbol_slot     (r_done_slot),
      .done_error           (r_error),
      .done_source_error    (r_source_error),
      .done_start_index     (r_done_start),
      .done_input_count     (r_input_count),
      .done_output_count    (r_output_count),
      .done_request_accepted(r_requested),
      .cancel               (r_cancel),
      .busy                 (r_busy)
  );
  sfo_residual_fft_service4 service (
      .clk_125            (clk),
      .clk_500            (clk500),
      .rst_n              (!child_reset),
      .s_valid            (r_m_valid && state == RUN && !cancel),
      .s_ready            (fft_in_ready),
      .s_data             (r_data),
      .s_transaction_end  (r_m_last),
      .m_valid            (fft_out_valid),
      .m_ready            (m_ready && state == RUN && !cancel),
      .m_data             (fft_data),
      .m_transaction_end  (fft_out_last),
      .ingress_overflow   (fft_errors[0]),
      .ingress_underflow  (fft_errors[1]),
      .egress_overflow    (fft_errors[2]),
      .egress_underflow   (fft_errors[3]),
      .xfft_protocol_error(fft_errors[4]),
      .xfft_overflow      (fft_errors[5]),
      .status_valid       (fft_status)
  );
  task automatic fail_run(input logic [3:0] code, input logic [7:0] detail);
    begin
      done_error <= code;
      done_detail <= detail;
      reset_count <= 0;
      state <= FLUSH;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= BOOT;
      reset_count <= 0;
      age <= 0;
      cfg_saved <= 0;saved_grant<=0;
      reader_done_seen <= 0;
      done_frame_id <= 0;
      done_generation <= 0;
      done_symbol_slot <= 0;
      done_error <= 0;
      done_detail <= 0;
      done_source_error <= 0;
      done_source_count <= 0;
      done_fft_input_count <= 0;
      done_fft_output_count <= 0;
      done_status_seen <= 0;
    end else begin
      if (active) age <= age + 1;
      if (state == BOOT) begin
        if (reset_count == 31) state <= IDLE;
        else reset_count <= reset_count + 1;
      end else if (state == FLUSH) begin
        if (reset_count == 31) state <= DONE;
        else reset_count <= reset_count + 1;
      end else
      if (state == HALT) begin
      end else if (state == DONE) begin
        if (done_ready) state <= done_error == 0 ? IDLE : HALT;
      end else if (state == IDLE) begin
        if (cfg_valid && cfg_ready) begin
          saved_grant<=PROGRESSIVE_SOURCE&&cfg_window_granted;
          cfg_saved <= {
            cfg_frame_id,
            cfg_generation,
            cfg_source_frame_id,
            cfg_source_generation,
            cfg_source_complete,
            cfg_source_error,
            cfg_nominal_length,
            cfg_available_first,
            cfg_available_last,
            cfg_symbol_slot
          };
          done_frame_id <= cfg_frame_id;
          done_generation <= cfg_generation;
          done_symbol_slot <= cfg_symbol_slot;
          done_error <= 0;
          done_detail <= 0;
          done_source_error <= cfg_source_error;
          done_source_count <= 0;
          done_fft_input_count <= 0;
          done_fft_output_count <= 0;
          done_status_seen <= 0;
          reader_done_seen <= 0;
          age <= 0;
          state <= CONFIG;
        end
      end else begin
        done_source_count <= r_input_count;
        if (fft_status) done_status_seen <= 1;
        if (r_m_valid && r_m_ready) done_fft_input_count <= done_fft_input_count + 1;
        if (m_valid && m_ready) done_fft_output_count <= done_fft_output_count + 1;
        if (abort) fail_run(5, 0);
        else if ((r_cancel && r_error != 0) || (r_done_valid && r_error != 0)) begin
          done_source_error <= r_source_error;
          fail_run(1, r_error);
        end else if (|fft_errors) fail_run(2, {2'b0, fft_errors});
        else if (timeout_now) fail_run(4, 0);
        else if (fft_status && done_status_seen) fail_run(3, 4);
        else if (m_valid && m_ready &&
                 (done_fft_output_count >= 512 || m_last != (done_fft_output_count == 511)))
          fail_run(3, 1);
        else if (r_m_valid && r_m_ready &&
                 (done_fft_input_count >= 512 || r_beat != done_fft_input_count[8:0] ||
                  r_m_last != (done_fft_input_count == 511) || r_frame != done_frame_id ||
                  r_gen != done_generation || r_slot != done_symbol_slot))
          fail_run(3, 2);
        else
          case (state)
            CONFIG:  if (r_cfg_ready) state <= RUN;
            RUN: begin
              if (r_done_valid) begin
                if (r_input_count != 512 || r_output_count != 512 || r_done_frame != done_frame_id
                    || r_done_gen != done_generation || r_done_slot != done_symbol_slot)
                  fail_run(3, 3);
                else reader_done_seen <= 1;
              end
              if (reader_done_seen && done_status_seen && done_fft_input_count == 512 &&
                  done_fft_output_count == 512)
                state <= DONE;
            end
            default: fail_run(6, 0);
          endcase
      end
    end
  end
endmodule
