// Four independent worst-case-II=1 lanes; lane 0 is the earliest sample.
// Semantic errors produce zero I/Q with explicit per-lane fault flags.
// The consumer must fail-close the affected frame, not treat zeros as data.
module t06_shared_gain_s16_4lane (
    input logic clk,
    input logic rst,
    input logic s_valid,
    output logic s_ready,
    input logic [147:0] s_i,
    input logic [147:0] s_q,
    input logic [31:0] s_tag,
    output logic m_valid,
    input logic m_ready,
    output logic [63:0] m_i,
    output logic [63:0] m_q,
    output logic [31:0] m_tag,
    output logic [3:0] m_scaled,
    output logic [3:0] m_limiting_i,
    output logic [3:0] m_s18_overflow,
    output logic [3:0] m_range_error
);
    logic [3:0] lane_valid;
    logic [31:0] lane_tag [0:3];
    logic global_ce;
    assign m_valid = lane_valid[0] && !rst;
    assign global_ce = rst || !m_valid || m_ready;
    assign s_ready = !rst && global_ce;
    assign m_tag = lane_tag[0];
    genvar lane;
    generate for (lane=0; lane<4; lane=lane+1) begin : g_lane
        t06_shared_gain_s16_lane u_lane (
            .clk(clk), .rst(rst), .ce(global_ce),
            .in_valid(s_valid && s_ready),
            .in_i(s_i[lane*37 +: 37]), .in_q(s_q[lane*37 +: 37]),
            .in_tag(s_tag), .out_valid(lane_valid[lane]),
            .out_i(m_i[lane*16 +: 16]), .out_q(m_q[lane*16 +: 16]),
            .out_tag(lane_tag[lane]), .out_scaled(m_scaled[lane]),
            .out_limiting_i(m_limiting_i[lane]),
            .out_s18_overflow(m_s18_overflow[lane]),
            .out_range_error(m_range_error[lane]));
    end endgenerate
`ifndef SYNTHESIS
    always @(posedge clk) if (!rst) begin
        if (lane_valid !== {4{lane_valid[0]}})
            $fatal(1,"T06 shared-gain lane valid alignment failed");
        if (m_valid && ((lane_tag[1] !== lane_tag[0]) ||
            (lane_tag[2] !== lane_tag[0]) || (lane_tag[3] !== lane_tag[0])))
            $fatal(1,"T06 shared-gain lane metadata alignment failed");
    end
`endif
endmodule
