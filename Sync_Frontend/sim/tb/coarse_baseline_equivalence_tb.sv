`timescale 1ns/1ps

module coarse_baseline_equivalence_tb;
  import bistatic_stream_pkg::*;

  localparam int unsigned VENDOR_PHASE_TOLERANCE_LSB = 0;
  localparam int unsigned IDEAL_PHASE_TOLERANCE_LSB = 4;
  localparam int unsigned MAGNITUDE_TOLERANCE_LSB = 1;
  localparam logic [48:0] PHASE_HALF_TURN_Q3_45 =
      49'd35_184_372_088_832;
  localparam logic [48:0] PHASE_FULL_TURN_Q3_45 =
      49'd70_368_744_177_664;

  localparam int unsigned CASE_COUNT = 91;
  localparam int unsigned HALO_BEATS = 64;
  localparam int unsigned CURRENT_BEATS = 704;
  localparam int unsigned BEATS_PER_CASE =
      HALO_BEATS + CURRENT_BEATS;
  localparam int unsigned METRICS_PER_CASE = 257;
  localparam int unsigned TOTAL_METRICS =
      CASE_COUNT * METRICS_PER_CASE;
  localparam int unsigned FRAME_SAMPLES = 1_336_320;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic data_valid = 1'b0;
  logic data_ready;
  logic [127:0] data = '0;
  bistatic_stream_metadata_t metadata = '0;
  logic estimator_result_valid;
  logic estimator_result_ready = 1'b1;
  bistatic_estimator_result_t estimator_result;
  logic deadline_miss_sticky;
  logic input_protocol_error_sticky;
  logic result_service_error_sticky;
  logic arithmetic_error_sticky;
  logic arithmetic_ip_error_sticky;
  logic [1:0] queued_result_pairs;

  logic [127:0] stimulus_beats [0:CASE_COUNT*BEATS_PER_CASE-1];
  logic [319:0] expected_metrics [0:TOTAL_METRICS-1];
  logic [255:0] expected_results [0:CASE_COUNT-1];

  string stimulus_path;
  string metrics_path;
  string results_path;
  int unsigned outage_case0;
  int unsigned outage_case1;
  bit smoke_only;
  int unsigned executed_case_count = 0;
  int unsigned current_case = 0;
  int unsigned case_metric_count = 0;
  int unsigned case_result_count = 0;
  int unsigned case_pair_commit_count = 0;
  int unsigned case_phase_result_count = 0;
  int unsigned cycle_count = 0;
  int unsigned frame_start_cycle = 0;
  int unsigned maximum_pair_commit_delta = 0;
  logic [48:0] maximum_vendor_phase_difference_lsb = '0;
  logic [48:0] maximum_ideal_phase_difference_lsb = '0;
  logic [48:0] maximum_magnitude_difference_lsb = '0;

  function automatic logic [48:0] circular_phase_distance_q3_45(
      input logic signed [47:0] actual,
      input logic signed [47:0] expected);
    logic signed [48:0] signed_difference;
    logic [48:0] absolute_difference;
    begin
      signed_difference =
          $signed({actual[47], actual}) -
          $signed({expected[47], expected});
      if (signed_difference < 0)
        absolute_difference = $unsigned(-signed_difference);
      else
        absolute_difference = $unsigned(signed_difference);
      if (absolute_difference > PHASE_HALF_TURN_Q3_45)
        circular_phase_distance_q3_45 =
            PHASE_FULL_TURN_Q3_45 - absolute_difference;
      else
        circular_phase_distance_q3_45 = absolute_difference;
    end
  endfunction

  function automatic logic is_principal_scaled_radians_q3_45(
      input logic signed [47:0] phase_code);
    begin
      // The extra integer bits exist only for the vendor container and sign
      // extension.  A legal phase is [-1,+1), i.e. [-pi,+pi); +1 is
      // represented canonically as -1 modulo one complete turn.
      is_principal_scaled_radians_q3_45 =
          phase_code[47:45] == {3{phase_code[45]}};
    end
  endfunction

  always #4 clk = ~clk;
  always @(posedge clk)
    cycle_count <= cycle_count + 1;

  to_coarse_estimator dut (.*);

  task automatic reset_case_state;
    begin
      @(negedge clk);
      rst_n <= 1'b0;
      data_valid <= 1'b0;
      data <= '0;
      metadata <= '0;
      repeat (8) @(posedge clk);
      @(negedge clk);
      rst_n <= 1'b1;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic drive_case(input int unsigned case_index);
    int unsigned stimulus_index;
    logic [31:0] test_frame_id;
    begin
      test_frame_id = 32'd1000 + case_index;
      @(negedge clk);
      for (int unsigned beat = 0; beat < HALO_BEATS; beat++) begin
        stimulus_index =
            case_index*BEATS_PER_CASE + beat;
        data_valid <= 1'b1;
        data <= stimulus_beats[stimulus_index];
        metadata.frame_id <= test_frame_id - 1'b1;
        metadata.beat_base_sample_index <=
            FRAME_SAMPLES - 256 + 4*beat;
        metadata.lane_valid <= 4'hf;
        metadata.transaction_end <= 1'b0;
        metadata.physical_frame_end <= 1'b0;
        metadata.nominal_region <= 1'b0;
        metadata.halo_or_guard <= 1'b1;
        @(negedge clk);
      end

      for (int unsigned beat = 0;
           beat < CURRENT_BEATS; beat++) begin
        stimulus_index =
            case_index*BEATS_PER_CASE + HALO_BEATS + beat;
        data_valid <= 1'b1;
        data <= stimulus_beats[stimulus_index];
        metadata.frame_id <= test_frame_id;
        metadata.beat_base_sample_index <= 4*beat;
        metadata.lane_valid <= 4'hf;
        metadata.transaction_end <= 1'b0;
        metadata.physical_frame_end <= 1'b0;
        metadata.nominal_region <= 1'b1;
        metadata.halo_or_guard <= 1'b0;
        @(negedge clk);
      end

      data_valid <= 1'b0;
      data <= '0;
      metadata <= '0;
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && dut.recognized_frame_start)
      frame_start_cycle <= cycle_count;

    if (rst_n && dut.fifo_pair_handshake) begin
      int unsigned commit_delta;
      commit_delta = cycle_count - frame_start_cycle;
      if (commit_delta > 1024)
        $fatal(1,
          "Case %0d pair commit missed deadline delta=%0d",
          current_case, commit_delta);
      if (commit_delta > maximum_pair_commit_delta)
        maximum_pair_commit_delta = commit_delta;
      case_pair_commit_count <= case_pair_commit_count + 1;
    end
  end

  always @(negedge clk) begin : metric_check
    logic [319:0] expected;
    int unsigned expected_address;
    if (rst_n && dut.metric_valid) begin
      if (case_metric_count >= METRICS_PER_CASE)
        $fatal(1, "Case %0d produced extra metric", current_case);
      expected_address =
          current_case*METRICS_PER_CASE + case_metric_count;
      expected = expected_metrics[expected_address];
      if (dut.metric_index !== case_metric_count[8:0] ||
          dut.metric_last !==
              (case_metric_count == METRICS_PER_CASE-1))
        $fatal(1,
          "Case %0d metric sequence mismatch count=%0d index=%0d last=%0b",
          current_case, case_metric_count, dut.metric_index,
          dut.metric_last);
      if (dut.metric_p_re !== expected[42:0] ||
          dut.metric_p_im !== expected[85:43] ||
          dut.metric_energy !== expected[127:86] ||
          dut.metric_threshold_lhs !== expected[221:128] ||
          dut.metric_threshold_rhs !== expected[307:222] ||
          dut.metric_qualified !== expected[308])
        $fatal(1,
          "Case %0d metric %0d declared-node mismatch",
          current_case, case_metric_count);
      case_metric_count = case_metric_count + 1;
    end
  end

  always @(negedge clk) begin : phase_magnitude_check
    logic [255:0] expected;
    logic signed [47:0] ideal_phase;
    logic signed [47:0] vendor_phase;
    logic [47:0] expected_magnitude;
    logic [48:0] vendor_phase_difference;
    logic [48:0] ideal_phase_difference;
    logic [48:0] magnitude_difference;
    if (rst_n && dut.phase_result_valid) begin
      expected = expected_results[current_case];
      ideal_phase = $signed(expected[145:98]);
      expected_magnitude = expected[193:146];
      vendor_phase = $signed(expected[241:194]);

      if ($isunknown({dut.phase_result_code_q3_45,
                      dut.phase_result_magnitude,
                      ideal_phase,
                      vendor_phase,
                      expected_magnitude}))
        $fatal(1,
          "Case %0d phase/magnitude check contains X or Z",
          current_case);

      if (!is_principal_scaled_radians_q3_45(ideal_phase))
        $fatal(1,
          "Case %0d ideal Q3.45 phase is outside canonical [-1,+1): %0d",
          current_case, ideal_phase);
      if (!is_principal_scaled_radians_q3_45(vendor_phase))
        $fatal(1,
          "Case %0d vendor Q3.45 phase is outside canonical [-1,+1): %0d",
          current_case, vendor_phase);
      if (!is_principal_scaled_radians_q3_45(
              $signed(dut.phase_result_code_q3_45)))
        $fatal(1,
          "Case %0d DUT Q3.45 phase is outside canonical [-1,+1): %0d",
          current_case, $signed(dut.phase_result_code_q3_45));

      vendor_phase_difference = circular_phase_distance_q3_45(
          $signed(dut.phase_result_code_q3_45), vendor_phase);
      ideal_phase_difference = circular_phase_distance_q3_45(
          vendor_phase, ideal_phase);
      if (dut.phase_result_magnitude >= expected_magnitude)
        magnitude_difference =
            dut.phase_result_magnitude - expected_magnitude;
      else
        magnitude_difference =
            expected_magnitude - dut.phase_result_magnitude;

      if (vendor_phase_difference >
          maximum_vendor_phase_difference_lsb)
        maximum_vendor_phase_difference_lsb =
            vendor_phase_difference;
      if (ideal_phase_difference >
          maximum_ideal_phase_difference_lsb)
        maximum_ideal_phase_difference_lsb =
            ideal_phase_difference;
      if (magnitude_difference >
          maximum_magnitude_difference_lsb)
        maximum_magnitude_difference_lsb =
            magnitude_difference;

      if (dut.phase_result_code_q3_45 !== vendor_phase)
        $fatal(1,
          "Case %0d DUT/vendor Q3.45 mismatch diff=%0d actual=%0d vendor=%0d",
          current_case, vendor_phase_difference,
          $signed(dut.phase_result_code_q3_45), vendor_phase);
      if (ideal_phase_difference >
          IDEAL_PHASE_TOLERANCE_LSB)
        $fatal(1,
          "Case %0d vendor/ideal circular Q3.45 mismatch diff=%0d vendor=%0d ideal=%0d",
          current_case, ideal_phase_difference,
          vendor_phase, ideal_phase);
      if (magnitude_difference > MAGNITUDE_TOLERANCE_LSB)
        $fatal(1,
          "Case %0d N20 magnitude mismatch diff=%0d actual=%0d expected=%0d",
          current_case, magnitude_difference,
          dut.phase_result_magnitude, expected_magnitude);
      case_phase_result_count = case_phase_result_count + 1;
    end
  end

  always @(posedge clk) begin : result_check
    logic [255:0] expected;
    logic signed [31:0] expected_start;
    logic signed [31:0] expected_cfo;
    logic [15:0] expected_quality;
    logic expected_valid;
    logic expected_ambiguity;
    logic [15:0] expected_error_code;
    logic [3:0] expected_kind;
    logic expected_outage;
    logic signed [32:0] cfo_difference;
    logic [16:0] quality_difference;
    if (rst_n && estimator_result_valid &&
        estimator_result_ready) begin
      if (case_result_count >= 2)
        $fatal(1, "Case %0d produced extra result record",
          current_case);
      expected = expected_results[current_case];
      expected_start = $signed(expected[31:0]);
      expected_cfo = $signed(expected[63:32]);
      expected_quality = expected[79:64];
      expected_valid = expected[80];
      expected_ambiguity = expected[81];
      expected_error_code = expected[97:82];
      expected_kind = (case_result_count == 0) ? 4'h1 : 4'h2;
      expected_outage =
          current_case == outage_case0 || current_case == outage_case1;

      if (expected_outage) begin
        if (expected_error_code != 16'd2 || expected_valid != 1'b0 ||
            expected_ambiguity != 1'b1 || expected_start != 32'sd0 ||
            expected_cfo != 32'sd0 || expected_quality != 16'd0)
          $fatal(1,
            "Outage fixture case %0d is not exact public fail-close",
            current_case);
      end else if (expected_error_code != 16'd0 ||
                   expected_valid != 1'b1 ||
                   expected_ambiguity != 1'b0) begin
        $fatal(1,
          "Non-outage fixture case %0d has invalid public policy fields",
          current_case);
      end
      if (estimator_result.frame_id !==
              (32'd1000 + current_case) ||
          estimator_result.status[15:12] !== expected_kind ||
          estimator_result.status[11] !== expected_valid ||
          estimator_result.status[10] !== expected_ambiguity)
        $fatal(1, "Case %0d result %0d metadata/status mismatch",
          current_case, case_result_count);
      if (expected_outage) begin
        if (estimator_result.status[9:0] !== 10'b0 ||
            estimator_result.value !== 32'sd0 ||
            estimator_result.quality !== 16'd0)
          $fatal(1,
            "Outage case %0d did not fail close status=%h value=%0d quality=%0d",
            current_case, estimator_result.status,
            estimator_result.value, estimator_result.quality);
      end else if (expected_valid &&
                   estimator_result.status[9:0] !== 10'b0) begin
        $fatal(1,
          "Case %0d valid result carries error/reserved status=%h",
          current_case, estimator_result.status);
      end

      if (case_result_count == 0) begin
        if (estimator_result.value !== expected_start ||
            estimator_result.quality !== 16'd0)
          $fatal(1,
            "Case %0d start mismatch got=%0d expected=%0d",
            current_case, estimator_result.value,
            expected_start);
      end else begin
        if ($isunknown({estimator_result.value,
                        estimator_result.quality,
                        expected_cfo,
                        expected_quality}))
          $fatal(1,
            "Case %0d CFO/quality check contains X or Z",
            current_case);
        cfo_difference =
            $signed({estimator_result.value[31],
                     estimator_result.value}) -
            $signed({expected_cfo[31], expected_cfo});
        if (cfo_difference < 0)
          cfo_difference = -cfo_difference;
        if (estimator_result.quality >= expected_quality)
          quality_difference =
              estimator_result.quality - expected_quality;
        else
          quality_difference =
              expected_quality - estimator_result.quality;
        if (cfo_difference > 1 || quality_difference > 1)
          $fatal(1,
            "Case %0d CFO/quality exceeds one LSB got=(%0d,%0d) expected=(%0d,%0d)",
            current_case, estimator_result.value,
            estimator_result.quality, expected_cfo,
            expected_quality);
      end
      case_result_count <= case_result_count + 1;
    end
  end

  initial begin : full_regression
    int unsigned timeout_cycles;
    // XSim 2021.1 on the NI toolchain passes paths containing spaces
    // inconsistently through xsim.bat.  The reproducible runner therefore
    // makes hash-checked local copies with these fixed relative names.
    // Explicit plusargs remain available for environments that pass them
    // correctly.
    if (!$value$plusargs("STIMULUS_MEM=%s", stimulus_path))
      stimulus_path = "fixture_stimulus_beats.mem";
    if (!$value$plusargs("METRICS_MEM=%s", metrics_path))
      metrics_path = "fixture_expected_metrics.mem";
    if (!$value$plusargs("RESULTS_MEM=%s", results_path))
      results_path = "fixture_expected_results.mem";

    $readmemh(stimulus_path, stimulus_beats);
    $readmemh(metrics_path, expected_metrics);
    $readmemh(results_path, expected_results);
    smoke_only = $test$plusargs("SMOKE_ONLY");
    if (!$value$plusargs("OUTAGE_CASE0_%d", outage_case0) ||
        !$value$plusargs("OUTAGE_CASE1_%d", outage_case1))
      $fatal(1, "Missing contract-resolved outage case plusargs");
    if (outage_case0 >= CASE_COUNT || outage_case1 >= CASE_COUNT ||
        outage_case0 == outage_case1 || outage_case0 == 0 ||
        outage_case1 == 0)
      $fatal(1, "Invalid outage indices %0d,%0d",
        outage_case0, outage_case1);

    for (int unsigned case_index = 0;
         case_index < CASE_COUNT; case_index++) begin
      if (!smoke_only || case_index == 0 ||
          case_index == outage_case0 || case_index == outage_case1) begin
      executed_case_count = executed_case_count + 1;
      current_case = case_index;
      case_metric_count = 0;
      case_result_count = 0;
      case_pair_commit_count = 0;
      case_phase_result_count = 0;
      reset_case_state();
      if (!data_ready)
        $fatal(1, "Case %0d data_ready is low after reset",
          case_index);
      drive_case(case_index);

      for (timeout_cycles = 0;
           timeout_cycles < 500 && case_result_count < 2;
           timeout_cycles++)
        @(posedge clk);

      if (case_result_count != 2 ||
          case_metric_count != METRICS_PER_CASE ||
          case_pair_commit_count != 1 ||
          case_phase_result_count != 1)
        $fatal(1,
          "Case %0d incomplete results=%0d metrics=%0d commits=%0d phase_results=%0d",
          case_index, case_result_count, case_metric_count,
          case_pair_commit_count, case_phase_result_count);
      if (deadline_miss_sticky ||
          input_protocol_error_sticky ||
          result_service_error_sticky ||
          arithmetic_error_sticky ||
          arithmetic_ip_error_sticky)
        $fatal(1,
          "Case %0d sticky error deadline=%0b input=%0b service=%0b arithmetic=%0b ip=%0b",
          case_index, deadline_miss_sticky,
          input_protocol_error_sticky,
          result_service_error_sticky,
          arithmetic_error_sticky,
          arithmetic_ip_error_sticky);
      repeat (4) @(posedge clk);
      end
    end

    if (smoke_only) begin
      if (executed_case_count != 3)
        $fatal(1, "Smoke executed %0d cases, expected 3",
          executed_case_count);
      $display("T04_CURRENT_GENERATION_V2_SMOKE_PASS cases=3 case0=0 outage_case0=%0d outage_case1=%0d metrics=771 result_records=6 pair_commits=3 maximum_pair_commit_delta=%0d maximum_vendor_phase_difference_lsb=%0d maximum_ideal_phase_difference_lsb=%0d maximum_magnitude_difference_lsb=%0d exact_public_fail_close=1 raw_internal_nodes_checked=1",
        outage_case0, outage_case1,
        maximum_pair_commit_delta,
        maximum_vendor_phase_difference_lsb,
        maximum_ideal_phase_difference_lsb,
        maximum_magnitude_difference_lsb);
    end else begin
      if (executed_case_count != CASE_COUNT)
        $fatal(1, "Full run executed %0d cases, expected %0d",
          executed_case_count, CASE_COUNT);
      $display("T04_CURRENT_GENERATION_V2_FULL91_PASS cases=91 metrics=23387 result_records=182 pair_commits=91 outage_case0=%0d outage_case1=%0d maximum_pair_commit_delta=%0d maximum_vendor_phase_difference_lsb=%0d maximum_ideal_phase_difference_lsb=%0d maximum_magnitude_difference_lsb=%0d exact_public_fail_close=1 raw_internal_nodes_checked=1",
        outage_case0, outage_case1,
        maximum_pair_commit_delta,
        maximum_vendor_phase_difference_lsb,
        maximum_ideal_phase_difference_lsb,
        maximum_magnitude_difference_lsb);
    end
    $finish;
  end
endmodule

