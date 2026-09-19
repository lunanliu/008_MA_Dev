// Dedicated main FFT + dedicated IFFT, with at most two windows in flight.
// Numerical operators and official FFT service wrappers are unchanged from CONN031.
// New integration prototype; standalone behavior does not imply timing or T09 PASS.
module sfo_residual_estimator4 #(parameter integer PROGRESSIVE_SOURCE=0) (
    input  logic         clk,
    input  logic         clk500,
    input  logic         rst,
    input  logic         abort,
    input wire cfg_streaming,
    input wire source_progress_valid,output wire source_progress_ready,input wire [99:0] source_progress_record,
    input  logic         cfg_valid,
    output logic         cfg_ready,
    input  logic [221:0] cfg_descriptor,
    output logic         req_valid,
    input  logic         req_ready,
    output logic [101:0] req_word,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [234:0] s_word,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [159:0] m_result,
    output logic         point_valid,
    output logic [128:0] point_record,
    output logic         window_done_valid,
    output logic [ 96:0] window_done_record,
    output logic [ 31:0] m_diagnostic,
    output logic         cancel,
    output logic         busy
);
  localparam [2:0] BOOT = 0, IDLE = 1, ARM = 2, RUN = 3, FLUSH = 4, DONE = 5, HALT = 6, WAIT_COMMIT=7;
  logic [2:0] state;
  logic [4:0] reset_count;
  logic [18:0] frame_age;
  logic [221:0] descriptor;
  logic streaming_mode,commit_seen;
  logic [18:0] expected_window_end;
  wire [31:0] tag = descriptor[221:190], generation = descriptor[189:158];
  wire active = state == ARM || state == RUN;
  wire child_reset = rst || state == BOOT || state == FLUSH || state == HALT;
  logic [6:0] front_issued, front_committed, aux_started, aux_completed, point_count;
  wire [6:0] inflight_windows = front_issued - point_count;
  logic front_inflight, aux_inflight;
  logic [12:0] aux_age;
  logic [3:0] frame_error;
  logic [7:0] frame_detail;
  logic signed [31:0] ppm;
  logic [31:0] step;
  logic [4:0] quality;
  logic estimate_valid;
  logic fv, fr, fdv, fdr, fbusy, fcancel;
  logic [208:0] fw;
  logic [ 96:0] fdone;
  logic [  7:0] fsource;
  logic [  5:0] funused;
  logic fcfgv, fcfgr, freqv, fsready;
  logic qav, qar, qcv, qcr, qpv, qv, qr, qfill, qerror;
  logic [ 70:0] qidentity;
  logic [208:0] qw;
  logic [1:0] qcount, qreserved;
  logic bfv, bfr, bwv, bwr, bv, br, bbusy;
  logic [139:0] bresult;
  logic pe, pvalid;
  logic [31:0] ptag;
  logic [6:0] pslot;
  logic [10:0] pbin;
  logic signed [17:0] pdelta;
  logic signed [23:0] pdelay;
  logic [3:0] pquality;
  logic [6:0] aux_slot;
  logic [9:0] aux_input_count, aux_output_count;
  logic aux_status_seen, aux_point_seen, aux_done_emitted;
  logic av, ar, ov, orr, ol, astatus;
  logic [127:0] od;
  logic [5:0] aerrors;
  logic backend_ready;
  wire front_start = fcfgv && fcfgr;
  wire progress_owner=source_progress_record[97:66]==tag&&source_progress_record[65:34]==generation;
  wire window_good=progress_owner&&source_progress_record[99:98]==0&&source_progress_record[33:27]==front_issued&&
    front_issued<74&&source_progress_record[26:8]==expected_window_end&&source_progress_record[7:0]==0;
  wire commit_good=progress_owner&&source_progress_record[99:98]==1&&source_progress_record[33:27]==74&&
    front_issued==74&&source_progress_record[26:8]==334098&&source_progress_record[7:0]==0&&!commit_seen;
  wire progress_active=streaming_mode&&!commit_seen&&(state==RUN||state==WAIT_COMMIT);
  wire progress_bad=progress_active&&source_progress_valid&&!(window_good||commit_good);
  wire commit_fire=source_progress_valid&&source_progress_ready&&commit_good;
  assign source_progress_ready=!rst&&!abort&&progress_active&&(commit_good||(window_good&&front_start));
  wire pure_producer_wait=streaming_mode&&state==RUN&&front_issued<74&&!source_progress_valid&&
    !front_inflight&&!aux_inflight&&qreserved==0&&front_issued==point_count&&fcfgr&&bwr&&qar;
  wire [31:0] available_window_last={11'd0,expected_window_end,2'b00}-32'd37;
  wire [221:0] window_descriptor=streaming_mode?{descriptor[221:64],-32'sd36,available_window_last}:descriptor;

  wire front_finish = fdv && fdr;
  wire aux_start = bwv && bwr;
  wire qfire = qv && qr;
  wire dfire = ov && orr;
  wire front_bad = fdv && (fdone[25:18] != 0 || fdone[96:26] !=
                           {tag, generation, 7'(front_committed)} || fdone[9:0] != 512);
  wire aux_finish = aux_inflight && aux_input_count == 512 && aux_output_count == 512 &&
      aux_status_seen && !aux_done_emitted;
  assign cfg_ready = !rst && !abort && state == IDLE && fcfgr && qreserved == 0 && !aux_inflight;
  assign busy = state != IDLE || fbusy;
  assign req_valid = freqv && !cancel;
  assign s_ready = fsready && !cancel;
  assign cancel = child_reset || (active && abort);
  assign m_valid = !rst && state == DONE;
  // Window count is the number launched into the front stage, including an unfinished
  // prefetched window on failure. Point count is the number actually accepted by LS.
  assign m_result = {
    tag,
    generation,
    front_issued,
    point_count,
    frame_error,
    frame_detail,
    ppm,
    step,
    quality,
    estimate_valid
  };
  assign point_valid = !child_reset && pe;
  assign point_record = {ptag, generation, pslot, pbin, pdelta, pdelay, pquality, pvalid};
  assign fcfgv = state == RUN && !abort && !front_inflight && front_issued < 74 &&
      inflight_windows < 2 && qar && (!streaming_mode||(source_progress_valid&&window_good));
  assign qav = fcfgv && fcfgr;
  assign qcv = state == RUN && !abort && front_inflight && fdv && !front_bad;
  assign fdr = state == RUN && !abort && (front_bad || qcr);
  assign bfv = state == ARM && !abort;
  assign bwv = state == RUN && !abort && !aux_inflight && qpv;
  assign br = state == RUN && !abort;
  assign av = state == RUN && !abort && aux_inflight && aux_input_count < 512 && qv;
  assign qr = state == RUN && !abort && aux_inflight && aux_input_count < 512 && ar;
  assign orr = state == RUN && !abort && aux_inflight && backend_ready;
  wire dv = ov && aux_inflight && state == RUN && !abort;
  wire dr = orr;
  wire [208:0] dw = {tag, generation, aux_slot, aux_output_count[8:0], ol, od};
  sfo_residual_fft_grid_stage4 #(.PROGRESSIVE_SOURCE(PROGRESSIVE_SOURCE)) front_stage (
      .clk              (clk),
      .clk500           (clk500),
      .rst              (child_reset),
      .abort            (1'b0),
      .cfg_valid        (fcfgv),
      .cfg_ready        (fcfgr),
      .cfg_descriptor   ({window_descriptor, front_issued}),
      .cfg_window_granted(streaming_mode),
      .req_valid        (freqv),
      .req_ready        (req_ready && !cancel),
      .req_word         (req_word),
      .s_valid          (s_valid && !cancel),
      .s_ready          (fsready),
      .s_word           (s_word),
      .m_valid          (fv),
      .m_ready          (fr),
      .m_word           (fw),
      .done_valid       (fdv),
      .done_ready       (fdr),
      .done_word        (fdone),
      .done_source_error(fsource),
      .done_aux_errors  (funused),
      .cancel           (fcancel),
      .busy             (fbusy)
  );
  sfo_residual_grid_packet_queue2 queue (
      .clk            (clk),
      .rst            (child_reset),
      .alloc_valid    (qav),
      .alloc_ready    (qar),
      .alloc_identity ({tag, generation, front_issued}),
      .s_valid        (fv),
      .s_ready        (fr),
      .s_word         (fw),
      .commit_valid   (qcv),
      .commit_ready   (qcr),
      .packet_valid   (qpv),
      .packet_identity(qidentity),
      .m_valid        (qv),
      .m_ready        (qr),
      .m_word         (qw),
      .committed_count(qcount),
      .fill_active    (qfill),
      .reserved_count (qreserved),
      .error          (qerror)
  );
  sfo_residual_ifft_service4 aux_service (
      .clk_125            (clk),
      .clk_500            (clk500),
      .rst_n              (!child_reset),
      .s_valid            (av),
      .s_ready            (ar),
      .s_data             (qw[127:0]),
      .s_transaction_end  (qw[128]),
      .m_valid            (ov),
      .m_ready            (orr),
      .m_data             (od),
      .m_transaction_end  (ol),
      .ingress_overflow   (aerrors[0]),
      .ingress_underflow  (aerrors[1]),
      .egress_overflow    (aerrors[2]),
      .egress_underflow   (aerrors[3]),
      .xfft_protocol_error(aerrors[4]),
      .xfft_overflow      (aerrors[5]),
      .status_valid       (astatus)
  );
  sfo_residual_delay_backend4 #(.ALLOW_SOURCE_WAIT(PROGRESSIVE_SOURCE)) backend (
      .clk                (clk),
      .rst                (child_reset),
      .abort              (1'b0),
      .source_wait(pure_producer_wait),
      .frame_valid        (bfv),
      .frame_ready        (bfr),
      .frame_tag          (tag),
      .window_valid       (bwv),
      .window_ready       (bwr),
      .window_slot        (qidentity[6:0]),
      .window_tag         (qidentity[70:39]),
      .s_valid            (ov && aux_inflight && state == RUN && !abort),
      .s_ready            (backend_ready),
      .s_data             (od),
      .s_symbol_slot      (aux_slot),
      .s_beat             (aux_output_count[8:0]),
      .s_tag              (tag),
      .s_last             (ol),
      .s_error            (4'd0),
      .m_valid            (bv),
      .m_ready            (br),
      .m_tag              (bresult[139:108]),
      .m_count            (bresult[107:101]),
      .m_window_count     (bresult[100:94]),
      .m_data_count       (bresult[93:78]),
      .m_error            (bresult[77:74]),
      .m_detail           (bresult[73:70]),
      .m_ppm_q18          (bresult[69:38]),
      .m_step_q28         (bresult[37:6]),
      .m_quality_flags    (bresult[5:1]),
      .m_estimate_valid   (bresult[0]),
      .busy               (bbusy),
      .point_event        (pe),
      .point_tag          (ptag),
      .point_slot         (pslot),
      .point_peak_bin     (pbin),
      .point_delta_q16    (pdelta),
      .point_delay_q16    (pdelay),
      .point_quality_flags(pquality),
      .point_quality_valid(pvalid)
  );
  task automatic fail_frame(input logic [3:0] code, input logic [7:0] detail,
                            input logic [31:0] diagnostic);
    begin
      frame_error <= code;
      frame_detail <= detail;
      m_diagnostic <= diagnostic;
      ppm <= 0;
      step <= 32'd268435456;
      quality <= 0;
      estimate_valid <= 0;
      reset_count <= 0;
      state <= FLUSH;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= BOOT;
      reset_count <= 0;
      frame_age <= 0;
      descriptor <= 0;streaming_mode<=0;commit_seen<=0;expected_window_end<=7017;
      front_issued <= 0;
      front_committed <= 0;
      aux_started <= 0;
      aux_completed <= 0;
      point_count <= 0;
      front_inflight <= 0;
      aux_inflight <= 0;
      aux_age <= 0;
      aux_slot <= 0;
      aux_input_count <= 0;
      aux_output_count <= 0;
      aux_status_seen <= 0;
      aux_point_seen <= 0;
      aux_done_emitted <= 0;
      frame_error <= 0;
      frame_detail <= 0;
      ppm <= 0;
      step <= 32'd268435456;
      quality <= 0;
      estimate_valid <= 0;
      m_diagnostic <= 0;
      window_done_valid <= 0;
      window_done_record <= 0;
    end else begin
      window_done_valid <= 0;
      if (active&&!pure_producer_wait) frame_age <= frame_age + 1;
      if(commit_fire)commit_seen<=1;
      if (aux_inflight) aux_age <= aux_age + 1;
      if (state == BOOT) begin
        if (reset_count == 31) state <= IDLE;
        else reset_count <= reset_count + 1;
      end else if (state == FLUSH) begin
        front_inflight <= 0;
        aux_inflight   <= 0;
        if (reset_count == 31) state <= DONE;
        else reset_count <= reset_count + 1;
      end else
      if (state == HALT) begin
      end else if (state == DONE) begin
        if (m_ready) state <= frame_error == 0 ? IDLE : HALT;
      end else if (state == IDLE) begin
        if (cfg_valid && cfg_ready) begin
          descriptor <= cfg_descriptor;
          streaming_mode<=PROGRESSIVE_SOURCE&&cfg_streaming;commit_seen<=0;expected_window_end<=7017;
          frame_age <= 0;
          front_issued <= 0;
          front_committed <= 0;
          aux_started <= 0;
          aux_completed <= 0;
          point_count <= 0;
          front_inflight <= 0;
          aux_inflight <= 0;
          aux_age <= 0;
          frame_error <= 0;
          frame_detail <= 0;
          m_diagnostic <= 0;
          ppm <= 0;
          step <= 32'd268435456;
          quality <= 0;
          estimate_valid <= 0;
          aux_input_count <= 0;
          aux_output_count <= 0;
          aux_status_seen <= 0;
          aux_point_seen <= 0;
          aux_done_emitted <= 0;
          state <= ARM;
          if ((!cfg_descriptor[93]&&!(PROGRESSIVE_SOURCE&&cfg_streaming)) || cfg_descriptor[92:85] != 0) fail_frame(1, 1, 0);
          else if (cfg_descriptor[221:190] != cfg_descriptor[157:126] ||
                   cfg_descriptor[189:158] != cfg_descriptor[125:94])
            fail_frame(1, 2, 0);
          else if (cfg_descriptor[84:64] != 21'd1336320) fail_frame(1, 3, 0);
          else if (!(PROGRESSIVE_SOURCE&&cfg_streaming)&&($signed(cfg_descriptor[63:32]) > 0 || $signed(cfg_descriptor[31:0]) < 1336319))
            fail_frame(1, 4, 0);
        end
      end else if (abort) fail_frame(5, 0, 0);
      else if (progress_bad) fail_frame(1, 8'h41, 0);
      else if (state==WAIT_COMMIT)begin
        if(qerror)fail_frame(3,8'h20,32'h20000000);
        else if(|aerrors)fail_frame(2,8'h30,{8'h30,8'd0,8'd0,aerrors,2'd0});
        else if(commit_seen||commit_fire)state<=DONE;
      end
      else if (frame_age >= 332999) fail_frame(7, 0, 0);
      else if (front_bad) fail_frame(2, fdone[25:18], {fdone[25:18], fdone[17:10], fsource, 8'd0});
      else if (qerror || inflight_windows > 2) fail_frame(3, 8'h20, 32'h20000000);
      else if (|aerrors) fail_frame(2, 8'h30, {8'h30, 8'd0, 8'd0, aerrors, 2'd0});
      else if (aux_inflight && aux_age >= 4479) fail_frame(6, 1, 0);
      else if (astatus && (!aux_inflight || aux_status_seen)) fail_frame(3, 8'h21, 0);
      else if (aux_start && (qidentity != {tag, generation, aux_started} || aux_started >= 74))
        fail_frame(3, 8'h22, 0);
      else if (qfire && (qw[208:138] != {tag, generation, aux_slot} || qw[137:129] !=
                         aux_input_count[8:0] || qw[128] != (aux_input_count == 511)))
        fail_frame(3, 8'h23, 0);
      else if (dfire && (aux_output_count >= 512 || ol != (aux_output_count == 511)))
        fail_frame(3, 8'h24, 0);
      else if (pe && (!aux_inflight || aux_point_seen || {ptag, pslot} != {tag, aux_slot} ||
                      pslot != point_count))
        fail_frame(3, 8'h25, 0);
      else if (bv && bresult[77:74] != 0) fail_frame(4, {bresult[77:74], bresult[73:70]}, 0);
      else begin
        if (state == ARM && bfr) state <= RUN;
        if (front_start) begin
          front_issued   <= front_issued + 1;expected_window_end<=expected_window_end+19'd4480;
          front_inflight <= 1;
        end
        if (front_finish) begin
          front_committed <= front_committed + 1;
          front_inflight  <= 0;
        end
        if (aux_start) begin
          aux_inflight <= 1;
          aux_slot <= qidentity[6:0];
          aux_started <= aux_started + 1;
          aux_age <= 0;
          aux_input_count <= 0;
          aux_output_count <= 0;
          aux_status_seen <= 0;
          aux_point_seen <= 0;
          aux_done_emitted <= 0;
        end
        if (qfire) aux_input_count <= aux_input_count + 1;
        if (dfire) aux_output_count <= aux_output_count + 1;
        if (astatus) aux_status_seen <= 1;
        if (pe) begin
          point_count <= point_count + 1;
          aux_point_seen <= 1;
        end
        if (aux_finish) begin
          aux_done_emitted <= 1;
          aux_completed <= aux_completed + 1;
          window_done_valid <= 1;
          window_done_record <= {tag, generation, aux_slot, 8'd0, 8'd0, 10'd512};
        end
        if (aux_inflight && aux_done_emitted && aux_point_seen) aux_inflight <= 0;
        if (bv) begin
          if (bresult[139:108] != tag || bresult[107:101] != 74 || bresult[100:94] != 74 || bresult[
              93:78] != 16'd37888 || front_issued != 74 || front_committed != 74 || aux_completed !=
              74 || point_count != 74 || qreserved != 0 || front_inflight || aux_inflight)
            fail_frame(3, 8'h26, 0);
          else begin
            ppm <= bresult[69:38];
            step <= bresult[37:6];
            quality <= bresult[5:1];
            estimate_valid <= bresult[0];
            state <= streaming_mode&&!commit_seen&&!commit_fire?WAIT_COMMIT:DONE;
          end
        end
      end
    end
  end
endmodule
