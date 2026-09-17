`timescale 1ns/1ps

module coarse_lag1024_beat_ring #(
  parameter int unsigned FRAME_SAMPLES = 1_336_320,
  parameter int unsigned ACTIVE_FIRST_BEAT = 192,
  parameter int unsigned ACTIVE_LAST_BEAT = 703
) (
  input  logic clk,
  input  logic rst_n,

  input  logic beat_accept,
  input  logic [127:0] beat_data,
  input  logic [31:0] beat_frame_id,
  input  logic [31:0] beat_base_sample_index,
  input  logic [3:0] beat_lane_valid,
  input  logic beat_nominal_region,
  input  logic beat_halo_or_guard,
  input  logic beat_physical_frame_end,

  output logic pair_valid,
  output logic pair_first,
  output logic pair_last,
  output logic [127:0] pair_current_data,
  output logic [127:0] pair_delayed_data,
  output logic [31:0] pair_frame_id,
  output logic [31:0] pair_current_base_sample_index,
  output logic pair_context_valid,

  output logic protocol_error_sticky
);
  localparam int unsigned ACTIVE_FIRST_SAMPLE = ACTIVE_FIRST_BEAT * 4;
  localparam int unsigned ACTIVE_LAST_SAMPLE = ACTIVE_LAST_BEAT * 4;
  localparam int unsigned REQUIRED_CONTEXT_SAMPLES = 256;
  localparam int unsigned REQUIRED_CONTEXT_BEATS =
      REQUIRED_CONTEXT_SAMPLES / 4;

  logic [7:0] ring_pointer;
  logic [127:0] ring_read_data;
  logic delayed_accept;
  logic delayed_active;
  logic delayed_first;
  logic delayed_last;
  logic [127:0] delayed_current_data;
  logic [31:0] delayed_frame_id;
  logic [31:0] delayed_base_sample_index;
  logic delayed_context_valid;

  logic [8:0] halo_history_count;
  logic explicit_halo_active;
  logic explicit_halo_clean;
  logic [31:0] explicit_halo_frame_id;
  logic [31:0] expected_halo_base_sample_index;
  logic previous_nominal_frame_complete;
  logic [31:0] previous_complete_frame_id;
  logic current_frame_context_valid;
  logic nominal_frame_active;
  logic nominal_frame_clean;
  logic [31:0] nominal_frame_id;
  logic [31:0] expected_nominal_base_sample_index;

  logic input_active;
  logic explicit_halo_context_ready;
  logic previous_frame_context_ready;
  logic nominal_continuation_ok;
  assign input_active = beat_nominal_region &&
      (beat_base_sample_index >= ACTIVE_FIRST_SAMPLE) &&
      (beat_base_sample_index <= ACTIVE_LAST_SAMPLE);
  assign explicit_halo_context_ready =
      explicit_halo_active && explicit_halo_clean &&
      (halo_history_count >= REQUIRED_CONTEXT_BEATS) &&
      (expected_halo_base_sample_index == FRAME_SAMPLES) &&
      (beat_frame_id == explicit_halo_frame_id + 1'b1);
  assign previous_frame_context_ready =
      previous_nominal_frame_complete &&
      (beat_frame_id == previous_complete_frame_id + 1'b1);
  assign nominal_continuation_ok =
      nominal_frame_active &&
      (beat_frame_id == nominal_frame_id) &&
      (beat_base_sample_index ==
          expected_nominal_base_sample_index) &&
      (beat_lane_valid == 4'hf);

  initial begin
    if (ACTIVE_FIRST_BEAT != 192 || ACTIVE_LAST_BEAT != 703)
      $error("The frozen T04 active input-beat interval is 192 through 703");
    if ((FRAME_SAMPLES % 1024) != 0)
      $error("Frame length must preserve the 1024-sample ring phase");
    if ((REQUIRED_CONTEXT_SAMPLES % 4) != 0)
      $error("Required previous context must contain complete four-lane beats");
  end

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(8),
    .ADDR_WIDTH_B(8),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(128),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(128 * 256),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(128),
    .READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(128),
    .WRITE_MODE_B("read_first")
  ) u_lag1024_history (
    .dbiterrb(),
    .doutb(ring_read_data),
    .sbiterrb(),
    .addra(ring_pointer),
    .addrb(ring_pointer),
    .clka(clk),
    .clkb(clk),
    .dina(beat_data),
    .ena(beat_accept),
    .enb(beat_accept),
    .injectdbiterra(1'b0),
    .injectsbiterra(1'b0),
    .regceb(1'b1),
    .rstb(!rst_n),
    .sleep(1'b0),
    .wea(beat_accept)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ring_pointer <= '0;
      delayed_accept <= 1'b0;
      delayed_active <= 1'b0;
      delayed_first <= 1'b0;
      delayed_last <= 1'b0;
      delayed_current_data <= '0;
      delayed_frame_id <= '0;
      delayed_base_sample_index <= '0;
      delayed_context_valid <= 1'b0;
      halo_history_count <= '0;
      explicit_halo_active <= 1'b0;
      explicit_halo_clean <= 1'b0;
      explicit_halo_frame_id <= '0;
      expected_halo_base_sample_index <= '0;
      previous_nominal_frame_complete <= 1'b0;
      previous_complete_frame_id <= '0;
      current_frame_context_valid <= 1'b0;
      nominal_frame_active <= 1'b0;
      nominal_frame_clean <= 1'b0;
      nominal_frame_id <= '0;
      expected_nominal_base_sample_index <= '0;
      protocol_error_sticky <= 1'b0;
    end else begin
      delayed_accept <= beat_accept;
      if (beat_accept) begin
        delayed_active <= input_active;
        delayed_first <= input_active &&
            (beat_base_sample_index == ACTIVE_FIRST_SAMPLE);
        delayed_last <= input_active &&
            (beat_base_sample_index == ACTIVE_LAST_SAMPLE);
        delayed_current_data <= beat_data;
        delayed_frame_id <= beat_frame_id;
        delayed_base_sample_index <= beat_base_sample_index;
        delayed_context_valid <= current_frame_context_valid;
        ring_pointer <= ring_pointer + 1'b1;

        if (beat_lane_valid != 4'hf) begin
          protocol_error_sticky <= 1'b1;
          halo_history_count <= '0;
          explicit_halo_active <= 1'b0;
          explicit_halo_clean <= 1'b0;
          previous_nominal_frame_complete <= 1'b0;
          nominal_frame_clean <= 1'b0;
        end else if (beat_halo_or_guard && !beat_nominal_region) begin
          previous_nominal_frame_complete <= 1'b0;
          if (nominal_frame_active) begin
            protocol_error_sticky <= 1'b1;
            nominal_frame_clean <= 1'b0;
          end
          if (!explicit_halo_active) begin
            explicit_halo_active <= 1'b1;
            explicit_halo_clean <=
                (beat_base_sample_index[1:0] == 2'b00) &&
                (beat_base_sample_index < FRAME_SAMPLES);
            explicit_halo_frame_id <= beat_frame_id;
            expected_halo_base_sample_index <=
                beat_base_sample_index + 32'd4;
            halo_history_count <= 9'd1;
            if (beat_base_sample_index[1:0] != 2'b00 ||
                beat_base_sample_index >= FRAME_SAMPLES)
              protocol_error_sticky <= 1'b1;
          end else if (beat_frame_id == explicit_halo_frame_id &&
                       beat_base_sample_index ==
                           expected_halo_base_sample_index &&
                       beat_base_sample_index < FRAME_SAMPLES) begin
            expected_halo_base_sample_index <=
                beat_base_sample_index + 32'd4;
            if (halo_history_count < REQUIRED_CONTEXT_BEATS)
              halo_history_count <= halo_history_count + 1'b1;
          end else begin
            protocol_error_sticky <= 1'b1;
            halo_history_count <= '0;
            explicit_halo_active <= 1'b0;
            explicit_halo_clean <= 1'b0;
          end
        end

        if (beat_nominal_region) begin
          if (beat_halo_or_guard)
            protocol_error_sticky <= 1'b1;
          if (beat_base_sample_index[1:0] != 2'b00)
            protocol_error_sticky <= 1'b1;

          if (beat_base_sample_index == 0) begin
            if (nominal_frame_active)
              protocol_error_sticky <= 1'b1;
            current_frame_context_valid <=
                (explicit_halo_context_ready ||
                 previous_frame_context_ready) &&
                (beat_lane_valid == 4'hf) &&
                !beat_halo_or_guard &&
                !nominal_frame_active;
            nominal_frame_active <= 1'b1;
            nominal_frame_clean <=
                !nominal_frame_active &&
                (beat_lane_valid == 4'hf) &&
                !beat_halo_or_guard;
            nominal_frame_id <= beat_frame_id;
            expected_nominal_base_sample_index <= 32'd4;
            halo_history_count <= '0;
            explicit_halo_active <= 1'b0;
            explicit_halo_clean <= 1'b0;
            previous_nominal_frame_complete <= 1'b0;
          end else begin
            if (!nominal_continuation_ok) begin
              protocol_error_sticky <= 1'b1;
              nominal_frame_clean <= 1'b0;
              previous_nominal_frame_complete <= 1'b0;
              halo_history_count <= '0;
              explicit_halo_active <= 1'b0;
              explicit_halo_clean <= 1'b0;
            end
            expected_nominal_base_sample_index <=
                beat_base_sample_index + 32'd4;
          end

          if (beat_physical_frame_end) begin
            if (beat_base_sample_index != FRAME_SAMPLES-4)
              protocol_error_sticky <= 1'b1;
            previous_nominal_frame_complete <=
                nominal_frame_clean &&
                nominal_continuation_ok &&
                (beat_base_sample_index == FRAME_SAMPLES-4) &&
                (beat_lane_valid == 4'hf);
            previous_complete_frame_id <= beat_frame_id;
            nominal_frame_active <= 1'b0;
            nominal_frame_clean <= 1'b0;
          end
        end else if (!beat_halo_or_guard) begin
          protocol_error_sticky <= 1'b1;
          halo_history_count <= '0;
          explicit_halo_active <= 1'b0;
          explicit_halo_clean <= 1'b0;
          previous_nominal_frame_complete <= 1'b0;
          nominal_frame_clean <= 1'b0;
        end
      end
    end
  end

  always_comb begin
    pair_valid = delayed_accept && delayed_active;
    pair_first = pair_valid && delayed_first;
    pair_last = pair_valid && delayed_last;
    pair_current_data = delayed_current_data;
    pair_delayed_data = ring_read_data;
    pair_frame_id = delayed_frame_id;
    pair_current_base_sample_index = delayed_base_sample_index;
    pair_context_valid = delayed_context_valid;
  end
endmodule
