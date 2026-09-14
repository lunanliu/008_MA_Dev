`timescale 1ns/1ps
// Shared arithmetic service only: caller owns weight clamps/sign/tail policy.
module t06_unsigned_divider_service (
    input logic clk,rst,s_valid,output logic s_ready,
    input logic [62:0] s_dividend,
    input logic [46:0] s_divisor,
    input logic [31:0] s_tag,
    output logic m_valid,input logic m_ready,
    output logic [31:0] m_tag,
    output logic [62:0] m_quotient,
    output logic [46:0] m_remainder,
    output logic [63:0] m_rne,
    output logic m_divide_by_zero,m_error,
    output logic [5:0] pending_count,
    output logic protocol_error_sticky
);
    typedef struct packed {logic [31:0] tag;logic [46:0] divisor;} meta_t;
    typedef struct packed {
        logic [31:0] tag;
        logic [62:0] quotient;
        logic [46:0] remainder;
        logic [63:0] rne;
        logic divide_by_zero,error;
    } result_t;
    meta_t meta_head;
    result_t result_head,result_word;
    logic meta_full,meta_empty,meta_wr_busy,meta_rd_busy,meta_overflow,meta_underflow;
    logic result_full,result_empty,result_wr_busy,result_rd_busy,result_overflow,result_underflow;
    logic divisor_ready,dividend_ready,divider_valid;
    logic [111:0] divider_data;
    logic [0:0] divider_user;
    logic issue,consume,retire,ready_storage;
    logic [62:0] quotient;
    logic [46:0] remainder;
    logic [47:0] twice_remainder,denominator;
    logic expected_zero,flag_mismatch,container_error,increment,transaction_error;
    logic [63:0] rounded;

    assign ready_storage=!rst && !meta_wr_busy && !meta_rd_busy && !result_wr_busy && !result_rd_busy;
    assign m_valid=!rst && !result_rd_busy && !result_empty;
    assign consume=m_valid && m_ready;
    assign s_ready=ready_storage && !protocol_error_sticky && !meta_full && !result_full &&
        ((pending_count<32) || consume) && divisor_ready && dividend_ready;
    assign issue=s_valid && s_ready;
    assign retire=!rst && divider_valid && !meta_empty && !meta_rd_busy && !result_wr_busy && !result_full;
    assign {m_tag,m_quotient,m_remainder,m_rne,m_divide_by_zero,m_error}=result_head;

    t04_div_u63_u47 divider (
        .aclk(clk),.aresetn(!rst),
        .s_axis_divisor_tvalid(issue),.s_axis_divisor_tready(divisor_ready),.s_axis_divisor_tdata({1'b0,s_divisor}),
        .s_axis_dividend_tvalid(issue),.s_axis_dividend_tready(dividend_ready),.s_axis_dividend_tdata({1'b0,s_dividend}),
        .m_axis_dout_tvalid(divider_valid),.m_axis_dout_tuser(divider_user),.m_axis_dout_tdata(divider_data));
    t06_unsigned_divider_service_fifo #(.WIDTH($bits(meta_t))) metadata_fifo (
        .clk(clk),.rst(rst),.wr_en(issue),.rd_en(retire),.din({s_tag,s_divisor}),.dout(meta_head),
        .full(meta_full),.empty(meta_empty),.wr_busy(meta_wr_busy),.rd_busy(meta_rd_busy),.overflow(meta_overflow),.underflow(meta_underflow));
    t06_unsigned_divider_service_fifo #(.WIDTH($bits(result_t))) output_fifo (
        .clk(clk),.rst(rst),.wr_en(retire),.rd_en(consume),.din(result_word),.dout(result_head),
        .full(result_full),.empty(result_empty),.wr_busy(result_wr_busy),.rd_busy(result_rd_busy),.overflow(result_overflow),.underflow(result_underflow));
    assign quotient=divider_data[110:48];
    assign remainder=divider_data[46:0];
    assign twice_remainder={remainder,1'b0};
    assign denominator={1'b0,meta_head.divisor};
    assign expected_zero=meta_head.divisor==0;
    assign flag_mismatch=divider_user[0]!=expected_zero;
    // PG151 v5.1 p20: every DOUT field is sign-extended to its byte boundary,
    // even for unsigned arithmetic. Only the payload bits represent U63/U47.
    assign container_error=!expected_zero && ((divider_data[111]!=quotient[62]) ||
        (divider_data[47]!=remainder[46]) || remainder>=meta_head.divisor);
    assign increment=(twice_remainder>denominator) || (twice_remainder==denominator && quotient[0]);
    assign rounded={1'b0,quotient}+{{63{1'b0}},increment};
    assign transaction_error=expected_zero || divider_user[0] || flag_mismatch || container_error;
    always_comb begin
        result_word.tag=meta_head.tag;
        result_word.quotient=transaction_error ? 63'd0 : quotient;
        result_word.remainder=transaction_error ? 47'd0 : remainder;
        result_word.rne=transaction_error ? 64'd0 : rounded;
        result_word.divide_by_zero=expected_zero || divider_user[0];
        result_word.error=transaction_error;
    end
    always_ff @(posedge clk) begin
        if (rst) begin pending_count<=0;protocol_error_sticky<=0;end
        else begin
            case ({issue,consume})
                2'b10:pending_count<=pending_count+1'b1;
                2'b01:pending_count<=pending_count-1'b1;
                default:begin end
            endcase
            if ((ready_storage && s_valid && divisor_ready!=dividend_ready) ||
                (divider_valid && (!retire || flag_mismatch || container_error)) ||
                meta_overflow || meta_underflow || result_overflow || result_underflow ||
                pending_count>32 || (consume && pending_count==0)) protocol_error_sticky<=1'b1;
        end
    end
    // synthesis translate_off
    integer simulation_cycle=0,last_issue_cycle=-100;
    always @(posedge clk) begin
        simulation_cycle=simulation_cycle+1;
        if (rst) last_issue_cycle=-100;
        else begin
            if (issue) begin
                if (simulation_cycle-last_issue_cycle<8) $fatal(1,"DIV official issue interval below CPD8");
                last_issue_cycle=simulation_cycle;
            end
            if (divider_valid && !retire) $fatal(1,"DIV result lost metadata/credit");
            if (retire && ((divider_user[0] !== expected_zero) || container_error))
                $fatal(1,"DIV vendor flag/container/remainder mismatch tag=%0d raw=%h user=%b divisor=%h",meta_head.tag,divider_data,divider_user,meta_head.divisor);
            if (pending_count>32 || (consume && pending_count==0)) $fatal(1,"DIV final credit invariant");
        end
    end
    // synthesis translate_on
endmodule
