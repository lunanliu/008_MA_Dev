`timescale 1ns / 1ps
module sfo_initial_weight_pack (
    input  logic        clk,
    input  logic        rst,
    input  logic        s_valid,
    output logic        s_ready,
    input  logic [63:0] s_n,
    input  logic [32:0] s_d,
    input  logic [63:0] s_n_max,
    input  logic [32:0] s_d_max,
    input  logic [31:0] s_tag,
    output logic        m_valid,
    input  logic        m_ready,
    output logic [62:0] m_dividend,
    output logic [46:0] m_divisor,
    output logic [45:0] m_aw,
    output logic [45:0] m_bw,
    output logic [ 5:0] m_common_shift,
    output logic [31:0] m_tag,
    output logic        m_zero_divisor_substitution,
    output logic        m_error,
    output logic [ 2:0] m_error_code
);
  localparam integer MULT_LATENCY = 4;
  typedef struct packed {
    logic [31:0] tag;
    logic both_zero;
    logic [2:0] error_code;
  } metadata_t;
  metadata_t input_meta, meta_pipe[0:MULT_LATENCY-1], cross_meta;
  logic ce, accept, cross_valid;
  logic [MULT_LATENCY-1:0] valid_pipe;
  logic [96:0] aw_product, bw_product, cross_aw, cross_bw;
  logic [5:0] cross_shift;
  logic [2:0] cross_error;
  assign ce = !m_valid || m_ready;
  assign s_ready = !rst && ce;
  assign accept = s_valid && s_ready;
  always_comb begin
    input_meta = '0;
    input_meta.tag = s_tag;
    input_meta.both_zero = (s_n == 0 && s_d == 0);
    if (s_n_max == 0) input_meta.error_code = 3'd1;
    else if (s_d_max == 0 || (s_n != 0 && s_d == 0)) input_meta.error_code = 3'd7;
  end
  t06_wp_mult_u64_u33 u_aw (
      .CLK (clk),
      .CE  (ce),
      .SCLR(rst),
      .A   (s_n),
      .B   (s_d_max),
      .P   (aw_product)
  );
  t06_wp_mult_u64_u33 u_bw (
      .CLK (clk),
      .CE  (ce),
      .SCLR(rst),
      .A   (s_n_max),
      .B   (s_d),
      .P   (bw_product)
  );
  function automatic logic [5:0] common_shift97(input logic [96:0] a, input logic [96:0] b);
    integer bit_index, length;
    begin
      length = 0;
      for (bit_index = 0; bit_index < 97; bit_index = bit_index + 1)
      if (a[bit_index] || b[bit_index]) length = bit_index + 1;
      common_shift97 = (length > 45) ? length - 45 : 0;
    end
  endfunction
  function automatic logic [97:0] rne97(input logic [96:0] value, input logic [5:0] shift);
    logic [96:0] quotient, remainder, mask, half_value;
    logic increment;
    begin
      quotient = value >> shift;
      mask = 0;
      half_value = 0;
      if (shift != 0) begin
        mask = (97'd1 << shift) - 97'd1;
        half_value = 97'd1 << (shift - 1);
      end
      remainder = value & mask;
      increment = (shift != 0) &&
          ((remainder > half_value) || (remainder == half_value && quotient[0]));
      rne97 = {1'b0, quotient} + {{97{1'b0}}, increment};
    end
  endfunction
  logic [97:0] aw_rounded, bw_rounded;
  logic [2:0] final_error;
  always_comb begin
    aw_rounded  = rne97(cross_aw, cross_shift);
    bw_rounded  = rne97(cross_bw, cross_shift);
    final_error = cross_error;
    if (final_error == 0 && (|aw_rounded[97:46] || |bw_rounded[97:46])) final_error = 3'd4;
    if (final_error == 0 && bw_rounded == 0) final_error = 3'd7;
  end
  integer i;
  always_ff @(posedge clk) begin
    if (rst) begin
      valid_pipe <= 0;
      cross_valid <= 0;
      m_valid <= 0;
      for (i = 0; i < MULT_LATENCY; i = i + 1) meta_pipe[i] <= '0;
      cross_meta <= '0;
      cross_aw <= 0;
      cross_bw <= 1;
      cross_shift <= 0;
      cross_error <= 0;
      m_dividend <= 0;
      m_divisor <= 1;
      m_aw <= 0;
      m_bw <= 1;
      m_common_shift <= 0;
      m_tag <= 0;
      m_zero_divisor_substitution <= 0;
      m_error <= 0;
      m_error_code <= 0;
    end else if (ce) begin
      valid_pipe   <= {valid_pipe[2:0], accept};
      meta_pipe[0] <= input_meta;
      for (i = 1; i < MULT_LATENCY; i = i + 1) meta_pipe[i] <= meta_pipe[i-1];
      cross_valid <= valid_pipe[3];
      cross_meta <= meta_pipe[3];
      cross_aw <= aw_product;
      cross_bw <= bw_product;
      cross_shift <= common_shift97(aw_product, bw_product);
      cross_error <= meta_pipe[3].error_code;
      if (meta_pipe[3].both_zero && meta_pipe[3].error_code == 0) begin
        cross_aw <= 0;
        cross_bw <= 1;
        cross_shift <= 0;
      end else if (meta_pipe[3].error_code == 0 && aw_product > bw_product) cross_error <= 3'd4;
      m_valid <= cross_valid;
      m_tag <= cross_meta.tag;
      m_error <= (final_error != 0);
      m_error_code <= final_error;
      m_zero_divisor_substitution <= cross_meta.both_zero && final_error == 0;
      m_aw <= aw_rounded[45:0];
      m_bw <= bw_rounded[45:0];
      m_common_shift <= cross_shift;
      m_dividend <= {aw_rounded[45:0], 17'b0};
      m_divisor <= {1'b0, bw_rounded[45:0]};
      if (final_error != 0) begin
        m_aw <= 0;
        m_bw <= 1;
        m_common_shift <= 0;
        m_dividend <= 0;
        m_divisor <= 1;
      end
    end
  end
endmodule
