// 74 signed Q16 delays -> exact integer least-squares SFO and Q28 resampling step.
// One configured frame. Local idle timeout measures consecutive COLLECT silence.
module sfo_residual_ls74 #(
    parameter integer ALLOW_SOURCE_WAIT=0,
    parameter integer IDLE_TIMEOUT_CYCLES = 20000
) (
    input  logic               clk,
    input  logic               rst,
    input  logic               abort,
    input wire source_wait,
    input  logic               cfg_valid,
    output logic               cfg_ready,
    input  logic        [31:0] cfg_tag,
    input  logic               s_valid,
    output logic               s_ready,
    input  logic        [31:0] s_tag,
    input  logic        [ 6:0] s_index,
    input  logic signed [23:0] s_delay_q16,
    input  logic               s_quality_valid,
    input  logic        [ 3:0] s_error,
    output logic               m_valid,
    input  logic               m_ready,
    output logic        [31:0] m_tag,
    output logic        [ 6:0] m_count,
    output logic        [ 3:0] m_error,
    output logic        [ 3:0] m_upstream_error,
    output logic signed [31:0] m_ppm_q18,
    output logic        [31:0] m_step_q28,
    output logic        [ 4:0] m_quality_flags,
    output logic               m_estimate_valid,
    output logic               busy
);
  localparam [4:0] IDLE = 0, COLLECT = 1, ACCUM = 2, SQUARE_SD = 3, SCALE_SD = 4, SCALE_SWD = 5,
      SUB_SD = 6, SUB_SWD = 7, PREP_PPM = 8, SET_PPM = 9, PPM_REQ = 10, PPM_WAIT = 11,
      PREP_STEP = 12, STEP_REQ = 13, STEP_WAIT = 14, DONE = 15,
      MUL_ITERATE = 16, SQUARE_SWD = 17, SCALE_SD2 = 18;
  localparam [48:0] BETA_DENOMINATOR = 49'd158603411456000;
  localparam [99:0] SSE_LIMIT = 100'd198517092830412800;
  logic [ 4:0] state;
  logic [31:0] idle_count;
  logic signed [23:0] point_delay, previous_delay;
  logic point_quality, all_quality, first_ok, jump_ok, rmse_ok, negative_ppm;
  logic [24:0] max_jump;
  logic [47:0] point_square;
  logic signed [32:0] point_weighted;
  logic signed [39:0] sum_delay, sum_weighted;
  logic [53:0] sum_square;
  wire signed [8:0] weight = $signed({2'b00, m_count}) * 9'sd2 - 9'sd73;
  wire signed [40:0] next_sum_delay = $signed(
      {sum_delay[39], sum_delay}
  ) + $signed(
      {{17{point_delay[23]}}, point_delay}
  );
  wire signed [40:0] next_sum_weighted = $signed(
      {sum_weighted[39], sum_weighted}
  ) + $signed(
      {{8{point_weighted[32]}}, point_weighted}
  );
  wire [54:0] next_sum_square = {1'b0, sum_square} + {7'd0, point_square};
  wire signed [24:0] adjacent_difference = $signed(
      {point_delay[23], point_delay}
  ) - $signed(
      {previous_delay[23], previous_delay}
  );
  wire [24:0]
      adjacent_magnitude = adjacent_difference[24] ? -adjacent_difference : adjacent_difference;
  wire [23:0] first_magnitude = point_delay[23] ? -point_delay : point_delay;
  wire [39:0] abs_sd = sum_delay[39] ? -sum_delay : sum_delay;
  wire [39:0] abs_swd = sum_weighted[39] ? -sum_weighted : sum_weighted;
  // Tail-only exact multiplier: one local carry chain per clock.
  // Operands and absolute values are registered before any iteration.
  localparam [2:0] MUL_SQUARE_SD=0, MUL_TERM_SD=1, MUL_SQUARE_SWD=2,
      MUL_TERM_SWD=3, MUL_TERM_SD2=4, MUL_PPM=5;
  logic [2:0] mul_kind;
  logic [5:0] mul_remaining;
  logic [40:0] mul_factor;
  logic [97:0] mul_shift, mul_accumulator;
  wire [97:0] mul_sum = mul_accumulator + (mul_factor[0] ? mul_shift : 98'd0);
  logic [79:0] wide_square;
  logic [97:0] term_sd, term_swd, term_sd2;
  logic signed [99:0] sse_partial, sse_numerator;
  wire signed [40:0] beta_numerator = $signed({sum_weighted, 1'b0});
  wire [40:0] abs_beta = beta_numerator[40] ? -beta_numerator : beta_numerator;
  logic [60:0] ppm_product;
  logic signed [49:0] denominator_calc;
  logic [79:0] numerator;
  logic [48:0] denominator;
  logic div_ready, div_valid, div_zero, div_busy;
  logic [79:0] div_quotient;
  logic [48:0] div_remainder;
  logic [80:0] div_rne;
  logic [31:0] div_tag;
  wire [31:0] abs_ppm = m_ppm_q18[31] ? -m_ppm_q18 : m_ppm_q18;
  wire signed [33:0] step_candidate = m_ppm_q18[31] ? 34'sd268435456 - $signed(
      {2'b00, div_rne[31:0]}
  ) : 34'sd268435456 + $signed(
      {2'b00, div_rne[31:0]}
  );
  wire timeout_now = idle_count >= IDLE_TIMEOUT_CYCLES - 1;
  wire div_request = (state == PPM_REQ || state == STEP_REQ) && !abort;
  wire div_response = (state == PPM_WAIT || state == STEP_WAIT) && div_valid && !abort;
  assign cfg_ready = !rst && !abort && state == IDLE;
  assign s_ready = !rst && !abort && state == COLLECT && !timeout_now;
  assign m_valid = !rst && state == DONE;
  assign busy = state != IDLE;
  sfo_residual_div_u80_u49_rne divider (
      .clk             (clk),
      .rst             (rst || abort || state == IDLE || state == DONE),
      .s_valid         (div_request),
      .s_ready         (div_ready),
      .s_numerator     (numerator),
      .s_denominator   (denominator),
      .s_tag           (m_tag),
      .m_valid         (div_valid),
      .m_ready         ((state == PPM_WAIT || state == STEP_WAIT) && !abort),
      .m_quotient      (div_quotient),
      .m_remainder     (div_remainder),
      .m_rne           (div_rne),
      .m_tag           (div_tag),
      .m_divide_by_zero(div_zero),
      .busy            (div_busy)
  );
  task automatic fail_frame(input logic [3:0] code);
    begin
      m_error <= code;
      m_ppm_q18 <= 0;
      m_step_q28 <= 32'd268435456;
      m_quality_flags <= 0;
      m_estimate_valid <= 0;
      state <= DONE;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      idle_count <= 0;
      m_tag <= 0;
      m_count <= 0;
      m_error <= 0;
      m_upstream_error <= 0;
      m_ppm_q18 <= 0;
      m_step_q28 <= 32'd268435456;
      m_quality_flags <= 0;
      m_estimate_valid <= 0;
      point_delay <= 0;
      previous_delay <= 0;
      point_quality <= 0;
      all_quality <= 1;
      first_ok <= 1;
      jump_ok <= 1;
      rmse_ok <= 0;
      negative_ppm <= 0;
      max_jump <= 0;
      point_square <= 0;
      point_weighted <= 0;
      sum_delay <= 0;
      sum_weighted <= 0;
      sum_square <= 0;
      wide_square <= 0;
      mul_kind <= 0; mul_remaining <= 0; mul_factor <= 0;
      mul_shift <= 0; mul_accumulator <= 0;
      term_sd <= 0;
      term_swd <= 0;
      term_sd2 <= 0;
      sse_partial <= 0;
      sse_numerator <= 0;
      ppm_product <= 0;
      denominator_calc <= 0;
      numerator <= 0;
      denominator <= 0;
    end else if (state == DONE) begin
      if (m_ready) state <= IDLE;
    end else if (state == IDLE) begin
      if (cfg_valid && cfg_ready) begin
        m_tag <= cfg_tag;
        m_count <= 0;
        m_error <= 0;
        m_upstream_error <= 0;
        m_ppm_q18 <= 0;
        m_step_q28 <= 32'd268435456;
        m_quality_flags <= 0;
        m_estimate_valid <= 0;
        idle_count <= 0;
        sum_delay <= 0;
        sum_weighted <= 0;
        sum_square <= 0;
        all_quality <= 1;
        first_ok <= 1;
        jump_ok <= 1;
        rmse_ok <= 0;
        max_jump <= 0;
        previous_delay <= 0;
        sse_partial <= 0;
        sse_numerator <= 0;
        state <= COLLECT;
      end
    end else if (abort) fail_frame(4);
    else
      case (state)
        COLLECT: begin
          if (timeout_now) fail_frame(5);
          else if (s_valid && s_ready) begin
            m_count <= m_count + 1;
            idle_count <= 0;
            if (s_tag != m_tag) fail_frame(2);
            else if (s_index != m_count) fail_frame(1);
            else if (s_error != 0) begin
              m_upstream_error <= s_error;
              fail_frame(3);
            end else begin
              point_delay <= s_delay_q16;
              point_quality <= s_quality_valid;
              point_square <= $signed(s_delay_q16) * $signed(s_delay_q16);
              point_weighted <= weight * $signed(s_delay_q16);
              state <= ACCUM;
            end
          end else if(!ALLOW_SOURCE_WAIT||!source_wait) idle_count <= idle_count + 1;
        end
        ACCUM: begin
          if (next_sum_delay[40] != next_sum_delay[39] ||
              next_sum_weighted[40] != next_sum_weighted[39] || next_sum_square[54])
            fail_frame(6);
          else begin
            sum_delay <= next_sum_delay[39:0];
            sum_weighted <= next_sum_weighted[39:0];
            sum_square <= next_sum_square[53:0];
            all_quality <= all_quality && point_quality;
            if (m_count == 1) first_ok <= first_magnitude <= 24'd262144;
            else begin
              jump_ok <= jump_ok && adjacent_magnitude <= 25'd65536;
              if (adjacent_magnitude > max_jump) max_jump <= adjacent_magnitude;
            end
            previous_delay <= point_delay;
            idle_count <= 0;
            state <= (m_count == 74) ? SQUARE_SD : COLLECT;
          end
        end
        SQUARE_SD: begin
          mul_factor <= {1'b0,abs_sd}; mul_shift <= {58'd0,abs_sd};
          mul_accumulator <= 0; mul_remaining <= 40; mul_kind <= MUL_SQUARE_SD;
          state <= MUL_ITERATE;
        end
        SCALE_SD: begin
          mul_factor <= 41'd135050; mul_shift <= {18'd0,wide_square};
          mul_accumulator <= 0; mul_remaining <= 18; mul_kind <= MUL_TERM_SD;
          state <= MUL_ITERATE;
        end
        SQUARE_SWD: begin
          mul_factor <= {1'b0,abs_swd}; mul_shift <= {58'd0,abs_swd};
          mul_accumulator <= 0; mul_remaining <= 40; mul_kind <= MUL_SQUARE_SWD;
          state <= MUL_ITERATE;
        end
        SCALE_SWD: begin
          mul_factor <= 41'd74; mul_shift <= {18'd0,wide_square};
          mul_accumulator <= 0; mul_remaining <= 7; mul_kind <= MUL_TERM_SWD;
          state <= MUL_ITERATE;
        end
        SCALE_SD2: begin
          mul_factor <= 41'd9993700; mul_shift <= {44'd0,sum_square};
          mul_accumulator <= 0; mul_remaining <= 24; mul_kind <= MUL_TERM_SD2;
          state <= MUL_ITERATE;
        end
        MUL_ITERATE: begin
          mul_accumulator <= mul_sum; mul_factor <= mul_factor >> 1;
          mul_shift <= mul_shift << 1; mul_remaining <= mul_remaining - 1'b1;
          if (mul_remaining == 1) begin
            case (mul_kind)
              MUL_SQUARE_SD: begin wide_square <= mul_sum[79:0]; state <= SCALE_SD; end
              MUL_TERM_SD: begin term_sd <= mul_sum; state <= SQUARE_SWD; end
              MUL_SQUARE_SWD: begin wide_square <= mul_sum[79:0]; state <= SCALE_SWD; end
              MUL_TERM_SWD: begin term_swd <= mul_sum; state <= SCALE_SD2; end
              MUL_TERM_SD2: begin term_sd2 <= mul_sum; state <= SUB_SD; end
              MUL_PPM: begin ppm_product <= mul_sum[60:0]; state <= SET_PPM; end
              default: fail_frame(6);
            endcase
          end
        end
        SUB_SD: begin
          sse_partial <= $signed({2'b00, term_sd2}) - $signed({2'b00, term_sd});
          state <= SUB_SWD;
        end
        SUB_SWD: begin
          sse_numerator <= sse_partial - $signed({2'b00, term_swd});
          state <= PREP_PPM;
        end
        PREP_PPM: begin
          if (sse_numerator < 0) fail_frame(6);
          else begin
            rmse_ok <= sse_numerator <= $signed(SSE_LIMIT);
            negative_ppm <= beta_numerator[40];
            mul_factor <= 41'd1000000; mul_shift <= {57'd0,abs_beta};
            mul_accumulator <= 0; mul_remaining <= 20; mul_kind <= MUL_PPM;
            denominator_calc <= $signed(
                {1'b0, BETA_DENOMINATOR}
            ) - $signed(
                {{9{beta_numerator[40]}}, beta_numerator}
            );
            state <= MUL_ITERATE;
          end
        end
        SET_PPM: begin
          if (denominator_calc <= 0 || denominator_calc[49]) fail_frame(6);
          else begin
            numerator <= {1'b0, ppm_product, 18'd0};
            denominator <= denominator_calc[48:0];
            state <= PPM_REQ;
          end
        end
        PPM_REQ:  if (div_ready) state <= PPM_WAIT;
        PPM_WAIT:
        if (div_valid) begin
          if (div_zero || div_tag != m_tag ||
              (negative_ppm ? div_rne > 81'd2147483648 : div_rne > 81'd2147483647))
            fail_frame(6);
          else begin
            m_ppm_q18 <= negative_ppm ? -$signed(div_rne[31:0]) : $signed(div_rne[31:0]);
            state <= PREP_STEP;
          end
        end
        PREP_STEP: begin
          numerator <= {44'd0, abs_ppm, 4'd0};
          denominator <= 49'd15625;
          state <= STEP_REQ;
        end
        STEP_REQ: if (div_ready) state <= STEP_WAIT;
        STEP_WAIT:
        if (div_valid) begin
          if (div_zero || div_tag != m_tag || div_rne > 81'd4294967295 || step_candidate < 1 ||
              step_candidate > 34'sd4294967295)
            fail_frame(6);
          else begin
            m_step_q28 <= step_candidate[31:0];
            m_quality_flags <= {all_quality, first_ok, jump_ok, rmse_ok, 1'b1};
            m_estimate_valid <= all_quality && first_ok && jump_ok && rmse_ok;
            state <= DONE;
          end
        end
        default:  fail_frame(6);
      endcase
  end
endmodule
