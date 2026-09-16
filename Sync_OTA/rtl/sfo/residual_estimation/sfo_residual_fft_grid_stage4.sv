// One front-stage window: nominal input -> main FFT -> pilots -> normalized sparse grid.
// No IFFT instance: the committed packet queue decouples this stage from the back stage.
module sfo_residual_fft_grid_stage4 (
    input  logic         clk,
    input  logic         clk500,
    input  logic         rst,
    input  logic         abort,
    input  logic         cfg_valid,
    output logic         cfg_ready,
    input  logic [228:0] cfg_descriptor,
    output logic         req_valid,
    input  logic         req_ready,
    output logic [101:0] req_word,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [234:0] s_word,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [208:0] m_word,
    output logic         done_valid,
    input  logic         done_ready,
    output logic [ 96:0] done_word,
    output logic [  7:0] done_source_error,
    output logic [  5:0] done_aux_errors,
    output logic         cancel,
    output logic         busy
);
  localparam [2:0] BOOT = 0, IDLE = 1, SETUP = 2, RUN = 3, FLUSH = 4, DONE = 5, HALT = 6;
  logic [  2:0] state;
  logic [  4:0] reset_count;
  logic [ 12:0] age;
  logic [228:0] descriptor;
  logic main_armed, grid_armed, main_seen, grid_seen;
  logic [9:0] dtp_count;
  logic [7:0] error_code, error_detail;
  wire [31:0] tag = descriptor[228:197], generation = descriptor[196:165];
  wire [6:0] slot = descriptor[6:0];
  wire active = state == SETUP || state == RUN;
  wire child_reset = rst || state == BOOT || state == FLUSH || state == HALT;
  wire timed_out = active && age >= 4999;
  logic source_ready, request_valid;
  logic main_cfg_ready, main_cancel, main_busy, mv, mr, ml;
  logic [127:0] md;
  logic [31:0] mt, mg;
  logic [6:0] ms;
  logic [8:0] mb;
  logic mdv;
  logic [31:0] mdt, mdg;
  logic [6:0] mds;
  logic [3:0] mde;
  logic [7:0] mdd, mdse;
  logic [9:0] mdsrc, mdin, mdout;
  logic mdstatus;
  logic fv, fr, fe, fb, front_ready;
  logic [71:0] fd;
  logic [ 1:0] fm;
  logic [ 6:0] fs;
  logic [ 8:0] fbeat;
  logic [31:0] ft;
  logic cr, gv, gr, gl, gb;
  logic [127:0] gd;
  logic [6:0] gs;
  logic [8:0] gbeat;
  logic [31:0] gt;
  logic signed [4:0] gain;
  logic gdv;
  logic [3:0] gde;
  logic [6:0] gds;
  logic [31:0] gdt;
  logic signed [4:0] gdgain;
  logic [9:0] gdi, gdo, gdp;
  wire [5:0] errors = 6'd0;
  wire stop_data = child_reset || (active && (abort || timed_out || main_cancel || (|errors)));
  assign cancel = stop_data;
  assign req_valid = request_valid && !stop_data;
  assign s_ready = source_ready && !stop_data;
  assign cfg_ready = !rst && !abort && state == IDLE && main_cfg_ready && cr;
  assign busy = state != IDLE || !main_cfg_ready;
  assign m_valid = state == RUN && !stop_data && gv;
  assign gr = state == RUN && !stop_data && m_ready;
  assign m_word = {tag, generation, slot, gbeat, gl, gd};
  assign done_valid = !rst && state == DONE;
  assign done_word = {tag, generation, slot, error_code, error_detail, dtp_count};
  sfo_residual_fft_window4 main (
      .clk                  (clk),
      .clk500               (clk500),
      .rst                  (child_reset),
      .abort                (1'b0),
      .cfg_valid            (state == SETUP && !main_armed && !stop_data),
      .cfg_ready            (main_cfg_ready),
      .cfg_frame_id         (descriptor[228:197]),
      .cfg_generation       (descriptor[196:165]),
      .cfg_source_frame_id  (descriptor[164:133]),
      .cfg_source_generation(descriptor[132:101]),
      .cfg_source_complete  (descriptor[100]),
      .cfg_source_error     (descriptor[99:92]),
      .cfg_nominal_length   (descriptor[91:71]),
      .cfg_available_first  (descriptor[70:39]),
      .cfg_available_last   (descriptor[38:7]),
      .cfg_symbol_slot      (slot),
      .req_valid            (request_valid),
      .req_ready            (req_ready && !stop_data),
      .req_frame_id         (req_word[101:70]),
      .req_generation       (req_word[69:38]),
      .req_symbol_slot      (req_word[37:31]),
      .req_start_index      (req_word[30:10]),
      .req_beats            (req_word[9:0]),
      .s_valid              (s_valid && !stop_data),
      .s_ready              (source_ready),
      .s_frame_id           (s_word[234:203]),
      .s_generation         (s_word[202:171]),
      .s_sample_index       (s_word[170:150]),
      .s_beat               (s_word[149:141]),
      .s_lane_mask          (s_word[140:137]),
      .s_last               (s_word[136]),
      .s_error              (s_word[135:128]),
      .s_data               (s_word[127:0]),
      .m_valid              (mv),
      .m_ready              (mr),
      .m_frame_id           (mt),
      .m_generation         (mg),
      .m_symbol_slot        (ms),
      .m_fft_beat           (mb),
      .m_last               (ml),
      .m_data               (md),
      .done_valid           (mdv),
      .done_ready           (active && !stop_data),
      .done_frame_id        (mdt),
      .done_generation      (mdg),
      .done_symbol_slot     (mds),
      .done_error           (mde),
      .done_detail          (mdd),
      .done_source_error    (mdse),
      .done_source_count    (mdsrc),
      .done_fft_input_count (mdin),
      .done_fft_output_count(mdout),
      .done_status_seen     (mdstatus),
      .cancel               (main_cancel),
      .busy                 (main_busy)
  );
  assign mr = state == RUN && !stop_data && front_ready;
  sfo_residual_pilot_front2 front (
      .clk          (clk),
      .rst          (child_reset),
      .s_valid      (mv && state == RUN && !stop_data),
      .s_ready      (front_ready),
      .s_data       (md),
      .s_symbol_slot(ms),
      .s_fft_beat   (mb),
      .s_tag        (mt),
      .m_valid      (fv),
      .m_ready      (fr),
      .m_data       (fd),
      .m_mask       (fm),
      .m_error      (fe),
      .m_symbol_slot(fs),
      .m_fft_beat   (fbeat),
      .m_tag        (ft),
      .busy         (fb)
  );
  sfo_residual_pilot_grid4 grid (
      .clk              (clk),
      .rst              (child_reset),
      .abort            (1'b0),
      .cfg_valid        (state == SETUP && !grid_armed && !stop_data),
      .cfg_ready        (cr),
      .cfg_symbol_slot  (slot),
      .cfg_tag          (tag),
      .s_valid          (fv && !stop_data),
      .s_ready          (fr),
      .s_data           (fd),
      .s_mask           (fm),
      .s_error          (fe),
      .s_symbol_slot    (fs),
      .s_fft_beat       (fbeat),
      .s_tag            (ft),
      .m_valid          (gv),
      .m_ready          (gr),
      .m_data           (gd),
      .m_symbol_slot    (gs),
      .m_fft_beat       (gbeat),
      .m_tag            (gt),
      .m_gain           (gain),
      .m_last           (gl),
      .done_valid       (gdv),
      .done_ready       (active && !stop_data),
      .done_error       (gde),
      .done_symbol_slot (gds),
      .done_tag         (gdt),
      .done_gain        (gdgain),
      .done_input_beats (gdi),
      .done_output_beats(gdo),
      .done_pilot_count (gdp),
      .busy             (gb)
  );
  task automatic fail_window(input logic [7:0] code, input logic [7:0] detail);
    begin
      error_code <= code;
      error_detail <= detail;
      reset_count <= 0;
      state <= FLUSH;
      done_aux_errors <= errors;
      done_source_error <= mdse;
    end
  endtask
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= BOOT;
      reset_count <= 0;
      age <= 0;
      descriptor <= 0;
      main_armed <= 0;
      grid_armed <= 0;
      main_seen <= 0;
      grid_seen <= 0;
      dtp_count <= 0;
      error_code <= 0;
      error_detail <= 0;
      done_source_error <= 0;
      done_aux_errors <= 0;
    end else begin
      if (active) age <= age + 1;
      if (state == BOOT) begin
        if (reset_count == 31) state <= IDLE;
        else reset_count <= reset_count + 1;
      end else if (state == FLUSH) begin
        if (reset_count == 31) state <= DONE;
        else reset_count <= reset_count + 1;
      end else
      if (state == HALT) begin
      end else if (state == DONE) begin
        if (done_ready) state <= error_code == 0 ? IDLE : HALT;
      end else if (state == IDLE) begin
        if (cfg_valid && cfg_ready) begin
          descriptor <= cfg_descriptor;
          main_armed <= 0;
          grid_armed <= 0;
          main_seen <= 0;
          grid_seen <= 0;
          age <= 0;
          dtp_count <= 0;
          error_code <= 0;
          error_detail <= 0;
          done_source_error <= 0;
          done_aux_errors <= 0;
          state <= SETUP;
        end
      end else if (abort) fail_window(8'h60, 0);
      else if (mde != 0 && (main_cancel || mdv)) fail_window(8'h10 | {4'd0, mde}, mdd);
      else if (|errors) fail_window(8'h30, {2'd0, errors});
      else if (gdv && gde != 0) fail_window(8'h20 | {4'd0, gde}, 0);
      else if (timed_out) fail_window(8'h50, 0);
      else if (mdv && !stop_data && (main_seen || {mdt, mdg, mds} != {tag, generation, slot} ||
                                     mdsrc != 512 || mdin != 512 || mdout != 512 || !mdstatus))
        fail_window(8'h40, 1);
      else if (gdv && !stop_data &&
               (grid_seen || {gdt, gds} != {tag, slot} || gdi != 512 || gdo != 512 || gdp != 820))
        fail_window(8'h40, 2);
      else if (m_valid && m_ready && (dtp_count >= 512 || gl != (dtp_count == 511) ||
                                      gbeat != dtp_count[8:0] || {gt, gs} != {tag, slot}))
        fail_window(8'h40, 4);
      else begin
        if (mdv && !stop_data) main_seen <= 1;
        if (gdv && !stop_data) grid_seen <= 1;
        if (m_valid && m_ready) dtp_count <= dtp_count + 1;
        case (state)
          SETUP: begin
            if (!main_armed && main_cfg_ready && !stop_data) main_armed <= 1;
            if (!grid_armed && cr && !stop_data) grid_armed <= 1;
            if ((main_armed || main_cfg_ready) && (grid_armed || cr) && !stop_data) state <= RUN;
          end
          RUN: if (main_seen && grid_seen && dtp_count == 512) state <= DONE;
          default: fail_window(8'h70, 0);
        endcase
      end
    end
  end
endmodule
