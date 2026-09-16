`timescale 1ns/1ps

package bistatic_stream_pkg;
  localparam int unsigned BISTATIC_LANES = 4;
  localparam int unsigned BISTATIC_COMPONENT_WIDTH = 16;
  localparam int unsigned BISTATIC_COMPLEX_WIDTH = 32;
  localparam int unsigned BISTATIC_BEAT_WIDTH = 128;
  localparam int unsigned BISTATIC_FRAME_SAMPLES = 1_336_320;
  localparam int unsigned BISTATIC_FRAME_BEATS = 334_080;
  localparam int unsigned BISTATIC_FRAME_SYMBOLS = 522;
  localparam int unsigned BISTATIC_FFT_LENGTH = 2_048;
  localparam int unsigned BISTATIC_CP_LENGTH = 512;
  localparam int unsigned BISTATIC_FRAME_ID_WIDTH = 32;
  localparam int unsigned BISTATIC_SAMPLE_INDEX_WIDTH = 32;

  // A complex lane is flattened as {Q[15:0], I[15:0]}.  In the packed beat
  // array lane[0] occupies bits 31:0 and is the earliest time sample;
  // lane[3] occupies bits 127:96 and is the latest time sample.
  typedef struct packed {
    logic signed [BISTATIC_COMPONENT_WIDTH-1:0] q;
    logic signed [BISTATIC_COMPONENT_WIDTH-1:0] i;
  } bistatic_complex_i16_t;

  typedef bistatic_complex_i16_t [BISTATIC_LANES-1:0]
      bistatic_data_beat_t;

  typedef enum logic [3:0] {
    BISTATIC_STAGE_CAPTURE       = 4'd0,
    BISTATIC_STAGE_COARSE_SYNC   = 4'd1,
    BISTATIC_STAGE_FINE_TO       = 4'd2,
    BISTATIC_STAGE_INITIAL_SFO   = 4'd3,
    BISTATIC_STAGE_RESAMPLE_1    = 4'd4,
    BISTATIC_STAGE_RESAMPLE_2_FO = 4'd5,
    BISTATIC_STAGE_FINAL_FO      = 4'd6,
    BISTATIC_STAGE_OUTPUT        = 4'd7
  } bistatic_stage_id_t;

  typedef struct packed {
    logic [BISTATIC_FRAME_ID_WIDTH-1:0] frame_id;
    logic [BISTATIC_SAMPLE_INDEX_WIDTH-1:0] beat_base_sample_index;
    logic [BISTATIC_LANES-1:0] lane_valid;
    logic transaction_end;
    logic physical_frame_end;
    logic nominal_region;
    logic halo_or_guard;
  } bistatic_stream_metadata_t;

  typedef struct packed {
    logic signed [31:0] value;
    logic [15:0] quality;
    logic [15:0] status;
    logic [BISTATIC_FRAME_ID_WIDTH-1:0] frame_id;
  } bistatic_estimator_result_t;

  typedef struct packed {
    logic overflow;
    logic underflow;
    logic frame_protocol_error;
    logic bank_collision;
    logic estimator_invalid;
    logic deadline_miss;
  } bistatic_error_status_t;
endpackage
