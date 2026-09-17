`timescale 1ns/1ps

module fine_corr_scheduler #(
  parameter int unsigned CANDIDATE_COUNT = 257,
  parameter int unsigned GROUPS_PER_CANDIDATE = 128,
  parameter int unsigned LANES = 16
) (
  input  logic clk,
  input  logic rst_n,

  input  logic start_valid,
  output logic start_ready,

  output logic schedule_valid,
  input  logic schedule_ready,
  output logic [8:0] candidate_index,
  output logic [6:0] group_index,
  output logic [LANES-1:0][11:0] sample_index,
  output logic [LANES-1:0][10:0] ref_index,
  output logic first,
  output logic last
);
  logic active;

  initial begin
    if (CANDIDATE_COUNT != 257)
      $error("T05 correlation scheduler requires 257 candidates");
    if (GROUPS_PER_CANDIDATE != 128)
      $error("T05 correlation scheduler requires 128 groups per candidate");
    if (LANES != 16)
      $error("T05 correlation scheduler requires 16 logical lanes");
  end

  always_comb begin
    start_ready = !active;
    schedule_valid = active;
    first = active && (group_index == 7'd0);
    last = active && (group_index == 7'd127);

    for (int unsigned lane = 0; lane < LANES; lane++) begin
      ref_index[lane] = {group_index,4'b0000} + lane;
      sample_index[lane] = {1'b0,{group_index,4'b0000}} +
          candidate_index + lane;
    end
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      active <= 1'b0;
      candidate_index <= '0;
      group_index <= '0;
    end else begin
      if (!active) begin
        if (start_valid && start_ready) begin
          active <= 1'b1;
          candidate_index <= '0;
          group_index <= '0;
        end
      end else if (schedule_valid && schedule_ready) begin
        if (group_index == GROUPS_PER_CANDIDATE-1) begin
          group_index <= '0;
          if (candidate_index == CANDIDATE_COUNT-1) begin
            active <= 1'b0;
            candidate_index <= '0;
          end else begin
            candidate_index <= candidate_index+1'b1;
          end
        end else begin
          group_index <= group_index+1'b1;
        end
      end
    end
  end
endmodule
