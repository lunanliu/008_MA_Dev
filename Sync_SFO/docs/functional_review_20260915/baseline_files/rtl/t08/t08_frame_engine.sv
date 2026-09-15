`timescale 1ns/1ps
// Error terminal poisons the current generation; abort resets only this engine.
// A failed completion never authorizes release/reuse of a partially accessed shared bank.
module t08_frame_engine #(
  parameter int unsigned SAMPLE_COUNT=1_336_392,
  parameter int unsigned INPUT_BEATS=334_215,
  parameter int unsigned PROCESSING_LIMIT_CYCLES=400_896
)(
  input logic clk,rst,abort_request,
  input logic cfg_valid,output logic cfg_ready,
  input logic [31:0] cfg_frame_id,cfg_generation,cfg_step,
  input logic signed [63:0] cfg_phase0,
  input logic signed [31:0] cfg_raw_first,s_raw_index,
  input logic [3:0] s_lane_valid,input logic s_last,
  input logic s_valid,output logic s_ready,input logic [127:0] s_data,
  input logic [31:0] s_frame_id,s_generation,s_beat,
  output logic m_valid,input logic m_ready,output logic [127:0] m_data,
  output logic [31:0] m_frame_id,m_generation,m_beat,output logic m_last,
  output logic completion_valid,input logic completion_ready,output logic completion_success,
  output logic [31:0] completed_frame_id,completed_generation,
  output logic [31:0] processing_cycles,
  output logic [5:0][31:0] accepted_stage_beats,
  output logic [31:0] accepted_packed_beats,
  output logic error_sticky,epoch_poisoned,
  output logic [7:0] first_error_code,
  output logic [31:0] first_error_cycle
);
  localparam int unsigned REQUEST_BEATS=(SAMPLE_COUNT+32)/4;
  localparam int unsigned PACKED_BEATS=SAMPLE_COUNT/4;
  typedef enum logic [3:0] {IDLE,CLEAR_CORE,START_CORE,INIT_PHASE,RUN_FRAME,QUIET_TAIL,
                            COMPLETE_FRAME,ABORT_CORE_RESET,COMPLETE_ERROR,HALTED} state_t;
  state_t state;
  logic [6:0] phase_counter;
  logic [31:0] frame_id,generation,step;
  logic signed [63:0] phase0;
  logic signed [63:0] raw_first;
  wire normal_active=state==CLEAR_CORE || state==START_CORE || state==INIT_PHASE || state==RUN_FRAME || state==QUIET_TAIL;
  wire faultable=normal_active || state==COMPLETE_FRAME;
  wire local_reset=rst || state==CLEAR_CORE || state==ABORT_CORE_RESET || state==COMPLETE_ERROR || state==HALTED;
  wire core_start=!rst && state==START_CORE && !abort_request;
  wire run_enable=!rst && state==RUN_FRAME && !abort_request && !error_sticky;
  wire core_input_valid=run_enable && s_valid && accepted_stage_beats[0]<INPUT_BEATS;
  wire core_input_ready,core_valid,core_ready,core_done,arithmetic_empty;
  wire [127:0] core_data;
  wire [3:0] core_mask;
  wire [31:0] core_beat;
  wire [5:0] observed_valid,observed_accept;
  wire pack_ready,pack_valid,pack_last,pack_error;
  wire [127:0] pack_data;
  wire [31:0] pack_beat,formed_beats,physical_beats;
  logic transport_complete;
  logic [7:0] fault_code;
  assign cfg_ready=!rst && !abort_request && state==IDLE && !error_sticky;
  assign s_ready=run_enable && accepted_stage_beats[0]<INPUT_BEATS && core_input_ready;
  assign core_ready=run_enable && pack_ready;
  assign m_valid=run_enable && pack_valid;
  assign m_data=pack_data;assign m_beat=pack_beat;assign m_last=pack_last;
  assign m_frame_id=frame_id;assign m_generation=generation;
  assign completed_frame_id=frame_id;assign completed_generation=generation;
  assign completion_valid=!rst && ((state==COMPLETE_FRAME && !abort_request) || state==COMPLETE_ERROR);
  assign completion_success=completion_valid && state==COMPLETE_FRAME && !error_sticky;
  assign epoch_poisoned=error_sticky || abort_request;
  always_comb begin
    transport_complete=1'b1;
    for(int i=0;i<6;i++)
      if(accepted_stage_beats[i]!=(i<3?INPUT_BEATS:REQUEST_BEATS))transport_complete=1'b0;
    fault_code=8'd0;
    if(faultable)begin
      if(abort_request)fault_code=8'd1;
      else if(normal_active && step==0)fault_code=8'd7;
      else if(normal_active && processing_cycles>=PROCESSING_LIMIT_CYCLES-1)fault_code=8'd8;
      else if(state==RUN_FRAME)begin
        if(pack_error)fault_code=8'd2;
        else begin
          for(int i=0;i<6;i++)
            if(observed_accept[i] && accepted_stage_beats[i]>=(i<3?INPUT_BEATS:REQUEST_BEATS))fault_code=8'd3;
          if(fault_code==0 && s_valid && s_ready &&
             (s_frame_id!=frame_id || s_generation!=generation || s_beat!=accepted_stage_beats[0]))fault_code=8'd4;
          if(fault_code==0 && s_valid && s_ready &&
             (s_lane_valid!=4'hf || s_last!=(accepted_stage_beats[0]==INPUT_BEATS-1) ||
              $signed({{32{s_raw_index[31]}},s_raw_index})!=raw_first+($signed({32'd0,accepted_stage_beats[0]})<<<2)))fault_code=8'h20;
          if(fault_code==0 && m_valid && m_ready &&
             (m_beat!=accepted_packed_beats || m_last!=(accepted_packed_beats==PACKED_BEATS-1)))fault_code=8'd5;
        end
      end else if(state==QUIET_TAIL &&
          (observed_valid!=0 || !core_done || !arithmetic_empty || pack_valid || pack_error))fault_code=8'd6;
    end
  end
  t07_guard_frame_core #(.NOMINAL_SAMPLES(SAMPLE_COUNT)) core(
    .clk(clk),.reset(local_reset),.start(core_start),.cfg_step(step),
    .cfg_request_beats(REQUEST_BEATS),.cfg_phase0(phase0),
    .s_valid(core_input_valid),.s_ready(core_input_ready),.s_data(s_data),
    .m_valid(core_valid),.m_ready(core_ready),.m_data(core_data),.m_beat(core_beat),
    .m_nominal_mask(core_mask),.done(core_done),.observed_valid(observed_valid),
    .observed_accept(observed_accept),.observed_arithmetic_empty(arithmetic_empty));
  t07_nominal_pack4_rev02 #(.SAMPLE_COUNT(SAMPLE_COUNT)) pack(
    .clk(clk),.rst(local_reset),.s_valid(run_enable && core_valid),.s_ready(pack_ready),
    .s_data(core_data),.s_mask(core_mask),.m_valid(pack_valid),.m_ready(run_enable && m_ready),
    .m_data(pack_data),.m_beat(pack_beat),.m_last(pack_last),.formed_beats(formed_beats),
    .physical_beats(physical_beats),.error_sticky(pack_error));
  always_ff @(posedge clk) begin
    if(rst)begin
      state<=IDLE;phase_counter<='0;frame_id<='0;generation<='0;step<='0;phase0<='0;raw_first<='0;
      processing_cycles<='0;accepted_stage_beats<='0;accepted_packed_beats<='0;
      error_sticky<=1'b0;first_error_code<='0;first_error_cycle<='0;
    end else begin
      if(normal_active || state==ABORT_CORE_RESET)processing_cycles<=processing_cycles+1'b1;
      // Accepted edges, including the edge which detects a fault, remain observable.
      if(state==RUN_FRAME)begin
        for(int i=0;i<6;i++)if(observed_accept[i])accepted_stage_beats[i]<=accepted_stage_beats[i]+1'b1;
        if(m_valid && m_ready)accepted_packed_beats<=accepted_packed_beats+1'b1;
      end
      if(faultable && fault_code!=0)begin
        error_sticky<=1'b1;first_error_code<=fault_code;first_error_cycle<=processing_cycles;
        phase_counter<='0;state<=ABORT_CORE_RESET;
      end else case(state)
        IDLE:if(cfg_valid && cfg_ready)begin
          frame_id<=cfg_frame_id;generation<=cfg_generation;step<=cfg_step;phase0<=cfg_phase0;raw_first<=$signed(cfg_raw_first);
          processing_cycles<='0;accepted_stage_beats<='0;accepted_packed_beats<='0;
          phase_counter<='0;state<=CLEAR_CORE;
        end
        CLEAR_CORE:if(phase_counter==31)begin phase_counter<='0;state<=START_CORE;end
                   else phase_counter<=phase_counter+1'b1;
        START_CORE:begin phase_counter<='0;state<=INIT_PHASE;end
        INIT_PHASE:if(phase_counter==15)begin phase_counter<='0;state<=RUN_FRAME;end
                   else phase_counter<=phase_counter+1'b1;
        RUN_FRAME:if(transport_complete && core_done && arithmetic_empty && !pack_valid &&
             accepted_packed_beats==PACKED_BEATS && formed_beats==PACKED_BEATS && physical_beats==REQUEST_BEATS)begin
            phase_counter<='0;state<=QUIET_TAIL;
          end
        QUIET_TAIL:if(phase_counter==100)state<=COMPLETE_FRAME;
                   else phase_counter<=phase_counter+1'b1;
        COMPLETE_FRAME:if(completion_valid && completion_ready)state<=IDLE;
        ABORT_CORE_RESET:if(phase_counter==31)state<=COMPLETE_ERROR;
                         else phase_counter<=phase_counter+1'b1;
        COMPLETE_ERROR:if(completion_valid && completion_ready)state<=HALTED;
        HALTED:begin end
        default:begin
          error_sticky<=1'b1;first_error_code<=8'd9;first_error_cycle<=processing_cycles;
          phase_counter<='0;state<=ABORT_CORE_RESET;
        end
      endcase
    end
  end
  // synthesis translate_off
  initial if(PROCESSING_LIMIT_CYCLES<64)$fatal(1,"processing watchdog below startup budget");
  // synthesis translate_on
endmodule

