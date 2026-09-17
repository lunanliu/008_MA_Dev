`timescale 1ns/1ps

module fine_energy_prefix_buffer #(
  parameter int unsigned SAMPLE_COUNT = 2304,
  parameter int unsigned PREFIX_DEPTH = 2305,
  parameter int unsigned PREFIX_WIDTH = 46,
  parameter int unsigned FIFO_DEPTH = 32,
  parameter int unsigned READ_LATENCY = 2
) (
  input  logic clk,
  input  logic rst_n,

  input  logic build_start,
  input  logic sample_valid,
  input  logic signed [17:0] sample_i,
  input  logic signed [17:0] sample_q,
  input  logic [11:0] sample_index,
  input  logic sample_first,
  input  logic sample_last,

  output logic square_i_req_valid,
  output logic signed [17:0] square_i_req_operand,
  input  logic square_i_rsp_valid,
  input  logic [35:0] square_i_rsp_value,
  output logic square_q_req_valid,
  output logic signed [17:0] square_q_req_operand,
  input  logic square_q_rsp_valid,
  input  logic [35:0] square_q_rsp_value,

  output logic build_done,
  input  logic read_req_valid,
  output logic read_req_ready,
  input  logic [8:0] read_candidate_offset,
  output logic segment_valid,
  input  logic segment_ready,
  output logic [8:0] segment_candidate_offset,
  output logic [PREFIX_WIDTH-1:0] segment_energy,

  output logic protocol_error_sticky,
  output logic prefix_overflow_sticky
);
  localparam int unsigned ADDRESS_WIDTH = 12;
  localparam int unsigned FIFO_ADDRESS_WIDTH = $clog2(FIFO_DEPTH);
  localparam int unsigned FIFO_COUNT_WIDTH = $clog2(FIFO_DEPTH+1);
  localparam int unsigned PREFIX_MEMORY_BITS = 106030;

  logic build_accepting;
  logic [11:0] expected_input_index;
  logic [FIFO_ADDRESS_WIDTH-1:0] fifo_write_pointer;
  logic [FIFO_ADDRESS_WIDTH-1:0] fifo_read_pointer;
  logic [FIFO_COUNT_WIDTH-1:0] fifo_count;
  logic [11:0] tag_index_memory [0:FIFO_DEPTH-1];
  logic tag_final_memory [0:FIFO_DEPTH-1];
  logic sample_fire;
  logic response_pair_valid;
  logic response_fire;
  logic [11:0] response_sample_index;
  logic response_sample_final;
  logic [36:0] sample_energy;
  logic [46:0] prefix_sum_extended;
  logic [PREFIX_WIDTH-1:0] prefix_accumulator;

  logic prefix_write_enable;
  logic [ADDRESS_WIDTH-1:0] prefix_write_address;
  logic [PREFIX_WIDTH-1:0] prefix_write_data;
  logic [ADDRESS_WIDTH-1:0] prefix_a_read_address;
  logic [ADDRESS_WIDTH-1:0] prefix_b_read_address;
  logic [PREFIX_WIDTH-1:0] prefix_a_read_data;
  logic [PREFIX_WIDTH-1:0] prefix_b_read_data;

  logic read_fire;
  logic read_outstanding;
  logic [READ_LATENCY-1:0] read_valid_pipe;
  logic [8:0] pending_candidate_offset;

  initial begin
    if (SAMPLE_COUNT != 2304 || PREFIX_DEPTH != 2305 || PREFIX_WIDTH != 46)
      $error("T05 energy prefix frozen dimensions were changed");
    if (FIFO_DEPTH < 2)
      $error("T05 energy prefix FIFO_DEPTH must be at least two");
    if (READ_LATENCY != 2)
      $error("T05 energy prefix READ_LATENCY must remain two");
  end

  always_comb begin
    sample_fire = sample_valid && build_accepting;
    square_i_req_valid = sample_fire;
    square_q_req_valid = sample_fire;
    square_i_req_operand = sample_i;
    square_q_req_operand = sample_q;

    response_pair_valid = square_i_rsp_valid && square_q_rsp_valid;
    response_fire = response_pair_valid && (fifo_count != 0);
    response_sample_index = tag_index_memory[fifo_read_pointer];
    response_sample_final = tag_final_memory[fifo_read_pointer];
    sample_energy = {1'b0,square_i_rsp_value}+{1'b0,square_q_rsp_value};
    prefix_sum_extended = {1'b0,prefix_accumulator}+
        {{10{1'b0}},sample_energy};

    prefix_write_enable = build_start || response_fire;
    if (build_start) begin
      prefix_write_address = '0;
      prefix_write_data = '0;
    end else begin
      prefix_write_address = response_sample_index+1'b1;
      prefix_write_data = prefix_sum_extended[PREFIX_WIDTH-1:0];
    end

    read_req_ready = build_done && !read_outstanding &&
        (!segment_valid || segment_ready);
    read_fire = read_req_valid && read_req_ready;
    prefix_a_read_address = {{3{1'b0}},read_candidate_offset};
    prefix_b_read_address = 12'd2048+read_candidate_offset;
  end

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(ADDRESS_WIDTH),
    .ADDR_WIDTH_B(ADDRESS_WIDTH),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(PREFIX_WIDTH),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(PREFIX_MEMORY_BITS),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(PREFIX_WIDTH),
    .READ_LATENCY_B(READ_LATENCY),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(PREFIX_WIDTH),
    .WRITE_MODE_B("read_first")
  ) u_prefix_copy_a (
    .dbiterrb(),.doutb(prefix_a_read_data),.sbiterrb(),
    .addra(prefix_write_address),.addrb(prefix_a_read_address),
    .clka(clk),.clkb(clk),.dina(prefix_write_data),
    .ena(prefix_write_enable),.enb(read_fire),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.rstb(!rst_n),.sleep(1'b0),.wea(prefix_write_enable)
  );

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(ADDRESS_WIDTH),
    .ADDR_WIDTH_B(ADDRESS_WIDTH),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(PREFIX_WIDTH),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(PREFIX_MEMORY_BITS),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(PREFIX_WIDTH),
    .READ_LATENCY_B(READ_LATENCY),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(PREFIX_WIDTH),
    .WRITE_MODE_B("read_first")
  ) u_prefix_copy_b (
    .dbiterrb(),.doutb(prefix_b_read_data),.sbiterrb(),
    .addra(prefix_write_address),.addrb(prefix_b_read_address),
    .clka(clk),.clkb(clk),.dina(prefix_write_data),
    .ena(prefix_write_enable),.enb(read_fire),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.rstb(!rst_n),.sleep(1'b0),.wea(prefix_write_enable)
  );

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      build_accepting <= 1'b0;
      expected_input_index <= '0;
      fifo_write_pointer <= '0;
      fifo_read_pointer <= '0;
      fifo_count <= '0;
      prefix_accumulator <= '0;
      build_done <= 1'b0;
      read_outstanding <= 1'b0;
      read_valid_pipe <= '0;
      pending_candidate_offset <= '0;
      segment_valid <= 1'b0;
      segment_candidate_offset <= '0;
      segment_energy <= '0;
      protocol_error_sticky <= 1'b0;
      prefix_overflow_sticky <= 1'b0;
    end else begin
      read_valid_pipe[0] <= read_fire;
      for (int stage=1;stage<READ_LATENCY;stage++)
        read_valid_pipe[stage] <= read_valid_pipe[stage-1];

      if (segment_valid && segment_ready)
        segment_valid <= 1'b0;

      if (read_fire) begin
        read_outstanding <= 1'b1;
        pending_candidate_offset <= read_candidate_offset;
        if (read_candidate_offset > 9'd256)
          protocol_error_sticky <= 1'b1;
      end

      if (read_valid_pipe[READ_LATENCY-1]) begin
        segment_valid <= 1'b1;
        segment_candidate_offset <= pending_candidate_offset;
        segment_energy <= prefix_b_read_data-prefix_a_read_data;
        read_outstanding <= 1'b0;
      end

      if (build_start) begin
        if (build_accepting || fifo_count != 0)
          protocol_error_sticky <= 1'b1;
        build_accepting <= 1'b1;
        expected_input_index <= '0;
        fifo_write_pointer <= '0;
        fifo_read_pointer <= '0;
        fifo_count <= '0;
        prefix_accumulator <= '0;
        build_done <= 1'b0;
        read_outstanding <= 1'b0;
        read_valid_pipe <= '0;
        segment_valid <= 1'b0;
      end else begin
        if (sample_valid && !build_accepting)
          protocol_error_sticky <= 1'b1;
        if (square_i_rsp_valid != square_q_rsp_valid)
          protocol_error_sticky <= 1'b1;
        if (response_pair_valid && fifo_count == 0)
          protocol_error_sticky <= 1'b1;

        if (sample_fire) begin
          if (fifo_count == FIFO_DEPTH)
            protocol_error_sticky <= 1'b1;
          else begin
            tag_index_memory[fifo_write_pointer] <= sample_index;
            tag_final_memory[fifo_write_pointer] <=
                (sample_index == SAMPLE_COUNT-1);
            if (fifo_write_pointer == FIFO_DEPTH-1)
              fifo_write_pointer <= '0;
            else
              fifo_write_pointer <= fifo_write_pointer+1'b1;
          end

          if (sample_index != expected_input_index ||
              sample_first != (sample_index == 0) ||
              sample_last != (sample_index == SAMPLE_COUNT-1))
            protocol_error_sticky <= 1'b1;
          expected_input_index <= expected_input_index+1'b1;
          if (sample_index == SAMPLE_COUNT-1)
            build_accepting <= 1'b0;
        end

        if (response_fire) begin
          prefix_accumulator <= prefix_sum_extended[PREFIX_WIDTH-1:0];
          if (prefix_sum_extended[46])
            prefix_overflow_sticky <= 1'b1;
          if (fifo_read_pointer == FIFO_DEPTH-1)
            fifo_read_pointer <= '0;
          else
            fifo_read_pointer <= fifo_read_pointer+1'b1;
          if (response_sample_final)
            build_done <= 1'b1;
        end

        case ({sample_fire && (fifo_count != FIFO_DEPTH),response_fire})
          2'b10: fifo_count <= fifo_count+1'b1;
          2'b01: fifo_count <= fifo_count-1'b1;
          default: fifo_count <= fifo_count;
        endcase
      end
    end
  end
endmodule
