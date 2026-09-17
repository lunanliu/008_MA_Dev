`timescale 1ns/1ps

module fine_local_window_reader #(
  parameter int signed CAPTURE_FIRST_SAMPLE = 152,
  parameter int signed CAPTURE_LAST_SAMPLE  = 2919,
  parameter int signed USEFUL_OFFSET_SAMPLES = 384,
  parameter int unsigned LOCAL_SAMPLE_COUNT = 2304,
  parameter int unsigned ADDR_WIDTH = 10,
  parameter int unsigned READ_LATENCY = 2
) (
  input  logic clk,
  input  logic rst_n,

  input  logic start_valid,
  output logic start_ready,
  input  logic signed [31:0] coarse_start_sample,

  output logic read_req_valid,
  input  logic read_req_ready,
  output logic [ADDR_WIDTH-1:0] read_req_addr,
  input  logic read_rsp_valid,
  input  logic [127:0] read_rsp_data,

  output logic sample_valid,
  output logic signed [15:0] sample_i,
  output logic signed [15:0] sample_q,
  output logic [11:0] sample_local_index,
  output logic signed [31:0] sample_global_index,
  output logic sample_first,
  output logic sample_last,

  output logic busy,
  output logic done_pulse,
  output logic range_error_sticky,
  output logic read_protocol_error_sticky
);
  localparam int unsigned LAST_LOCAL_INDEX = LOCAL_SAMPLE_COUNT-1;

  logic issuing;
  logic signed [31:0] first_global_sample;
  logic [11:0] issue_index;
  logic [READ_LATENCY-1:0] tag_valid_pipe;
  logic [1:0] tag_lane_pipe [0:READ_LATENCY-1];
  logic [11:0] tag_local_pipe [0:READ_LATENCY-1];
  logic signed [31:0] tag_global_pipe [0:READ_LATENCY-1];
  logic tag_first_pipe [0:READ_LATENCY-1];
  logic tag_last_pipe [0:READ_LATENCY-1];

  logic signed [32:0] requested_global;
  logic signed [32:0] requested_relative;
  logic read_fire;
  logic response_tag_valid;
  logic [1:0] response_lane;

  initial begin
    if (READ_LATENCY < 1)
      $error("T05 local-window reader requires READ_LATENCY >= 1");
    if (LOCAL_SAMPLE_COUNT != 2304)
      $error("T05 frozen local union must contain 2304 samples");
  end

  always_comb begin
    requested_global = $signed(first_global_sample) + $signed({1'b0,issue_index});
    requested_relative = requested_global - CAPTURE_FIRST_SAMPLE;
    start_ready = !busy && !(|tag_valid_pipe);
    read_req_valid = busy && issuing;
    read_req_addr = requested_relative[ADDR_WIDTH+1:2];
    read_fire = read_req_valid && read_req_ready;

    response_tag_valid = tag_valid_pipe[READ_LATENCY-1];
    response_lane = tag_lane_pipe[READ_LATENCY-1];
    sample_valid = response_tag_valid && read_rsp_valid;
    sample_i = $signed(read_rsp_data[32*response_lane +: 16]);
    sample_q = $signed(read_rsp_data[32*response_lane+16 +: 16]);
    sample_local_index = tag_local_pipe[READ_LATENCY-1];
    sample_global_index = tag_global_pipe[READ_LATENCY-1];
    sample_first = tag_first_pipe[READ_LATENCY-1];
    sample_last = tag_last_pipe[READ_LATENCY-1];
  end

  always_ff @(posedge clk) begin
    logic signed [32:0] proposed_first;
    logic signed [32:0] proposed_last;
    if (!rst_n) begin
      issuing <= 1'b0;
      first_global_sample <= '0;
      issue_index <= '0;
      tag_valid_pipe <= '0;
      for (int stage=0; stage<READ_LATENCY; stage++) begin
        tag_lane_pipe[stage] <= '0;
        tag_local_pipe[stage] <= '0;
        tag_global_pipe[stage] <= '0;
        tag_first_pipe[stage] <= 1'b0;
        tag_last_pipe[stage] <= 1'b0;
      end
      busy <= 1'b0;
      done_pulse <= 1'b0;
      range_error_sticky <= 1'b0;
      read_protocol_error_sticky <= 1'b0;
    end else begin
      done_pulse <= 1'b0;

      for (int stage=READ_LATENCY-1; stage>0; stage--) begin
        tag_valid_pipe[stage] <= tag_valid_pipe[stage-1];
        tag_lane_pipe[stage] <= tag_lane_pipe[stage-1];
        tag_local_pipe[stage] <= tag_local_pipe[stage-1];
        tag_global_pipe[stage] <= tag_global_pipe[stage-1];
        tag_first_pipe[stage] <= tag_first_pipe[stage-1];
        tag_last_pipe[stage] <= tag_last_pipe[stage-1];
      end
      tag_valid_pipe[0] <= read_fire;
      if (read_fire) begin
        tag_lane_pipe[0] <= requested_relative[1:0];
        tag_local_pipe[0] <= issue_index;
        tag_global_pipe[0] <= requested_global[31:0];
        tag_first_pipe[0] <= issue_index == 0;
        tag_last_pipe[0] <= issue_index == LAST_LOCAL_INDEX[11:0];
        if (issue_index == LAST_LOCAL_INDEX[11:0]) begin
          issuing <= 1'b0;
        end else begin
          issue_index <= issue_index + 1'b1;
        end
      end

      if (response_tag_valid != read_rsp_valid)
        read_protocol_error_sticky <= 1'b1;

      if (sample_valid && sample_last) begin
        busy <= 1'b0;
        done_pulse <= 1'b1;
      end

      if (start_valid && start_ready) begin
        proposed_first = $signed(coarse_start_sample) + USEFUL_OFFSET_SAMPLES;
        proposed_last = proposed_first + LOCAL_SAMPLE_COUNT - 1;
        first_global_sample <= proposed_first[31:0];
        issue_index <= '0;
        if (proposed_first < CAPTURE_FIRST_SAMPLE ||
            proposed_last > CAPTURE_LAST_SAMPLE) begin
          range_error_sticky <= 1'b1;
          busy <= 1'b0;
          issuing <= 1'b0;
          done_pulse <= 1'b1;
        end else begin
          busy <= 1'b1;
          issuing <= 1'b1;
        end
      end
    end
  end
endmodule
