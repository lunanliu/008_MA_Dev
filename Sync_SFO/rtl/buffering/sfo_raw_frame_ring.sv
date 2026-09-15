`timescale 1ns / 1ps
// Full-frame raw context in a non-power-of-two URAM ring. Coordinates are
// absolute accepted 128-bit word ordinals since capture reset; no low-bit wrap.
module sfo_raw_frame_ring #(
    parameter integer DEPTH_BEATS = 393216,
    AW = 19,
    WINDOW_BEATS = 334215,
    RETAIN_BEATS = 256,
    FIFO_DEPTH = 64
) (
    input  logic         clk,
    input  logic         rst,
    input  logic         poison,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_data,
    input  logic         req_valid,
    output logic         req_ready,
    input  logic [ 63:0] req_first_word,
    input  logic [ 31:0] req_frame,
    input  logic [ 31:0] req_generation,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [127:0] m_data,
    output logic [ 31:0] m_frame,
    output logic [ 31:0] m_generation,
    output logic [ 31:0] m_beat,
    output logic         m_last,
    output logic         complete,
    output logic [ 63:0] written_words,
    output logic [ 63:0] retired_words,
    output logic [ 31:0] occupancy_high_water,
    output logic [ 31:0] issued,
    output logic [ 31:0] returned,
    output logic [ 31:0] consumed,
    output logic         fault,
    output logic [  7:0] first_error
);
  localparam [1:0] IDLE = 0, CHECK = 1, ADDRESS = 2, READ = 3;
  logic [1:0] state;
  logic [AW-1:0] wp, rp;
  logic [63:0] start_word, gap, read_absolute;
  logic [2:0] rv;
  wire [127:0] ram_data, qdata;
  wire qr, qv, qbusy, qerror;
  localparam integer OCW = $clog2(DEPTH_BEATS + 1);
  logic [OCW-1:0] occupancy_count;
  // Absolute counters remain for ownership checks. Fast admission uses a bounded counter.
  wire halted = poison || fault;
  wire [63:0] occupancy = 64'(occupancy_count);
  wire [31:0] outstanding = issued - consumed;
  assign s_ready = !rst && !halted && occupancy < DEPTH_BEATS;
  assign req_ready = !rst && !halted && state == IDLE && !qv && !qbusy && rv == 0;
  assign m_valid = !rst && !halted && state == READ && qv;
  assign m_data = qdata;
  assign m_beat = consumed;
  assign m_last = consumed == WINDOW_BEATS - 1;
  wire wf = s_valid && s_ready, cf = req_valid && req_ready, pop = m_valid && m_ready;
  wire issue = !rst && !halted && state == READ && issued < WINDOW_BEATS &&
      outstanding < FIFO_DEPTH && qr && !qbusy;
  wire collision = wf && issue && wp == rp;
  wire [63:0]
      retire_candidate = read_absolute + 1 >= RETAIN_BEATS ? read_absolute + 1 - RETAIN_BEATS : 0;
  localparam integer HCW = RETAIN_BEATS > 0 ? $clog2(RETAIN_BEATS + 1) : 1;
  logic [HCW-1:0] retain_countdown;
  logic [OCW-1:0] first_retire_delta;
  // CHECK proves start_word lies in the live ring, so this bounded difference is exact.
  wire [OCW-1:0] start_gap = OCW'(start_word) - OCW'(retired_words);
  wire [OCW-1:0]
      retire_delta = retain_countdown != 0 ? '0 : (issued == 0 ? first_retire_delta : OCW'(1));
  // Pipeline the complete read/write command together. The existing same-address
  // check therefore applies to the pair that reaches the RAM one cycle later.
  logic ram_wr_q, ram_rd_q;
  logic [AW-1:0] ram_wa_q, ram_ra_q;
  logic [127:0] ram_wd_q;
  logic [  7:0] bad;
  always_comb begin
    bad = 0;
    if (qerror || (rv[2] && !qr)) bad = 1;
    else if (state == CHECK &&
             (start_word < retired_words || start_word + WINDOW_BEATS > written_words ||
              start_word + WINDOW_BEATS < start_word || gap > DEPTH_BEATS))
      bad = 2;
    else if (collision) bad = 3;
    else if (occupancy > DEPTH_BEATS || consumed > returned || returned > issued ||
             outstanding > FIFO_DEPTH)
      bad = 4;
  end
  sfo_uram_frame_bank #(
      .DEPTH_BEATS(DEPTH_BEATS),
      .ADDR_WIDTH (AW)
  ) memory (
      .clk    (clk),
      .rst    (rst),
      .wr_en  (ram_wr_q),
      .wr_addr(ram_wa_q),
      .wr_data(ram_wd_q),
      .rd_en  (ram_rd_q),
      .rd_addr(ram_ra_q),
      .rd_data(ram_data)
  );
  sfo_sync_fifo #(
      .WIDTH(128),
      .DEPTH(FIFO_DEPTH)
  ) responses (
      .clk         (clk),
      .rst         (rst),
      .s_valid     (rv[2]),
      .s_ready     (qr),
      .s_data      (ram_data),
      .m_valid     (qv),
      .m_ready     (pop),
      .m_data      (qdata),
      .level       (),
      .high_water  (),
      .reset_busy  (qbusy),
      .error_sticky(qerror)
  );
  logic [AW-1:0] saved_wp;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      wp <= 0;
      rp <= 0;
      saved_wp <= 0;
      start_word <= 0;
      gap <= 0;
      read_absolute <= 0;
      written_words <= 0;
      retired_words <= 0;
      issued <= 0;
      returned <= 0;
      consumed <= 0;
      rv <= 0;
      m_frame <= 0;
      m_generation <= 0;
      fault <= 0;
      first_error <= 0;
      complete <= 0;
      occupancy_high_water <= 0;
      occupancy_count <= 0;
      retain_countdown <= 0;
      first_retire_delta <= 0;
      ram_wr_q <= 0;
      ram_rd_q <= 0;
      ram_wa_q <= 0;
      ram_ra_q <= 0;
      ram_wd_q <= 0;
    end else begin
      rv <= {rv[1:0], issue && !collision};
      complete <= 0;
      ram_wr_q <= wf && !collision;
      ram_rd_q <= issue && !collision;
      ram_wa_q <= wp;
      ram_ra_q <= rp;
      ram_wd_q <= s_data;
      if (!fault && bad != 0) begin
        fault <= 1;
        first_error <= bad;
      end
      if (occupancy > occupancy_high_water) occupancy_high_water <= occupancy[31:0];
      if (rv[2] && qr) returned <= returned + 1;
      if (!halted && bad == 0) begin
        occupancy_count <= occupancy_count + OCW'(wf) - (issue ? retire_delta : OCW'(0));
        if (wf) begin
          written_words <= written_words + 1;
          wp <= wp == DEPTH_BEATS - 1 ? 0 : wp + 1'b1;
        end
        if (cf) begin
          state <= CHECK;
          start_word <= req_first_word;
          gap <= written_words - req_first_word;
          saved_wp <= wp;
          m_frame <= req_frame;
          m_generation <= req_generation;
          issued <= 0;
          returned <= 0;
          consumed <= 0;
        end
        if (state == CHECK) begin
          retain_countdown <= start_gap < RETAIN_BEATS ? HCW'(RETAIN_BEATS - start_gap) : '0;
          first_retire_delta <= start_gap >= RETAIN_BEATS ?
              start_gap - OCW'(RETAIN_BEATS) + OCW'(1) : '0;
          rp <= saved_wp >= gap ? saved_wp - AW'(gap) : saved_wp + AW'(DEPTH_BEATS) - AW'(gap);
          read_absolute <= start_word;
          state <= ADDRESS;
        end
        if (state == ADDRESS) state <= READ;
        if (issue) begin
          issued <= issued + 1;
          rp <= rp == DEPTH_BEATS - 1 ? 0 : rp + 1'b1;
          read_absolute <= read_absolute + 1;
          if (retain_countdown != 0) retain_countdown <= retain_countdown - 1'b1;
          retired_words <= retired_words + 64'(retire_delta);
        end
        if (pop) begin
          consumed <= consumed + 1;
          if (m_last) begin
            state <= IDLE;
            complete <= 1;
          end
        end
      end
    end
  end
  // synthesis translate_off
  always @(posedge clk)
    if (!rst && !halted) begin
      if (64'(occupancy_count) != (written_words - retired_words))
        $fatal(1, "Raw registered occupancy identity");
      if (issue && 64'(retire_delta) !=
          (retire_candidate > retired_words ? retire_candidate - retired_words : 64'(0)))
        $fatal(1, "Raw retirement differs from absolute-coordinate oracle");
      if (ram_wr_q && ram_rd_q && ram_wa_q == ram_ra_q) $fatal(1, "Raw pipelined RAM collision");
    end
  initial
    if (WINDOW_BEATS >= DEPTH_BEATS || RETAIN_BEATS >= WINDOW_BEATS) $fatal(1, "Raw ring geometry");
  // synthesis translate_on
endmodule
