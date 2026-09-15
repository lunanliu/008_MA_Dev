`include "t06_shared_gain_ip_config.svh"

// One sample per CE-enabled cycle. Official mult_gen/div_gen own all
// multiplications and division. This module only compares, selects and RNEs.
// ce must stop EVERY lane/IP/register together; reset must last >= 2 clocks.
module t06_shared_gain_s16_lane (
    input  logic clk,
    input  logic rst,
    input  logic ce,
    input  logic in_valid,
    input  logic signed [36:0] in_i,
    input  logic signed [36:0] in_q,
    input  logic [31:0] in_tag,
    output logic out_valid,
    output logic signed [15:0] out_i,
    output logic signed [15:0] out_q,
    output logic [31:0] out_tag,
    output logic out_scaled,
    output logic out_limiting_i,
    output logic out_s18_overflow,
    output logic out_range_error
);
    localparam integer MULT_LATENCY = `T06_SG_MULT_LATENCY;
    typedef struct packed {
        logic [36:0] magnitude_i;
        logic [36:0] magnitude_q;
        logic [31:0] tag;
        logic [15:0] bypass_i;
        logic [15:0] bypass_q;
        logic negative_i;
        logic negative_q;
        logic scaled;
        logic s18_overflow;
    } multiply_metadata_t;
    // The official divider transports this metadata using dividend TUSER.
    // No independently guessed divider-latency shift register is needed.
    typedef struct packed {
        logic [21:0] reserved;
        logic [36:0] denominator;
        logic [31:0] tag;
        logic [15:0] bypass_i;
        logic [15:0] bypass_q;
        logic negative_i;
        logic negative_q;
        logic limiting_i;
        logic scaled;
        logic s18_overflow;
    } divide_metadata_t;

    function automatic logic [36:0] magnitude37(input logic signed [36:0] value);
        magnitude37 = value[36] ? (~$unsigned(value) + 37'd1) : $unsigned(value);
    endfunction

    function automatic logic signed [20:0] provisional_rne(input logic signed [36:0] value);
        logic [36:0] magnitude;
        logic [20:0] rounded;
        logic increment;
        begin
            magnitude = magnitude37(value);
            increment = (magnitude[16:0] > 17'd65536) ||
                ((magnitude[16:0] == 17'd65536) && magnitude[17]);
            rounded = {1'b0,magnitude[36:17]} + {{20{1'b0}},increment};
            provisional_rne = value[36] ? -$signed(rounded) : $signed(rounded);
        end
    endfunction

    function automatic logic [15:0] signed_magnitude16(
        input logic [15:0] magnitude, input logic negative_value);
        logic signed [16:0] result;
        begin
            result = $signed({1'b0,magnitude});
            if (negative_value) result = -result;
            signed_magnitude16 = result[15:0];
        end
    endfunction

    logic signed [20:0] provisional_i, provisional_q;
    logic [15:0] capacity_i, capacity_q;
    multiply_metadata_t input_metadata;
    multiply_metadata_t mult_metadata [0:MULT_LATENCY-1];
    logic [MULT_LATENCY-1:0] mult_valid;
    logic [52:0] cross_i, cross_q;
    always_comb begin
        provisional_i = provisional_rne(in_i);
        provisional_q = provisional_rne(in_q);
        input_metadata = '0;
        input_metadata.magnitude_i = magnitude37(in_i);
        input_metadata.magnitude_q = magnitude37(in_q);
        input_metadata.tag = in_tag;
        input_metadata.negative_i = in_i[36];
        input_metadata.negative_q = in_q[36];
        input_metadata.s18_overflow =
            (provisional_i < -21'sd131072) || (provisional_i > 21'sd131071) ||
            (provisional_q < -21'sd131072) || (provisional_q > 21'sd131071);
        input_metadata.scaled = !input_metadata.s18_overflow &&
            ((provisional_i < -21'sd32768) || (provisional_i > 21'sd32767) ||
             (provisional_q < -21'sd32768) || (provisional_q > 21'sd32767));
        if (!input_metadata.s18_overflow && !input_metadata.scaled) begin
            input_metadata.bypass_i = provisional_i[15:0];
            input_metadata.bypass_q = provisional_q[15:0];
        end
        capacity_i = in_i[36] ? 16'd32768 : 16'd32767;
        capacity_q = in_q[36] ? 16'd32768 : 16'd32767;
    end

    // cross_i = cap(I)*abs(Q), cross_q = cap(Q)*abs(I), full U53.
    t06_sg_mult_u37_u16 u_cross_i (
        .CLK(clk), .CE(ce), .SCLR(rst),
        .A(input_metadata.magnitude_q), .B(capacity_i), .P(cross_i));
    t06_sg_mult_u37_u16 u_cross_q (
        .CLK(clk), .CE(ce), .SCLR(rst),
        .A(input_metadata.magnitude_i), .B(capacity_q), .P(cross_q));

    integer stage;
    always_ff @(posedge clk) begin
        if (rst) begin
            mult_valid <= '0;
            for (stage=0; stage<MULT_LATENCY; stage=stage+1)
                mult_metadata[stage] <= '0;
        end else if (ce) begin
            mult_valid[0] <= in_valid;
            mult_metadata[0] <= input_metadata;
            for (stage=1; stage<MULT_LATENCY; stage=stage+1) begin
                mult_valid[stage] <= mult_valid[stage-1];
                mult_metadata[stage] <= mult_metadata[stage-1];
            end
        end
    end

    logic [52:0] numerator;
    logic [36:0] denominator;
    logic limiting_i;
    divide_metadata_t div_metadata_in, div_metadata_out;
    logic [127:0] div_user_out;
    logic [95:0] div_data_out;
    logic div_valid_out;
    always_comb begin
        limiting_i = cross_i <= cross_q; // exact tie selects I
        numerator = 53'd0;
        denominator = 37'd1; // bypass/errors still traverse the same pipeline
        if (mult_metadata[MULT_LATENCY-1].scaled) begin
            numerator = limiting_i ? cross_i : cross_q;
            denominator = limiting_i ? mult_metadata[MULT_LATENCY-1].magnitude_i :
                mult_metadata[MULT_LATENCY-1].magnitude_q;
        end
        div_metadata_in = '0;
        div_metadata_in.denominator = denominator;
        div_metadata_in.tag = mult_metadata[MULT_LATENCY-1].tag;
        div_metadata_in.bypass_i = mult_metadata[MULT_LATENCY-1].bypass_i;
        div_metadata_in.bypass_q = mult_metadata[MULT_LATENCY-1].bypass_q;
        div_metadata_in.negative_i = mult_metadata[MULT_LATENCY-1].negative_i;
        div_metadata_in.negative_q = mult_metadata[MULT_LATENCY-1].negative_q;
        div_metadata_in.limiting_i = limiting_i;
        div_metadata_in.scaled = mult_metadata[MULT_LATENCY-1].scaled;
        div_metadata_in.s18_overflow = mult_metadata[MULT_LATENCY-1].s18_overflow;
        div_metadata_out = divide_metadata_t'(div_user_out);
    end
    t06_sg_div_u53_u37 u_ratio (
        .aclk(clk), .aclken(ce), .aresetn(!rst),
        .s_axis_dividend_tvalid(mult_valid[MULT_LATENCY-1]),
        .s_axis_dividend_tdata({3'b000,numerator}),
        .s_axis_dividend_tuser(div_metadata_in),
        .s_axis_divisor_tvalid(mult_valid[MULT_LATENCY-1]),
        .s_axis_divisor_tdata({3'b000,denominator}),
        .m_axis_dout_tvalid(div_valid_out),
        .m_axis_dout_tdata(div_data_out), .m_axis_dout_tuser(div_user_out));

    logic [52:0] quotient;
    logic [36:0] remainder, half_other;
    logic [53:0] rounded_magnitude;
    logic [15:0] other_capacity, result_i, result_q;
    logic increment, other_negative, arithmetic_error;
    always_comb begin
        // Generated XCI must confirm quotient [92:40], remainder [36:0],
        // zero padding [95:93]/[39:37]. Generation fails on any other layout.
        quotient = div_data_out[92:40];
        remainder = div_data_out[36:0];
        half_other = div_metadata_out.denominator - remainder;
        increment = (remainder > half_other) ||
            ((remainder == half_other) && quotient[0]);
        rounded_magnitude = {1'b0,quotient} + {{53{1'b0}},increment};
        other_negative = div_metadata_out.limiting_i ?
            div_metadata_out.negative_q : div_metadata_out.negative_i;
        other_capacity = other_negative ? 16'd32768 : 16'd32767;
        arithmetic_error = div_metadata_out.scaled &&
            ((div_metadata_out.denominator == 0) ||
             (remainder >= div_metadata_out.denominator) ||
             (rounded_magnitude > {38'd0,other_capacity}) ||
             (div_data_out[95:93] != 0) || (div_data_out[39:37] != 0));
        result_i = div_metadata_out.bypass_i;
        result_q = div_metadata_out.bypass_q;
        if (div_metadata_out.scaled) begin
            if (div_metadata_out.limiting_i) begin
                result_i = div_metadata_out.negative_i ? 16'h8000 : 16'h7fff;
                result_q = signed_magnitude16(rounded_magnitude[15:0],other_negative);
            end else begin
                result_q = div_metadata_out.negative_q ? 16'h8000 : 16'h7fff;
                result_i = signed_magnitude16(rounded_magnitude[15:0],other_negative);
            end
        end
        if (div_metadata_out.s18_overflow || arithmetic_error) begin
            result_i = '0;
            result_q = '0;
        end
    end
    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            out_i <= '0; out_q <= '0; out_tag <= '0;
            out_scaled <= 1'b0; out_limiting_i <= 1'b0;
            out_s18_overflow <= 1'b0; out_range_error <= 1'b0;
        end else if (ce) begin
            out_valid <= div_valid_out;
            out_i <= result_i; out_q <= result_q;
            out_tag <= div_metadata_out.tag;
            out_scaled <= div_metadata_out.scaled;
            out_limiting_i <= div_metadata_out.scaled && div_metadata_out.limiting_i;
            out_s18_overflow <= div_metadata_out.s18_overflow;
            out_range_error <= arithmetic_error;
        end
    end
endmodule
