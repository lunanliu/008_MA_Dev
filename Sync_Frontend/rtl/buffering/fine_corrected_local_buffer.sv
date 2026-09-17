`timescale 1ns/1ps

module fine_corrected_local_buffer #(
  parameter int unsigned SAMPLE_COUNT = 2304,
  parameter int unsigned LANES = 16,
  parameter int unsigned COMPONENT_WIDTH = 18,
  parameter int unsigned READ_LATENCY = 2
) (
  input  logic clk,
  input  logic rst_n,

  input  logic write_valid,
  output logic write_ready,
  input  logic [11:0] write_index,
  input  logic signed [COMPONENT_WIDTH-1:0] write_i,
  input  logic signed [COMPONENT_WIDTH-1:0] write_q,

  output logic buffer_full,
  input  logic buffer_release,

  input  logic read_req_valid,
  output logic read_req_ready,
  input  logic [11:0] read_base_index,
  output logic read_valid,
  input  logic read_ready,
  output logic [LANES-1:0][COMPONENT_WIDTH-1:0] read_i,
  output logic [LANES-1:0][COMPONENT_WIDTH-1:0] read_q,

  output logic protocol_error_sticky,
  output logic overwrite_error_sticky,
  output logic read_error_sticky
);
  localparam int unsigned COMPLEX_WIDTH = 2*COMPONENT_WIDTH;
  localparam int unsigned ROW_WIDTH = LANES*COMPLEX_WIDTH;
  localparam int unsigned ROW_COUNT = SAMPLE_COUNT/LANES;
  localparam int unsigned ROW_ADDR_WIDTH = $clog2(ROW_COUNT);
  localparam int unsigned MAX_READ_BASE = SAMPLE_COUNT-LANES;

  logic [11:0] expected_write_index;
  logic [ROW_WIDTH-1:0] row_assembly;
  logic [ROW_WIDTH-1:0] completed_row;
  logic write_fire;
  logic row_write_enable;
  logic [ROW_ADDR_WIDTH-1:0] row_write_address;

  logic read_accept;
  logic read_address_valid;
  logic [ROW_ADDR_WIDTH-1:0] read_row_a;
  logic [ROW_ADDR_WIDTH-1:0] read_row_b;
  logic [ROW_WIDTH-1:0] row_data_a;
  logic [ROW_WIDTH-1:0] row_data_b;
  logic [READ_LATENCY-1:0] read_valid_pipe;
  logic [READ_LATENCY-1:0] read_bad_pipe;
  logic [3:0] residue_pipe [0:READ_LATENCY-1];

  initial begin
    if (SAMPLE_COUNT != 2304)
      $error("T05 corrected buffer requires 2304 samples");
    if (LANES != 16 || COMPONENT_WIDTH != 18)
      $error("T05 corrected buffer requires 16 lanes of complex signed18");
    if (ROW_COUNT != 144 || ROW_WIDTH != 576)
      $error("T05 corrected buffer row geometry must be 144x576");
    if (READ_LATENCY != 2)
      $error("T05 corrected buffer requires READ_LATENCY=2");
  end

  always_comb begin
    write_ready = !buffer_full && !buffer_release;
    write_fire = write_valid && write_ready;
    row_write_enable = write_fire &&
        (expected_write_index[3:0] == 4'd15);
    row_write_address = expected_write_index[11:4];

    completed_row = row_assembly;
    completed_row[expected_write_index[3:0]*COMPLEX_WIDTH +:
        COMPONENT_WIDTH] = write_i;
    completed_row[expected_write_index[3:0]*COMPLEX_WIDTH +
        COMPONENT_WIDTH +: COMPONENT_WIDTH] = write_q;

    // The P16 correlation loop requires one accepted 16-sample window every
    // clock.  Output backpressure is therefore a protocol error, not a reason
    // to reduce the memory initiation interval.
    read_req_ready = buffer_full && !buffer_release;
    read_accept = read_req_valid && read_req_ready;
    read_address_valid = read_base_index <= MAX_READ_BASE;
    if (read_address_valid) begin
      read_row_a = read_base_index[11:4];
      if (read_base_index[3:0] == 4'd0)
        read_row_b = read_base_index[11:4];
      else
        read_row_b = read_base_index[11:4]+1'b1;
    end else begin
      read_row_a = '0;
      read_row_b = '0;
    end
  end

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(ROW_ADDR_WIDTH),
    .ADDR_WIDTH_B(ROW_ADDR_WIDTH),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(ROW_WIDTH),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(ROW_WIDTH*ROW_COUNT),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(ROW_WIDTH),
    .READ_LATENCY_B(READ_LATENCY),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(ROW_WIDTH),
    .WRITE_MODE_B("read_first")
  ) u_corrected_copy_a (
    .dbiterrb(),.doutb(row_data_a),.sbiterrb(),
    .addra(row_write_address),.addrb(read_row_a),
    .clka(clk),.clkb(clk),.dina(completed_row),
    .ena(row_write_enable),.enb(read_accept),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.rstb(!rst_n),.sleep(1'b0),.wea(row_write_enable)
  );

  xpm_memory_sdpram #(
    .ADDR_WIDTH_A(ROW_ADDR_WIDTH),
    .ADDR_WIDTH_B(ROW_ADDR_WIDTH),
    .AUTO_SLEEP_TIME(0),
    .BYTE_WRITE_WIDTH_A(ROW_WIDTH),
    .CASCADE_HEIGHT(0),
    .CLOCKING_MODE("common_clock"),
    .ECC_MODE("no_ecc"),
    .MEMORY_INIT_FILE("none"),
    .MEMORY_INIT_PARAM("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE("block"),
    .MEMORY_SIZE(ROW_WIDTH*ROW_COUNT),
    .MESSAGE_CONTROL(0),
    .READ_DATA_WIDTH_B(ROW_WIDTH),
    .READ_LATENCY_B(READ_LATENCY),
    .READ_RESET_VALUE_B("0"),
    .RST_MODE_B("SYNC"),
    .SIM_ASSERT_CHK(1),
    .USE_EMBEDDED_CONSTRAINT(0),
    .USE_MEM_INIT(0),
    .WAKEUP_TIME("disable_sleep"),
    .WRITE_DATA_WIDTH_A(ROW_WIDTH),
    .WRITE_MODE_B("read_first")
  ) u_corrected_copy_b (
    .dbiterrb(),.doutb(row_data_b),.sbiterrb(),
    .addra(row_write_address),.addrb(read_row_b),
    .clka(clk),.clkb(clk),.dina(completed_row),
    .ena(row_write_enable),.enb(read_accept),
    .injectdbiterra(1'b0),.injectsbiterra(1'b0),
    .regceb(1'b1),.rstb(!rst_n),.sleep(1'b0),.wea(row_write_enable)
  );

  always_ff @(posedge clk) begin : control_and_splice
    int unsigned source_lane;
    if (!rst_n) begin
      expected_write_index <= '0;
      row_assembly <= '0;
      buffer_full <= 1'b0;
      read_valid_pipe <= '0;
      read_bad_pipe <= '0;
      for (int stage = 0; stage < READ_LATENCY; stage++)
        residue_pipe[stage] <= '0;
      read_valid <= 1'b0;
      read_i <= '0;
      read_q <= '0;
      protocol_error_sticky <= 1'b0;
      overwrite_error_sticky <= 1'b0;
      read_error_sticky <= 1'b0;
    end else begin
      read_valid_pipe[0] <= read_accept;
      read_bad_pipe[0] <= read_accept && !read_address_valid;
      residue_pipe[0] <= read_base_index[3:0];
      for (int stage = 1; stage < READ_LATENCY; stage++) begin
        read_valid_pipe[stage] <= read_valid_pipe[stage-1];
        read_bad_pipe[stage] <= read_bad_pipe[stage-1];
        residue_pipe[stage] <= residue_pipe[stage-1];
      end

      read_valid <= read_valid_pipe[READ_LATENCY-1];
      if (read_valid && !read_ready)
        read_error_sticky <= 1'b1;

      if (read_valid_pipe[READ_LATENCY-1]) begin
        for (int unsigned lane = 0; lane < LANES; lane++) begin
          source_lane = lane+residue_pipe[READ_LATENCY-1];
          if (read_bad_pipe[READ_LATENCY-1]) begin
            read_i[lane] <= '0;
            read_q[lane] <= '0;
          end else if (source_lane < LANES) begin
            read_i[lane] <= row_data_a[
                source_lane*COMPLEX_WIDTH +: COMPONENT_WIDTH];
            read_q[lane] <= row_data_a[
                source_lane*COMPLEX_WIDTH+COMPONENT_WIDTH +:
                COMPONENT_WIDTH];
          end else begin
            read_i[lane] <= row_data_b[
                (source_lane-LANES)*COMPLEX_WIDTH +: COMPONENT_WIDTH];
            read_q[lane] <= row_data_b[
                (source_lane-LANES)*COMPLEX_WIDTH+COMPONENT_WIDTH +:
                COMPONENT_WIDTH];
          end
        end
      end

      if (write_fire) begin
        if (write_index != expected_write_index)
          protocol_error_sticky <= 1'b1;
        if (expected_write_index[3:0] == 4'd15)
          row_assembly <= '0;
        else
          row_assembly <= completed_row;

        if (expected_write_index == SAMPLE_COUNT-1) begin
          buffer_full <= 1'b1;
        end else begin
          expected_write_index <= expected_write_index+1'b1;
        end
      end

      if (write_valid && buffer_full && !buffer_release)
        overwrite_error_sticky <= 1'b1;
      if (read_accept && !read_address_valid)
        read_error_sticky <= 1'b1;

      if (buffer_release) begin
        if (!buffer_full || read_valid || (read_valid_pipe != '0))
          protocol_error_sticky <= 1'b1;
        expected_write_index <= '0;
        row_assembly <= '0;
        buffer_full <= 1'b0;
        read_valid_pipe <= '0;
        read_bad_pipe <= '0;
        read_valid <= 1'b0;
        read_i <= '0;
        read_q <= '0;
      end
    end
  end
endmodule
