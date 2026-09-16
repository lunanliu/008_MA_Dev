`timescale 1ns/1ps

module fine_corr_accumulator #(
  parameter int unsigned LANES = 16,
  parameter int unsigned PRODUCT_WIDTH = 35,
  parameter int unsigned ACCUMULATOR_WIDTH = 48
) (
  input  logic clk,
  input  logic rst_n,

  input  logic input_valid,
  output logic input_ready,
  input  logic [LANES*PRODUCT_WIDTH-1:0] product_re,
  input  logic [LANES*PRODUCT_WIDTH-1:0] product_im,
  input  logic signed [31:0] candidate_start,
  input  logic first_group,
  input  logic last_group,
  input  logic candidate_last,

  output logic result_valid,
  input  logic result_ready,
  output logic signed [31:0] result_candidate_start,
  output logic signed [ACCUMULATOR_WIDTH-1:0] corr_re,
  output logic signed [ACCUMULATOR_WIDTH-1:0] corr_im,
  output logic overflow,
  output logic result_candidate_last
);
  localparam int unsigned REDUCTION_WIDTH = PRODUCT_WIDTH+4;

  logic signed [PRODUCT_WIDTH-1:0] lane_re [0:15];
  logic signed [PRODUCT_WIDTH-1:0] lane_im [0:15];
  logic signed [PRODUCT_WIDTH:0] reduction_re_l1 [0:7];
  logic signed [PRODUCT_WIDTH:0] reduction_im_l1 [0:7];
  logic signed [PRODUCT_WIDTH+1:0] reduction_re_l2 [0:3];
  logic signed [PRODUCT_WIDTH+1:0] reduction_im_l2 [0:3];
  logic signed [PRODUCT_WIDTH+2:0] reduction_re_l3 [0:1];
  logic signed [PRODUCT_WIDTH+2:0] reduction_im_l3 [0:1];
  logic signed [REDUCTION_WIDTH-1:0] reduction_re_comb;
  logic signed [REDUCTION_WIDTH-1:0] reduction_im_comb;

  logic reduction_valid;
  logic signed [REDUCTION_WIDTH-1:0] reduction_re_reg;
  logic signed [REDUCTION_WIDTH-1:0] reduction_im_reg;
  logic signed [31:0] reduction_candidate_start;
  logic reduction_first_group;
  logic reduction_last_group;
  logic reduction_candidate_last;

  logic signed [ACCUMULATOR_WIDTH-1:0] accumulator_re;
  logic signed [ACCUMULATOR_WIDTH-1:0] accumulator_im;
  logic signed [31:0] active_candidate_start;
  logic overflow_sticky;

  logic result_slot_available;
  logic reduction_can_advance;
  logic reduction_fire;
  logic input_fire;
  logic signed [ACCUMULATOR_WIDTH-1:0] reduction_re_extended;
  logic signed [ACCUMULATOR_WIDTH-1:0] reduction_im_extended;
  logic signed [ACCUMULATOR_WIDTH-1:0] accumulator_base_re;
  logic signed [ACCUMULATOR_WIDTH-1:0] accumulator_base_im;
  logic signed [ACCUMULATOR_WIDTH-1:0] accumulator_next_re;
  logic signed [ACCUMULATOR_WIDTH-1:0] accumulator_next_im;
  logic addition_overflow_re;
  logic addition_overflow_im;
  logic overflow_after_group;

  initial begin
    if (LANES != 16)
      $error("T05 correlation accumulator requires exactly 16 lanes");
    if (PRODUCT_WIDTH == 0)
      $error("T05 correlation accumulator PRODUCT_WIDTH must be nonzero");
    if (ACCUMULATOR_WIDTH < REDUCTION_WIDTH)
      $error("T05 correlation accumulator width cannot hold one lane reduction");
  end

  for (genvar lane=0;lane<16;lane++) begin : g_lane_unpack
    always_comb begin
      lane_re[lane] = $signed(product_re[lane*PRODUCT_WIDTH +: PRODUCT_WIDTH]);
      lane_im[lane] = $signed(product_im[lane*PRODUCT_WIDTH +: PRODUCT_WIDTH]);
    end
  end

  for (genvar pair_index=0;pair_index<8;pair_index++) begin : g_reduce_l1
    always_comb begin
      reduction_re_l1[pair_index] =
          {lane_re[2*pair_index][PRODUCT_WIDTH-1],lane_re[2*pair_index]}+
          {lane_re[2*pair_index+1][PRODUCT_WIDTH-1],lane_re[2*pair_index+1]};
      reduction_im_l1[pair_index] =
          {lane_im[2*pair_index][PRODUCT_WIDTH-1],lane_im[2*pair_index]}+
          {lane_im[2*pair_index+1][PRODUCT_WIDTH-1],lane_im[2*pair_index+1]};
    end
  end

  for (genvar quad_index=0;quad_index<4;quad_index++) begin : g_reduce_l2
    always_comb begin
      reduction_re_l2[quad_index] =
          {reduction_re_l1[2*quad_index][PRODUCT_WIDTH],
           reduction_re_l1[2*quad_index]}+
          {reduction_re_l1[2*quad_index+1][PRODUCT_WIDTH],
           reduction_re_l1[2*quad_index+1]};
      reduction_im_l2[quad_index] =
          {reduction_im_l1[2*quad_index][PRODUCT_WIDTH],
           reduction_im_l1[2*quad_index]}+
          {reduction_im_l1[2*quad_index+1][PRODUCT_WIDTH],
           reduction_im_l1[2*quad_index+1]};
    end
  end

  for (genvar octet_index=0;octet_index<2;octet_index++) begin : g_reduce_l3
    always_comb begin
      reduction_re_l3[octet_index] =
          {reduction_re_l2[2*octet_index][PRODUCT_WIDTH+1],
           reduction_re_l2[2*octet_index]}+
          {reduction_re_l2[2*octet_index+1][PRODUCT_WIDTH+1],
           reduction_re_l2[2*octet_index+1]};
      reduction_im_l3[octet_index] =
          {reduction_im_l2[2*octet_index][PRODUCT_WIDTH+1],
           reduction_im_l2[2*octet_index]}+
          {reduction_im_l2[2*octet_index+1][PRODUCT_WIDTH+1],
           reduction_im_l2[2*octet_index+1]};
    end
  end

  always_comb begin
    reduction_re_comb =
        {reduction_re_l3[0][PRODUCT_WIDTH+2],reduction_re_l3[0]}+
        {reduction_re_l3[1][PRODUCT_WIDTH+2],reduction_re_l3[1]};
    reduction_im_comb =
        {reduction_im_l3[0][PRODUCT_WIDTH+2],reduction_im_l3[0]}+
        {reduction_im_l3[1][PRODUCT_WIDTH+2],reduction_im_l3[1]};

    result_slot_available = !result_valid || result_ready;
    reduction_can_advance = !reduction_valid ||
        !reduction_last_group || result_slot_available;
    input_ready = reduction_can_advance;
    reduction_fire = reduction_valid &&
        (!reduction_last_group || result_slot_available);
    input_fire = input_valid && input_ready;

    reduction_re_extended =
        {{(ACCUMULATOR_WIDTH-REDUCTION_WIDTH){reduction_re_reg[REDUCTION_WIDTH-1]}},
         reduction_re_reg};
    reduction_im_extended =
        {{(ACCUMULATOR_WIDTH-REDUCTION_WIDTH){reduction_im_reg[REDUCTION_WIDTH-1]}},
         reduction_im_reg};
    accumulator_base_re = reduction_first_group ? '0 : accumulator_re;
    accumulator_base_im = reduction_first_group ? '0 : accumulator_im;
    accumulator_next_re = accumulator_base_re+reduction_re_extended;
    accumulator_next_im = accumulator_base_im+reduction_im_extended;
    addition_overflow_re =
        (accumulator_base_re[ACCUMULATOR_WIDTH-1] ==
         reduction_re_extended[ACCUMULATOR_WIDTH-1]) &&
        (accumulator_next_re[ACCUMULATOR_WIDTH-1] !=
         accumulator_base_re[ACCUMULATOR_WIDTH-1]);
    addition_overflow_im =
        (accumulator_base_im[ACCUMULATOR_WIDTH-1] ==
         reduction_im_extended[ACCUMULATOR_WIDTH-1]) &&
        (accumulator_next_im[ACCUMULATOR_WIDTH-1] !=
         accumulator_base_im[ACCUMULATOR_WIDTH-1]);
    overflow_after_group =
        (reduction_first_group ? 1'b0 : overflow_sticky) ||
        addition_overflow_re || addition_overflow_im;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reduction_valid <= 1'b0;
      reduction_re_reg <= '0;
      reduction_im_reg <= '0;
      reduction_candidate_start <= '0;
      reduction_first_group <= 1'b0;
      reduction_last_group <= 1'b0;
      reduction_candidate_last <= 1'b0;
      accumulator_re <= '0;
      accumulator_im <= '0;
      active_candidate_start <= '0;
      overflow_sticky <= 1'b0;
      result_valid <= 1'b0;
      result_candidate_start <= '0;
      corr_re <= '0;
      corr_im <= '0;
      overflow <= 1'b0;
      result_candidate_last <= 1'b0;
    end else begin
      if (result_valid && result_ready)
        result_valid <= 1'b0;

      if (reduction_fire) begin
        accumulator_re <= accumulator_next_re;
        accumulator_im <= accumulator_next_im;
        overflow_sticky <= overflow_after_group;
        if (reduction_first_group)
          active_candidate_start <= reduction_candidate_start;

        if (reduction_last_group) begin
          result_valid <= 1'b1;
          result_candidate_start <= reduction_first_group ?
              reduction_candidate_start : active_candidate_start;
          corr_re <= accumulator_next_re;
          corr_im <= accumulator_next_im;
          overflow <= overflow_after_group;
          result_candidate_last <= reduction_candidate_last;
        end
      end

      if (input_fire) begin
        reduction_valid <= 1'b1;
        reduction_re_reg <= reduction_re_comb;
        reduction_im_reg <= reduction_im_comb;
        reduction_candidate_start <= candidate_start;
        reduction_first_group <= first_group;
        reduction_last_group <= last_group;
        reduction_candidate_last <= candidate_last;
      end else if (reduction_fire) begin
        reduction_valid <= 1'b0;
      end
    end
  end
endmodule
