`timescale 1ns/1ps

module coarse_safe_phase_replay (
  input  logic clk,
  input  logic rst_n,

  input  logic trace_valid,
  input  logic [8:0] trace_index,
  input  logic signed [42:0] trace_p_re,
  input  logic signed [42:0] trace_p_im,
  input  logic [41:0] trace_energy,

  input  logic selection_done,
  input  logic selection_found,
  input  logic signed [10:0] safe_first_trace_index,
  input  logic signed [10:0] safe_last_trace_index,

  output logic replay_busy,
  output logic replay_done,
  output logic aggregate_valid,
  output logic signed [47:0] aggregate_p_re,
  output logic signed [47:0] aggregate_p_im,
  output logic [46:0] aggregate_energy,
  output logic [5:0] aggregate_point_count,
  output logic protocol_error_sticky,
  output logic arithmetic_overflow_sticky
);
  logic [127:0] trace_write_data;
  logic [127:0] trace_read_data;
  logic [8:0] read_address;
  logic [8:0] last_read_address;
  logic read_request;
  logic read_valid_d;
  logic read_last_d;
  logic [8:0] expected_trace_index;

  logic signed [42:0] read_p_re;
  logic signed [42:0] read_p_im;
  logic [41:0] read_energy;

  assign trace_write_data = {
      trace_p_re, trace_p_im, trace_energy};
  assign read_p_re = $signed(trace_read_data[127:85]);
  assign read_p_im = $signed(trace_read_data[84:42]);
  assign read_energy = trace_read_data[41:0];
  assign replay_busy = read_request || read_valid_d;

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(9),
    .ADDR_WIDTH_B(9),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(128),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(128 * 257),
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
  ) u_metric_trace (
    .dbiterrb(),
    .doutb(trace_read_data),
    .sbiterrb(),
    .addra(trace_index),
    .addrb(read_address),
    .clka(clk),
    .clkb(clk),
    .dina(trace_write_data),
    .ena(trace_valid),
    .enb(read_request),
    .injectdbiterra(1'b0),
    .injectsbiterra(1'b0),
    .regceb(1'b1),
    .rstb(!rst_n),
    .sleep(1'b0),
    .wea(trace_valid)
  );

  always_ff @(posedge clk) begin
    logic signed [47:0] next_p_re;
    logic signed [47:0] next_p_im;
    logic [46:0] next_energy;
    logic signed [10:0] clamped_first;
    logic signed [10:0] clamped_last;
    if (!rst_n) begin
      read_address <= '0;
      last_read_address <= '0;
      read_request <= 1'b0;
      read_valid_d <= 1'b0;
      read_last_d <= 1'b0;
      expected_trace_index <= '0;
      replay_done <= 1'b0;
      aggregate_valid <= 1'b0;
      aggregate_p_re <= '0;
      aggregate_p_im <= '0;
      aggregate_energy <= '0;
      aggregate_point_count <= '0;
      protocol_error_sticky <= 1'b0;
      arithmetic_overflow_sticky <= 1'b0;
    end else begin
      replay_done <= 1'b0;
      aggregate_valid <= 1'b0;
      read_valid_d <= read_request;
      read_last_d <= read_request &&
          (read_address == last_read_address);

      if (trace_valid) begin
        if (trace_index != expected_trace_index)
          protocol_error_sticky <= 1'b1;
        if (trace_index == 256)
          expected_trace_index <= '0;
        else
          expected_trace_index <= expected_trace_index + 1'b1;
      end

      if (selection_done) begin
        if (replay_busy)
          protocol_error_sticky <= 1'b1;

        if (safe_first_trace_index < 0)
          clamped_first = 0;
        else
          clamped_first = safe_first_trace_index;
        if (safe_last_trace_index > 256)
          clamped_last = 256;
        else
          clamped_last = safe_last_trace_index;

        aggregate_p_re <= '0;
        aggregate_p_im <= '0;
        aggregate_energy <= '0;
        aggregate_point_count <= '0;
        if (selection_found &&
            safe_first_trace_index <= 256 &&
            safe_last_trace_index >= 0 &&
            clamped_first <= clamped_last) begin
          read_address <= clamped_first[8:0];
          last_read_address <= clamped_last[8:0];
          read_request <= 1'b1;
        end else begin
          read_request <= 1'b0;
          replay_done <= 1'b1;
        end
      end else if (read_request) begin
        if (read_address == last_read_address)
          read_request <= 1'b0;
        else
          read_address <= read_address + 1'b1;
      end

      if (read_valid_d) begin
        next_p_re = aggregate_p_re +
            {{5{read_p_re[42]}}, read_p_re};
        next_p_im = aggregate_p_im +
            {{5{read_p_im[42]}}, read_p_im};
        next_energy = aggregate_energy +
            {{5{1'b0}}, read_energy};

        if ((aggregate_p_re[47] == read_p_re[42]) &&
            (next_p_re[47] != aggregate_p_re[47]))
          arithmetic_overflow_sticky <= 1'b1;
        if ((aggregate_p_im[47] == read_p_im[42]) &&
            (next_p_im[47] != aggregate_p_im[47]))
          arithmetic_overflow_sticky <= 1'b1;
        if (next_energy < aggregate_energy)
          arithmetic_overflow_sticky <= 1'b1;

        aggregate_p_re <= next_p_re;
        aggregate_p_im <= next_p_im;
        aggregate_energy <= next_energy;
        aggregate_point_count <= aggregate_point_count + 1'b1;

        if (read_last_d) begin
          aggregate_valid <= 1'b1;
          replay_done <= 1'b1;
        end
      end
    end
  end
endmodule
