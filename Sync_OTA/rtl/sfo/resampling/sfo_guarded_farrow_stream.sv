`timescale 1ns / 1ps
// 053 guard-aware finite research transaction: C14 D16 M8 R28, 16 temporal complex lanes.
module sfo_guarded_farrow_stream #(
    // Historical parameter name: this is target_count, including requested guard.
    // In053 E1 target_count=4168; the nominal payload remains4096.
    parameter integer NOMINAL_SAMPLES = 4096
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 start,
    input  wire        [  31:0] cfg_step,
    input  wire signed [  63:0] cfg_phase0,
    input  wire        [  31:0] cfg_request_beats,
    input  wire                 s_valid,
    output wire                 s_ready,
    input  wire        [ 511:0] s_data,
    output wire                 m_valid,
    input  wire                 m_ready,
    output wire        [ 511:0] m_data,
    output wire        [  31:0] m_tag,
    output wire                 issue_valid,
    output wire        [  31:0] issue_tag,
    output reg         [2175:0] issue_window,
    output wire signed [  63:0] issue_phase0,
    output reg         [ 511:0] issue_base,
    output reg         [ 127:0] issue_mu,
    output reg         [   6:0] credit_used,
    output reg         [   6:0] fifo_count,
    output wire        [   6:0] inflight,
    output reg         [  31:0] write_count,
    output wire                 input_pipeline_empty,
    output wire                 done
);
  localparam [31:0] REQUEST_BEATS = (NOMINAL_SAMPLES + 32) / 4;
  reg started;
  reg [31:0] step, request_beats, issued, returned, popped;
  reg signed [63:0] phase0;
  typedef struct packed {
    logic [95:0] ring_base;
    logic [127:0] mu;
    logic [31:0] lo,hi,tag;
    logic coordinate_valid;
    logic [511:0] debug_base;
    logic signed [63:0] debug_phase;
  } descriptor_t;
  descriptor_t descriptor_new,descriptor_head,descriptor_slot[0:1];
  reg descriptor_wp,descriptor_rp,more_generate,more_issue;
  assign descriptor_head=descriptor_slot[descriptor_rp];
  reg [511:0] ingress_slot[0:1],ring_cmd_data;
  reg ingress_wp,ingress_rp,ring_cmd_valid;
  reg [1:0] ingress_count,ring_cmd_group;
  reg [31:0] reserved_written;
  reg partial_valid;
  reg [31:0] partial[0:3][0:63];
  reg [1:0] select_q[0:63];
  wire [5:0] tap_index[0:63];
  reg [127:0] mu_q;
  reg [511:0] base_q;
  reg [31:0] tag_q;
  reg signed [63:0] phase_q;
  reg [2047:0] selected_window;
  for(genvar l=0;l<16;l=l+1)begin:tap_lane
    for(genvar t=0;t<4;t=t+1)begin:tap_word
      assign tap_index[4*l+t]=descriptor_head.ring_base[l*6+:6]-6'd1+6'(t);
    end
  end
  reg [1:0] descriptor_count;
  reg [31:0] generated;
  reg window_valid;
  reg [31:0] window_tag;
  reg signed [63:0] window_phase;
  reg [2175:0] read_window;
  wire read_fire;
  // One setup adder fills the bank; steady state advances all lanes in parallel.
  reg signed [63:0] lane_phase[0:15];
  reg signed [63:0] init_phase;
  reg [3:0] init_lane;
  reg phase_ready;
  wire generate_descriptor = started && phase_ready && more_generate && descriptor_count<2;
  wire signed [63:0] step64 = $signed({32'd0, step});
  wire signed [63:0] beat_step = step64 <<< 4;
  wire signed [63:0] init_next = init_phase + step64;
  reg [31:0] ring[0:63];
  reg [511:0] data_fifo[0:63];
  reg [31:0] tag_fifo[0:63];
  reg [5:0] wr_ptr, rd_ptr;
  wire core_ready, core_valid;
  wire [511:0] core_data;
  wire [31:0] core_tag;
  wire pending = started && more_issue;
  wire pop = m_valid && m_ready;
  wire push = core_valid && !reset;
  wire [32:0] reserved_next={1'b0,reserved_written}+33'd16;
  wire [32:0] reserve_floor=(reserved_next>64)?reserved_next-33'd64:33'd0;
  wire keep_current=descriptor_count!=0 && descriptor_head.coordinate_valid &&
      reserve_floor<={1'b0,descriptor_head.lo};
  // At an actual read edge the old window is completely captured. For the
  // frozen positive step range the next window lo advances by at least 15.
  // Parallel comparisons keep read_fire out of the wide coordinate arithmetic.
  wire keep_after_capture=descriptor_count!=0 && descriptor_head.coordinate_valid &&
      reserve_floor<=({1'b0,descriptor_head.lo}+33'd15);
  wire can_reserve=!reserved_next[32] && (!pending || keep_current ||
      (read_fire && keep_after_capture));
  wire ring_reserve=!reset && started && phase_ready && ingress_count!=0 && can_reserve;
  reg signed [63:0] min_index, max_index;
  reg signed [63:0] lane_base;
  reg [5:0] ring_base;
  reg [27:0] frac;
  reg [ 8:0] rounded_mu;
  reg round_up;
  integer lane;
  always @* begin
    descriptor_new='0;
    descriptor_new.tag=generated;descriptor_new.debug_phase=phase0;
    min_index = 64'sh7fffffffffffffff;
    max_index = -64'sd1;
    lane_base = 64'sd0;
    ring_base = 6'd0;
    frac = 28'd0;
    rounded_mu = 9'd0;
    round_up = 1'b0;
    for (lane = 0; lane < 16; lane = lane + 1) begin
      lane_base = lane_phase[lane] >>> 28;
      frac = lane_phase[lane][27:0];
      round_up = (frac[19:0] > 20'h80000) || ((frac[19:0] == 20'h80000) && frac[20]);
      rounded_mu = {1'b0, frac[27:20]} + {8'd0, round_up};
      // Data selection needs only the exact modulo-64 ring index. Keep the
      // full coordinate below for ownership checks, off the 64:1 data mux.
      ring_base = lane_phase[lane][33:28] + {5'd0,rounded_mu[8]};
      if (rounded_mu == 9'd256) begin
        lane_base  = lane_base + 64'sd1;
        rounded_mu = 9'd0;
      end
      descriptor_new.debug_base[lane*32+:32] = lane_base[31:0];
      descriptor_new.mu[lane*8+:8] = rounded_mu[7:0];
      descriptor_new.ring_base[lane*6+:6] = ring_base;
      if (lane == 0) min_index = lane_base - 64'sd1;
      if (lane == 15) max_index = lane_base + 64'sd2;
    end
    // Positive phase step and monotone RNE make endpoint bounds exact for
    // every lane/tap. Avoid 64 replicated wide range comparators.
    descriptor_new.lo=min_index[31:0];descriptor_new.hi=max_index[31:0];
    descriptor_new.coordinate_valid=min_index>=0 && max_index<=64'shffffffff;
  end
  // Descriptor ownership ends only when its ring words are actually sampled.
  // The phase generator is independent of window availability and downstream ready.
  // synthesis translate_off
  always @* begin
    read_window=2176'd0;
    read_window[2175:2048]=descriptor_head.mu;
    for(integer l=0;l<16;l=l+1)begin
      for(integer t=0;t<4;t=t+1)begin
        read_window[((l*2)*4+t)*16+:16]=ring[descriptor_head.ring_base[l*6+:6]-6'd1+$unsigned(6'(t))][15:0];
        read_window[((l*2+1)*4+t)*16+:16]=ring[descriptor_head.ring_base[l*6+:6]-6'd1+$unsigned(6'(t))][31:16];
      end
    end
  end
  // synthesis translate_on
  wire head_available=descriptor_count!=0 && descriptor_head.coordinate_valid &&
      {1'b0,descriptor_head.lo}>=((write_count>64)?({1'b0,write_count}-33'd64):33'd0) &&
      descriptor_head.hi<write_count;
  assign s_ready=!reset && started && phase_ready && ingress_count<2;
  assign input_pipeline_empty=(ingress_count==0)&&!ring_cmd_valid;
  wire input_fire = s_valid && s_ready;
  // Reserve response capacity before the extra window pipeline stage.
  assign read_fire=!reset && pending && head_available && credit_used<64;
  assign issue_valid=!reset && window_valid;
  assign issue_tag=window_tag;
  assign issue_phase0=window_phase;
  assign m_valid = !reset && (fifo_count != 0);
  assign m_data = m_valid ? data_fifo[rd_ptr] : 512'd0;
  assign m_tag = m_valid ? tag_fifo[rd_ptr] : 32'd0;
  assign inflight = credit_used - fifo_count;
  assign done = !reset && started && (popped == request_beats);
  sfo_farrow_parallel #(
      .C(14),
      .D(16),
      .M(8),
      .LANES(16)
  ) arithmetic (
      .clk         (clk),
      .reset       (reset),
      .input_valid (issue_valid),
      .input_tag   (issue_tag),
      .input_data  (issue_window),
      .input_ready (core_ready),
      .output_valid(core_valid),
      .output_tag  (core_tag),
      .output_data (core_data),
      .trace_data  (),
      .saturation  (),
      .trace_valid (),
      .trace_tag   ()
  );
  always @* begin
    selected_window='0;
    for(integer l=0;l<16;l=l+1)begin
      for(integer t=0;t<4;t=t+1)begin
        selected_window[(l*8+t)*16+:16]=partial[select_q[4*l+t]][4*l+t][15:0];
        selected_window[(l*8+4+t)*16+:16]=partial[select_q[4*l+t]][4*l+t][31:16];
      end
    end
  end
  // Valid bits own observability. Local data registers have neither reset nor CE.
  always @(posedge clk)begin
    for(integer k=0;k<64;k=k+1)begin
      for(integer g=0;g<4;g=g+1)partial[g][k]<=ring[g*16+tap_index[k][3:0]];
      select_q[k]<=tap_index[k][5:4];
    end
    mu_q<=descriptor_head.mu;base_q<=descriptor_head.debug_base;
    tag_q<=descriptor_head.tag;phase_q<=descriptor_head.debug_phase;
    issue_window<={mu_q,selected_window};issue_base<=base_q;
    issue_mu<=mu_q;window_tag<=tag_q;window_phase<=phase_q;
    ring_cmd_data<=ingress_slot[ingress_rp];ring_cmd_group<=reserved_written[5:4];
    if(input_fire)ingress_slot[ingress_wp]<=s_data;
    if(generate_descriptor)descriptor_slot[descriptor_wp]<=descriptor_new;
    if(ring_cmd_valid)begin
      for(integer k=0;k<16;k=k+1)ring[{ring_cmd_group,4'd0}+k]<=ring_cmd_data[k*32+:32];
    end
  end
  integer write_lane, phase_lane;
  always @(posedge clk) begin
    if (reset) begin
      started<=0;descriptor_count<=0;generated<=0;window_valid<=0;partial_valid<=0;
      descriptor_wp<=0;descriptor_rp<=0;more_generate<=0;more_issue<=0;
      ingress_wp<=0;ingress_rp<=0;ingress_count<=0;ring_cmd_valid<=0;reserved_written<=0;
      step <= 0;
      request_beats <= 0;
      phase0 <= 0;
      phase_ready <= 0;
      init_phase <= 0;
      init_lane <= 0;
      for (phase_lane = 0; phase_lane < 16; phase_lane = phase_lane + 1)begin
        lane_phase[phase_lane] <= 0;
      end
      issued <= 0;
      returned <= 0;
      popped <= 0;
      write_count <= 0;
      credit_used <= 0;
      fifo_count <= 0;
      wr_ptr <= 0;
      rd_ptr <= 0;
    end else begin
      partial_valid<=read_fire;window_valid<=partial_valid;
      ring_cmd_valid<=ring_reserve;
      if(input_fire)ingress_wp<=!ingress_wp;
      if(ring_reserve)begin ingress_rp<=!ingress_rp;reserved_written<=reserved_written+32'd16;end
      if(ring_cmd_valid)write_count<=write_count+32'd16;
      case({input_fire,ring_reserve})
        2'b10:ingress_count<=ingress_count+1'b1;
        2'b01:ingress_count<=ingress_count-1'b1;
        default:begin end
      endcase
      case({generate_descriptor,read_fire})
        2'b10:descriptor_count<=descriptor_count+1'b1;
        2'b01:descriptor_count<=descriptor_count-1'b1;
        default:begin end
      endcase
      if(generate_descriptor)begin
        descriptor_wp<=!descriptor_wp;generated<=generated+1'b1;
        if(generated+32'd1==request_beats)more_generate<=0;
      end
      if(read_fire)begin
        descriptor_rp<=!descriptor_rp;
        if(issued+32'd1==request_beats)more_issue<=0;
      end
      if (start && !started) begin
        started <= 1;more_generate<=cfg_request_beats!=0;more_issue<=cfg_request_beats!=0;
        step <= cfg_step;
        phase0 <= cfg_phase0;
        request_beats <= cfg_request_beats;
        lane_phase[0] <= cfg_phase0;
        init_phase <= cfg_phase0;
        init_lane <= 4'd1;
        phase_ready <= 0;
      end else if (started && !phase_ready) begin
        lane_phase[init_lane] <= init_next;
        init_phase <= init_next;
        if (init_lane == 4'd15) phase_ready <= 1;
        else init_lane <= init_lane + 4'd1;
      end
      if (read_fire) issued<=issued+32'd1;
      if (generate_descriptor) begin
        phase0 <= phase0 + beat_step;
        for (phase_lane = 0; phase_lane < 16; phase_lane = phase_lane + 1)
        lane_phase[phase_lane] <= lane_phase[phase_lane] + beat_step;
      end
      if (push) begin
        data_fifo[wr_ptr] <= core_data;
        tag_fifo[wr_ptr] <= core_tag;
        wr_ptr <= wr_ptr + 6'd1;
        returned <= returned + 32'd1;
      end
      if (pop) begin
        rd_ptr <= rd_ptr + 6'd1;
        popped <= popped + 32'd1;
      end
      case ({
        read_fire, pop
      })
        2'b10:   credit_used <= credit_used + 7'd1;
        2'b01:   credit_used <= credit_used - 7'd1;
        default: credit_used <= credit_used;
      endcase
      case ({
        push, pop
      })
        2'b10:   fifo_count <= fifo_count + 7'd1;
        2'b01:   fifo_count <= fifo_count - 7'd1;
        default: fifo_count <= fifo_count;
      endcase
    end
  end
  // synthesis translate_off
  initial
    if (NOMINAL_SAMPLES != 4096 && NOMINAL_SAMPLES != 4168 && NOMINAL_SAMPLES != 5120 &&
        NOMINAL_SAMPLES != 5192 && NOMINAL_SAMPLES != 1336320 && NOMINAL_SAMPLES != 1336392)
      $fatal(1, "Unsupported target sample count");
  integer check_lane;
  reg stalled;
  reg [511:0] held_data;
  reg [31:0] held_tag;
  always @(posedge clk) begin
    if (reset) begin
      stalled   <= 0;
      held_data <= 0;
      held_tag  <= 0;
    end else begin
      if (start) begin
        if ($isunknown({cfg_step, cfg_phase0, cfg_request_beats}))
          $fatal(1, "Unknown start configuration");
        if (started) $fatal(1, "Only one start is supported between initial resets");
        if (cfg_request_beats != REQUEST_BEATS)
          $fatal(1, "Request count must match selected target profile");
        // T10 production callers validate the full first-pass +/-150 ppm range;
        // the second-pass descriptor additionally enforces +/-3 ppm and context.
        // The historical five fixture values were never a synthesized mux/table.
        if (cfg_step < 32'd268395191 || cfg_step > 32'd268475721)
          $fatal(1, "R28 step outside the production descriptor range +/-150 ppm");
        if (cfg_phase0 < 64'sd268435456 || cfg_phase0 > 64'sh0000ffffffffffff)
          $fatal(1, "Finite initial phase outside reviewed coordinate headroom");
      end
      if (!phase_ready && (read_fire || issue_valid || s_ready))
        $fatal(1, "Handshake before phase initialization completed");
      if (phase_ready) begin
        if (step64 <= 0 || lane_phase[0] !== phase0)
          $fatal(1, "Lookahead origin or positive-step invariant");
        for (check_lane = 0; check_lane < 16; check_lane = check_lane + 1) begin
          if ($isunknown(
                  lane_phase[check_lane]
              ) || lane_phase[check_lane] < 0 ||
                  lane_phase[check_lane] > 64'sh7fffffffffffffff - beat_step)
            $fatal(1, "Lookahead signed64 headroom");
          if (lane_phase[check_lane] !== phase0 + check_lane * step64)
            $fatal(1, "Lookahead lane phase identity");
          if (check_lane > 0 && descriptor_new.debug_base[check_lane*32+:32] < descriptor_new.debug_base[(check_lane-1)*32+:32])
            $fatal(1, "Rounded lane bases are not monotone");
        end
      end
      if(ingress_count>2 || reserved_written-write_count!=(ring_cmd_valid?32'd16:32'd0))
        $fatal(1,"Farrow input reservation/commit invariant");
      if(issue_valid && $isunknown(issue_window))$fatal(1,"Unknown selected Farrow window");
      if (credit_used > 64 || fifo_count > credit_used || credit_used != (issued - popped) ||
          fifo_count != (returned - popped) || returned > issued)
        $fatal(1, "Output reservation accounting violated");
      if (push && (fifo_count == 64 || core_tag !== returned))
        $fatal(1, "Unreserved or reordered Farrow return");
      if (pop && m_tag !== popped) $fatal(1, "Output tag order violated");
      if (read_fire && (!head_available || descriptor_head.tag!=issued || $isunknown(read_window)))
        $fatal(1, "Farrow sampled absent, overwritten or reordered samples");
      if(descriptor_count>2 || generated-issued!=descriptor_count)
        $fatal(1,"Descriptor ownership accounting");
      if(issue_valid && !core_ready)$fatal(1,"Farrow arithmetic must have II=1 without input backpressure");
      if (stalled && (!m_valid || m_data !== held_data || m_tag !== held_tag))
        $fatal(1, "Output changed while stalled");
      stalled   <= m_valid && !m_ready;
      held_data <= m_data;
      held_tag  <= m_tag;
    end
  end
  // synthesis translate_on
endmodule
