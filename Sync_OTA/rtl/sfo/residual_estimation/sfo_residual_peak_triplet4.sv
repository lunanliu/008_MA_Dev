// One-window exact power cache and peak/neighbour/competitor extraction.
// Search order is signed offset -48..48, including earliest-offset tie breaking.
// Competitor is the maximum over all 2048 bins outside circular distance <=8.
module sfo_residual_peak_triplet4 #(
    parameter integer TIMEOUT_CYCLES = 20000
) (
    input  logic                clk,
    input  logic                rst,
    input  logic                abort,
    input  logic                cfg_valid,
    output logic                cfg_ready,
    input  logic        [  6:0] cfg_symbol_slot,
    input  logic        [ 31:0] cfg_tag,
    input  logic                s_valid,
    output logic                s_ready,
    input  logic        [127:0] s_data,
    input  logic        [  6:0] s_symbol_slot,
    input  logic        [  8:0] s_beat,
    input  logic        [ 31:0] s_tag,
    input  logic                s_last,
    output logic                m_valid,
    input  logic                m_ready,
    output logic        [  3:0] m_error,
    output logic        [  6:0] m_symbol_slot,
    output logic        [ 31:0] m_tag,
    output logic        [  9:0] m_input_count,
    output logic        [  9:0] m_power_count,
    output logic        [ 10:0] m_peak_bin,
    output logic signed [ 11:0] m_peak_offset,
    output logic                m_search_interior,
    output logic        [ 31:0] m_prev_power,
    output logic        [ 31:0] m_peak_power,
    output logic        [ 31:0] m_next_power,
    output logic        [ 31:0] m_competing_power,
    output logic                busy
);
  localparam [2:0] IDLE=0,FILL=1,SCAN=2,DONE=3,PEAK_DRAIN=4,SCAN_DRAIN=5;
  logic [2:0] state;
  logic [31:0] age;
  logic [9:0] issued_count;
  logic raw_valid;
  logic [8:0] raw_beat;
  logic [31:0] raw0, raw1, raw2, raw3;
  (* ram_style="block" *) logic [31:0] bank0[0:511], bank1[0:511], bank2[0:511], bank3[0:511];
  logic p_valid, p_ready, p_busy;
  logic [127:0] p_power;
  logic [41:0] p_meta;
  wire timing_active = (state==FILL || state==SCAN || state==PEAK_DRAIN || state==SCAN_DRAIN);
  wire timeout_now = timing_active && age >= TIMEOUT_CYCLES - 1;
  wire field_bad = (s_symbol_slot != m_symbol_slot || s_tag != m_tag ||
                    s_beat != m_input_count[8:0]);
  wire last_bad = (s_last != (m_input_count == 511));
  wire accepted = s_valid && s_ready;
  wire input_bad_accept = accepted && (field_bad || last_bad);
  wire p_meta_bad = p_meta != {m_tag, m_power_count[8:0], (m_power_count == 511)};
  wire write_fire = !rst && !abort && !timeout_now && state == FILL && !input_bad_accept &&
      p_valid && !p_meta_bad;
  wire [10:0] prev_bin = m_peak_bin - 11'd1, next_bin = m_peak_bin + 11'd1;
  logic [10:0] scan_index,distance_bin;
  logic [31:0] previous_next,following_next,scan_value;
  logic [42:0] peak_lane[0:3],peak_pair0,peak_pair1,peak_beat;
  logic [31:0] competitor_lane[0:3],competitor_pair0,competitor_pair1,competitor_beat;
  logic peak_pair_valid,peak_beat_valid,peak_pair_last,peak_beat_last;
  logic competitor_pair_valid,competitor_beat_valid,competitor_pair_last,competitor_beat_last;
  function automatic [42:0] better_peak(input logic [42:0] a,b);
    if(a[42:11]>b[42:11] || (a[42:11]==b[42:11] && $signed(a[10:0])<$signed(b[10:0])))
      better_peak=a;
    else better_peak=b;
  endfunction
  function automatic [31:0] max_power(input logic [31:0] a,b);
    max_power=a>b?a:b;
  endfunction
  function automatic signed [11:0] offset_of(input logic [10:0] bin);
    offset_of = bin[10] ? $signed({1'b0, bin}) - 12'sd2048 : $signed({1'b0, bin});
  endfunction
  assign m_peak_offset = offset_of(m_peak_bin);
  assign m_search_interior = (m_peak_offset > -12'sd48 && m_peak_offset < 12'sd48);
  assign cfg_ready = !rst && !abort && state == IDLE;
  assign s_ready = !rst && !abort && !timeout_now && state == FILL && m_input_count < 512;
  assign m_valid = !rst && state == DONE;
  assign busy = state != IDLE;
  sfo_residual_power4 power_unit (
      .clk    (clk),
      .rst    (rst || state == IDLE || state == DONE),
      .s_valid(accepted && !field_bad && !last_bad),
      .s_ready(p_ready),
      .s_data (s_data),
      .s_meta ({s_tag, s_beat, s_last}),
      .m_valid(p_valid),
      .m_ready(1'b1),
      .m_power(p_power),
      .m_meta (p_meta),
      .busy   (p_busy)
  );
  always_comb begin
    for(integer l=0;l<4;l=l+1)begin
      peak_lane[l]={32'd0,11'd2000};
      if(({m_power_count[8:0],2'b00}+11'(l))<=48 ||
         ({m_power_count[8:0],2'b00}+11'(l))>=2000)
        peak_lane[l]={p_power[l*32+:32],({m_power_count[8:0],2'b00}+11'(l))};
    end
  end
  always_ff @(posedge clk)begin
    peak_pair0<=better_peak(peak_lane[0],peak_lane[1]);
    peak_pair1<=better_peak(peak_lane[2],peak_lane[3]);
    peak_beat<=better_peak(peak_pair0,peak_pair1);
    competitor_pair0<=max_power(competitor_lane[0],competitor_lane[1]);
    competitor_pair1<=max_power(competitor_lane[2],competitor_lane[3]);
    competitor_beat<=max_power(competitor_pair0,competitor_pair1);
    peak_pair_last<=m_power_count==511;peak_beat_last<=peak_pair_last;
    competitor_pair_last<=raw_beat==511;competitor_beat_last<=competitor_pair_last;
    if(rst || abort || timeout_now || state==IDLE || state==DONE)begin
      peak_pair_valid<=0;peak_beat_valid<=0;
      competitor_pair_valid<=0;competitor_beat_valid<=0;
    end else begin
      peak_pair_valid<=write_fire;peak_beat_valid<=peak_pair_valid;
      competitor_pair_valid<=state==SCAN && raw_valid;
      competitor_beat_valid<=competitor_pair_valid;
    end
  end
  always_comb begin
    previous_next = m_prev_power;
    following_next = m_next_power;
    for(integer l=0;l<4;l=l+1)competitor_lane[l]=0;
    scan_index = 0;
    distance_bin = 0;
    scan_value = 0;
    for (integer l = 0; l < 4; l = l + 1) begin
      scan_index = {raw_beat, 2'b00} + l;
      case (l)
        0: scan_value = raw0;
        1: scan_value = raw1;
        2: scan_value = raw2;
        default: scan_value = raw3;
      endcase
      if (scan_index == prev_bin) previous_next = scan_value;
      if (scan_index == next_bin) following_next = scan_value;
      distance_bin = scan_index - m_peak_bin;
      if (distance_bin > 8 && distance_bin < 2040) competitor_lane[l]=scan_value;
    end
  end
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      age <= 0;
      m_error <= 0;
      m_symbol_slot <= 0;
      m_tag <= 0;
      m_input_count <= 0;
      m_power_count <= 0;
      m_peak_bin <= 2000;
      m_peak_power <= 0;
      m_prev_power <= 0;
      m_next_power <= 0;
      m_competing_power <= 0;
      issued_count <= 0;
      raw_valid <= 0;
      raw_beat <= 0;
      raw0 <= 0;
      raw1 <= 0;
      raw2 <= 0;
      raw3 <= 0;
    end else begin
      if (timing_active) age <= age + 1;
      if (state == DONE) begin
        if (m_ready) state <= IDLE;
      end else if (state == IDLE) begin
        if (cfg_valid && cfg_ready) begin
          m_symbol_slot <= cfg_symbol_slot;
          m_tag <= cfg_tag;
          m_input_count <= 0;
          m_power_count <= 0;
          m_peak_bin <= 2000;
          m_peak_power <= 0;
          m_prev_power <= 0;
          m_next_power <= 0;
          m_competing_power <= 0;
          issued_count <= 0;
          raw_valid <= 0;
          age <= 0;
          m_error <= 0;
          if (cfg_symbol_slot >= 74) begin
            m_error <= 1;
            state   <= DONE;
          end else state <= FILL;
        end
      end else if (abort) begin
        m_error <= 4;
        state <= DONE;
        raw_valid <= 0;
      end else if (timeout_now) begin
        m_error <= 5;
        state <= DONE;
        raw_valid <= 0;
      end else if (state == FILL) begin
        if (accepted) m_input_count <= m_input_count + 1;
        if (input_bad_accept) begin
          m_error <= field_bad ? 4'd2 : 4'd3;
          state   <= DONE;
        end else if (p_valid) begin
          if (p_meta_bad || m_power_count >= 512 || !p_ready) begin
            m_error <= 6;
            state   <= DONE;
          end else begin
            bank0[m_power_count[8:0]] <= p_power[31:0];
            bank1[m_power_count[8:0]] <= p_power[63:32];
            bank2[m_power_count[8:0]] <= p_power[95:64];
            bank3[m_power_count[8:0]] <= p_power[127:96];
            m_power_count <= m_power_count + 1;
            if (m_power_count == 511) begin
              state <= PEAK_DRAIN;
              issued_count <= 0;
              raw_valid <= 0;
            end
          end
        end
      end else if(state==PEAK_DRAIN)begin
        if(peak_beat_valid && peak_beat_last)state<=SCAN;
      end else if (state == SCAN) begin
        raw_valid <= issued_count < 512;
        if (issued_count < 512) begin
          raw0 <= bank0[issued_count[8:0]];
          raw1 <= bank1[issued_count[8:0]];
          raw2 <= bank2[issued_count[8:0]];
          raw3 <= bank3[issued_count[8:0]];
          raw_beat <= issued_count[8:0];
          issued_count <= issued_count + 1;
        end
        if (raw_valid) begin
          m_prev_power <= previous_next;
          m_next_power <= following_next;
          if (raw_beat == 511) begin
            state <= SCAN_DRAIN;
            raw_valid <= 0;
          end
        end
      end else if(state==SCAN_DRAIN)begin
        if(competitor_beat_valid && competitor_beat_last)state<=DONE;
      end
      // Each clock now contains one 32-bit maximum comparison, not four in series.
      if(!abort && !timeout_now)begin
        if(peak_beat_valid && (state==PEAK_DRAIN ||
           (state==FILL && !input_bad_accept && !(p_valid && (p_meta_bad || m_power_count>=512 || !p_ready)))))
          {m_peak_power,m_peak_bin}<=better_peak(peak_beat,{m_peak_power,m_peak_bin});
        if(competitor_beat_valid && (state==SCAN || state==SCAN_DRAIN))
          m_competing_power<=max_power(competitor_beat,m_competing_power);
      end
    end
  end
endmodule
