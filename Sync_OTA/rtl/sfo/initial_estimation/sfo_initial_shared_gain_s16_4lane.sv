// Registered CE may consume the first reset edge; hold wrapper reset >=3 clocks.
// Production callers hold 8 or 64 clocks, covering >=2 enabled native reset edges.
// Four independent worst-case-II=1 lanes; lane 0 is the earliest sample.
// Semantic errors produce zero I/Q with explicit per-lane fault flags.
// The consumer must fail-close the affected frame, not treat zeros as data.
module sfo_initial_shared_gain_s16_4lane (
    input  logic         clk,
    input  logic         rst,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [147:0] s_i,
    input  logic [147:0] s_q,
    input  logic [ 31:0] s_tag,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [ 63:0] m_i,
    output logic [ 63:0] m_q,
    output logic [ 31:0] m_tag,
    output logic [  3:0] m_scaled,
    output logic [  3:0] m_limiting_i,
    output logic [  3:0] m_s18_overflow,
    output logic [  3:0] m_range_error
);
  logic [3:0] lane_valid;
  logic [31:0] lane_tag[0:3];
  // Two local result slots absorb a stopped consumer. All gain IPs and their
  // metadata use same-cycle registered CE replicas, never remote m_ready.
  (* keep="true" *) logic [3:0] lane_ce;
  logic [1:0] queue_count,queue_next_count;
  logic [175:0] queue_head,queue_tail;
  wire [63:0] lane_i,lane_q;
  wire [3:0] lane_scaled,lane_limiting,lane_overflow,lane_range;
  wire [175:0] lane_payload={lane_i,lane_q,lane_tag[0],lane_scaled,
                            lane_limiting,lane_overflow,lane_range};
  wire queue_push=!rst && lane_ce[0] && lane_valid[0];
  wire queue_pop=m_valid && m_ready;
  assign m_valid=!rst && queue_count!=0;
  assign s_ready=!rst && lane_ce[0];
  assign {m_i,m_q,m_tag,m_scaled,m_limiting_i,m_s18_overflow,m_range_error}=queue_head;
  always_comb begin
    queue_next_count=queue_count;
    case({queue_push,queue_pop})
      2'b10:queue_next_count=queue_count+1'b1;
      2'b01:queue_next_count=queue_count-1'b1;
      default:begin end
    endcase
  end
  always_ff @(posedge clk)begin
    // The existing lane contract requires reset >=2 clocks. CE is forced on
    // during reset so all native IP pipelines clear with their matching tags.
    if(rst)begin queue_count<=0;lane_ce<=4'b1111;end
    else begin queue_count<=queue_next_count;lane_ce<={4{queue_next_count<2}};end
    if(queue_push)begin
      if(queue_count==0 || (queue_count==1 && queue_pop))queue_head<=lane_payload;
      else queue_tail<=lane_payload;
    end
    if(queue_pop && queue_count==2)queue_head<=queue_tail;
  end
  genvar lane;
  generate
    for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
      sfo_initial_shared_gain_s16_lane u_lane (
          .clk             (clk),
          .rst             (rst),
          .ce              (lane_ce[lane]),
          .in_valid        (s_valid && s_ready),
          .in_i            (s_i[lane*37+:37]),
          .in_q            (s_q[lane*37+:37]),
          .in_tag          (s_tag),
          .out_valid       (lane_valid[lane]),
          .out_i           (lane_i[lane*16+:16]),
          .out_q           (lane_q[lane*16+:16]),
          .out_tag         (lane_tag[lane]),
          .out_scaled      (lane_scaled[lane]),
          .out_limiting_i  (lane_limiting[lane]),
          .out_s18_overflow(lane_overflow[lane]),
          .out_range_error (lane_range[lane])
      );
    end
  endgenerate
`ifndef SYNTHESIS
  always @(posedge clk)
    if (!rst) begin
      if (lane_valid !== {4{lane_valid[0]}})
        $fatal(1, "T06 shared-gain lane valid alignment failed");
      if (lane_valid[0] && ((lane_tag[1] !== lane_tag[0]) || (lane_tag[2] !== lane_tag[0]) ||
                      (lane_tag[3] !== lane_tag[0])))
        $fatal(1, "T06 shared-gain lane metadata alignment failed");
    end
`endif
endmodule
