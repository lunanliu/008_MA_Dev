`timescale 1ns/1ps

module t05_local_capture_buffer #(
  parameter int unsigned FIRST_SAMPLE = 152,
  parameter int unsigned LAST_SAMPLE  = 2919,
  parameter int unsigned BEAT_WIDTH   = 128,
  parameter int unsigned ADDR_WIDTH   = 10
) (
  input  logic clk,
  input  logic rst_n,

  input  logic tap_fire,
  input  logic [127:0] tap_data,
  input  logic [31:0] tap_frame_id,
  input  logic signed [31:0] tap_base_sample_index,
  input  logic [3:0] tap_lane_valid,

  output logic capture_valid,
  output logic capture_context_valid,
  output logic [31:0] capture_frame_id,
  input  logic capture_release,

  input  logic read_req_valid,
  output logic read_req_ready,
  input  logic [ADDR_WIDTH-1:0] read_req_addr,
  output logic read_rsp_valid,
  output logic [BEAT_WIDTH-1:0] read_rsp_data,

  output logic capture_protocol_error_sticky,
  output logic capture_overwrite_error_sticky,
  output logic read_protocol_error_sticky
);
  localparam int unsigned FIRST_BEAT = FIRST_SAMPLE / 4;
  localparam int unsigned LAST_BEAT = LAST_SAMPLE / 4;
  localparam int unsigned DEPTH_BEATS = LAST_BEAT-FIRST_BEAT+1;
  localparam int unsigned READ_LATENCY = 2;

  logic capture_active;
  logic [31:0] active_frame_id;
  logic [ADDR_WIDTH-1:0] expected_addr;
  logic active_context_valid;
  logic write_enable;
  logic [ADDR_WIDTH-1:0] write_addr;
  logic [READ_LATENCY-1:0] read_valid_pipe;

  logic tap_in_range;
  logic tap_aligned;
  logic [ADDR_WIDTH-1:0] tap_relative_addr;
  logic read_accept;

  initial begin
    if ((FIRST_SAMPLE % 4) != 0 || ((LAST_SAMPLE+1) % 4) != 0)
      $error("T05 capture bounds must cover whole four-sample beats");
    if ((1 << ADDR_WIDTH) < DEPTH_BEATS)
      $error("T05 local capture ADDR_WIDTH is too small");
  end

  always_comb begin
    tap_in_range = tap_base_sample_index >= $signed(FIRST_SAMPLE) &&
        tap_base_sample_index <= $signed(LAST_SAMPLE-3);
    tap_aligned = tap_base_sample_index[1:0] == 2'b00;
    tap_relative_addr = (tap_base_sample_index-FIRST_SAMPLE) >>> 2;
    write_enable = tap_fire && tap_in_range && tap_aligned &&
        (!capture_valid || capture_active);
    write_addr = tap_relative_addr;
    read_req_ready = capture_valid &&
        (read_req_addr < DEPTH_BEATS[ADDR_WIDTH-1:0]);
    read_accept = read_req_valid && read_req_ready;
    read_rsp_valid = read_valid_pipe[READ_LATENCY-1];
  end

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(ADDR_WIDTH),
    .ADDR_WIDTH_B(ADDR_WIDTH),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(BEAT_WIDTH),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(BEAT_WIDTH*DEPTH_BEATS),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(BEAT_WIDTH),
    .READ_LATENCY_B(READ_LATENCY),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(BEAT_WIDTH),
    .WRITE_MODE_B("read_first")
  ) u_local_raw_memory (
    .dbiterrb(),.doutb(read_rsp_data),.sbiterrb(),
    .addra(write_addr),.addrb(read_req_addr),
    .clka(clk),.clkb(clk),.dina(tap_data),
    .ena(write_enable),.enb(read_accept),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.rstb(!rst_n),.sleep(1'b0),.wea(write_enable)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      capture_active <= 1'b0;
      active_frame_id <= '0;
      expected_addr <= '0;
      active_context_valid <= 1'b0;
      capture_valid <= 1'b0;
      capture_context_valid <= 1'b0;
      capture_frame_id <= '0;
      read_valid_pipe <= '0;
      capture_protocol_error_sticky <= 1'b0;
      capture_overwrite_error_sticky <= 1'b0;
      read_protocol_error_sticky <= 1'b0;
    end else begin
      read_valid_pipe[0] <= read_accept;
      for (int stage=1; stage<READ_LATENCY; stage++)
        read_valid_pipe[stage] <= read_valid_pipe[stage-1];

      if (capture_release && !capture_active) begin
        capture_valid <= 1'b0;
        capture_context_valid <= 1'b0;
      end

      if (read_req_valid && !read_req_ready)
        read_protocol_error_sticky <= 1'b1;

      if (tap_fire && tap_in_range) begin
        if (capture_valid && !capture_active) begin
          capture_overwrite_error_sticky <= 1'b1;
        end else if (!capture_active) begin
          capture_active <= 1'b1;
          active_frame_id <= tap_frame_id;
          expected_addr <= tap_relative_addr + 1'b1;
          active_context_valid <= tap_aligned &&
              (tap_relative_addr == 0) && (tap_lane_valid == 4'hf);
          if (!tap_aligned || tap_relative_addr != 0 ||
              tap_lane_valid != 4'hf)
            capture_protocol_error_sticky <= 1'b1;
          if (tap_relative_addr == DEPTH_BEATS-1) begin
            capture_active <= 1'b0;
            capture_valid <= 1'b1;
            capture_context_valid <= tap_aligned &&
                (tap_relative_addr == 0) && (tap_lane_valid == 4'hf);
            capture_frame_id <= tap_frame_id;
          end
        end else begin
          if (!tap_aligned || tap_frame_id != active_frame_id ||
              tap_relative_addr != expected_addr ||
              tap_lane_valid != 4'hf) begin
            active_context_valid <= 1'b0;
            capture_protocol_error_sticky <= 1'b1;
          end
          expected_addr <= tap_relative_addr + 1'b1;
          if (tap_relative_addr == DEPTH_BEATS-1) begin
            capture_active <= 1'b0;
            capture_valid <= 1'b1;
            capture_context_valid <= active_context_valid && tap_aligned &&
                (tap_frame_id == active_frame_id) &&
                (tap_relative_addr == expected_addr) &&
                (tap_lane_valid == 4'hf);
            capture_frame_id <= active_frame_id;
          end
        end
      end
    end
  end
endmodule
