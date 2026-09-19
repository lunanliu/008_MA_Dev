`timescale 1ns / 1ps
module sfo_initial_regression_tail (
    input  logic                clk,
    input  logic                rst,
    input  logic                s_valid,
    output logic                s_ready,
    input  logic        [ 31:0] s_frame_id,
    input  logic        [ 29:0] s_s0,
    input  logic signed [ 40:0] s_s1,
    input  logic        [ 47:0] s_s2,
    input  logic signed [ 75:0] s_t0,
    input  logic signed [ 84:0] s_t1,
    output logic                div_req_valid,
    input  logic                div_req_ready,
    output logic        [ 62:0] div_req_dividend,
    output logic        [ 46:0] div_req_divisor,
    output logic        [ 31:0] div_req_tag,
    input  logic                div_rsp_valid,
    output logic                div_rsp_ready,
    input  logic        [ 63:0] div_rsp_rne,
    input  logic        [ 31:0] div_rsp_tag,
    input  logic                div_rsp_error,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [ 31:0] m_frame_id,
    output logic signed [ 47:0] m_slope,
    output logic signed [ 31:0] m_sfo_ppm,
    output logic        [ 15:0] m_quality,
    output logic                m_error,
    output logic        [  2:0] m_error_code,
    output logic        [ 77:0] debug_d,
    output logic signed [117:0] debug_n,
    output logic        [  5:0] debug_hq,
    output logic        [  5:0] debug_hs,
    output logic        [  5:0] debug_hppm,
    output logic        [ 31:0] elapsed_cycles
);
  typedef enum logic [3:0] {
    IDLE,
    MULT_WAIT,
    DN_CHECK,
    RATIO_PACK,
    Q_SEND,
    Q_WAIT,
    S_SEND,
    S_WAIT,
    P_MULT_WAIT,
    P_CHECK,
    P_PACK,
    P_SEND,
    P_WAIT,
    HOLD_RESULT, ROUND_PRE, ROUND_ADD
  } state_t;
  state_t state;
  logic [29:0] s0;
  logic signed [40:0] s1;
  logic [47:0] s2;
  logic signed [75:0] t0;
  logic signed [84:0] t1;
  logic [3:0] wait_count;
  logic [77:0] p02_product, p02;
  logic signed [81:0] p11_product;
  logic [72:0] p0t1_lo;
  logic signed [71:0] p0t1_hi;
  logic signed [78:0] p1t0_lo, p1t0_hi;
  logic signed [115:0] p0t1_combined;
  logic signed [117:0] p1t0_combined, n_combined;
  logic signed [82:0] d_combined;
  logic products_error;
  logic [117:0] n_magnitude;
  logic [62:0] saved_slope_n, saved_quality_n;
  logic [46:0] saved_slope_d, saved_quality_d;
  logic [47:0] slope_magnitude;
  logic [67:0] ppm_product;
  logic [85:0] ppm_magnitude;
  logic signed [48:0] ppm_denominator;
  logic ppm_negative;

  t06_rt_mult_u30_u48 u_p02 (
      .CLK (clk),
      .SCLR(rst),
      .A   (s0),
      .B   (s2),
      .P   (p02_product)
  );
  t06_rt_mult_s41_s41 u_p11 (
      .CLK (clk),
      .SCLR(rst),
      .A   (s1),
      .B   (s1),
      .P   (p11_product)
  );
  t06_rt_mult_u30_u43 u_p0t1_lo (
      .CLK (clk),
      .SCLR(rst),
      .A   (s0),
      .B   (t1[42:0]),
      .P   (p0t1_lo)
  );
  t06_rt_mult_u30_s42 u_p0t1_hi (
      .CLK (clk),
      .SCLR(rst),
      .A   (s0),
      .B   (t1[84:43]),
      .P   (p0t1_hi)
  );
  t06_rt_mult_s41_u38 u_p1t0_lo (
      .CLK (clk),
      .SCLR(rst),
      .A   (s1),
      .B   (t0[37:0]),
      .P   (p1t0_lo)
  );
  t06_rt_mult_s41_s38 u_p1t0_hi (
      .CLK (clk),
      .SCLR(rst),
      .A   (s1),
      .B   (t0[75:38]),
      .P   (p1t0_hi)
  );
  t06_rt_mult_u48_u20 u_ppm (
      .CLK (clk),
      .SCLR(rst),
      .A   (slope_magnitude),
      .B   (20'd1000000),
      .P   (ppm_product)
  );
  always_comb begin
    p0t1_combined = ($signed({{44{p0t1_hi[71]}}, p0t1_hi}) <<< 43) + $signed({43'd0, p0t1_lo});
    p1t0_combined = ($signed({{39{p1t0_hi[78]}}, p1t0_hi}) <<< 38) +
        $signed({{39{p1t0_lo[78]}}, p1t0_lo});
    n_combined = $signed({{2{p0t1_combined[115]}}, p0t1_combined}) - p1t0_combined;
    d_combined = $signed({5'd0, p02_product}) - $signed({p11_product[81], p11_product});
    products_error = (|p11_product[81:78]) || (p0t1_combined[115] != p0t1_combined[114]) ||
        (p1t0_combined[117] != p1t0_combined[116]);
  end
  assign n_magnitude = debug_n[117] ? (~$unsigned(debug_n) + 118'd1) : $unsigned(debug_n);
  assign slope_magnitude = m_slope[47] ? (~$unsigned(m_slope) + 48'd1) : $unsigned(m_slope);
  function automatic integer bitlength118(input logic [117:0] value);
    integer j;
    begin
      bitlength118 = 0;
      for (j = 0; j < 118; j = j + 1) if (value[j]) bitlength118 = j + 1;
    end
  endfunction
  function automatic logic [5:0] headroom_shift(input logic [117:0] numerator,
                                                input logic [117:0] divisor);
    integer hn, hd, h;
    begin
      hn = bitlength118(numerator) - 62;
      hd = bitlength118(divisor) - 46;
      h = hn > hd ? hn : hd;
      headroom_shift = h > 0 ? h : 0;
    end
  endfunction
  function automatic logic [118:0] rne118_pre(input logic [117:0] value, input logic [5:0] shift);
    logic [117:0] q, r, half_value, mask;
    logic inc;
    begin
      q = value >> shift;
      half_value = 0;
      mask = 0;
      if (shift != 0) begin
        mask = (118'd1 << shift) - 118'd1;
        half_value = 118'd1 << (shift - 1);
      end
      r = value & mask;
      inc = (shift != 0) && ((r > half_value) || (r == half_value && q[0]));
      rne118_pre = {q, inc};
    end
  endfunction
  logic round_is_ppm;
  logic [118:0] round_pre[0:3],round_value[0:3];
  wire [118:0] qn_round=round_value[0],qd_round=round_value[1];
  wire [118:0] sn_round=round_value[2],sd_round=round_value[3];
  wire [118:0] pn_round=round_value[0],pd_round=round_value[1];
  assign s_ready = !rst && state == IDLE;
  assign m_valid = !rst && state == HOLD_RESULT;
  assign div_req_valid = !rst && (state == Q_SEND || state == S_SEND || state == P_SEND);
  assign div_rsp_ready = !rst && (state == Q_WAIT || state == S_WAIT || state == P_WAIT);
  task automatic fail_close(input logic [2:0] code);
    begin
      m_error <= 1;
      m_error_code <= code;
      m_sfo_ppm <= 0;
      m_quality <= 0;
      m_slope <= 0;
      state <= HOLD_RESULT;
    end
  endtask
  integer hquality;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;round_is_ppm<=0;
      wait_count <= 0;
      s0 <= 0;
      s1 <= 0;
      s2 <= 0;
      t0 <= 0;
      t1 <= 0;
      m_frame_id <= 0;
      m_slope <= 0;
      m_sfo_ppm <= 0;
      m_quality <= 0;
      m_error <= 0;
      m_error_code <= 0;
      debug_d <= 0;
      debug_n <= 0;
      debug_hq <= 0;
      debug_hs <= 0;
      debug_hppm <= 0;
      elapsed_cycles <= 0;
      p02 <= 0;
      saved_slope_n <= 0;
      saved_slope_d <= 1;
      saved_quality_n <= 0;
      saved_quality_d <= 1;
      ppm_magnitude <= 0;
      ppm_denominator <= 1;
      ppm_negative <= 0;
      div_req_dividend <= 0;
      div_req_divisor <= 1;
      div_req_tag <= 0;
    end else begin
      if (state != IDLE && state != HOLD_RESULT) elapsed_cycles <= elapsed_cycles + 32'd1;
      case (state)
        IDLE:
        if (s_valid && s_ready) begin
          s0 <= s_s0;
          s1 <= s_s1;
          s2 <= s_s2;
          t0 <= s_t0;
          t1 <= s_t1;
          m_frame_id <= s_frame_id;
          m_slope <= 0;
          m_sfo_ppm <= 0;
          m_quality <= 0;
          m_error <= 0;
          m_error_code <= 0;
          debug_d <= 0;
          debug_n <= 0;
          debug_hq <= 0;
          debug_hs <= 0;
          debug_hppm <= 0;
          elapsed_cycles <= 0;
          wait_count <= 0;
          state <= MULT_WAIT;
        end
        MULT_WAIT:
        if (wait_count == 5) begin
          p02 <= p02_product;
          debug_n <= n_combined;
          debug_d <= d_combined[77:0];
          if (products_error) fail_close(3'd4);
          else if (d_combined <= 0 || |d_combined[82:78]) fail_close(3'd3);
          else state <= DN_CHECK;
        end else wait_count <= wait_count + 1'b1;
        DN_CHECK: begin
          hquality = bitlength118({40'd0, p02}) - 46;
          debug_hq <= hquality > 0 ? hquality : 0;
          debug_hs <= headroom_shift(n_magnitude, {40'd0, debug_d});
          round_is_ppm<=0;state<=ROUND_PRE;
        end
        ROUND_PRE:begin
          if(round_is_ppm)begin
            round_pre[0]<=rne118_pre({32'd0,ppm_magnitude},debug_hppm);
            round_pre[1]<=rne118_pre({69'd0,$unsigned(ppm_denominator)},debug_hppm);
          end else begin
            round_pre[0]<=rne118_pre({40'd0,debug_d},debug_hq);
            round_pre[1]<=rne118_pre({40'd0,p02},debug_hq);
            round_pre[2]<=rne118_pre(n_magnitude,debug_hs);
            round_pre[3]<=rne118_pre({40'd0,debug_d},debug_hs);
          end
          state<=ROUND_ADD;
        end
        ROUND_ADD:begin
          for(integer j=0;j<4;j=j+1)
            round_value[j]<={1'b0,round_pre[j][118:1]}+{{118{1'b0}},round_pre[j][0]};
          state<=round_is_ppm?P_PACK:RATIO_PACK;
        end
        RATIO_PACK: begin
          if (|qn_round[118:47] || |qd_round[118:47] || |sn_round[118:63] || |sd_round[118:47])
            fail_close(3'd4);
          else if (qd_round == 0 || sd_round == 0) fail_close(3'd7);
          else begin
            saved_quality_n <= {1'b0, qn_round[46:0], 15'd0};
            saved_quality_d <= qd_round[46:0];
            saved_slope_n <= sn_round[62:0];
            saved_slope_d <= sd_round[46:0];
            div_req_dividend <= {1'b0, qn_round[46:0], 15'd0};
            div_req_divisor <= qd_round[46:0];
            div_req_tag <= 32'hf6000000;
            state <= Q_SEND;
          end
        end
        Q_SEND: if (div_req_ready) state <= Q_WAIT;
        Q_WAIT:
        if (div_rsp_valid) begin
          if (div_rsp_tag != 32'hf6000000) fail_close(3'd6);
          else if (div_rsp_error) fail_close(3'd7);
          else begin
            m_quality <= div_rsp_rne > 64'd32768 ? 16'd32768 : div_rsp_rne[15:0];
            div_req_dividend <= saved_slope_n;
            div_req_divisor <= saved_slope_d;
            div_req_tag <= 32'hf6000001;
            state <= S_SEND;
          end
        end
        S_SEND: if (div_req_ready) state <= S_WAIT;
        S_WAIT:
        if (div_rsp_valid) begin
          if (div_rsp_tag != 32'hf6000001) fail_close(3'd6);
          else if (div_rsp_error) fail_close(3'd7);
          else if (div_rsp_rne > (debug_n[117] ? 64'd140737488355328 : 64'd140737488355327))
            fail_close(3'd4);
          else begin
            m_slope <= debug_n[117] ? -$signed(div_rsp_rne[47:0]) : $signed(div_rsp_rne[47:0]);
            wait_count <= 0;
            state <= P_MULT_WAIT;
          end
        end
        P_MULT_WAIT:
        if (wait_count == 5) begin
          ppm_magnitude <= {ppm_product, 18'd0};
          ppm_denominator <= 49'sd87960930222080 + $signed({m_slope[47], m_slope});
          ppm_negative <= !m_slope[47] && m_slope != 0;
          state <= P_CHECK;
        end else wait_count <= wait_count + 1'b1;
        P_CHECK: begin
          if (ppm_denominator <= 0) fail_close(3'd7);
          // Exact frozen delta-S64 overflow predicate, derived from
          // q=RNE(abs(slope)*65536/5), delta=RNE(q*2^60/(2^60-q)).
          // Preserve the MATLAB error4 before ppm common reduction.
          else if (m_slope < -48'sd78187493530737) fail_close(3'd4);
          else begin
            debug_hppm <= headroom_shift(
                {32'd0, ppm_magnitude}, {69'd0, $unsigned(ppm_denominator)}
            );
            round_is_ppm<=1;state<=ROUND_PRE;
          end
        end
        P_PACK: begin
          if (|pn_round[118:63] || |pd_round[118:47]) fail_close(3'd4);
          else if (pd_round == 0) fail_close(3'd7);
          else begin
            div_req_dividend <= pn_round[62:0];
            div_req_divisor <= pd_round[46:0];
            div_req_tag <= 32'hf6000002;
            state <= P_SEND;
          end
        end
        P_SEND: if (div_req_ready) state <= P_WAIT;
        P_WAIT:
        if (div_rsp_valid) begin
          if (div_rsp_tag != 32'hf6000002) fail_close(3'd6);
          else if (div_rsp_error) fail_close(3'd7);
          else if (div_rsp_rne > (ppm_negative ? 64'd2147483648 : 64'd2147483647)) fail_close(3'd4);
          else begin
            m_sfo_ppm <= ppm_negative ? -$signed(div_rsp_rne[31:0]) : $signed(div_rsp_rne[31:0]);
            state <= HOLD_RESULT;
          end
        end
        HOLD_RESULT: if (m_ready) state <= IDLE;
        default: fail_close(3'd6);
      endcase
    end
  end
endmodule
