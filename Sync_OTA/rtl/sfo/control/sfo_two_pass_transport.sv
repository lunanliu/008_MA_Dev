`timescale 1ns / 1ps
// The estimator boundary ports are connected to real T06/T09 in t10_two_pass_system.
// Short tests drive these same ports with explicitly labelled saved estimate records.
module sfo_two_pass_transport #(
    parameter integer REQUIRE_CONTEXT_ACK = 0,
    parameter integer NOMINAL_SAMPLES = 1336320,
    RAW_DEPTH = 393216,
    BANK_DEPTH = 335872,
    OUTPUT_DEPTH = 65536,
    parameter integer PROCESSING_LIMIT_CYCLES = 400896,
    // Legacy callers retain125; the frozen T10-to-CFO candidate selects150 explicitly.
    parameter integer OUTPUT_CLOCK_MHZ = 125
) (
    // Formal successful descriptor launches, clk150. No debug-derived configuration.
    output wire first_context_valid,
    input wire first_context_ready,
    output wire [223:0] first_context_record,
    output wire second_context_valid,
    input wire second_context_ready,
    output wire [223:0] second_context_record,
    input  logic         clk125,
    input  logic         clk150,
    input  logic         reset_request,
    input  logic         abort125,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_data,
    // {frame32,generation32,raw_first_word64,to32,q0Q28,ppmQ18,status16}.
    input  logic         context_valid,
    output logic         context_ready,
    input  logic [235:0] context_record,
    output logic         residual_cfg_valid,
    input  logic         residual_cfg_ready,
    output logic [221:0] residual_cfg_record,
    input  logic         residual_req_valid,
    output logic         residual_req_ready,
    input  logic [101:0] residual_req_record,
    output logic         residual_data_valid,
    input  logic         residual_data_ready,
    output logic [234:0] residual_data_record,
    input  logic         residual_result_valid,
    output logic         residual_result_ready,
    input  logic [159:0] residual_result_record,
    // m_* handshake, reset and fault are synchronous to OUTPUT_CLOCK_MHZ.
    output logic         m_valid,
    input  logic         m_ready,
    output logic [224:0] m_record,
    output logic         m_reset,
    output logic         m_fault,
    output logic         reset125,
    output logic         fault125,
    output logic [  7:0] first_error150,
    output logic [255:0] diagnostic,
    output wire  [511:0] debug150,
    output wire          debug_e1_valid,
    output wire  [127:0] debug_e1_data,
    output wire  [ 31:0] debug_e1_beat,
    output wire          debug_e1_last
);
  localparam integer NB = NOMINAL_SAMPLES / 4, WIN = NB + 135, FB = NB + 18;
  wire rst150;
  logic fault_local125, fault150;
  wire from125, from150;
  wire halted150 = fault150 || from125;
  sfo_domain_reset reset_125 (
      .clk          (clk125),
      .reset_request(reset_request),
      .reset_active (reset125)
  );
  sfo_domain_reset reset_150 (
      .clk          (clk150),
      .reset_request(reset_request),
      .reset_active (rst150)
  );
  xpm_cdc_single #(
      .DEST_SYNC_FF (2),
      .SRC_INPUT_REG(0),
      .INIT_SYNC_FF (1)
  ) fault_125_to_150 (
      .src_clk (clk125),
      .src_in  (fault_local125),
      .dest_clk(clk150),
      .dest_out(from125)
  );
  xpm_cdc_single #(
      .DEST_SYNC_FF (2),
      .SRC_INPUT_REG(0),
      .INIT_SYNC_FF (1)
  ) fault_150_to_125 (
      .src_clk (clk150),
      .src_in  (fault150),
      .dest_clk(clk125),
      .dest_out(from150)
  );
  assign fault125 = !reset125 && (fault_local125 || from150);
  wire [6:0] we, re;
  wire rawv, rawready;
  wire [127:0] rawdata;
  wire cv, cr;
  wire [235:0] cw;
  wire cfgv, cfgr;
  wire [221:0] cfgw;
  wire reqv, reqr;
  wire [101:0] reqw;
  wire datav, datar;
  wire [234:0] dataw;
  wire resv, resr;
  wire [159:0] resw;
  wire outv, outr;
  wire [224:0] outw;
  wire src_ready, ctx_ready, req_ready, res_ready, out_valid, cfg_valid, data_valid;
  assign s_ready = !reset125 && !fault125 && src_ready;
  assign context_ready = !reset125 && !fault125 && ctx_ready;
  assign residual_req_ready = !reset125 && !fault125 && req_ready;
  assign residual_result_ready = !reset125 && !fault125 && res_ready;
  assign residual_cfg_valid = !reset125 && !fault125 && cfg_valid;
  assign residual_data_valid = !reset125 && !fault125 && data_valid;
  sfo_record_cdc_fifo #(
      .WIDTH(128),
      .DEPTH(1024)
  ) raw_samples_cdc (
      .wr_clk         (clk125),
      .rd_clk         (clk150),
      .reset_request  (reset_request),
      .s_valid        (s_valid && !reset125 && !fault125),
      .s_ready        (src_ready),
      .s_data         (s_data),
      .m_valid        (rawv),
      .m_ready        (rawready),
      .m_data         (rawdata),
      .wr_level       (),
      .rd_level       (),
      .wr_high_water  (),
      .rd_high_water  (),
      .wr_reset_active(),
      .rd_reset_active(),
      .wr_error       (we[0]),
      .rd_error       (re[0])
  );
  sfo_record_cdc_fifo #(
      .WIDTH(236),
      .DEPTH(32)
  ) initial_context_cdc (
      .wr_clk         (clk125),
      .rd_clk         (clk150),
      .reset_request  (reset_request),
      .s_valid        (context_valid && !reset125 && !fault125),
      .s_ready        (ctx_ready),
      .s_data         (context_record),
      .m_valid        (cv),
      .m_ready        (cr),
      .m_data         (cw),
      .wr_level       (),
      .rd_level       (),
      .wr_high_water  (),
      .rd_high_water  (),
      .wr_reset_active(),
      .rd_reset_active(),
      .wr_error       (we[1]),
      .rd_error       (re[1])
  );
  sfo_record_cdc_fifo #(
      .WIDTH(222),
      .DEPTH(32)
  ) residual_config_cdc (
      .wr_clk         (clk150),
      .rd_clk         (clk125),
      .reset_request  (reset_request),
      .s_valid        (cfgv),
      .s_ready        (cfgr),
      .s_data         (cfgw),
      .m_valid        (cfg_valid),
      .m_ready        (residual_cfg_ready && !reset125 && !fault125),
      .m_data         (residual_cfg_record),
      .wr_level       (),
      .rd_level       (),
      .wr_high_water  (),
      .rd_high_water  (),
      .wr_reset_active(),
      .rd_reset_active(),
      .wr_error       (we[2]),
      .rd_error       (re[2])
  );
  sfo_record_cdc_fifo #(
      .WIDTH(102),
      .DEPTH(32)
  ) residual_request_cdc (
      .wr_clk         (clk125),
      .rd_clk         (clk150),
      .reset_request  (reset_request),
      .s_valid        (residual_req_valid && !reset125 && !fault125),
      .s_ready        (req_ready),
      .s_data         (residual_req_record),
      .m_valid        (reqv),
      .m_ready        (reqr),
      .m_data         (reqw),
      .wr_level       (),
      .rd_level       (),
      .wr_high_water  (),
      .rd_high_water  (),
      .wr_reset_active(),
      .rd_reset_active(),
      .wr_error       (we[3]),
      .rd_error       (re[3])
  );
  sfo_record_cdc_fifo #(
      .WIDTH(235),
      .DEPTH(1024)
  ) residual_data_cdc (
      .wr_clk         (clk150),
      .rd_clk         (clk125),
      .reset_request  (reset_request),
      .s_valid        (datav),
      .s_ready        (datar),
      .s_data         (dataw),
      .m_valid        (data_valid),
      .m_ready        (residual_data_ready && !reset125 && !fault125),
      .m_data         (residual_data_record),
      .wr_level       (),
      .rd_level       (),
      .wr_high_water  (),
      .rd_high_water  (),
      .wr_reset_active(),
      .rd_reset_active(),
      .wr_error       (we[4]),
      .rd_error       (re[4])
  );
  sfo_record_cdc_fifo #(
      .WIDTH(160),
      .DEPTH(32)
  ) residual_result_cdc (
      .wr_clk         (clk125),
      .rd_clk         (clk150),
      .reset_request  (reset_request),
      .s_valid        (residual_result_valid && !reset125 && !fault125),
      .s_ready        (res_ready),
      .s_data         (residual_result_record),
      .m_valid        (resv),
      .m_ready        (resr),
      .m_data         (resw),
      .wr_level       (),
      .rd_level       (),
      .wr_high_water  (),
      .rd_high_water  (),
      .wr_reset_active(),
      .rd_reset_active(),
      .wr_error       (we[5]),
      .rd_error       (re[5])
  );
  generate
    if (OUTPUT_CLOCK_MHZ == 150) begin : output150
      // The URAM response FIFO and frame header already belong to clk150.
      // No sample conversion, truncation, pacing or asynchronous handshake is added.
      assign m_valid = !rst150 && !halted150 && outv;
      assign outr = !rst150 && !halted150 && m_ready;
      assign m_record = outw;
      assign m_reset = rst150;
      assign m_fault = halted150 || obfault;
      assign we[6] = 1'b0;
      assign re[6] = 1'b0;
    end else begin : output125
      assign m_valid = !reset125 && !fault125 && out_valid;
      assign m_reset = reset125;
      assign m_fault = fault125;
      sfo_record_cdc_fifo #(
          .WIDTH(225),
          .DEPTH(1024)
      ) output_data_cdc (
          .wr_clk         (clk150),
          .rd_clk         (clk125),
          .reset_request  (reset_request),
          .s_valid        (outv),
          .s_ready        (outr),
          .s_data         (outw),
          .m_valid        (out_valid),
          .m_ready        (m_ready && !reset125 && !fault125),
          .m_data         (m_record),
          .wr_level       (),
          .rd_level       (),
          .wr_high_water  (),
          .rd_high_water  (),
          .wr_reset_active(),
          .rd_reset_active(),
          .wr_error       (we[6]),
          .rd_error       (re[6])
      );
    end
  endgenerate

  always_ff @(posedge clk125)
    if (reset125) fault_local125 <= 0;
    else if (abort125 || we[0] || we[1] || we[3] || we[5] || re[2] || re[4] || re[6])
      fault_local125 <= 1;
  wire raw_req_ready, raw_m_valid, raw_m_ready, raw_last, raw_done, raw_fault;
  wire [  7:0] raw_error;
  wire [127:0] raw_m_data;
  wire [31:0] raw_frame, raw_gen, raw_beat, raw_high, raw_i, raw_r, raw_c;
  wire [63:0] raw_written, raw_retired;
  logic [1:0] e1state;
  logic next_bank, e1bank;
  logic [31:0] e1frame, e1gen;
  logic [63:0] e1rawbase;
  wire [31:0] dbg_e1step, dbg_e2step;
  wire e1cv, e1cr, e1sr, e1mv, e1mr, e1last, e1done, e1ok, e1halt;
  wire [127:0] e1data;
  wire [31:0] e1of, e1og, e1ob, e1cycles;
  wire [ 7:0] e1error;
  wire [31:0] ctxframe = cw[235:204], ctxgen = cw[203:172];
  wire [63:0] ctxraw = cw[171:108];
  wire [31:0] ctxto = cw[107:76];
  wire [27:0] ctxq0 = cw[75:48];
  wire [31:0] ctxppm = cw[47:16];
  wire [15:0] ctxstatus = cw[15:0];
  wire [1:0] bwready, bpubready, bestready, bcomm, breqready, bmv, bml, bms, bdone, bfault;
  wire [1:0][31:0] bframe, bgen, bmf, bmg, bmb, baddr, bi, br, bc, bwstall, brstall, bhwm;
  wire [1:0][127:0] bdata;
  wire [1:0][  7:0] berror;
  wire [1:0] bpub, best, breq, bseq, bmr;
  wire [1:0][31:0] brf, brg, brbase, brcount;
  wire raw_available = raw_written >= ctxraw + WIN && ctxraw + WIN >= ctxraw &&
      ctxraw >= raw_retired;
  assign e1cv = !rst150 && !halted150 && e1state == 0 && cv && raw_available && bwready[next_bank];
  assign cr   = e1cv && e1cr;
  wire publish = e1state == 2 && e1done && e1ok && bpubready[e1bank] && cfgr && !halted150;
  assign cfgv = publish;
  assign cfgw = {
    e1frame,
    e1gen,
    e1frame,
    e1gen,
    1'b1,
    8'd0,
    21'(NOMINAL_SAMPLES),
    32'd0,
    32'(NOMINAL_SAMPLES - 1)
  };
  assign e1mr = !halted150 && bwready[e1bank];
  sfo_raw_frame_ring #(
      .DEPTH_BEATS(RAW_DEPTH),
      .AW($clog2(RAW_DEPTH)),
      .WINDOW_BEATS(WIN),
      .RETAIN_BEATS(256)
  ) raw_frame_buffer (
      .clk                 (clk150),
      .rst                 (rst150),
      .poison              (halted150),
      .s_valid             (rawv),
      .s_ready             (rawready),
      .s_data              (rawdata),
      .req_valid           (e1state == 1 && !halted150),
      .req_ready           (raw_req_ready),
      .req_first_word      (e1rawbase),
      .req_frame           (e1frame),
      .req_generation      (e1gen),
      .m_valid             (raw_m_valid),
      .m_ready             (raw_m_ready),
      .m_data              (raw_m_data),
      .m_frame             (raw_frame),
      .m_generation        (raw_gen),
      .m_beat              (raw_beat),
      .m_last              (raw_last),
      .complete            (raw_done),
      .written_words       (raw_written),
      .retired_words       (raw_retired),
      .occupancy_high_water(raw_high),
      .issued              (raw_i),
      .returned            (raw_r),
      .consumed            (raw_c),
      .fault               (raw_fault),
      .first_error         (raw_error)
  );
  assign raw_m_ready = e1sr;
  sfo_first_resampler #(
      .REQUIRE_CONTEXT_ACK(REQUIRE_CONTEXT_ACK),
      .NOMINAL_SAMPLES(NOMINAL_SAMPLES),
      .PROCESSING_LIMIT_CYCLES(PROCESSING_LIMIT_CYCLES)
  ) first_resampling (
      .context_valid(first_context_valid),
      .context_ready(first_context_ready),
      .context_frame(first_context_record[223:192]),
      .context_generation(first_context_record[191:160]),
      .context_step_q28(first_context_record[159:128]),
      .context_phase(first_context_record[127:64]),
      .context_raw_first(first_context_record[63:32]),
      .context_nominal_first(first_context_record[31:0]),
      .clk                    (clk150),
      .rst                    (rst150),
      .abort_request          (halted150),
      .cfg_valid              (e1cv),
      .cfg_ready              (e1cr),
      .cfg_frame_id           (ctxframe),
      .cfg_generation         (ctxgen),
      .cfg_estimate_frame_id  (ctxframe),
      .cfg_estimate_generation(ctxgen),
      .cfg_estimate_status    (ctxstatus),
      .cfg_ppm_q18            (ctxppm),
      .cfg_to                 (ctxto),
      .cfg_raw_first          (-32'sd172),
      .cfg_available_first    (-32'sd172),
      .cfg_available_last     (32'(NOMINAL_SAMPLES + 367)),
      .cfg_nominal_first      (32'd0),
      .cfg_q0                 (ctxq0),
      .cfg_input_count        (32'(NOMINAL_SAMPLES + 540)),
      .cfg_nominal_count      (32'(NOMINAL_SAMPLES)),
      .s_valid                (raw_m_valid),
      .s_ready                (e1sr),
      .s_data                 (raw_m_data),
      .s_frame_id             (raw_frame),
      .s_generation           (raw_gen),
      .s_beat                 (raw_beat),
      .s_raw_index            (-32'sd172 + $signed(raw_beat << 2)),
      .s_lane_valid           (4'hf),
      .s_last                 (raw_last),
      .m_valid                (e1mv),
      .m_ready                (e1mr),
      .m_data                 (e1data),
      .m_frame_id             (e1of),
      .m_generation           (e1og),
      .m_beat                 (e1ob),
      .m_sample_index         (),
      .m_lane_valid           (),
      .m_nominal_mask         (),
      .m_guard_mask           (),
      .m_first                (),
      .m_last                 (e1last),
      .m_nominal_first        (),
      .m_nominal_last         (),
      .completion_valid       (e1done),
      .completion_ready       (publish),
      .completion_success     (e1ok),
      .completed_frame_id     (),
      .completed_generation   (),
      .error_code             (e1error),
      .halted                 (e1halt),
      .diagnostic_step        (dbg_e1step),
      .diagnostic_phase       (),
      .processing_cycles      (e1cycles),
      .accepted_input_beats   (),
      .accepted_output_beats  (),
      .accepted_stage_beats   ()
  );
  always_ff @(posedge clk150) begin
    if (rst150) begin
      e1state <= 0;
      next_bank <= 0;
      e1bank <= 0;
      e1frame <= 0;
      e1gen <= 0;
      e1rawbase <= 0;
    end else if (!halted150)
      case (e1state)
        0:
        if (cr) begin
          e1state <= 1;
          e1bank <= next_bank;
          e1frame <= ctxframe;
          e1gen <= ctxgen;
          e1rawbase <= ctxraw;
        end
        1: if (raw_req_ready) e1state <= 2;
        2:
        if (publish) begin
          e1state   <= 0;
          next_bank <= !next_bank;
        end
        default: e1state <= 0;
      endcase
  end
  // A single T09 source transaction, while the other bank may feed second_pass.
  logic [1:0] wstate;
  logic wbank;
  logic [31:0] wf, wg, wstart;
  logic [6:0] wslot;
  wire match_req0 = bcomm[0] && bframe[0] == reqw[101:70] && bgen[0] == reqw[69:38];
  wire match_req1 = bcomm[1] && bframe[1] == reqw[101:70] && bgen[1] == reqw[69:38];
  wire req_geometry = reqw[9:0] == 512 && reqw[11:10] == 0 &&
      {1'b0, reqw[30:10]} + 22'd2048 <= NOMINAL_SAMPLES;
  assign reqr = !rst150 && !halted150 && wstate == 0;
  wire wpop = wstate == 2 && bmv[wbank] && !bms[wbank] && datar;
  assign datav = !rst150 && !halted150 && wstate == 2 && bmv[wbank] && !bms[wbank];
  assign dataw = {
    bmf[wbank],
    bmg[wbank],
    21'(wstart + (bmb[wbank] << 2)),
    bmb[wbank][8:0],
    4'hf,
    bml[wbank],
    8'd0,
    bdata[wbank]
  };
  always_ff @(posedge clk150) begin
    if (rst150) begin
      wstate <= 0;
      wbank <= 0;
      wf <= 0;
      wg <= 0;
      wstart <= 0;
      wslot <= 0;
    end else if (!halted150)
      case (wstate)
        0:
        if (reqv && reqr && req_geometry && (match_req0 ^ match_req1)) begin
          wbank <= match_req1;
          wf <= reqw[101:70];
          wg <= reqw[69:38];
          wstart <= {11'd0, reqw[30:10]};
          wslot <= reqw[37:31];
          wstate <= 1;
        end
        1: if (breqready[wbank]) wstate <= 2;
        2: if (wpop && bml[wbank]) wstate <= 0;
        default: wstate <= 0;
      endcase
  end
  logic [1:0] e2state;
  logic e2bank;
  logic [31:0] e2frame, e2gen;
  wire e2cv, e2cr, e2sr, e2mv, e2mr, e2last, e2done, e2ok, e2halt;
  wire [127:0] e2data;
  wire [31:0] e2of, e2og, e2ob, e2cycles;
  wire [7:0] e2error;
  wire match_res0 = bcomm[0] && bframe[0] == resw[159:128] && bgen[0] == resw[127:96];
  wire match_res1 = bcomm[1] && bframe[1] == resw[159:128] && bgen[1] == resw[127:96];
  wire res_bank = match_res1;
  wire res_good = resw[95:89] == 74 && resw[88:82] == 74 && resw[81:70] == 0 && resw[0];
  assign e2cv = !rst150 && !halted150 && e2state == 0 && resv && res_good &&
      (match_res0 ^ match_res1) && bestready[res_bank];
  assign resr = e2cv && e2cr;
  sfo_second_resampler #(
      .REQUIRE_CONTEXT_ACK(REQUIRE_CONTEXT_ACK),
      .NOMINAL_SAMPLES(NOMINAL_SAMPLES),
      .PROCESSING_LIMIT_CYCLES(PROCESSING_LIMIT_CYCLES)
  ) second_resampling (
      .context_valid(second_context_valid),
      .context_ready(second_context_ready),
      .context_frame(second_context_record[223:192]),
      .context_generation(second_context_record[191:160]),
      .context_step_q28(second_context_record[159:128]),
      .context_phase(second_context_record[127:64]),
      .context_raw_first(second_context_record[63:32]),
      .context_nominal_first(second_context_record[31:0]),
      .clk                  (clk150),
      .rst                  (rst150),
      .abort_request        (halted150),
      .cfg_valid            (e2cv),
      .cfg_ready            (e2cr),
      .cfg_frame_id         (resw[159:128]),
      .cfg_generation       (resw[127:96]),
      .cfg_t09_result       (resw),
      .cfg_source_complete  (1'b1),
      .cfg_source_error     (8'd0),
      .cfg_available_first  (-32'sd36),
      .cfg_available_last   (32'(NOMINAL_SAMPLES + 35)),
      .cfg_nominal_first    (32'd0),
      .cfg_input_count      (32'(NOMINAL_SAMPLES + 72)),
      .cfg_nominal_count    (32'(NOMINAL_SAMPLES)),
      .s_valid              (e2state == 2 && bmv[e2bank] && bms[e2bank]),
      .s_ready              (e2sr),
      .s_data               (bdata[e2bank]),
      .s_frame_id           (bmf[e2bank]),
      .s_generation         (bmg[e2bank]),
      .s_beat               (bmb[e2bank]),
      .s_raw_index          (-32'sd36 + $signed(bmb[e2bank] << 2)),
      .s_lane_valid         (4'hf),
      .s_last               (bml[e2bank]),
      .m_valid              (e2mv),
      .m_ready              (e2mr),
      .m_data               (e2data),
      .m_frame_id           (e2of),
      .m_generation         (e2og),
      .m_beat               (e2ob),
      .m_sample_index       (),
      .m_lane_valid         (),
      .m_nominal_mask       (),
      .m_guard_mask         (),
      .m_first              (),
      .m_last               (e2last),
      .m_nominal_first      (),
      .m_nominal_last       (),
      .completion_valid     (e2done),
      .completion_ready     (e2state == 2 && !halted150),
      .completion_success   (e2ok),
      .completed_frame_id   (),
      .completed_generation (),
      .error_code           (e2error),
      .halted               (e2halt),
      .diagnostic_step      (dbg_e2step),
      .diagnostic_phase     (),
      .processing_cycles    (e2cycles),
      .accepted_input_beats (),
      .accepted_output_beats(),
      .accepted_stage_beats ()
  );
  always_ff @(posedge clk150) begin
    if (rst150) begin
      e2state <= 0;
      e2bank  <= 0;
      e2frame <= 0;
      e2gen   <= 0;
    end else if (!halted150)
      case (e2state)
        0:
        if (resr) begin
          e2state <= 1;
          e2bank  <= res_bank;
          e2frame <= resw[159:128];
          e2gen   <= resw[127:96];
        end
        1: if (breqready[e2bank]) e2state <= 2;
        2: if (e2done && e2ok) e2state <= 0;
        default: e2state <= 0;
      endcase
  end
  genvar g;
  generate
    for (g = 0; g < 2; g = g + 1) begin : intermediate
      assign bpub[g] = publish && e1bank == g;
      assign best[g] = resr && res_bank == g;
      wire e2request = e2state == 1 && e2bank == g;
      wire wrequest = wstate == 1 && wbank == g;
      assign breq[g] = !halted150 && (e2request || wrequest);
      assign bseq[g] = e2request;
      assign brf[g] = e2request ? e2frame : wf;
      assign brg[g] = e2request ? e2gen : wg;
      assign brbase[g] = e2request ? 0 : (wstart >> 2) + 9;
      assign brcount[g] = e2request ? FB : 512;
      assign bmr[g] = !halted150 && ((e2state == 2 && e2bank == g && bms[g]) ? e2sr :
                                     ((wstate == 2 && wbank == g && !bms[g]) ? datar : 1'b0));
      sfo_intermediate_frame_bank #(
          .FRAME_BEATS(FB),
          .DEPTH_BEATS(BANK_DEPTH),
          .AW($clog2(BANK_DEPTH))
      ) intermediate_bank (
          .clk                   (clk150),
          .rst                   (rst150),
          .poison                (halted150),
          .s_valid               (e1mv && e1bank == g),
          .s_ready               (bwready[g]),
          .s_data                (e1data),
          .s_frame               (e1of),
          .s_generation          (e1og),
          .s_beat                (e1ob),
          .s_last                (e1last),
          .publish_valid         (bpub[g]),
          .publish_ready         (bpubready[g]),
          .publish_frame         (e1frame),
          .publish_generation    (e1gen),
          .estimate_valid        (best[g]),
          .estimate_ready        (bestready[g]),
          .estimate_frame        (resw[159:128]),
          .estimate_generation   (resw[127:96]),
          .estimate_good         (res_good),
          .committed             (bcomm[g]),
          .committed_frame       (bframe[g]),
          .committed_generation  (bgen[g]),
          .req_valid             (breq[g]),
          .req_ready             (breqready[g]),
          .req_sequential        (bseq[g]),
          .req_frame             (brf[g]),
          .req_generation        (brg[g]),
          .req_base              (brbase[g]),
          .req_count             (brcount[g]),
          .m_valid               (bmv[g]),
          .m_ready               (bmr[g]),
          .m_data                (bdata[g]),
          .m_frame               (bmf[g]),
          .m_generation          (bmg[g]),
          .m_beat                (bmb[g]),
          .m_address             (baddr[g]),
          .m_last                (bml[g]),
          .m_sequential          (bms[g]),
          .read_done             (bdone[g]),
          .write_done            (),
          .issued                (bi[g]),
          .returned              (br[g]),
          .consumed              (bc[g]),
          .write_stalls          (bwstall[g]),
          .read_stalls           (brstall[g]),
          .outstanding_high_water(bhwm[g]),
          .fifo_high_water       (),
          .fault                 (bfault[g]),
          .first_error           (berror[g])
      );
    end
  endgenerate
  wire obfault;
  wire [7:0] oberror;
  wire [31:0] obocc, obhwm, obohwm;
  wire [63:0] oa, oi, orr, oc;
  sfo_output_buffer #(
      .FRAME_BEATS(NB),
      .DEPTH(OUTPUT_DEPTH)
  ) output_buffer (
      .clk                   (clk150),
      .rst                   (rst150),
      .poison                (halted150),
      .s_valid               (e2mv),
      .s_ready               (e2mr),
      .s_data                (e2data),
      .s_frame               (e2of),
      .s_generation          (e2og),
      .s_beat                (e2ob),
      .s_last                (e2last),
      .m_valid               (outv),
      .m_ready               (outr),
      .m_record              (outw),
      .occupancy             (obocc),
      .high_water            (obhwm),
      .outstanding_high_water(obohwm),
      .accepted              (oa),
      .issued                (oi),
      .returned              (orr),
      .consumed              (oc),
      .fault                 (obfault),
      .first_error           (oberror)
  );
  logic [7:0] bad;
  always_comb begin
    bad = 0;
    if (re[0] || re[1] || re[3] || re[5] || we[2] || we[4] || we[6]) bad = 1;
    else if (raw_fault) bad = 2;
    else if (|bfault) bad = 3;
    else if (obfault) bad = 4;
    else if (e1halt || (e1done && !e1ok)) bad = 5;
    else if (e2halt || (e2done && !e2ok)) bad = 6;
    else if (reqv && reqr && (!req_geometry || !(match_req0 ^ match_req1))) bad = 7;
    else if (resv && e2state == 0 && (!res_good || !(match_res0 ^ match_res1))) bad = 8;
    else if ((wstate == 1 && e2state == 1 && wbank == e2bank)) bad = 9;
    else if (cv && e1state == 0 && (ctxraw < raw_retired || ctxraw + WIN < ctxraw)) bad = 10;
  end
  always_ff @(posedge clk150)
    if (rst150) begin
      fault150 <= 0;
      first_error150 <= 0;
    end else if (!fault150 && bad != 0) begin
      fault150 <= 1;
      first_error150 <= bad;
    end
  assign diagnostic = {
    raw_high, obhwm, bhwm[1], bhwm[0], e2cycles, e1cycles, bwstall[1], bwstall[0]
  };
  // synthesis translate_off
  initial begin
    if (NOMINAL_SAMPLES != 1336320 && NOMINAL_SAMPLES != 5120)
      $fatal(1, "Only frozen production or explicit short geometry");
    if (OUTPUT_CLOCK_MHZ != 125 && OUTPUT_CLOCK_MHZ != 150)
      $fatal(1, "Output clock must be125 or150 MHz");
  end
  // synthesis translate_on

  logic [31:0] dbg_n1, dbg_n2, dbg_no;
  always_ff @(posedge clk150) begin
    if (rst150) begin
      dbg_n1 <= 0;
      dbg_n2 <= 0;
      dbg_no <= 0;
    end else begin
      if (e1mv && e1mr) dbg_n1 <= dbg_n1 + 1'b1;
      if (e2mv && e2mr) dbg_n2 <= dbg_n2 + 1'b1;
      if (m_valid && m_ready) dbg_no <= dbg_no + 1'b1;
    end
  end
  assign debug_e1_valid = e1mv && e1mr && !rst150;
  assign debug_e1_data = e1data;
  assign debug_e1_beat = e1ob;
  assign debug_e1_last = e1last;
  assign debug150[0*32+:32] = dbg_n1;
  assign debug150[1*32+:32] = dbg_n2;
  assign debug150[2*32+:32] = dbg_no;
  assign debug150[3*32+:32] = dbg_e1step;
  assign debug150[4*32+:32] = dbg_e2step;
  assign debug150[5*32+:32] = e1cycles;
  assign debug150[6*32+:32] = e2cycles;
  assign debug150[7*32+:32] = {oberror, e2error, e1error, raw_error};
  assign debug150[8*32+:32] = {8'd0, berror[1], berror[0], first_error150};
  assign debug150[9*32+:32] = raw_high;
  assign debug150[10*32+:32] = obhwm;
  assign debug150[11*32+:32] = {23'd0, halted150, bcomm, wstate, e2state, e1state};
  assign debug150[12*32+:32] = raw_written[31:0];
  assign debug150[13*32+:32] = bc[0];
  assign debug150[14*32+:32] = bc[1];
  assign debug150[15*32+:32] = obocc;
endmodule
