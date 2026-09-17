`timescale 1ns/1ps

module sync_coarse_pair_join (
  input  logic clk,
  input  logic rst_n,

  input  logic coarse_result_valid,
  output logic coarse_result_ready,
  input  bistatic_stream_pkg::bistatic_estimator_result_t coarse_result,

  output logic job_valid,
  input  logic job_ready,
  output logic [31:0] job_frame_id,
  output logic signed [31:0] job_coarse_start,
  output logic signed [31:0] job_coarse_cfo_hz,
  output logic job_handoff_valid,
  output logic [15:0] job_error_status,
  output logic pair_protocol_error_sticky
);
  import bistatic_stream_pkg::*;

  typedef enum logic [1:0] {
    WAIT_START,
    WAIT_CFO,
    HOLD_JOB
  } state_t;

  state_t state;
  bistatic_estimator_result_t start_record;
  logic [31:0] held_frame_id;
  logic signed [31:0] held_start;
  logic signed [31:0] held_cfo;
  logic held_handoff_valid;
  logic [15:0] held_error_status;

  logic [3:0] incoming_kind;
  logic incoming_status_valid;
  logic start_status_valid;
  logic incoming_status_ambiguity;
  logic start_status_ambiguity;
  logic incoming_start_kind;
  logic incoming_cfo_kind;

  assign incoming_kind = coarse_result.status[15:12];
  assign incoming_start_kind = incoming_kind == 4'h1;
  assign incoming_cfo_kind = incoming_kind == 4'h2;
  assign incoming_status_valid = coarse_result.status[11] &&
      !(|coarse_result.status[10:4]);
  assign start_status_valid = start_record.status[11] &&
      !(|start_record.status[10:4]);
  // T04 acquisition outage is a legitimate fail-close handoff, not a bus
  // protocol error.  Both public records use valid=0, ambiguity=1 and leave
  // every lower status bit clear.
  assign incoming_status_ambiguity = !coarse_result.status[11] &&
      coarse_result.status[10] && !(|coarse_result.status[9:0]);
  assign start_status_ambiguity = !start_record.status[11] &&
      start_record.status[10] && !(|start_record.status[9:0]);

  assign coarse_result_ready = state != HOLD_JOB;
  assign job_valid = state == HOLD_JOB;
  assign job_frame_id = held_frame_id;
  assign job_coarse_start = held_start;
  assign job_coarse_cfo_hz = held_cfo;
  assign job_handoff_valid = held_handoff_valid;
  assign job_error_status = held_error_status;

  always_ff @(posedge clk) begin
    logic record_fire;
    logic pair_identity_valid;
    logic pair_status_valid;
    logic pair_status_ambiguity;
    if (!rst_n) begin
      state <= WAIT_START;
      start_record <= '0;
      held_frame_id <= '0;
      held_start <= '0;
      held_cfo <= '0;
      held_handoff_valid <= 1'b0;
      held_error_status <= '0;
      pair_protocol_error_sticky <= 1'b0;
    end else begin
      record_fire = coarse_result_valid && coarse_result_ready;
      pair_identity_valid = 1'b0;
      pair_status_valid = 1'b0;
      pair_status_ambiguity = 1'b0;

      if (state == HOLD_JOB && job_ready)
        state <= WAIT_START;

      if (record_fire) begin
        unique case (state)
          WAIT_START: begin
            if (incoming_start_kind) begin
              start_record <= coarse_result;
              state <= WAIT_CFO;
            end else begin
              held_frame_id <= coarse_result.frame_id;
              held_start <= '0;
              held_cfo <= '0;
              held_handoff_valid <= 1'b0;
              held_error_status <= 16'h0010;
              pair_protocol_error_sticky <= 1'b1;
              state <= HOLD_JOB;
            end
          end

          WAIT_CFO: begin
            pair_identity_valid = incoming_cfo_kind &&
                (coarse_result.frame_id == start_record.frame_id);
            pair_status_valid = start_status_valid &&
                incoming_status_valid;
            pair_status_ambiguity = start_status_ambiguity &&
                incoming_status_ambiguity;
            held_frame_id <= start_record.frame_id;
            held_start <= pair_identity_valid && pair_status_valid ?
                start_record.value : 32'sd0;
            held_cfo <= pair_identity_valid && pair_status_valid ?
                coarse_result.value : 32'sd0;
            held_handoff_valid <= pair_identity_valid && pair_status_valid;
            held_error_status <= '0;
            if (!pair_identity_valid) begin
              held_error_status[4] <= 1'b1;
              pair_protocol_error_sticky <= 1'b1;
            end else if (pair_status_ambiguity) begin
              held_error_status[10] <= 1'b1;
            end else if (!pair_status_valid) begin
              held_error_status[5] <= 1'b1;
            end
            state <= HOLD_JOB;
          end

          default: begin
            pair_protocol_error_sticky <= 1'b1;
          end
        endcase
      end
    end
  end
endmodule
