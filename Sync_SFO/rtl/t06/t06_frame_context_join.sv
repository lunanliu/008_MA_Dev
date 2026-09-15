`timescale 1ns/1ps
module t06_frame_context_join #(
  parameter integer WATCHDOG_CYCLES = 65024
)(
  input logic clk, input logic rst,
  input logic s_cfo_valid, output logic s_cfo_ready,
  input bistatic_stream_pkg::bistatic_estimator_result_t s_cfo,
  input logic s_fine_valid, output logic s_fine_ready,
  input bistatic_stream_pkg::bistatic_estimator_result_t s_fine,
  output logic m_valid, input logic m_ready,
  output bistatic_stream_pkg::bistatic_estimator_result_t m_result,
  output logic signed [31:0] m_coarse_cfo_hz, m_fine_start,
  output logic m_numeric_valid, m_fail_close, m_approved_outage,
  output logic m_protocol_fault,
  output logic halted,
  output logic [7:0] fault_reason,
  output logic [31:0] fault_expected_id, fault_observed_id,
  output logic [1:0] fault_source_mask,
  output logic [2:0] canceled_cfo, canceled_fine,
  output logic [1:0] cfo_occupancy, fine_occupancy,
  output logic [31:0] watchdog_age
);
  import bistatic_stream_pkg::*;
  localparam integer AGE_WIDTH = (WATCHDOG_CYCLES < 2) ? 1 : $clog2(WATCHDOG_CYCLES+1);
  bistatic_estimator_result_t cfo_fifo [0:1], fine_fifo [0:1];
  bistatic_estimator_result_t cfo_head, fine_head;
  logic cfo_rd, cfo_wr, fine_rd, fine_wr;
  logic seeded;
  logic [31:0] next_cfo, next_fine, next_join;
  logic [AGE_WIDTH-1:0] age;
  logic fault_pending;
  logic [31:0] pending_fault_id;
  logic [15:0] pending_fault_status;
  logic take_cfo, take_fine, slot_free, do_join, unmatched, partner_now;
  logic fault_now;
  logic [7:0] reason_now;
  logic [31:0] expected_now, observed_now, fault_frame_now, seed_now;
  logic [1:0] source_now;
  logic [15:0] joined_status;
  logic normal_pair, approved_pair;

  initial if (WATCHDOG_CYCLES < 1) $error("WATCHDOG_CYCLES must be >= 1");
  assign cfo_head = cfo_fifo[cfo_rd];
  assign fine_head = fine_fifo[fine_rd];
  assign watchdog_age = {{(32-AGE_WIDTH){1'b0}},age};
  assign s_cfo_ready = !rst && !halted && (cfo_occupancy < 2);
  assign s_fine_ready = !rst && !halted && (fine_occupancy < 2);
  assign take_cfo = s_cfo_valid && s_cfo_ready;
  assign take_fine = s_fine_valid && s_fine_ready;
  assign slot_free = !m_valid || m_ready;

  function automatic logic input_normal(input logic [15:0] status);
    return status[11] && (status[10:4] == 0) && (status[2:0] == 0);
  endfunction

  function automatic logic [15:0] invalid_status(input logic [15:0] c, f);
    logic [2:0] code;
    logic [15:0] flags, result;
    begin
      flags = c | f;
      if (f[2:0] != 0) code = f[2:0];
      else if (c[2:0] != 0) code = c[2:0];
      else if (flags[6] || flags[5] || flags[4]) code = 6;
      else if (flags[7]) code = 7;
      else if (flags[8]) code = 4;
      else if (flags[10]) code = 2;
      else if (flags[9]) code = 1;
      else code = 6;
      result = 16'h4010; // kind4 non-approved pair/handoff error, NOT T05 bit4 rewriting
      result[10] = flags[10] || (code == 2);
      result[9] = flags[9] || (code == 1) || (code == 3);
      result[8] = flags[8] || (code == 4) || (code == 5);
      result[7] = flags[7] || (code == 7);
      result[6] = flags[6];
      result[5] = flags[5] || ((code == 6) && !flags[6]);
      result[2:0] = code;
      return result;
    end
  endfunction

  always_comb begin
    seed_now = take_cfo ? s_cfo.frame_id : s_fine.frame_id;
    fault_frame_now = seeded ? next_join : seed_now;
    fault_now = 0; reason_now = 0; expected_now = 0; observed_now = 0; source_now = 0;
    if (take_cfo && s_cfo.status[15:12] != 2) begin
      fault_now=1; reason_now=1; expected_now=seeded ? next_cfo : seed_now;
      observed_now=s_cfo.frame_id; source_now=1;
    end else if (take_fine && s_fine.status[15:12] != 3) begin
      fault_now=1; reason_now=1; expected_now=seeded ? next_fine : seed_now;
      observed_now=s_fine.frame_id; source_now=2;
    end else if (!seeded && take_cfo && take_fine && s_cfo.frame_id != s_fine.frame_id) begin
      fault_now=1; reason_now=4; expected_now=seed_now; observed_now=s_fine.frame_id; source_now=2;
    end else if (seeded && take_cfo && s_cfo.frame_id != next_cfo) begin
      fault_now=1; reason_now=(s_cfo.frame_id == (next_cfo-32'd1)) ? 2 : 3;
      expected_now=next_cfo; observed_now=s_cfo.frame_id; source_now=1;
    end else if (seeded && take_fine && s_fine.frame_id != next_fine) begin
      fault_now=1; reason_now=(s_fine.frame_id == (next_fine-32'd1)) ? 2 : 3;
      expected_now=next_fine; observed_now=s_fine.frame_id; source_now=2;
    end else if (!halted && cfo_occupancy != 0 && fine_occupancy != 0 &&
                 (cfo_head.frame_id != next_join || fine_head.frame_id != next_join)) begin
      fault_now=1; reason_now=6; expected_now=next_join;
      observed_now=(cfo_head.frame_id != next_join) ? cfo_head.frame_id : fine_head.frame_id;
      source_now=3;
    end
    unmatched = (cfo_occupancy != 0) != (fine_occupancy != 0);
    partner_now = ((cfo_occupancy != 0) && take_fine) || ((fine_occupancy != 0) && take_cfo);
    if (!halted && !fault_now && unmatched && !partner_now && age == WATCHDOG_CYCLES-1) begin
      fault_now=1; reason_now=5; expected_now=next_join; observed_now=next_join;
      source_now=(cfo_occupancy == 0) ? 1 : 2;
    end
    do_join = !halted && !fault_now && slot_free && (cfo_occupancy != 0) && (fine_occupancy != 0);
    normal_pair = input_normal(cfo_head.status) && input_normal(fine_head.status);
    approved_pair = (cfo_head.status == 16'h2400) && (fine_head.status == 16'h3402);
    joined_status = normal_pair ? 16'h4800 : (approved_pair ? 16'h4402 : invalid_status(cfo_head.status,fine_head.status));
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      cfo_rd<=0; cfo_wr<=0; fine_rd<=0; fine_wr<=0;
      cfo_occupancy<=0; fine_occupancy<=0; seeded<=0;
      next_cfo<=0; next_fine<=0; next_join<=0; age<=0;
      m_valid<=0; m_result<='0; m_coarse_cfo_hz<=0; m_fine_start<=0;
      m_numeric_valid<=0; m_fail_close<=0; m_approved_outage<=0; m_protocol_fault<=0;
      halted<=0; fault_reason<=0; fault_expected_id<=0; fault_observed_id<=0;
      fault_source_mask<=0; canceled_cfo<=0; canceled_fine<=0;
      fault_pending<=0; pending_fault_id<=0; pending_fault_status<=0;
    end else begin
      if (m_valid && m_ready) m_valid<=0;
      if (fault_pending && slot_free) begin
        m_valid<=1; m_result<={32'd0,16'd0,pending_fault_status,pending_fault_id};
        m_coarse_cfo_hz<=0; m_fine_start<=0;
        m_numeric_valid<=0; m_fail_close<=1; m_approved_outage<=0; m_protocol_fault<=1;
        fault_pending<=0;
      end
      if (!halted) begin
        if (fault_now) begin
          halted<=1; fault_pending<=1; pending_fault_id<=fault_frame_now;
          pending_fault_status<=(reason_now == 5) ? 16'h4056 : 16'h4036;
          fault_reason<=reason_now; fault_expected_id<=expected_now;
          fault_observed_id<=observed_now; fault_source_mask<=source_now;
          canceled_cfo<={1'b0,cfo_occupancy}+{2'b0,take_cfo};
          canceled_fine<={1'b0,fine_occupancy}+{2'b0,take_fine};
          cfo_occupancy<=0; fine_occupancy<=0; cfo_rd<=0; cfo_wr<=0; fine_rd<=0; fine_wr<=0;
          age<=0;
        end else begin
          if (unmatched && !partner_now) age<=age+1'b1; else age<=0;
          if (!seeded && (take_cfo || take_fine)) begin
            seeded<=1; next_join<=seed_now;
            next_cfo<=seed_now+{31'd0,take_cfo};
            next_fine<=seed_now+{31'd0,take_fine};
          end else begin
            if (take_cfo) next_cfo<=next_cfo+32'd1;
            if (take_fine) next_fine<=next_fine+32'd1;
          end
          if (take_cfo) begin cfo_fifo[cfo_wr]<=s_cfo; cfo_wr<=!cfo_wr; end
          if (take_fine) begin fine_fifo[fine_wr]<=s_fine; fine_wr<=!fine_wr; end
          case ({take_cfo,do_join})
            2'b10:cfo_occupancy<=cfo_occupancy+1'b1;
            2'b01:cfo_occupancy<=cfo_occupancy-1'b1;
            default: ;
          endcase
          case ({take_fine,do_join})
            2'b10:fine_occupancy<=fine_occupancy+1'b1;
            2'b01:fine_occupancy<=fine_occupancy-1'b1;
            default: ;
          endcase
          if (do_join) begin
            cfo_rd<=!cfo_rd; fine_rd<=!fine_rd; next_join<=next_join+32'd1;
            m_valid<=1; m_result<={32'd0,16'd0,joined_status,next_join};
            m_coarse_cfo_hz<=normal_pair ? cfo_head.value : 32'sd0;
            m_fine_start<=normal_pair ? fine_head.value : 32'sd0;
            m_numeric_valid<=normal_pair; m_fail_close<=!normal_pair; m_approved_outage<=approved_pair; m_protocol_fault<=0;
          end
        end
      end
    end
  end
endmodule
