`timescale 1ns/1ps
// Autonomous input: raw IQ plus transport/session controls only.
module sync_frontend_top #(
    parameter integer STREAM_BOUNDARIES=0,
    parameter string PS1_MEMORY_INIT_FILE = "fine_ps1_reference_16lane.mem"
) (
    input logic clk,
    input logic reset_n,
    input logic session_start, session_abort, stream_gap,
    // Terminal end of an independent replay segment; not a temporary pause.
    input wire segment_end,output wire segment_quiescent,
    input logic s_valid,
    output logic s_ready,
    input logic [127:0] s_data,
    output logic m_valid,
    input logic m_ready,
    output logic [287:0] m_result,
    output logic [63:0] accepted_samples,
    output logic [31:0] epoch,
    output logic [31:0] candidate_count, rejected_count, capture_drop_count,
    output logic [31:0] duplicate_count, confirmed_count,
    output logic [1:0] snapshot_occupancy, snapshot_peak,
    output logic [15:0] max_history_age, error_sticky,
    // Conservative raw ownership watermark, in accepted SAMPLE coordinates of
    // retention_epoch. The descriptor converter must retain its own pin until
    // the frame lease has entered the same ordered FIFO as subsequent floors.
    output wire retention_valid,
    output wire [31:0] retention_epoch,
    output logic [63:0] retention_floor_samples
);
    import bistatic_stream_pkg::*;
    (* ASYNC_REG="TRUE" *) logic [1:0] reset_release;
    logic rst_n, armed;
    logic [4:0] flush_count;
    logic core_rst_n, sample_fire, boundary;
    logic end_seen;logic [7:0] end_idle_cycles;
    always_ff @(posedge clk)begin
        if(!core_rst_n)begin end_seen<=0;end_idle_cycles<=0;end
        else if(STREAM_BOUNDARIES&&segment_end)begin end_seen<=1;end_idle_cycles<=0;end
        else if(sample_fire)begin end_seen<=0;end_idle_cycles<=0;end
        else if(end_seen&&end_idle_cycles!=255)end_idle_cycles<=end_idle_cycles+1'b1;
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) reset_release <= 0;
        else reset_release <= {reset_release[0],1'b1};
    end
    assign rst_n = reset_release[1];
    assign boundary = session_start || session_abort || stream_gap;
    assign core_rst_n = rst_n && armed && flush_count == 0 && !boundary;
    assign s_ready = core_rst_n;
    assign sample_fire = s_valid && s_ready;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            armed <= 1; flush_count <= 16; epoch <= 0;
        end else if (boundary) begin
            if (session_abort) armed <= 0;
            else if (session_start) armed <= 1;
            flush_count <= 16; epoch <= epoch+1'b1;
        end else if (flush_count != 0) flush_count <= flush_count-1'b1;
    end

    logic candidate_valid, detector_error;
    logic [63:0] candidate_anchor;
    logic [31:0] rejected_plateaus;
    logic metric_valid, metric_qualified;
    logic [63:0] metric_position;
    logic signed [42:0] metric_p_re, metric_p_im;
    logic [41:0] metric_energy;
    sync_continuous_detector acquisition (
        .clk(clk), .rst_n(core_rst_n), .sample_fire(sample_fire), .sample_data(s_data),
        .candidate_valid(candidate_valid), .candidate_anchor(candidate_anchor),
        .rejected_plateaus(rejected_plateaus), .arithmetic_error(detector_error),
        .metric_valid(metric_valid), .metric_qualified(metric_qualified),
        .metric_position(metric_position), .metric_p_re(metric_p_re),
        .metric_p_im(metric_p_im), .metric_energy(metric_energy)
    );

    logic [1:0] bank_used, bank_ready;
    logic [63:0] bank_anchor [0:1];
    logic [31:0] bank_candidate [0:1];
    logic copy_active, copy_started, copy_slot;
    logic [9:0] copy_request_count, copy_response_count;
    logic history_rd, history_rsp;
    logic [63:0] history_position, oldest_age;
    logic [127:0] history_data;
    logic snapshot_wr;
    logic [10:0] snapshot_wr_addr;
    assign history_position = bank_anchor[copy_slot]-64'd256+({54'd0,copy_request_count}<<2);
    assign oldest_age = accepted_samples-(bank_anchor[copy_slot]-64'd256);
    assign history_rd = core_rst_n && copy_active && copy_started && copy_request_count < 794;
    sync_beat_ram #(.ADDR_BITS(11)) raw_history (
        .clk(clk), .rst_n(core_rst_n), .wr_valid(sample_fire),
        .wr_addr(accepted_samples[12:2]), .wr_data(s_data),
        .rd_valid(history_rd), .rd_addr(history_position[12:2]),
        .rsp_valid(history_rsp), .rsp_data(history_data)
    );
    assign snapshot_wr = history_rsp && copy_active && copy_started;
    assign snapshot_wr_addr = {copy_slot,copy_response_count};

    typedef enum logic [2:0] {IDLE, RESET_ESTIMATORS, REPLAY, WAIT_RESULT, CHECK_COORD} worker_state_t;
    worker_state_t worker_state;
    logic worker_slot;
    logic [4:0] estimator_flush;
    logic [9:0] replay_request_count, replay_response_count;
    logic [16:0] worker_cycles;
    logic snapshot_rd, snapshot_rsp;
    logic [127:0] snapshot_data;
    logic [63:0] active_anchor;
    logic [31:0] active_candidate;
    logic [31:0] next_frame_id;
    logic last_confirmed_valid;
    logic [63:0] last_confirmed_position;
    logic choice;
    logic choice_is_duplicate;
    // Candidate IDs are modulo-2^32 tags, not chronological sequence numbers.
    // Accepted-sample anchors retain order across a candidate-counter wrap.
    assign choice = bank_ready[0] && bank_ready[1] ?
        (bank_anchor[1] < bank_anchor[0]) : !bank_ready[0];
    assign choice_is_duplicate = last_confirmed_valid &&
        ((bank_anchor[choice] >= last_confirmed_position && bank_anchor[choice]-last_confirmed_position < 4096) ||
         (bank_anchor[choice] < last_confirmed_position && last_confirmed_position-bank_anchor[choice] < 4096));
    assign snapshot_rd = core_rst_n && worker_state == REPLAY && replay_request_count < 794;
    sync_beat_ram #(.ADDR_BITS(11)) candidate_snapshots (
        .clk(clk), .rst_n(core_rst_n), .wr_valid(snapshot_wr),
        .wr_addr(snapshot_wr_addr), .wr_data(history_data),
        .rd_valid(snapshot_rd), .rd_addr({worker_slot,replay_request_count}),
        .rsp_valid(snapshot_rsp), .rsp_data(snapshot_data)
    );
    assign snapshot_occupancy = {1'b0,bank_used[0]}+{1'b0,bank_used[1]};

    logic estimator_rst_n;
    logic coarse_valid, coarse_ready, coarse_data_ready;
    bistatic_stream_metadata_t local_metadata;
    bistatic_estimator_result_t coarse_result, fine_result;
    logic fine_valid, fine_ready, fine_busy;
    logic [31:0] fine_service_cycles;
    logic coarse_deadline, coarse_protocol, coarse_service, coarse_arithmetic, coarse_ip;
    logic fine_deadline, fine_protocol, fine_arithmetic, fine_ip;
    logic [1:0] coarse_queued;
    logic signed [31:0] local_position, held_coarse_to, held_cfo;
    logic signed [64:0] fine_absolute, coarse_absolute;
    logic [15:0] confirmed_quality;
    logic [15:0] confirmed_status;
    assign estimator_rst_n = core_rst_n && worker_state != IDLE && worker_state != RESET_ESTIMATORS;
    assign local_position = $signed({20'd0,replay_response_count,2'b00})-32'sd256;
    always_comb begin
        local_metadata = '0;
        local_metadata.lane_valid = 4'hf;
        if (replay_response_count < 64) begin
            local_metadata.frame_id = active_candidate-1'b1;
            local_metadata.beat_base_sample_index = 1_336_064+({22'd0,replay_response_count}<<2);
            local_metadata.halo_or_guard = 1;
        end else begin
            local_metadata.frame_id = active_candidate;
            local_metadata.beat_base_sample_index = $unsigned(local_position);
            local_metadata.nominal_region = 1;
        end
    end
    to_coarse_estimator coarse_confirmation (
        .clk(clk), .rst_n(estimator_rst_n),
        .data_valid(snapshot_rsp && replay_response_count < 768),
        .data_ready(coarse_data_ready), .data(snapshot_data), .metadata(local_metadata),
        .estimator_result_valid(coarse_valid), .estimator_result_ready(coarse_ready),
        .estimator_result(coarse_result), .deadline_miss_sticky(coarse_deadline),
        .input_protocol_error_sticky(coarse_protocol), .result_service_error_sticky(coarse_service),
        .arithmetic_error_sticky(coarse_arithmetic), .arithmetic_ip_error_sticky(coarse_ip),
        .queued_result_pairs(coarse_queued)
    );
    to_fine_estimator #(.PS1_MEMORY_INIT_FILE(PS1_MEMORY_INIT_FILE)) fine_confirmation (
        .clk(clk), .rst_n(estimator_rst_n), .raw_tap_fire(snapshot_rsp),
        .raw_tap_data(snapshot_data), .raw_tap_frame_id(active_candidate),
        .raw_tap_base_sample_index(local_position), .raw_tap_lane_valid(4'hf),
        .coarse_result_valid(coarse_valid), .coarse_result_ready(coarse_ready), .coarse_result(coarse_result),
        .estimator_result_valid(fine_valid), .estimator_result_ready(fine_ready), .estimator_result(fine_result),
        .busy(fine_busy), .service_cycle_count(fine_service_cycles),
        .deadline_miss_sticky(fine_deadline), .protocol_error_sticky(fine_protocol),
        .arithmetic_error_sticky(fine_arithmetic), .quality_ip_protocol_error_sticky(fine_ip)
    );
    assign fine_ready = !fine_result.status[11] || !m_valid || m_ready;

    always_ff @(posedge clk) begin
        if (!core_rst_n) begin
            accepted_samples <= 0; candidate_count <= 0; rejected_count <= 0;
            capture_drop_count <= 0; duplicate_count <= 0; confirmed_count <= 0;
            bank_used <= 0; bank_ready <= 0; bank_anchor[0] <= 0; bank_anchor[1] <= 0;
            bank_candidate[0] <= 0; bank_candidate[1] <= 0;
            copy_active <= 0; copy_started <= 0; copy_slot <= 0;
            copy_request_count <= 0; copy_response_count <= 0;
            worker_state <= IDLE; worker_slot <= 0; estimator_flush <= 0;
            replay_request_count <= 0; replay_response_count <= 0; worker_cycles <= 0;
            active_anchor <= 0; active_candidate <= 0; next_frame_id <= 0;
            last_confirmed_valid <= 0; last_confirmed_position <= 0;
            held_coarse_to <= 0; held_cfo <= 0;
            fine_absolute<=0;coarse_absolute<=0;confirmed_quality<=0;confirmed_status<=0;
            m_valid <= 0; m_result <= 0; error_sticky <= 0;
            snapshot_peak <= 0; max_history_age <= 0;
        end else begin
            if (sample_fire) accepted_samples <= accepted_samples+64'd4;
            if (m_valid && m_ready) m_valid <= 0;
            if (snapshot_occupancy > snapshot_peak) snapshot_peak <= snapshot_occupancy;
            if (detector_error) error_sticky[0] <= 1;
            if (coarse_deadline || fine_deadline) error_sticky[1] <= 1;
            if (coarse_protocol || coarse_service || fine_protocol) error_sticky[2] <= 1;
            if (coarse_arithmetic || coarse_ip || fine_arithmetic || fine_ip) error_sticky[3] <= 1;
            if (candidate_valid) begin
                candidate_count <= candidate_count+1'b1;
                if (copy_active || (&bank_used) || candidate_anchor < 256) begin
                    capture_drop_count <= capture_drop_count+1'b1;
                end else begin
                    copy_slot <= bank_used[0];
                    bank_used[bank_used[0]] <= 1;
                    bank_anchor[bank_used[0]] <= candidate_anchor;
                    bank_candidate[bank_used[0]] <= candidate_count+1'b1;
                    copy_active <= 1; copy_started <= 0;
                    copy_request_count <= 0; copy_response_count <= 0;
                end
            end
            if (copy_active && !copy_started) begin
                if (oldest_age+64'd3200 >= 8192) begin
                    bank_used[copy_slot] <= 0; copy_active <= 0;
                    capture_drop_count <= capture_drop_count+(candidate_valid ? 32'd2 : 32'd1);
                    error_sticky[4] <= 1;
                end else if (accepted_samples >= bank_anchor[copy_slot]+64'd2920) begin
                    copy_started <= 1;
                    if (oldest_age > max_history_age) max_history_age <= oldest_age[15:0];
                end
            end
            // The caller has closed this independent segment and will not
            // append future samples. Reject an incomplete snapshot only after
            // the input detector pipeline has drained; no artificial samples.
            if(STREAM_BOUNDARIES&&end_seen&&end_idle_cycles==255&&copy_active&&!copy_started&&
               accepted_samples<bank_anchor[copy_slot]+64'd2920&&!candidate_valid)begin
                copy_active<=0;bank_used[copy_slot]<=0;capture_drop_count<=capture_drop_count+1'b1;error_sticky[7]<=1;
            end
            if (history_rd) begin
                copy_request_count <= copy_request_count+1'b1;
                if (accepted_samples-history_position >= 8192 || history_position+4 > accepted_samples) error_sticky[5] <= 1;
            end
            if (snapshot_wr) begin
                copy_response_count <= copy_response_count+1'b1;
                if (copy_response_count == 793) begin
                    bank_ready[copy_slot] <= 1;
                    copy_active <= 0; copy_started <= 0;
                end
            end
            if (coarse_valid && coarse_ready) begin
                if (coarse_result.status[15:12] == 1) held_coarse_to <= coarse_result.value;
                if (coarse_result.status[15:12] == 2) held_cfo <= coarse_result.value;
            end
            if (snapshot_rd) replay_request_count <= replay_request_count+1'b1;
            if (snapshot_rsp) replay_response_count <= replay_response_count+1'b1;
            case (worker_state)
                IDLE: if (|bank_ready) begin
                    bank_ready[choice] <= 0;
                    if (choice_is_duplicate) begin
                        bank_used[choice] <= 0; duplicate_count <= duplicate_count+1'b1;
                    end else begin
                        worker_slot <= choice; active_anchor <= bank_anchor[choice];
                        active_candidate <= bank_candidate[choice];
                        estimator_flush <= 16; worker_state <= RESET_ESTIMATORS;
                        replay_request_count <= 0; replay_response_count <= 0;
                        worker_cycles <= 0; held_coarse_to <= 0; held_cfo <= 0;
                    end
                end
                RESET_ESTIMATORS: if (estimator_flush == 0) worker_state <= REPLAY;
                    else estimator_flush <= estimator_flush-1'b1;
                REPLAY: if (snapshot_rd && replay_request_count == 793) worker_state <= WAIT_RESULT;
                WAIT_RESULT: begin
                    worker_cycles <= worker_cycles+1'b1;
                    if (fine_valid && fine_ready) begin
                        worker_state <= IDLE; bank_used[worker_slot] <= 0;
                        if (fine_result.status[11] && fine_result.frame_id == active_candidate) begin
                            // Keep ownership while the signed coordinate is checked.
                            worker_state<=CHECK_COORD;bank_used[worker_slot]<=1;
                            fine_absolute <= $signed({1'b0,active_anchor}) + $signed({{33{fine_result.value[31]}},fine_result.value});
                            coarse_absolute <= $signed({1'b0,active_anchor}) + $signed({{33{held_coarse_to[31]}},held_coarse_to});
                            confirmed_quality<=fine_result.quality;confirmed_status<=fine_result.status;
                        end else rejected_count <= rejected_count+1'b1;
                    end else if (worker_cycles == 70000 && !fine_valid) begin
                        worker_state <= IDLE; bank_used[worker_slot] <= 0;
                        rejected_count <= rejected_count+1'b1; error_sticky[6] <= 1;
                    end
                end
                CHECK_COORD:begin
                    worker_state<=IDLE;bank_used[worker_slot]<=0;
                    if(fine_absolute[64] || coarse_absolute[64])begin
                        rejected_count<=rejected_count+1'b1;error_sticky[5]<=1;
                    end else begin
                        m_valid<=1;
                        m_result<={epoch,next_frame_id,active_candidate,coarse_absolute[63:0],fine_absolute[63:0],held_cfo,confirmed_quality,confirmed_status};
                        next_frame_id<=next_frame_id+1'b1;confirmed_count<=confirmed_count+1'b1;
                        last_confirmed_position<=fine_absolute[63:0];last_confirmed_valid<=1;
                    end
                end
            endcase
        end
    end
    // Two comparator levels separated by registers. A stale lower bound only
    // retains extra words; it never grants permission to overwrite a live word.
    // The 8192-point detector guard covers candidate formation before bank_used.
    logic [63:0] retention_scan,retention_bank0,retention_bank1,retention_result;
    logic [63:0] retention_pair0,retention_pair1;
    wire [63:0] result_nominal={m_result[127:66],2'b00};
    assign segment_quiescent=STREAM_BOUNDARIES&&core_rst_n&&end_seen&&end_idle_cycles==255&&
        !copy_active&&bank_used==0&&worker_state==IDLE&&!m_valid&&!candidate_valid&&!history_rsp&&!snapshot_rsp;
    assign retention_valid=core_rst_n;
    assign retention_epoch=epoch;
    always_ff @(posedge clk)begin
        if(!core_rst_n)begin
            retention_scan<=0;retention_bank0<=0;retention_bank1<=0;retention_result<=0;
            retention_pair0<=0;retention_pair1<=0;retention_floor_samples<=0;
        end else begin
            retention_scan<=accepted_samples>8192?accepted_samples-64'd8192:64'd0;
            retention_bank0<=bank_used[0]?(bank_anchor[0]>532?bank_anchor[0]-64'd532:64'd0):64'hffffffffffffffff;
            retention_bank1<=bank_used[1]?(bank_anchor[1]>532?bank_anchor[1]-64'd532:64'd0):64'hffffffffffffffff;
            retention_result<=m_valid?(result_nominal>172?result_nominal-64'd172:64'd0):64'hffffffffffffffff;
            retention_pair0<=retention_scan<retention_bank0?retention_scan:retention_bank0;
            retention_pair1<=retention_bank1<retention_result?retention_bank1:retention_result;
            retention_floor_samples<=retention_pair0<retention_pair1?retention_pair0:retention_pair1;
        end
    end
endmodule
