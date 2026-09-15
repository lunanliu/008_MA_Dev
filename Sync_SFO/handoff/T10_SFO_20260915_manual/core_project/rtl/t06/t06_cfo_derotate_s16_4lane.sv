// Native arbitrary phase DDS -> exact S37 derotation -> shared-gain S16.
// Raw samples follow a real-transaction FIFO, never a guessed DDS delay.
module t06_cfo_derotate_s16_4lane (
    input logic clk, input logic rst,
    input logic s_valid, output logic s_ready,
    input logic [127:0] s_phase,
    input logic [63:0] s_i, input logic [63:0] s_q,
    input logic [31:0] s_tag,
    output logic m_valid, input logic m_ready,
    output logic [63:0] m_i, output logic [63:0] m_q,
    output logic [31:0] m_tag,
    output logic [3:0] m_scaled, m_limiting_i, m_s18_overflow, m_range_error,
    output logic [5:0] raw_pending_count,
    output logic protocol_error_sticky
);
    localparam integer RAW_DEPTH=32;
    logic dds_s_valid,dds_s_ready,dds_valid,dds_ready,dds_error;
    logic [71:0] dds_cos,dds_sin;
    logic [31:0] dds_tag;
    logic raw_push,raw_pop,raw_full,raw_empty,raw_wr_busy,raw_rd_busy;
    logic raw_overflow,raw_underflow,raw_available,tag_match;
    logic [159:0] raw_head;
    logic join_valid,join_ready;
    logic wide_valid,wide_ready,wide_protocol_error;
    logic [147:0] wide_i,wide_q;
    logic [31:0] wide_tag;
    logic [3:0] wide_error;
    logic [5:0] wide_pending;
    logic gain_valid;
    assign raw_available=!rst && !raw_wr_busy && !raw_rd_busy && !raw_full && raw_pending_count<RAW_DEPTH;
    assign dds_s_valid=s_valid && raw_available && !protocol_error_sticky;
    assign s_ready=dds_s_ready && raw_available && !protocol_error_sticky;
    assign raw_push=s_valid && s_ready;
    assign tag_match=(dds_tag==raw_head[159:128]);
    assign join_valid=dds_valid && !raw_empty && !raw_rd_busy && tag_match && !protocol_error_sticky;
    assign dds_ready=join_ready && !raw_empty && !raw_rd_busy && tag_match && !protocol_error_sticky;
    assign raw_pop=join_valid && join_ready;
    t06_dds_phase_4lane u_dds (
        .clk(clk),.rst_n(!rst),.s_valid(dds_s_valid),.s_ready(dds_s_ready),
        .s_phase(s_phase),.s_tag(s_tag),.m_valid(dds_valid),.m_ready(dds_ready),
        .m_cosine(dds_cos),.m_sine(dds_sin),.m_tag(dds_tag),.protocol_error_sticky(dds_error));
    t06_derotate_wide_4lane u_rotate (
        .clk(clk),.rst(rst),.s_valid(join_valid),.s_ready(join_ready),
        .s_i(raw_head[63:0]),.s_q(raw_head[127:64]),.s_cos(dds_cos),.s_sin(dds_sin),.s_tag(dds_tag),
        .m_valid(wide_valid),.m_ready(wide_ready),.m_i(wide_i),.m_q(wide_q),
        .m_tag(wide_tag),.m_error(wide_error),.pending_count(wide_pending),
        .protocol_error_sticky(wide_protocol_error));
    t06_shared_gain_s16_4lane u_gain (
        .clk(clk),.rst(rst),.s_valid(wide_valid && !protocol_error_sticky),.s_ready(wide_ready),
        .s_i(wide_i),.s_q(wide_q),.s_tag(wide_tag),
        .m_valid(gain_valid),.m_ready(m_ready && !protocol_error_sticky),
        .m_i(m_i),.m_q(m_q),.m_tag(m_tag),.m_scaled(m_scaled),.m_limiting_i(m_limiting_i),
        .m_s18_overflow(m_s18_overflow),.m_range_error(m_range_error));
    assign m_valid=gain_valid && !rst && !protocol_error_sticky;
    always_ff @(posedge clk) begin
        if(rst) begin raw_pending_count<='0;protocol_error_sticky<=1'b0;end
        else begin
            case({raw_push,raw_pop})
                2'b10:raw_pending_count<=raw_pending_count+1'b1;
                2'b01:raw_pending_count<=raw_pending_count-1'b1;
                default:raw_pending_count<=raw_pending_count;
            endcase
            if(dds_error || wide_protocol_error || raw_overflow || raw_underflow ||
                (dds_valid && !raw_empty && !raw_rd_busy && !tag_match) ||
                (raw_pop && raw_pending_count==0) || (raw_push && raw_pending_count>=RAW_DEPTH) ||
                (wide_valid && (|wide_error))) protocol_error_sticky<=1'b1;
        end
    end
    // Same locally verified 2021.1 XPM reset/busy contract as the wide unit.
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(0),
        .FIFO_WRITE_DEPTH(RAW_DEPTH),.WRITE_DATA_WIDTH(160),.READ_DATA_WIDTH(160),
        .WR_DATA_COUNT_WIDTH(6),.RD_DATA_COUNT_WIDTH(6),.PROG_FULL_THRESH(24),.PROG_EMPTY_THRESH(8),
        .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.DOUT_RESET_VALUE("0"),
        .FULL_RESET_VALUE(0),.USE_ADV_FEATURES("0707"),.WAKEUP_TIME(0)
    ) u_raw_fifo (
        .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(raw_push),.din({s_tag,s_q,s_i}),
        .full(raw_full),.prog_full(),.wr_data_count(),.overflow(raw_overflow),
        .wr_rst_busy(raw_wr_busy),.almost_full(),.wr_ack(),
        .rd_en(raw_pop),.dout(raw_head),.empty(raw_empty),.prog_empty(),
        .rd_data_count(),.underflow(raw_underflow),.rd_rst_busy(raw_rd_busy),
        .almost_empty(),.data_valid(),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
endmodule
