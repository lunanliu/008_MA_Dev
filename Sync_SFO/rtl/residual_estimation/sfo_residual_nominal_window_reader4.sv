// Read one required nominal A128 window into a local 2048-complex cache,
// then replay continuously into the main-FFT service, subject only to its ready.
// All coordinates are COMPLEX SAMPLE indices relative to nominal frame origin 0.
module sfo_residual_nominal_window_reader4 #(
    parameter integer TIMEOUT_CYCLES = 20000
) (
    input  logic                clk,
    input  logic                rst,
    input  logic                abort,
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
    output logic        [ 20:0] m_sample_index,
    output logic        [  8:0] m_beat,
    output logic                m_last,
    output logic        [127:0] m_data,
    output logic                done_valid,
    input  logic                done_ready,
    output logic        [ 31:0] done_frame_id,
    output logic        [ 31:0] done_generation,
    output logic        [  6:0] done_symbol_slot,
    output logic        [  7:0] done_error,
    output logic        [  7:0] done_source_error,
    output logic        [ 20:0] done_start_index,
    output logic        [  9:0] done_input_count,
    output logic        [  9:0] done_output_count,
    output logic                done_request_accepted,
    output logic                cancel,
    output logic                busy
);
  localparam [2:0] IDLE = 0, REQUEST = 1, CAPTURE = 2, PLAY = 3, FLUSH = 4, DONE = 5, HALT = 6;
  logic [ 2:0] state;
  logic [31:0] age;
  logic [ 4:0] flush_count;
  logic [ 9:0] issued;
  logic raw_valid, out_valid;
  logic [127:0] raw_data, out_data;
  (* ram_style="block" *) logic [127:0] window_cache[0:511];
  wire [21:0] start_calc = {15'd0, cfg_symbol_slot} * 22'd17920 + 22'd25984;
  wire timing_active = state == REQUEST || state == CAPTURE || state == PLAY;
  wire timeout_now = timing_active && age >= TIMEOUT_CYCLES - 1;
  wire input_fire = s_valid && s_ready;
  wire output_fire = m_valid && m_ready;
  wire [20:0] expected_index = done_start_index + ({11'd0, done_input_count} << 2);
  wire identity_bad = (s_frame_id != done_frame_id || s_generation != done_generation);
  wire coordinate_bad = (s_sample_index != expected_index || s_beat != done_input_count[8:0] ||
                         done_input_count >= 512);
  wire last_bad = s_last != (done_input_count == 511);
  wire mask_bad = s_lane_mask != 4'hf;
  wire input_good = !identity_bad && !coordinate_bad && !last_bad && !mask_bad && s_error == 0;
  wire play_advance = state == PLAY && !rst && !abort && !timeout_now && (!out_valid || m_ready);
  wire read_fire = play_advance && issued < 512;
  assign cfg_ready = !rst && !abort && state == IDLE;
  assign req_valid = !rst && !abort && !timeout_now && state == REQUEST;
  assign req_frame_id = done_frame_id;
  assign req_generation = done_generation;
  assign req_symbol_slot = done_symbol_slot;
  assign req_start_index = done_start_index;
  assign req_beats = 10'd512;
  assign s_ready = !rst && !abort && !timeout_now && state == CAPTURE && done_input_count < 512;
  assign m_valid = !rst && !abort && !timeout_now && state == PLAY && out_valid;
  assign m_frame_id = done_frame_id;
  assign m_generation = done_generation;
  assign m_symbol_slot = done_symbol_slot;
  assign m_sample_index = done_start_index + ({11'd0, done_output_count} << 2);
  assign m_beat = done_output_count[8:0];
  assign m_last = done_output_count == 511;
  assign m_data = out_data;
  assign done_valid = !rst && state == DONE;
  // Cancellation is visible in the SAME cycle that abort/watchdog withdraw offered valid.
  assign cancel = rst || state == FLUSH || state == HALT || timeout_now || (abort && timing_active);
  assign busy = state != IDLE;
  // No cache reset loop: the entire 512-word window must be accepted before any read.
  always_ff @(posedge clk) begin
    if (input_fire && input_good) window_cache[done_input_count[8:0]] <= s_data;
    if (read_fire) raw_data <= window_cache[issued[8:0]];
  end
  task automatic fail_run(input logic [7:0] code);
    begin
      done_error <= code;
      flush_count <= 0;
      raw_valid <= 0;
      out_valid <= 0;
      state <= FLUSH;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      age <= 0;
      flush_count <= 0;
      issued <= 0;
      raw_valid <= 0;
      out_valid <= 0;
      out_data <= 0;
      done_frame_id <= 0;
      done_generation <= 0;
      done_symbol_slot <= 0;
      done_error <= 0;
      done_source_error <= 0;
      done_start_index <= 0;
      done_input_count <= 0;
      done_output_count <= 0;
      done_request_accepted <= 0;
    end else begin
      if (timing_active) age <= age + 1;
      if (state == DONE) begin
        if (done_ready) state <= (done_error == 0) ? IDLE : HALT;
      end else
      if (state == HALT) begin
      end else if (state == FLUSH) begin
        if (flush_count == 31) state <= DONE;
        else flush_count <= flush_count + 1;
      end else if (state == IDLE) begin
        if (cfg_valid && cfg_ready) begin
          done_frame_id <= cfg_frame_id;
          done_generation <= cfg_generation;
          done_symbol_slot <= cfg_symbol_slot;
          done_error <= 0;
          done_source_error <= cfg_source_error;
          done_start_index <= 0;
          done_input_count <= 0;
          done_output_count <= 0;
          done_request_accepted <= 0;
          age <= 0;
          flush_count <= 0;
          issued <= 0;
          raw_valid <= 0;
          out_valid <= 0;
          out_data <= 0;
          if (!cfg_source_complete || cfg_source_error != 0) begin
            done_error <= 1;
            state <= DONE;
          end else if (cfg_source_frame_id != cfg_frame_id ||
                       cfg_source_generation != cfg_generation) begin
            done_error <= 2;
            state <= DONE;
          end else if (cfg_symbol_slot >= 74) begin
            done_error <= 3;
            state <= DONE;
          end else if (cfg_nominal_length != 21'd1336320) begin
            done_error <= 4;
            state <= DONE;
          end else if (cfg_available_first > 32'sd0 || cfg_available_last < 32'sd1336319) begin
            done_error <= 5;
            state <= DONE;
          end else begin
            done_start_index <= start_calc[20:0];
            state <= REQUEST;
          end
        end
      end else if (abort) fail_run(11);
      else if (timeout_now) fail_run(12);
      else
        case (state)
          REQUEST:
          if (req_ready) begin
            done_request_accepted <= 1;
            state <= CAPTURE;
          end
          CAPTURE:
          if (input_fire) begin
            done_input_count <= done_input_count + 1;
            if (identity_bad) fail_run(6);
            else if (coordinate_bad) fail_run(7);
            else if (last_bad) fail_run(8);
            else if (mask_bad) fail_run(9);
            else if (s_error != 0) begin
              done_source_error <= s_error;
              fail_run(10);
            end else if (done_input_count == 511) begin
              state <= PLAY;
              issued <= 0;
              raw_valid <= 0;
              out_valid <= 0;
            end
          end
          PLAY: begin
            if (play_advance) begin
              out_valid <= raw_valid;
              if (raw_valid) out_data <= raw_data;
              raw_valid <= issued < 512;
              if (issued < 512) issued <= issued + 1;
            end
            if (output_fire) begin
              done_output_count <= done_output_count + 1;
              if (done_output_count == 511) begin
                state <= DONE;
                raw_valid <= 0;
                out_valid <= 0;
              end
            end
          end
          default: fail_run(13);
        endcase
    end
  end
endmodule
