`timescale 1ns/1ps

module cfo_preamble_rotator #(
  parameter int unsigned LOCAL_SAMPLE_COUNT = 2304,
  parameter int unsigned FIFO_DEPTH = 16,
  parameter int unsigned CMPY_LATENCY = 4
) (
  input  logic clk,
  input  logic rst_n,

  input  logic start_valid,
  output logic start_ready,
  input  logic [31:0] phase_increment_code,
  output logic reader_start_pulse,

  input  logic raw_sample_valid,
  input  logic signed [15:0] raw_sample_i,
  input  logic signed [15:0] raw_sample_q,
  input  logic [11:0] raw_local_index,
  input  logic raw_first,
  input  logic raw_last,

  output logic corrected_valid,
  output logic signed [17:0] corrected_i,
  output logic signed [17:0] corrected_q,
  output logic [11:0] corrected_local_index,
  output logic corrected_first,
  output logic corrected_last,

  output logic busy,
  output logic done_pulse,
  output logic fifo_overflow_sticky,
  output logic dds_underflow_sticky,
  output logic ip_protocol_error_sticky,
  output logic corrected_overflow_sticky
);
  localparam int unsigned FIFO_ADDR_WIDTH = $clog2(FIFO_DEPTH);
  localparam int unsigned LAST_LOCAL_INDEX = LOCAL_SAMPLE_COUNT-1;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_DDS_RESET,
    ST_DDS_CONFIG,
    ST_RUN
  } state_t;

  state_t state;
  logic [1:0] reset_count;
  logic [31:0] held_phase_increment;

  logic signed [15:0] fifo_i [0:FIFO_DEPTH-1];
  logic signed [15:0] fifo_q [0:FIFO_DEPTH-1];
  logic [11:0] fifo_index [0:FIFO_DEPTH-1];
  logic fifo_first [0:FIFO_DEPTH-1];
  logic fifo_last [0:FIFO_DEPTH-1];
  logic [FIFO_ADDR_WIDTH-1:0] fifo_write_pointer;
  logic [FIFO_ADDR_WIDTH-1:0] fifo_read_pointer;
  logic [FIFO_ADDR_WIDTH:0] fifo_count;

  logic dds_aresetn;
  logic dds_config_valid;
  logic dds_output_valid;
  logic [47:0] dds_output_data;
  logic signed [17:0] dds_cosine;
  logic signed [17:0] dds_sine;
  logic signed [17:0] negative_sine;

  logic cmpy_launch;
  logic [47:0] cmpy_a_data;
  logic [47:0] cmpy_b_data;
  logic cmpy_output_valid;
  logic [79:0] cmpy_output_data;
  logic [11:0] launch_count;

  // The IP latency is the number of registered positions from an accepted
  // input to its output.  Therefore a latency of four uses positions 0..3;
  // the previous 0..4 declaration delayed tags one cycle beyond the real
  // CMPY TVALID and silently dropped the final corrected sample.
  logic [CMPY_LATENCY-1:0] tag_valid_pipe;
  logic [11:0] tag_index_pipe [0:CMPY_LATENCY-1];
  logic tag_first_pipe [0:CMPY_LATENCY-1];
  logic tag_last_pipe [0:CMPY_LATENCY-1];
  logic [18:0] quantized_i;
  logic [18:0] quantized_q;
  logic raw_push;

  function automatic [47:0] pack_complex18(
      input logic signed [17:0] re,
      input logic signed [17:0] im);
    logic [47:0] packed_value;
    begin
      packed_value = '0;
      packed_value[17:0] = re;
      packed_value[23:18] = {6{re[17]}};
      packed_value[41:24] = im;
      packed_value[47:42] = {6{im[17]}};
      return packed_value;
    end
  endfunction

  function automatic [18:0] rne_shift17_saturate18(
      input logic signed [36:0] value);
    logic signed [19:0] quotient;
    logic [16:0] remainder;
    logic increment, overflow;
    logic signed [20:0] rounded;
    logic signed [17:0] result;
    begin
      // Floor quotient and nonnegative remainder give exact signed ties-to-even.
      quotient = $signed(value[36:17]);
      remainder = value[16:0];
      increment = (remainder > 17'h10000) ||
          ((remainder == 17'h10000) && quotient[0]);
      rounded = $signed({quotient[19],quotient}) + $signed({20'd0,increment});
      overflow = (rounded > 21'sd131071) || (rounded < -21'sd131072);
      if (overflow) result = rounded[20] ? -18'sd131072 : 18'sd131071;
      else result = rounded[17:0];
      return {overflow,result};
    end
  endfunction

  initial begin
    if (LOCAL_SAMPLE_COUNT != 2304)
      $error("T05 CFO corrector frozen local length is 2304 samples");
    if (FIFO_DEPTH < 12 || (FIFO_DEPTH & (FIFO_DEPTH-1)) != 0)
      $error("T05 CFO corrector FIFO_DEPTH must be a power of two >= 12");
    if (CMPY_LATENCY < 1)
      $error("T05 CFO corrector CMPY latency must be positive");
  end

  assign start_ready = state == ST_IDLE;
  assign reader_start_pulse = state == ST_DDS_CONFIG;
  assign dds_aresetn = rst_n && state != ST_DDS_RESET;
  assign dds_config_valid = state == ST_DDS_CONFIG;
  assign dds_cosine = $signed(dds_output_data[17:0]);
  assign dds_sine = $signed(dds_output_data[41:24]);
  assign negative_sine = -dds_sine;

  assign cmpy_launch = state == ST_RUN && dds_output_valid &&
      launch_count < LOCAL_SAMPLE_COUNT && fifo_count != 0;
  assign raw_push = raw_sample_valid &&
      (fifo_count < FIFO_DEPTH || cmpy_launch);
  assign cmpy_a_data = pack_complex18(
      {{2{fifo_i[fifo_read_pointer][15]}},fifo_i[fifo_read_pointer]},
      {{2{fifo_q[fifo_read_pointer][15]}},fifo_q[fifo_read_pointer]});
  assign cmpy_b_data = pack_complex18(dds_cosine,negative_sine);

  assign quantized_i = rne_shift17_saturate18(
      $signed(cmpy_output_data[36:0]));
  assign quantized_q = rne_shift17_saturate18(
      $signed(cmpy_output_data[76:40]));
  assign corrected_valid = cmpy_output_valid &&
      tag_valid_pipe[CMPY_LATENCY-1];
  assign corrected_i = quantized_i[17:0];
  assign corrected_q = quantized_q[17:0];
  assign corrected_local_index = tag_index_pipe[CMPY_LATENCY-1];
  assign corrected_first = tag_first_pipe[CMPY_LATENCY-1];
  assign corrected_last = tag_last_pipe[CMPY_LATENCY-1];

  t05_dds_pinc32_sincos18 u_fine_dds (
    .aclk(clk),
    .aresetn(dds_aresetn),
    .s_axis_config_tvalid(dds_config_valid),
    .s_axis_config_tdata(held_phase_increment),
    .m_axis_data_tvalid(dds_output_valid),
    .m_axis_data_tdata(dds_output_data)
  );

  t05_cmpy_rotate_18x18 u_fine_rotate_cmpy (
    .aclk(clk),
    .s_axis_a_tvalid(cmpy_launch),
    .s_axis_a_tdata(cmpy_a_data),
    .s_axis_b_tvalid(cmpy_launch),
    .s_axis_b_tdata(cmpy_b_data),
    .m_axis_dout_tvalid(cmpy_output_valid),
    .m_axis_dout_tdata(cmpy_output_data)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      reset_count <= '0;
      held_phase_increment <= '0;
      fifo_write_pointer <= '0;
      fifo_read_pointer <= '0;
      fifo_count <= '0;
      launch_count <= '0;
      tag_valid_pipe <= '0;
      for (int stage=0; stage<CMPY_LATENCY; stage++) begin
        tag_index_pipe[stage] <= '0;
        tag_first_pipe[stage] <= 1'b0;
        tag_last_pipe[stage] <= 1'b0;
      end
      busy <= 1'b0;
      done_pulse <= 1'b0;
      fifo_overflow_sticky <= 1'b0;
      dds_underflow_sticky <= 1'b0;
      ip_protocol_error_sticky <= 1'b0;
      corrected_overflow_sticky <= 1'b0;
    end else begin
      done_pulse <= 1'b0;

      for (int stage=CMPY_LATENCY-1; stage>0; stage--) begin
        tag_valid_pipe[stage] <= tag_valid_pipe[stage-1];
        tag_index_pipe[stage] <= tag_index_pipe[stage-1];
        tag_first_pipe[stage] <= tag_first_pipe[stage-1];
        tag_last_pipe[stage] <= tag_last_pipe[stage-1];
      end
      tag_valid_pipe[0] <= cmpy_launch;
      if (cmpy_launch) begin
        tag_index_pipe[0] <= fifo_index[fifo_read_pointer];
        tag_first_pipe[0] <= fifo_first[fifo_read_pointer];
        tag_last_pipe[0] <= fifo_last[fifo_read_pointer];
      end

      if (raw_sample_valid && !raw_push)
        fifo_overflow_sticky <= 1'b1;
      if (raw_push) begin
        fifo_i[fifo_write_pointer] <= raw_sample_i;
        fifo_q[fifo_write_pointer] <= raw_sample_q;
        fifo_index[fifo_write_pointer] <= raw_local_index;
        fifo_first[fifo_write_pointer] <= raw_first;
        fifo_last[fifo_write_pointer] <= raw_last;
        fifo_write_pointer <= fifo_write_pointer + 1'b1;
      end
      if (cmpy_launch) begin
        fifo_read_pointer <= fifo_read_pointer + 1'b1;
        launch_count <= launch_count + 1'b1;
      end
      unique case ({raw_push,cmpy_launch})
        2'b10: fifo_count <= fifo_count + 1'b1;
        2'b01: fifo_count <= fifo_count - 1'b1;
        default: fifo_count <= fifo_count;
      endcase

      if (state == ST_RUN && dds_output_valid &&
          launch_count < LOCAL_SAMPLE_COUNT && fifo_count == 0)
        dds_underflow_sticky <= 1'b1;
      if (cmpy_output_valid != tag_valid_pipe[CMPY_LATENCY-1])
        ip_protocol_error_sticky <= 1'b1;
      if (corrected_valid && (quantized_i[18] || quantized_q[18]))
        corrected_overflow_sticky <= 1'b1;

      if (corrected_valid && corrected_last) begin
        if (corrected_local_index != LAST_LOCAL_INDEX[11:0])
          ip_protocol_error_sticky <= 1'b1;
        state <= ST_IDLE;
        busy <= 1'b0;
        done_pulse <= 1'b1;
      end

      unique case (state)
        ST_IDLE: begin
          if (start_valid && start_ready) begin
            held_phase_increment <= phase_increment_code;
            reset_count <= '0;
            fifo_write_pointer <= '0;
            fifo_read_pointer <= '0;
            fifo_count <= '0;
            launch_count <= '0;
            tag_valid_pipe <= '0;
            busy <= 1'b1;
            state <= ST_DDS_RESET;
          end
        end
        ST_DDS_RESET: begin
          if (reset_count == 2)
            state <= ST_DDS_CONFIG;
          else
            reset_count <= reset_count + 1'b1;
        end
        ST_DDS_CONFIG: state <= ST_RUN;
        ST_RUN: begin end
        default: begin
          state <= ST_IDLE;
          busy <= 1'b0;
          ip_protocol_error_sticky <= 1'b1;
        end
      endcase
    end
  end
endmodule
