`timescale 1ns/1ps

module coarse_result_pair_fifo #(
  parameter int unsigned PAIR_DEPTH = 2
) (
  input  logic clk,
  input  logic rst_n,

  input  logic pair_valid,
  output logic pair_ready,
  input  bistatic_stream_pkg::bistatic_estimator_result_t start_record,
  input  bistatic_stream_pkg::bistatic_estimator_result_t cfo_record,

  output logic result_valid,
  input  logic result_ready,
  output bistatic_stream_pkg::bistatic_estimator_result_t result_record,

  output logic overflow_sticky,
  output logic [$clog2(PAIR_DEPTH+1)-1:0] queued_pairs
);
  import bistatic_stream_pkg::*;

  localparam int unsigned PTR_WIDTH =
      (PAIR_DEPTH <= 1) ? 1 : $clog2(PAIR_DEPTH);
  localparam int unsigned COUNT_WIDTH = $clog2(PAIR_DEPTH + 1);

  typedef struct packed {
    bistatic_estimator_result_t cfo;
    bistatic_estimator_result_t start;
  } result_pair_t;

  result_pair_t storage [0:PAIR_DEPTH-1];
  logic [PTR_WIDTH-1:0] write_pointer;
  logic [PTR_WIDTH-1:0] read_pointer;
  logic [COUNT_WIDTH-1:0] pair_count;
  logic emit_cfo;
  logic pop_record;
  logic pop_pair;
  logic push_pair;

  initial begin
    if (PAIR_DEPTH < 2)
      $error("PAIR_DEPTH must retain at least two complete result pairs");
  end

  function automatic logic [PTR_WIDTH-1:0] increment_pointer(
      input logic [PTR_WIDTH-1:0] pointer);
    if (pointer == PAIR_DEPTH-1)
      increment_pointer = '0;
    else
      increment_pointer = pointer + 1'b1;
  endfunction

  always_comb begin
    result_valid = (pair_count != 0);
    result_record = '0;
    if (result_valid) begin
      if (emit_cfo)
        result_record = storage[read_pointer].cfo;
      else
        result_record = storage[read_pointer].start;
    end

    pop_record = result_valid && result_ready;
    pop_pair = pop_record && emit_cfo;
    pair_ready = (pair_count < PAIR_DEPTH) || pop_pair;
    push_pair = pair_valid && pair_ready;
    queued_pairs = pair_count;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      write_pointer <= '0;
      read_pointer <= '0;
      pair_count <= '0;
      emit_cfo <= 1'b0;
      overflow_sticky <= 1'b0;
    end else begin
      if (pair_valid && !pair_ready)
        overflow_sticky <= 1'b1;

      if (push_pair) begin
        storage[write_pointer].start <= start_record;
        storage[write_pointer].cfo <= cfo_record;
        write_pointer <= increment_pointer(write_pointer);
      end

      if (pop_record) begin
        if (emit_cfo) begin
          emit_cfo <= 1'b0;
          read_pointer <= increment_pointer(read_pointer);
        end else begin
          emit_cfo <= 1'b1;
        end
      end

      case ({push_pair, pop_pair})
        2'b10: pair_count <= pair_count + 1'b1;
        2'b01: pair_count <= pair_count - 1'b1;
        default: pair_count <= pair_count;
      endcase
    end
  end
endmodule
