`timescale 1ns / 1ps
// One R1 bank: committed sparse T09 reads, then authorized destructive sequential read.
// A replacement writer stays strictly behind issued sequential reads. RAM responses
// are already reserved in a separate FIFO before any address can be reclaimed.
module sfo_intermediate_frame_bank #(
    parameter integer PROGRESSIVE_READ = 0,
    parameter integer FRAME_BEATS = 334098,
    DEPTH_BEATS = 335872,
    AW = 19,
    FIFO_DEPTH = 64
) (
    input  logic                        clk,
    input  logic                        rst,
    input  logic                        poison,
    input  logic                        s_valid,
    output logic                        s_ready,
    input  logic [               127:0] s_data,
    input  logic [                31:0] s_frame,
    input  logic [                31:0] s_generation,
    input  logic [                31:0] s_beat,
    input  logic                        s_last,
    input  logic                        publish_valid,
    output logic                        publish_ready,
    input  logic [                31:0] publish_frame,
    input  logic [                31:0] publish_generation,
    input  logic                        estimate_valid,
    output logic                        estimate_ready,
    input  logic [                31:0] estimate_frame,
    input  logic [                31:0] estimate_generation,
    input  logic                        estimate_good,
    output logic                        source_valid,
    output logic [31:0]                  source_frame,source_generation,
    output logic [18:0]                  source_written_exclusive,
    output logic                        committed,
    output logic [                31:0] committed_frame,
    output logic [                31:0] committed_generation,
    input  logic                        req_valid,
    output logic                        req_ready,
    input  logic                        req_sequential,
    input  logic [                31:0] req_frame,
    input  logic [                31:0] req_generation,
    input  logic [                31:0] req_base,
    input  logic [                31:0] req_count,
    output logic                        m_valid,
    input  logic                        m_ready,
    output logic [               127:0] m_data,
    output logic [                31:0] m_frame,
    output logic [                31:0] m_generation,
    output logic [                31:0] m_beat,
    output logic [                31:0] m_address,
    output logic                        m_last,
    output logic                        m_sequential,
    output logic                        read_done,
    output logic                        write_done,
    output logic [                31:0] issued,
    output logic [                31:0] returned,
    output logic [                31:0] consumed,
    output logic [                31:0] write_stalls,
    output logic [                31:0] read_stalls,
    output logic [                31:0] outstanding_high_water,
    output logic [$clog2(FIFO_DEPTH):0] fifo_high_water,
    output logic                        fault,
    output logic [                 7:0] first_error
);
  logic writing, filled, estimate_seen, reading;
  logic [31:0] write_frame, write_gen, write_next, read_base, read_count;
  logic [  1:0] rv;
  wire  [127:0] ram_data;
  wire qready, qvalid, qbusy, qerror;
  wire [127:0] qdata;
  wire [31:0] outstanding = issued - consumed;
  wire halted = poison || fault;
  wire seq_active = reading && m_sequential;
  wire safe_frontier = !seq_active || write_next < issued;
  wire completely_free=!source_valid&&!filled&&!committed&&!reading&&!qvalid&&!qbusy&&rv==0;
  wire writer_allowed = writing || (PROGRESSIVE_READ?completely_free:(!filled && !committed));
  assign s_ready = !rst && !halted && writer_allowed && safe_frontier;
  wire wf = s_valid && s_ready;
  wire write_ok = s_beat == write_next && s_beat < FRAME_BEATS &&
      s_last == (s_beat == FRAME_BEATS - 1) &&
      (!writing || (s_frame == write_frame && s_generation == write_gen));
  assign publish_ready = !rst && !halted && filled;
  assign estimate_ready = !rst && !halted && committed && !estimate_seen;
  assign req_ready = !rst && !halted && !reading && !qvalid && !qbusy && rv == 0;
  assign m_valid = !rst && !halted && reading && qvalid;
  assign m_data = qdata;
  assign m_beat = consumed;
  assign m_address = read_base + consumed;
  assign m_last = consumed == read_count - 1;
  wire pop = m_valid && m_ready;
  wire issue = !rst && !halted && reading && issued < read_count && outstanding < FIFO_DEPTH &&
      qready && !qbusy;
  wire [AW-1:0] ra = AW'(read_base + issued), wa = AW'(write_next);
  wire collision = wf && write_ok && issue && wa == ra;
  wire pf = publish_valid && publish_ready, ef = estimate_valid && estimate_ready,
      cf = req_valid && req_ready;
  logic [7:0] bad;
  always_comb begin
    bad = 0;
    if (qerror || (rv[1] && !qready)) bad = 1;
    else if (wf && !write_ok) bad = 2;
    else if (pf && (publish_frame != write_frame || publish_generation != write_gen)) bad = 3;
    else if (ef && (!estimate_good || estimate_frame != committed_frame ||
                    estimate_generation != committed_generation))
      bad = 4;
    else if (cf && (req_count==0||req_base>=FRAME_BEATS||
                    {1'b0,req_base}+{1'b0,req_count}>FRAME_BEATS ||
       ((req_sequential||!PROGRESSIVE_READ) ?
        (!committed||req_frame!=committed_frame||req_generation!=committed_generation||
         (req_sequential?(!estimate_seen||req_base!=0||req_count!=FRAME_BEATS):
          (req_count!=512||req_base<9||req_base+512>FRAME_BEATS-9))) :
        (!source_valid||req_frame!=source_frame||req_generation!=source_generation||
         req_count!=512||req_base<9||{1'b0,req_base}+{1'b0,req_count}>{14'd0,source_written_exclusive}))))
      bad=5;
    else if (collision) bad = 6;
    else if (outstanding > FIFO_DEPTH || consumed > returned || returned > issued) bad = 7;
  end
  sfo_uram_frame_bank #(
      .DEPTH_BEATS(DEPTH_BEATS),
      .ADDR_WIDTH (AW)
  ) memory (
      .clk    (clk),
      .rst    (rst),
      .wr_en  (wf && write_ok && !collision),
      .wr_addr(wa),
      .wr_data(s_data),
      .rd_en  (issue && !collision),
      .rd_addr(ra),
      .rd_data(ram_data)
  );
  sfo_sync_fifo #(
      .WIDTH(128),
      .DEPTH(FIFO_DEPTH)
  ) responses (
      .clk         (clk),
      .rst         (rst),
      .s_valid     (rv[1]),
      .s_ready     (qready),
      .s_data      (ram_data),
      .m_valid     (qvalid),
      .m_ready     (pop),
      .m_data      (qdata),
      .level       (),
      .high_water  (fifo_high_water),
      .reset_busy  (qbusy),
      .error_sticky(qerror)
  );
  always_ff @(posedge clk) begin
    if (rst) begin
      source_valid<=0;source_frame<=0;source_generation<=0;source_written_exclusive<=0;
      writing <= 0;
      filled <= 0;
      estimate_seen <= 0;
      reading <= 0;
      write_frame <= 0;
      write_gen <= 0;
      write_next <= 0;
      committed <= 0;
      committed_frame <= 0;
      committed_generation <= 0;
      m_frame <= 0;
      m_generation <= 0;
      m_sequential <= 0;
      read_base <= 0;
      read_count <= 0;
      rv <= 0;
      issued <= 0;
      returned <= 0;
      consumed <= 0;
      fault <= 0;
      first_error <= 0;
      read_done <= 0;
      write_done <= 0;
      write_stalls <= 0;
      read_stalls <= 0;
      outstanding_high_water <= 0;
    end else begin
      rv <= {rv[0], issue && !collision};
      read_done <= 0;
      write_done <= 0;
      if (!fault && bad != 0) begin
        fault <= 1;
        first_error <= bad;
      end
      if (s_valid && !s_ready && !halted) write_stalls <= write_stalls + 1;
      if (m_valid && !m_ready) read_stalls <= read_stalls + 1;
      if (outstanding > outstanding_high_water) outstanding_high_water <= outstanding;
      if (rv[1] && qready) returned <= returned + 1;
      if (!halted && bad == 0) begin
        if (wf) begin
          source_valid<=1;source_frame<=s_frame;source_generation<=s_generation;
          source_written_exclusive<=19'(s_beat+1);
          if (!writing) begin
            write_frame <= s_frame;
            write_gen   <= s_generation;
          end
          if (s_last) begin
            writing <= 0;
            filled <= 1;
            write_next <= 0;
            write_done <= 1;
          end else begin
            writing <= 1;
            write_next <= write_next + 1;
          end
        end
        if (pf) begin
          committed <= 1;
          committed_frame <= publish_frame;
          committed_generation <= publish_generation;
          filled <= 0;
          estimate_seen <= 0;
        end
        if (ef) estimate_seen <= 1;
        if (cf) begin
          reading <= 1;
          m_frame <= req_frame;
          m_generation <= req_generation;
          m_sequential <= req_sequential;
          read_base <= req_base;
          read_count <= req_count;
          issued <= 0;
          returned <= 0;
          consumed <= 0;
          if (req_sequential) begin
            committed <= 0;
            estimate_seen <= 0;
          end
        end
        if (issue) issued <= issued + 1;
        if (pop) begin
          consumed <= consumed + 1;
          if (m_last) begin
            reading   <= 0;
            read_done <= 1;
            if(m_sequential&&PROGRESSIVE_READ)begin source_valid<=0;source_written_exclusive<=0;end
          end
        end
      end
    end
  end
  // synthesis translate_off
  initial if (FRAME_BEATS > DEPTH_BEATS || FRAME_BEATS < 530) $fatal(1, "R1 geometry");
  always @(posedge clk)
    if (!rst && !halted) begin
      if (wf && seq_active && write_next >= issued) $fatal(1, "Overwrite beyond read frontier");
      if (issue && seq_active && read_base != 0) $fatal(1, "Sequential ownership origin");
    end
  // synthesis translate_on
endmodule
