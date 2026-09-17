`timescale 1ns/1ps

module coarse_rolling_sc_accumulator #(
  parameter int unsigned WINDOW_BEATS = 256,
  parameter int unsigned AGGREGATE_BEATS_PER_FRAME = 512
) (
  input  logic clk,
  input  logic rst_n,

  input  logic aggregate_valid,
  input  logic aggregate_first,
  input  logic aggregate_last,
  input  logic signed [34:0] aggregate_p_re,
  input  logic signed [34:0] aggregate_p_im,
  input  logic [33:0] aggregate_energy,

  output logic metric_valid,
  output logic metric_last,
  output logic [8:0] metric_index,
  output logic signed [42:0] rolling_p_re,
  output logic signed [42:0] rolling_p_im,
  output logic [41:0] rolling_energy,
  output logic arithmetic_overflow_sticky,
  output logic protocol_error_sticky
);
  localparam int unsigned AGGREGATE_WIDTH = 35 + 35 + 34;

  logic [7:0] memory_address;
  logic [AGGREGATE_WIDTH-1:0] memory_write_data;
  logic [AGGREGATE_WIDTH-1:0] memory_read_data;
  logic [7:0] write_pointer;

  logic delayed_valid;
  logic delayed_first;
  logic delayed_last;
  logic signed [34:0] delayed_p_re;
  logic signed [34:0] delayed_p_im;
  logic [33:0] delayed_energy;

  logic signed [34:0] old_p_re;
  logic signed [34:0] old_p_im;
  logic [33:0] old_energy;

  logic [8:0] fill_count;
  logic [8:0] next_metric_index;
  logic input_frame_active;
  logic [9:0] input_aggregate_count;

  initial begin
    if (WINDOW_BEATS != 256)
      $error("The frozen 1024-sample/4-lane window is exactly 256 beats");
    if (AGGREGATE_BEATS_PER_FRAME != 512)
      $error("The frozen active correlation interval is exactly 512 beats");
  end

  assign memory_address = aggregate_first ? 8'd0 : write_pointer;
  assign memory_write_data = {
      aggregate_p_re, aggregate_p_im, aggregate_energy};
  assign old_p_re = $signed(memory_read_data[103:69]);
  assign old_p_im = $signed(memory_read_data[68:34]);
  assign old_energy = memory_read_data[33:0];

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(8),
    .ADDR_WIDTH_B(8),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(AGGREGATE_WIDTH),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(AGGREGATE_WIDTH * WINDOW_BEATS),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(AGGREGATE_WIDTH),
    .READ_LATENCY_B(1),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(AGGREGATE_WIDTH),
    .WRITE_MODE_B("read_first")
  ) u_aggregate_history (
    .dbiterrb(),
    .doutb(memory_read_data),
    .sbiterrb(),
    .addra(memory_address),
    .addrb(memory_address),
    .clka(clk),
    .clkb(clk),
    .dina(memory_write_data),
    .ena(aggregate_valid),
    .enb(aggregate_valid),
    .injectdbiterra(1'b0),
    .injectsbiterra(1'b0),
    .regceb(1'b1),
    .rstb(!rst_n),
    .sleep(1'b0),
    .wea(aggregate_valid)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      write_pointer <= '0;
      delayed_valid <= 1'b0;
      delayed_first <= 1'b0;
      delayed_last <= 1'b0;
      delayed_p_re <= '0;
      delayed_p_im <= '0;
      delayed_energy <= '0;
      input_frame_active <= 1'b0;
      input_aggregate_count <= '0;
      protocol_error_sticky <= 1'b0;
    end else begin
      delayed_valid <= aggregate_valid;
      if (aggregate_valid) begin
        delayed_first <= aggregate_first;
        delayed_last <= aggregate_last;
        delayed_p_re <= aggregate_p_re;
        delayed_p_im <= aggregate_p_im;
        delayed_energy <= aggregate_energy;

        if (aggregate_first) begin
          if (input_frame_active || aggregate_last)
            protocol_error_sticky <= 1'b1;
          input_frame_active <= 1'b1;
          input_aggregate_count <= 10'd1;
          write_pointer <= 8'd1;
        end else begin
          if (!input_frame_active)
            protocol_error_sticky <= 1'b1;
          write_pointer <= write_pointer + 1'b1;
          if (aggregate_last) begin
            if (input_aggregate_count !=
                AGGREGATE_BEATS_PER_FRAME-1)
              protocol_error_sticky <= 1'b1;
            input_frame_active <= 1'b0;
            input_aggregate_count <= '0;
          end else begin
            if (input_aggregate_count >=
                AGGREGATE_BEATS_PER_FRAME-1)
              protocol_error_sticky <= 1'b1;
            input_aggregate_count <=
                input_aggregate_count + 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    logic signed [43:0] next_p_re_ext;
    logic signed [43:0] next_p_im_ext;
    logic [42:0] next_energy_ext;
    if (!rst_n) begin
      fill_count <= '0;
      next_metric_index <= '0;
      metric_valid <= 1'b0;
      metric_last <= 1'b0;
      metric_index <= '0;
      rolling_p_re <= '0;
      rolling_p_im <= '0;
      rolling_energy <= '0;
      arithmetic_overflow_sticky <= 1'b0;
    end else begin
      metric_valid <= 1'b0;
      metric_last <= 1'b0;
      if (delayed_valid) begin
        if (delayed_first) begin
          next_p_re_ext =
              {{9{delayed_p_re[34]}}, delayed_p_re};
          next_p_im_ext =
              {{9{delayed_p_im[34]}}, delayed_p_im};
          next_energy_ext = {{9{1'b0}}, delayed_energy};
          fill_count <= 9'd1;
          next_metric_index <= '0;
        end else if (fill_count < WINDOW_BEATS) begin
          next_p_re_ext =
              {{1{rolling_p_re[42]}}, rolling_p_re} +
              {{9{delayed_p_re[34]}}, delayed_p_re};
          next_p_im_ext =
              {{1{rolling_p_im[42]}}, rolling_p_im} +
              {{9{delayed_p_im[34]}}, delayed_p_im};
          next_energy_ext =
              {1'b0, rolling_energy} +
              {{9{1'b0}}, delayed_energy};
          fill_count <= fill_count + 1'b1;
        end else begin
          next_p_re_ext =
              {{1{rolling_p_re[42]}}, rolling_p_re} +
              {{9{delayed_p_re[34]}}, delayed_p_re} -
              {{9{old_p_re[34]}}, old_p_re};
          next_p_im_ext =
              {{1{rolling_p_im[42]}}, rolling_p_im} +
              {{9{delayed_p_im[34]}}, delayed_p_im} -
              {{9{old_p_im[34]}}, old_p_im};
          next_energy_ext =
              {1'b0, rolling_energy} +
              {{9{1'b0}}, delayed_energy} -
              {{9{1'b0}}, old_energy};
          fill_count <= fill_count;
        end

        if (next_p_re_ext[43] != next_p_re_ext[42] ||
            next_p_im_ext[43] != next_p_im_ext[42] ||
            next_energy_ext[42])
          arithmetic_overflow_sticky <= 1'b1;

        rolling_p_re <= next_p_re_ext[42:0];
        rolling_p_im <= next_p_im_ext[42:0];
        rolling_energy <= next_energy_ext[41:0];

        if (!delayed_first && fill_count >= WINDOW_BEATS-1) begin
          metric_valid <= 1'b1;
          metric_last <= delayed_last;
          metric_index <= next_metric_index;
          if (!delayed_last)
            next_metric_index <= next_metric_index + 1'b1;
        end
      end
    end
  end
endmodule
