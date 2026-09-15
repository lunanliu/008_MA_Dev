`timescale 1ns/1ps
// Exact Rsecond * conj_safe(Rfirst), then the frozen T06 dynamic BFP.
// Official CMPY has no CE/reset. Every accepted item reserves an output-FIFO
// credit before launch; reset clears metadata and quarantines its old outputs.
module t06_pair_phasor_bfp (
    input logic clk, input logic rst,
    input logic s_valid, output logic s_ready,
    input logic [31:0] s_first_iq, input logic [31:0] s_second_iq,
    input logic [31:0] s_tag,
    output logic m_valid, input logic m_ready,
    output logic signed [32:0] m_phasor_re, output logic signed [32:0] m_phasor_im,
    output logic signed [47:0] m_bfp_re, output logic signed [47:0] m_bfp_im,
    output logic [5:0] m_shift, output logic m_zero, output logic m_error,
    output logic [31:0] m_tag,
    output logic [5:0] pending_count,
    output logic protocol_error_sticky
);
    localparam integer CMPY_LATENCY=4, FIFO_DEPTH=32;
    typedef struct packed {
        logic [31:0] tag;
        logic signed [32:0] phasor_re, phasor_im;
        logic signed [47:0] bfp_re, bfp_im;
        logic [5:0] shift;
        logic zero_phasor, range_error;
    } result_t;
    localparam integer DATA_WIDTH=$bits(result_t);
    logic [CMPY_LATENCY-1:0] metadata_valid, reset_guard;
    logic [31:0] tag_pipe[0:CMPY_LATENCY-1];
    logic signed [16:0] first_re, first_conjugate_im;
    logic [47:0] cmpy_a;
    logic [79:0] cmpy_data;
    logic cmpy_valid, accept, release_credit;
    logic fifo_full, fifo_empty, fifo_wr_busy, fifo_rd_busy;
    logic fifo_overflow, fifo_underflow, fifo_write;
    logic [5:0] fifo_wr_count, fifo_rd_count;
    result_t fifo_input, fifo_output;
    assign first_re=$signed({s_first_iq[15],s_first_iq[15:0]});
    assign first_conjugate_im=-$signed({s_first_iq[31],s_first_iq[31:16]});
    assign cmpy_a={{7{first_conjugate_im[16]}},first_conjugate_im,
                   {7{first_re[16]}},first_re};
    assign m_valid=!rst && !fifo_rd_busy && !fifo_empty;
    assign release_credit=m_valid && m_ready;
    assign s_ready=!rst && !(|reset_guard) && !fifo_wr_busy && !fifo_rd_busy &&
        !protocol_error_sticky && ((pending_count<FIFO_DEPTH) || release_credit);
    assign accept=s_valid && s_ready;
    t04_cmpy_17x16 u_cmpy (
        .aclk(clk),.s_axis_a_tvalid(accept),.s_axis_a_tdata(cmpy_a),
        .s_axis_b_tvalid(accept),.s_axis_b_tdata(s_second_iq),
        .m_axis_dout_tvalid(cmpy_valid),.m_axis_dout_tdata(cmpy_data));
    integer stage;
    always_ff @(posedge clk) begin
        if (rst) begin
            metadata_valid<='0; reset_guard<='1; pending_count<='0;
            for(stage=0;stage<CMPY_LATENCY;stage=stage+1) tag_pipe[stage]<='0;
            protocol_error_sticky<=1'b0;
        end else begin
            reset_guard<={reset_guard[CMPY_LATENCY-2:0],1'b0};
            metadata_valid<={metadata_valid[CMPY_LATENCY-2:0],accept};
            tag_pipe[0]<=s_tag;
            for(stage=1;stage<CMPY_LATENCY;stage=stage+1) tag_pipe[stage]<=tag_pipe[stage-1];
            case ({accept,release_credit})
                2'b10: pending_count<=pending_count+6'd1;
                2'b01: pending_count<=pending_count-6'd1;
                default: pending_count<=pending_count;
            endcase
            if ((!(|reset_guard) && (cmpy_valid != metadata_valid[CMPY_LATENCY-1])) ||
                fifo_overflow || fifo_underflow || (fifo_write && fifo_full))
                protocol_error_sticky<=1'b1;
        end
    end
    function automatic logic [32:0] magnitude33(input logic signed [32:0] value);
        magnitude33=value[32] ? (~$unsigned(value)+33'd1) : $unsigned(value);
    endfunction
    logic signed [33:0] wide_re,wide_im;
    logic [32:0] magnitude_re,magnitude_im,maximum_magnitude;
    integer bit_index,highest_bit;
    always_comb begin
        wide_re=$signed(cmpy_data[33:0]); wide_im=$signed(cmpy_data[73:40]);
        fifo_input='0;
        fifo_input.tag=tag_pipe[CMPY_LATENCY-1];
        fifo_input.range_error=(wide_re[33]!=wide_re[32]) || (wide_im[33]!=wide_im[32]);
        fifo_input.phasor_re=wide_re[32:0]; fifo_input.phasor_im=wide_im[32:0];
        magnitude_re=magnitude33(fifo_input.phasor_re);
        magnitude_im=magnitude33(fifo_input.phasor_im);
        maximum_magnitude=(magnitude_re>=magnitude_im) ? magnitude_re : magnitude_im;
        fifo_input.zero_phasor=(maximum_magnitude==0);
        highest_bit=0;
        for(bit_index=0;bit_index<33;bit_index=bit_index+1)
            if(maximum_magnitude[bit_index]) highest_bit=bit_index;
        if (fifo_input.zero_phasor || fifo_input.range_error) begin
            // Preserve the frozen algorithm trace (zero BFP). A future vendor
            // adapter may insert its private safe dummy and force phase code 0.
            fifo_input.bfp_re='0;
            fifo_input.bfp_im='0; fifo_input.shift='0;
        end else begin
            fifo_input.shift=6'd45-highest_bit[5:0];
            fifo_input.bfp_re=$signed({{15{wide_re[32]}},wide_re[32:0]}) <<< fifo_input.shift;
            fifo_input.bfp_im=$signed({{15{wide_im[32]}},wide_im[32:0]}) <<< fifo_input.shift;
        end
    end
    assign fifo_write=!rst && !fifo_wr_busy && metadata_valid[CMPY_LATENCY-1] && cmpy_valid;
    xpm_fifo_sync #(
        // 2021.1 XPM sleep/empty edge assertions misreport this fixed-sleep,
        // FWFT-reset use. Explicit wrapper/TB checks replace those assertions;
        // see T06_PAIR_PHASOR_BFP_XPM_ASSERTION_NOTE.md. The IP is unmodified.
        .FIFO_MEMORY_TYPE("block"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(0),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH),.WRITE_DATA_WIDTH(DATA_WIDTH),.READ_DATA_WIDTH(DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH(6),.RD_DATA_COUNT_WIDTH(6),.PROG_FULL_THRESH(24),.PROG_EMPTY_THRESH(8),
        .READ_MODE("fwft"),.FIFO_READ_LATENCY(0),.DOUT_RESET_VALUE("0"),
        .FULL_RESET_VALUE(0),.USE_ADV_FEATURES("0707"),.WAKEUP_TIME(0)
    ) u_result_fifo (
        .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(fifo_write),.din(fifo_input),
        .full(fifo_full),.prog_full(),.wr_data_count(fifo_wr_count),
        .overflow(fifo_overflow),.wr_rst_busy(fifo_wr_busy),.almost_full(),.wr_ack(),
        .rd_en(release_credit),.dout(fifo_output),.empty(fifo_empty),.prog_empty(),
        .rd_data_count(fifo_rd_count),.underflow(fifo_underflow),.rd_rst_busy(fifo_rd_busy),
        .almost_empty(),.data_valid(),.injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
    assign m_tag=fifo_output.tag;
    assign m_phasor_re=fifo_output.phasor_re; assign m_phasor_im=fifo_output.phasor_im;
    assign m_bfp_re=fifo_output.bfp_re; assign m_bfp_im=fifo_output.bfp_im;
    assign m_shift=fifo_output.shift; assign m_zero=fifo_output.zero_phasor; assign m_error=fifo_output.range_error;
`ifndef SYNTHESIS
    always @(posedge clk) begin
        if ((rst || fifo_wr_busy) && fifo_write)
            $fatal(1,"T06 pair/BFP write during reset/busy");
        if ((rst || fifo_rd_busy) && release_credit)
            $fatal(1,"T06 pair/BFP read during reset/busy");
        if (!rst) begin
        if(pending_count>FIFO_DEPTH || (release_credit && pending_count==0))
            $fatal(1,"T06 pair/BFP credit invariant failed");
        if(!(|reset_guard) && (cmpy_valid !== metadata_valid[CMPY_LATENCY-1]))
            $fatal(1,"T06 pair/BFP official CMPY latency is not four clocks");
        if(fifo_write && (fifo_full || fifo_input.range_error))
            $fatal(1,"T06 pair/BFP FIFO capacity or S34-to-S33 invariant failed");
        if(fifo_overflow || fifo_underflow || protocol_error_sticky)
            $fatal(1,"T06 pair/BFP FIFO/protocol failure");
        end
    end
`endif
endmodule
