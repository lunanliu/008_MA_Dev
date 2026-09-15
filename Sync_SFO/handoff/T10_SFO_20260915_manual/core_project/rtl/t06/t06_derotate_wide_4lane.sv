// S16 samples and S18/F17 cos/sin -> exact complex S37/F17.
// conj(conj(raw)*coefficient) avoids negating the S18 minimum sine code.
// Four unchanged official T05 CMPYs; no custom arithmetic multiplier.
module t06_derotate_wide_4lane (
    input logic clk, input logic rst,
    input logic s_valid, output logic s_ready,
    input logic [63:0] s_i, input logic [63:0] s_q,
    input logic [71:0] s_cos, input logic [71:0] s_sin,
    input logic [31:0] s_tag,
    output logic m_valid, input logic m_ready,
    output logic [147:0] m_i, output logic [147:0] m_q,
    output logic [31:0] m_tag, output logic [3:0] m_error,
    output logic [5:0] pending_count,
    output logic protocol_error_sticky
);
    localparam integer LATENCY=4, DEPTH=32;
    localparam integer FIFO_WIDTH=332;
    logic accept, release_credit, fifo_write, fifo_full, fifo_empty;
    logic fifo_wr_busy, fifo_rd_busy, fifo_overflow, fifo_underflow;
    logic [3:0] metadata_valid, reset_guard, cmpy_valid;
    logic [31:0] tag_pipe[0:LATENCY-1];
    logic [79:0] cmpy_data[0:3];
    logic [147:0] wide_i,wide_q;
    logic [3:0] wide_error;
    logic [FIFO_WIDTH-1:0] fifo_input,fifo_output;
    assign m_valid=!rst && !fifo_rd_busy && !fifo_empty;
    assign release_credit=m_valid && m_ready;
    assign s_ready=!rst && !(|reset_guard) && !fifo_wr_busy && !fifo_rd_busy &&
        !protocol_error_sticky && ((pending_count<DEPTH) || release_credit);
    assign accept=s_valid && s_ready;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin : g_lane
        wire signed [17:0] raw_re={{2{s_i[lane*16+15]}},s_i[lane*16+:16]};
        wire signed [17:0] raw_conj_im=-$signed({{2{s_q[lane*16+15]}},s_q[lane*16+:16]});
        wire signed [17:0] coefficient_re=s_cos[lane*18+:18];
        wire signed [17:0] coefficient_im=s_sin[lane*18+:18];
        // Byte-aligned complex IP ports: real bits17:0, imaginary bits41:24.
        wire [47:0] raw_data={{6{raw_conj_im[17]}},raw_conj_im,{6{raw_re[17]}},raw_re};
        wire [47:0] coefficient_data={{6{coefficient_im[17]}},coefficient_im,
                                     {6{coefficient_re[17]}},coefficient_re};
        t05_cmpy_rotate_18x18 u_rotate (
            .aclk(clk),.s_axis_a_tvalid(accept),.s_axis_a_tdata(raw_data),
            .s_axis_b_tvalid(accept),.s_axis_b_tdata(coefficient_data),
            .m_axis_dout_tvalid(cmpy_valid[lane]),.m_axis_dout_tdata(cmpy_data[lane]));
        wire signed [36:0] re_full=cmpy_data[lane][36:0];
        wire signed [36:0] im_full=cmpy_data[lane][76:40];
        // Two S16*S18 products fit signed35. This also proves S37 negation safe.
        assign wide_error[lane]=(re_full[36:34]!={3{re_full[34]}}) ||
            (im_full[36:34]!={3{im_full[34]}});
        assign wide_i[lane*37+:37]=wide_error[lane] ? 37'b0 : re_full;
        assign wide_q[lane*37+:37]=wide_error[lane] ? 37'b0 : -im_full;
    end endgenerate
    integer stage;
    always_ff @(posedge clk) begin
        if(rst) begin
            metadata_valid<='0;reset_guard<='1;pending_count<='0;protocol_error_sticky<=0;
            for(stage=0;stage<LATENCY;stage=stage+1) tag_pipe[stage]<='0;
        end else begin
            reset_guard<={reset_guard[2:0],1'b0};
            metadata_valid<={metadata_valid[2:0],accept};tag_pipe[0]<=s_tag;
            for(stage=1;stage<LATENCY;stage=stage+1) tag_pipe[stage]<=tag_pipe[stage-1];
            case({accept,release_credit})
                2'b10:pending_count<=pending_count+6'd1;
                2'b01:pending_count<=pending_count-6'd1;
                default:pending_count<=pending_count;
            endcase
            if((!(|reset_guard) && cmpy_valid!={4{metadata_valid[3]}}) ||
                fifo_overflow || fifo_underflow || (fifo_write && fifo_full))
                protocol_error_sticky<=1;
        end
    end
    assign fifo_write=!rst && !fifo_wr_busy && metadata_valid[3] && (&cmpy_valid);
    assign fifo_input={tag_pipe[3],wide_error,wide_q,wide_i};
    assign {m_tag,m_error,m_q,m_i}=fifo_output;
    // XPM 2021.1 stock SVA has WAKEUP_TIME=0 / already-empty startup issues.
    // Keep checks below plus explicit reset/busy/empty assertions in the TB.
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(0),
        .FIFO_WRITE_DEPTH(DEPTH),.WRITE_DATA_WIDTH(FIFO_WIDTH),.READ_DATA_WIDTH(FIFO_WIDTH),
        .WR_DATA_COUNT_WIDTH(6),.RD_DATA_COUNT_WIDTH(6),.PROG_FULL_THRESH(24),.PROG_EMPTY_THRESH(8),
        .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.DOUT_RESET_VALUE("0"),
        .FULL_RESET_VALUE(0),.USE_ADV_FEATURES("0707"),.WAKEUP_TIME(0)
    ) u_result_fifo (
        .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(fifo_write),.din(fifo_input),
        .full(fifo_full),.prog_full(),.wr_data_count(),.overflow(fifo_overflow),
        .wr_rst_busy(fifo_wr_busy),.almost_full(),.wr_ack(),
        .rd_en(release_credit),.dout(fifo_output),.empty(fifo_empty),.prog_empty(),
        .rd_data_count(),.underflow(fifo_underflow),.rd_rst_busy(fifo_rd_busy),
        .almost_empty(),.data_valid(),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst) begin
        if(pending_count>DEPTH || (release_credit && pending_count==0))
            $fatal(1,"T06 derotation credit invariant failed");
        if(!( |reset_guard) && cmpy_valid !== {4{metadata_valid[3]}})
            $fatal(1,"T06 derotation official CMPY latency/lane alignment mismatch");
        if(fifo_write && (fifo_full || (|wide_error)))
            $fatal(1,"T06 derotation FIFO capacity or exact wide range failure");
        if(fifo_overflow || fifo_underflow || protocol_error_sticky)
            $fatal(1,"T06 derotation FIFO/protocol failure");
    end
`endif
endmodule
