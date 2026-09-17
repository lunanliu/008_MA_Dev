`timescale 1ns/1ps

module fine_corr_metric_controller (
  input  logic clk,
  input  logic rst_n,

  input  logic corr_valid,
  output logic corr_ready,
  input  logic signed [47:0] corr_re,
  input  logic signed [47:0] corr_im,
  input  logic signed [31:0] corr_candidate_start,
  input  logic corr_candidate_last,
  input  logic corr_overflow,

  output logic mul_req_valid,
  output logic signed [47:0] mul_req_operand,
  input  logic mul_rsp_valid,
  input  logic [95:0] mul_rsp_square,

  output logic metric_valid,
  input  logic metric_ready,
  output logic signed [31:0] metric_candidate_start,
  output logic metric_candidate_last,
  output logic [96:0] metric,
  output logic metric_overflow
);
  logic transaction_active;
  logic [1:0] requests_issued;
  logic response_phase;
  logic signed [47:0] held_corr_re;
  logic signed [47:0] held_corr_im;
  logic signed [31:0] held_candidate_start;
  logic held_candidate_last;
  logic held_corr_overflow;
  logic [95:0] held_re_square;
  logic corr_fire;

  always_comb begin
    corr_ready = !transaction_active && (!metric_valid || metric_ready);
    corr_fire = corr_valid && corr_ready;
    mul_req_valid = transaction_active && (requests_issued < 2);
    if (requests_issued == 0)
      mul_req_operand = held_corr_re;
    else
      mul_req_operand = held_corr_im;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      transaction_active <= 1'b0;
      requests_issued <= '0;
      response_phase <= 1'b0;
      held_corr_re <= '0;
      held_corr_im <= '0;
      held_candidate_start <= '0;
      held_candidate_last <= 1'b0;
      held_corr_overflow <= 1'b0;
      held_re_square <= '0;
      metric_valid <= 1'b0;
      metric_candidate_start <= '0;
      metric_candidate_last <= 1'b0;
      metric <= '0;
      metric_overflow <= 1'b0;
    end else begin
      if (metric_valid && metric_ready)
        metric_valid <= 1'b0;

      if (corr_fire) begin
        transaction_active <= 1'b1;
        requests_issued <= '0;
        response_phase <= 1'b0;
        held_corr_re <= corr_re;
        held_corr_im <= corr_im;
        held_candidate_start <= corr_candidate_start;
        held_candidate_last <= corr_candidate_last;
        held_corr_overflow <= corr_overflow;
      end

      if (mul_req_valid)
        requests_issued <= requests_issued+1'b1;

      if (mul_rsp_valid && transaction_active) begin
        if (!response_phase) begin
          held_re_square <= mul_rsp_square;
          response_phase <= 1'b1;
        end else begin
          metric <= {1'b0,held_re_square}+{1'b0,mul_rsp_square};
          metric_candidate_start <= held_candidate_start;
          metric_candidate_last <= held_candidate_last;
          metric_overflow <= held_corr_overflow;
          metric_valid <= 1'b1;
          transaction_active <= 1'b0;
          response_phase <= 1'b0;
        end
      end
    end
  end
endmodule
