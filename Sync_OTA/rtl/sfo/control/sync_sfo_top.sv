`timescale 1ns / 1ps
// Production closure: actual T06, two independent resamplers, actual T09,
// full-size R0/R1/output memories and explicit 125/150/500 MHz boundaries.
// Select150 explicitly for the T10-to-CFO output profile; IQ sample rate remains500MS/s.
module sync_sfo_top #(
    parameter integer REQUIRE_CONTEXT_ACK = 0,
    parameter integer SHARED_RAW_INPUT = 0,
    parameter integer PROCESSING_LIMIT_CYCLES = 400896,
    parameter integer OUTPUT_CLOCK_MHZ = 150
) (
    // Formal successful descriptor launches, clk150. No debug-derived configuration.
    output wire first_context_valid,
    input wire first_context_ready,
    output wire [223:0] first_context_record,
    output wire second_context_valid,
    input wire second_context_ready,
    output wire [223:0] second_context_record,
    input  logic                                               clk125,
    input  logic                                               clk150,
    input  logic                                               clk500,
    input  logic                                               reset_request,
    input  logic                                               abort125,
    input wire abort150,
    input  logic                                               s_valid,
    output logic                                               s_ready,
    input  logic                                       [127:0] s_data,
    input  logic                                       [ 31:0] s_frame_id,
    input  logic signed                                [ 31:0] s_absolute_index,
    input  logic                                       [  3:0] s_lane_valid,
    // V5.1 ordered raw control, clk125. Legacy descriptor ports are disabled
    // when SHARED_RAW_INPUT=1; records are generated only after training fill.
    input wire raw_event_valid,output wire raw_event_ready,input wire [208:0] raw_event_record,
    output wire metadata_valid,input wire metadata_ready,output wire [149:0] metadata_record,
    // Producer's capture descriptor: {frame32,generation32,raw_first_word64,nominal_absolute32,q0Q28}.
    input  logic                                               frame_valid,
    output logic                                               frame_ready,
    input  logic                                       [187:0] frame_record,
    input  logic                                               cfo_valid,
    output logic                                               cfo_ready,
    input  sfo_stream_pkg::bistatic_estimator_result_t         cfo_record,
    input  logic                                               fine_valid,
    output logic                                               fine_ready,
    input  sfo_stream_pkg::bistatic_estimator_result_t         fine_record,
    // m_* belong to the selected output domain; all existing control ports retain clk125.
    output logic                                               m_valid,
    input  logic                                               m_ready,
    output logic                                       [224:0] m_record,
    output logic                                               m_reset,
    output logic                                               m_fault,
    output logic                                               fault,
    output logic                                       [  7:0] error_code125,
    output logic                                       [  7:0] error_code150,
    output logic                                       [255:0] diagnostic,
    output logic                                               residual_point_valid,
    output logic                                       [128:0] residual_point_record,
    output wire                                        [511:0] debug125,
    output wire                                        [511:0] debug150,
    output wire                                                debug_e1_valid,
    output wire                                        [127:0] debug_e1_data,
    output wire                                        [ 31:0] debug_e1_beat,
    output wire                                                debug_e1_last
);
  import sfo_stream_pkg::*;
  wire [31:0] debug_elapsed;
  wire [12:0] debug_fft_in, debug_fft_out, debug_obs, debug_weights;
  wire reset125, transport_fault;
  logic control_fault;
  wire dispatch_fault;
  wire system_fault = control_fault || transport_fault || dispatch_fault;
  wire ctx_sr, ctx_v, ctx_r, ctx_busy, ctx_error, fc_sr, fc_v, fc_r, fc_busy, fc_error;
  wire [187:0] ctx_data;
  wire [ 95:0] fc_data;
  wire initial_fine_valid, initial_fine_ready, initial_cfo_valid, initial_cfo_ready,
      initial_result_valid, initial_result_ready, initial_halted;
  wire [7:0] initial_error_stage;
  bistatic_estimator_result_t initial_result, stored_fine;
  logic context_history;
  logic [31:0] previous_frame;
  wire training_cfg_v,training_cfg_r,training_data_v,training_data_r,training_release_v,training_release_r;
  wire [207:0] training_cfg_w;wire [224:0] training_data_w;wire [63:0] training_release_w;
  wire generated_fv,generated_cv,generated_tv,selected_fr,selected_cr,selected_tr;
  wire [187:0] generated_fw;wire [95:0] generated_cw,generated_tw;
  wire training_tap;wire [127:0] training_iq;wire [31:0] training_frame;wire signed [31:0] training_abs;
  wire dispatch_done_ready;
  wire selected_fv=SHARED_RAW_INPUT?generated_fv:frame_valid;
  wire selected_cv=SHARED_RAW_INPUT?generated_cv:cfo_valid;
  wire selected_tv=SHARED_RAW_INPUT?generated_tv:fine_valid;
  wire [187:0] selected_fw=SHARED_RAW_INPUT?generated_fw:frame_record;
  wire [95:0] selected_cw=SHARED_RAW_INPUT?generated_cw:cfo_record;
  wire [95:0] selected_tw=SHARED_RAW_INPUT?generated_tw:fine_record;
  assign frame_ready=SHARED_RAW_INPUT?1'b0:selected_fr;
  assign cfo_ready=SHARED_RAW_INPUT?1'b0:selected_cr;
  assign fine_ready=SHARED_RAW_INPUT?1'b0:selected_tr;
  generate if(SHARED_RAW_INPUT!=0)begin : training_dispatch
    ota_training_dispatch dispatch(
      .clk(clk125),.rst(reset125),.poison(control_fault||transport_fault||abort125),
      .cfg_valid(training_cfg_v),.cfg_ready(training_cfg_r),.cfg_record(training_cfg_w),
      .s_valid(training_data_v),.s_ready(training_data_r),.s_record(training_data_w),
      .tap_fire(training_tap),.tap_data(training_iq),.tap_frame(training_frame),.tap_absolute(training_abs),
      .frame_valid(generated_fv),.frame_ready(selected_fr),.frame_record(generated_fw),
      .coarse_valid(generated_cv),.coarse_ready(selected_cr),.coarse_record(generated_cw),
      .fine_valid(generated_tv),.fine_ready(selected_tr),.fine_record(generated_tw),
      .meta_valid(metadata_valid),.meta_ready(metadata_ready),.meta_record(metadata_record),
      // Atomic completion fork: consume_join is impossible before this ready.
      .initial_done_valid(consume_join),.initial_done_ready(dispatch_done_ready),.initial_done_frame(initial_result.frame_id),
      .release_valid(training_release_v),.release_ready(training_release_r),.release_record(training_release_w),
      .fault(dispatch_fault),.error_code());
  end else begin : legacy_training
    assign dispatch_fault=0;assign dispatch_done_ready=1;
    assign training_cfg_r=0;assign training_data_r=0;assign training_release_v=0;assign training_release_w=0;
    assign generated_fv=0;assign generated_cv=0;assign generated_tv=0;
    assign generated_fw=0;assign generated_cw=0;assign generated_tw=0;
    assign training_tap=0;assign training_iq=0;assign training_frame=0;assign training_abs=0;
    assign metadata_valid=0;assign metadata_record=0;
  end endgenerate
  assign stored_fine = fc_data;
  assign selected_fr = !reset125 && !system_fault && ctx_sr;
  sfo_sync_fifo #(
      .WIDTH(188),
      .DEPTH(32)
  ) frame_context_fifo (
      .clk         (clk125),
      .rst         (reset125),
      .s_valid     (selected_fv && !system_fault && !reset125),
      .s_ready     (ctx_sr),
      .s_data      (selected_fw),
      .m_valid     (ctx_v),
      .m_ready     (ctx_r),
      .m_data      (ctx_data),
      .level       (),
      .high_water  (),
      .reset_busy  (ctx_busy),
      .error_sticky(ctx_error)
  );
  // Atomic fork: T06 and the binding FIFO accept the same fine record together.
  assign selected_tr = !reset125 && !system_fault && initial_fine_ready && fc_sr;
  assign initial_fine_valid = selected_tv && !reset125 && !system_fault && fc_sr;
  sfo_sync_fifo #(
      .WIDTH(96),
      .DEPTH(32)
  ) fine_record_fifo (
      .clk         (clk125),
      .rst         (reset125),
      .s_valid     (selected_tv && !reset125 && !system_fault && initial_fine_ready),
      .s_ready     (fc_sr),
      .s_data      (selected_tw),
      .m_valid     (fc_v),
      .m_ready     (fc_r),
      .m_data      (fc_data),
      .level       (),
      .high_water  (),
      .reset_busy  (fc_busy),
      .error_sticky(fc_error)
  );
  assign selected_cr = !reset125 && !system_fault && initial_cfo_ready;
  assign initial_cfo_valid = selected_cv && !reset125 && !system_fault;
  sfo_initial_estimator #(
      .MAX_CYCLES(65024)
  ) initial_estimator (
      .clk_125                 (clk125),
      .clk_500                 (clk500),
      .rst                     (reset125),
      .tap_fire                (SHARED_RAW_INPUT?training_tap:(s_valid && s_ready)),
      .tap_data                (SHARED_RAW_INPUT?training_iq:s_data),
      .tap_frame_id            (SHARED_RAW_INPUT?training_frame:s_frame_id),
      .tap_abs                 (SHARED_RAW_INPUT?training_abs:s_absolute_index),
      .tap_lane_valid          (SHARED_RAW_INPUT?4'hf:s_lane_valid),
      .s_cfo_valid             (initial_cfo_valid),
      .s_cfo_ready             (initial_cfo_ready),
      .s_cfo                   (selected_cw),
      .s_fine_valid            (initial_fine_valid),
      .s_fine_ready            (initial_fine_ready),
      .s_fine                  (selected_tw),
      .m_valid                 (initial_result_valid),
      .m_ready                 (initial_result_ready),
      .m_result                (initial_result),
      .m_slope                 (),
      .m_error_stage           (initial_error_stage),
      .halted                  (initial_halted),
      .elapsed_cycles          (debug_elapsed),
      .fft_lease_wait_cycles   (),
      .fft_input_stall_cycles  (),
      .fft_output_stall_cycles (),
      .shared_gain_sample_count(),
      .fft_input_count         (debug_fft_in),
      .fft_output_count        (debug_fft_out),
      .observation_count       (debug_obs),
      .weight_count            (debug_weights),
      .cfo_context_occupancy   (),
      .fine_context_occupancy  (),
      .fft_owned               (),
      .fft_error               ()
  );
  wire [31:0] ctx_frame = ctx_data[187:156], ctx_gen = ctx_data[155:124];
  wire [63:0] ctx_raw = ctx_data[123:60];
  wire signed [32:0] timing_offset = $signed(
      {stored_fine.value[31], stored_fine.value}
  ) - $signed(
      {ctx_data[59], ctx_data[59:28]}
  );
  wire identity_good = ctx_frame == initial_result.frame_id && ctx_frame == stored_fine.frame_id;
  // T05 fine timing carries kind 3; T06 initial SFO carries kind 4.
  wire numeric_good = initial_result.status == 16'h4800 && stored_fine.status == 16'h3800 &&
      timing_offset >= -33'sd101 && timing_offset <= 33'sd101;
  wire joined = ctx_v && fc_v && initial_result_valid;
  wire transport_ctx_v, transport_ctx_r;
  wire [235:0] transport_ctx_data;
  assign transport_ctx_v = !reset125 && !system_fault && joined && identity_good && numeric_good && dispatch_done_ready;
  assign transport_ctx_data = {
    ctx_frame,
    ctx_gen,
    ctx_raw,
    timing_offset[31:0],
    ctx_data[27:0],
    initial_result.value,
    initial_result.status
  };
  wire consume_join = transport_ctx_v && transport_ctx_r;
  assign ctx_r = consume_join;
  assign fc_r = consume_join;
  assign initial_result_ready = consume_join;
  wire qcv, qcr, qrv, qrr, qdv, qdr, qmv, qmr, qcancel, qbusy;
  wire [221:0] qcw;
  wire [101:0] qrw;
  wire [234:0] qdw;
  wire [159:0] qmw;
  wire progress_v,progress_r,cfg_streaming;
  wire [99:0] progress_record;
  sfo_residual_estimator4 #(.PROGRESSIVE_SOURCE(SHARED_RAW_INPUT)) residual_estimator (
      .clk               (clk125),
      .clk500            (clk500),
      .rst               (reset125),
      .abort             (system_fault || abort125),
      .cfg_streaming(cfg_streaming),.source_progress_valid(progress_v),.source_progress_ready(progress_r),.source_progress_record(progress_record),
      .cfg_valid         (qcv),
      .cfg_ready         (qcr),
      .cfg_descriptor    (qcw),
      .req_valid         (qrv),
      .req_ready         (qrr),
      .req_word          (qrw),
      .s_valid           (qdv),
      .s_ready           (qdr),
      .s_word            (qdw),
      .m_valid           (qmv),
      .m_ready           (qmr),
      .m_result          (qmw),
      .point_valid       (residual_point_valid),
      .point_record      (residual_point_record),
      .window_done_valid (),
      .window_done_record(),
      .m_diagnostic      (),
      .cancel            (qcancel),
      .busy              (qbusy)
  );
  sfo_two_pass_transport #(
      .REQUIRE_CONTEXT_ACK(REQUIRE_CONTEXT_ACK),
      .SHARED_RAW_INPUT(SHARED_RAW_INPUT),
      .PROCESSING_LIMIT_CYCLES(PROCESSING_LIMIT_CYCLES),
      .OUTPUT_CLOCK_MHZ(OUTPUT_CLOCK_MHZ)
  ) two_pass_transport (
      .first_context_valid(first_context_valid),.first_context_ready(first_context_ready),.first_context_record(first_context_record),
      .second_context_valid(second_context_valid),.second_context_ready(second_context_ready),.second_context_record(second_context_record),
      .raw_event_valid(raw_event_valid),.raw_event_ready(raw_event_ready),.raw_event_record(raw_event_record),
      .training_cfg_valid(training_cfg_v),.training_cfg_ready(training_cfg_r),.training_cfg_record(training_cfg_w),
      .training_data_valid(training_data_v),.training_data_ready(training_data_r),.training_data_record(training_data_w),
      .training_release_valid(training_release_v),.training_release_ready(training_release_r),.training_release_record(training_release_w),
      .clk125                (clk125),
      .clk150                (clk150),
      .reset_request         (reset_request),
      .abort125              (abort125 || control_fault),
      .abort150(SHARED_RAW_INPUT?abort150:1'b0),
      .s_valid               (s_valid),
      .s_ready               (s_ready),
      .s_data                (s_data),
      .context_valid         (transport_ctx_v),
      .context_ready         (transport_ctx_r),
      .context_record        (transport_ctx_data),
      .residual_cfg_streaming(cfg_streaming),.residual_progress_valid(progress_v),.residual_progress_ready(progress_r),.residual_progress_record(progress_record),
      .residual_cfg_valid    (qcv),
      .residual_cfg_ready    (qcr),
      .residual_cfg_record   (qcw),
      .residual_req_valid    (qrv),
      .residual_req_ready    (qrr),
      .residual_req_record   (qrw),
      .residual_data_valid   (qdv),
      .residual_data_ready   (qdr),
      .residual_data_record  (qdw),
      .residual_result_valid (qmv),
      .residual_result_ready (qmr),
      .residual_result_record(qmw),
      .m_valid               (m_valid),
      .m_ready               (m_ready),
      .m_record              (m_record),
      .m_reset               (m_reset),
      .m_fault               (m_fault),
      .reset125              (reset125),
      .fault125              (transport_fault),
      .first_error150        (error_code150),
      .diagnostic            (diagnostic),
      .debug150              (debug150),
      .debug_e1_valid        (debug_e1_valid),
      .debug_e1_data         (debug_e1_data),
      .debug_e1_beat         (debug_e1_beat),
      .debug_e1_last         (debug_e1_last)
  );
  assign fault = !reset125 && system_fault;
  always_ff @(posedge clk125) begin
    if (reset125) begin
      control_fault   <= 0;
      error_code125   <= 0;
      context_history <= 0;
      previous_frame  <= 0;
    end else begin
      if (selected_fv && selected_fr) begin
        context_history <= 1;
        previous_frame  <= selected_fw[187:156];
      end
      if (!control_fault) begin
        if (abort125) begin
          control_fault <= 1;
          error_code125 <= 1;
        end else if (ctx_error || fc_error) begin
          control_fault <= 1;
          error_code125 <= 2;
        end else if (SHARED_RAW_INPUT==0 && s_valid && s_ready && s_lane_valid != 4'hf) begin
          control_fault <= 1;
          error_code125 <= 3;
        end else if (selected_fv && selected_fr && context_history &&
                     selected_fw[187:156] <= previous_frame) begin
          control_fault <= 1;
          error_code125 <= 4;
        end else if (joined && !identity_good) begin
          control_fault <= 1;
          error_code125 <= 5;
        end else if (joined && !numeric_good) begin
          control_fault <= 1;
          error_code125 <= 6;
        end else if (dispatch_fault) begin
          control_fault <= 1;
          error_code125 <= 8;
        end else if (initial_halted) begin
          control_fault <= 1;
          error_code125 <= 7;
        end
      end
    end
  end

  logic [31:0] dbg_raw, dbg_points, dbg_requests;
  logic dbg_seen1, dbg_seen2;
  logic [ 95:0] dbg_first;
  logic [159:0] dbg_second;
  always_ff @(posedge clk125) begin
    if (reset125) begin
      dbg_raw <= 0;
      dbg_points <= 0;
      dbg_requests <= 0;
      dbg_seen1 <= 0;
      dbg_seen2 <= 0;
      dbg_first <= 0;
      dbg_second <= 0;
    end else begin
      if (s_valid && s_ready) dbg_raw <= dbg_raw + 1'b1;
      if (residual_point_valid) dbg_points <= dbg_points + 1'b1;
      if (qrv && qrr) dbg_requests <= dbg_requests + 1'b1;
      if (initial_result_valid) begin
        dbg_first <= initial_result;
        dbg_seen1 <= 1;
      end
      if (qmv) begin
        dbg_second <= qmw;
        dbg_seen2  <= 1;
      end
    end
  end
  assign debug125[0*32+:32]  = dbg_raw;
  assign debug125[1*32+:32]  = {27'd0, fault, qbusy, initial_halted, dbg_seen2, dbg_seen1};
  assign debug125[2*32+:32]  = dbg_first[95:64];
  assign debug125[3*32+:32]  = dbg_first[63:32];
  assign debug125[4*32+:32]  = dbg_first[31:0];
  assign debug125[5*32+:32]  = dbg_second[69:38];
  assign debug125[6*32+:32]  = dbg_second[37:6];
  assign debug125[7*32+:32]  = dbg_second[159:128];
  assign debug125[8*32+:32]  = dbg_second[127:96];
  assign debug125[9*32+:32]  = debug_elapsed;
  assign debug125[10*32+:32] = {3'd0, debug_fft_out, 3'd0, debug_fft_in};
  assign debug125[11*32+:32] = {3'd0, debug_weights, 3'd0, debug_obs};
  assign debug125[12*32+:32] = dbg_second[95:64];
  assign debug125[13*32+:32] = dbg_points;
  assign debug125[14*32+:32] = dbg_requests;
  assign debug125[15*32+:32] = {10'd0, dbg_second[5:0], initial_error_stage, error_code125};
endmodule
