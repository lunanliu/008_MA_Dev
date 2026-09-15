`timescale 1ns/1ps
module t06_observation_engine_2lane (
    input logic clk,rst,
    input logic frame_start_valid,output logic frame_start_ready,input logic [31:0] frame_start_id,
    input logic s_valid,output logic s_ready,input logic [31:0] s_frame_id,input logic [1:0] s_pair,
    input logic [10:0] s_index0,s_index1,input logic [63:0] s_first_iq,s_second_iq,
    input logic s_pair_last,s_last,s_upstream_error,
    output logic m_valid,input logic m_ready,output logic [31:0] m_frame_id,
    output logic [1:0] m_pair,output logic [10:0] m_index0,m_index1,
    output logic signed [47:0] m_phase0,m_phase1,m_native_phase0,m_native_phase1,
    output logic [63:0] m_nw0,m_nw1,output logic [32:0] m_dw0,m_dw1,
    output logic [31:0] m_power_first0,m_power_first1,m_power_second0,m_power_second1,m_tag0,m_tag1,
    output logic [1:0] m_zero_power,m_axis_mapped,output logic m_pair_last,m_last,
    output logic status_valid,input logic status_ready,output logic [31:0] status_frame_id,
    output logic status_error,output logic [7:0] status_error_code,output logic halted,error_sticky,
    output logic [12:0] accepted_observations,emitted_observations,cancelled_engine_observations,
    output logic [8:0] pending_pair_beats
);
    typedef enum logic [1:0] {IDLE,RUN,FINISH,HALT} state_t;
    typedef struct packed {
        logic signed [47:0] phase,native_phase;
        logic [31:0] p1,p2;
        logic [63:0] nw;logic [32:0] dw;logic [31:0] tag;
        logic zero_power,axis_mapped,error;
    } observation_t;
    state_t state;
    logic [31:0] active_frame;
    logic [1:0] input_pair,join_pair;
    logic [10:0] input_index,join_index;
    logic [1:0] lane_ready,lane_valid,lane_protocol;
    logic [7:0] lane_pending[0:1];
    observation_t lane_output[0:1],held[0:1];
    logic engine_rst,hold_valid,input_accept,input_error,admit,join_available,join_tag_error,join_error;
    logic join_fire,consume,error_event;logic [7:0] error_code;
    logic [31:0] input_tag[0:1],expected_tag[0:1];
    assign halted=state==HALT;
    assign engine_rst=rst || halted;
    assign frame_start_ready=!rst && state==IDLE && !s_upstream_error && (&lane_ready) && lane_pending[0]==0 && lane_pending[1]==0;
    // Do not use the cores' full-credit consume lookahead: input_error gates
    // join_fire, so using that lookahead would close a ready/error/pop loop.
    assign s_ready=!rst && state==RUN && !s_upstream_error && lane_pending[0]<128 && lane_pending[1]<128 &&
        (&lane_ready) && accepted_observations<6560;
    assign input_accept=s_valid && s_ready;
    assign input_error=input_accept && (s_frame_id!=active_frame || s_pair!=input_pair || s_index0!=input_index ||
        s_index1!=input_index+11'd1 || s_pair_last!=(input_index==1638) || s_last!=(input_pair==3 && input_index==1638));
    assign input_tag[0]={19'd0,s_pair,s_index0};assign input_tag[1]={19'd0,s_pair,s_index1};
    assign expected_tag[0]={19'd0,join_pair,join_index};assign expected_tag[1]={19'd0,join_pair,(join_index+11'd1)};
    assign m_valid=!rst && hold_valid;
    assign consume=m_valid && m_ready;
    assign join_available=(&lane_valid);
    assign join_tag_error=join_available && (lane_output[0].tag!=expected_tag[0] || lane_output[1].tag!=expected_tag[1]);
    assign join_error=join_available && (lane_output[0].error || lane_output[1].error);
    always_comb begin
        error_event=0;error_code=0;
        if(!rst && state==RUN)begin
            if(s_upstream_error || (|lane_protocol) || lane_pending[0]!=lane_pending[1] || join_error)begin error_event=1;error_code=7;end
            else if(input_error || join_tag_error)begin error_event=1;error_code=6;end
        end
    end
    assign admit=input_accept && !error_event;
    assign join_fire=!rst && state==RUN && join_available && (!hold_valid || m_ready) && !error_event;
    assign pending_pair_beats={1'b0,lane_pending[0]}+{{8{1'b0}},hold_valid};
    for(genvar lane=0;lane<2;lane=lane+1)begin : engines
        wire local_ready,local_valid,local_protocol,local_zero,local_axis,local_error;
        wire [7:0] local_pending;
        wire signed [47:0] local_phase,local_native_phase;
        wire [31:0] local_p1,local_p2,local_tag;
        wire [63:0] local_nw;wire [32:0] local_dw;
        assign lane_ready[lane]=local_ready;assign lane_valid[lane]=local_valid;
        assign lane_protocol[lane]=local_protocol;assign lane_pending[lane]=local_pending;
        // One packed driver per array element; avoid several child outputs
        // driving fields of one unpacked struct element in XSim2021.1.
        assign lane_output[lane]={local_phase,local_native_phase,local_p1,local_p2,local_nw,local_dw,local_tag,local_zero,local_axis,local_error};
        t06_observation_engine engine (
            .clk(clk),.rst(engine_rst),.s_valid(admit),.s_ready(local_ready),
            .s_first_iq(s_first_iq[lane*32+:32]),.s_second_iq(s_second_iq[lane*32+:32]),.s_tag(input_tag[lane]),
            .m_valid(local_valid),.m_ready(join_fire),
            .m_phase(local_phase),.m_native_phase(local_native_phase),
            .m_power_first(local_p1),.m_power_second(local_p2),
            .m_weight_numerator(local_nw),.m_weight_denominator(local_dw),.m_tag(local_tag),
            .m_zero_power(local_zero),.m_axis_mapped(local_axis),.m_error(local_error),
            .pending_count(local_pending),.protocol_error_sticky(local_protocol));
    end
    assign m_frame_id=active_frame;assign m_pair=held[0].tag[12:11];
    assign m_index0=held[0].tag[10:0];assign m_index1=held[1].tag[10:0];
    assign m_phase0=held[0].phase;assign m_phase1=held[1].phase;
    assign m_native_phase0=held[0].native_phase;assign m_native_phase1=held[1].native_phase;
    assign m_nw0=held[0].nw;assign m_nw1=held[1].nw;assign m_dw0=held[0].dw;assign m_dw1=held[1].dw;
    assign m_power_first0=held[0].p1;assign m_power_first1=held[1].p1;
    assign m_power_second0=held[0].p2;assign m_power_second1=held[1].p2;
    assign m_tag0=held[0].tag;assign m_tag1=held[1].tag;
    assign m_zero_power={held[1].zero_power,held[0].zero_power};assign m_axis_mapped={held[1].axis_mapped,held[0].axis_mapped};
    assign m_pair_last=m_index1==1639;assign m_last=m_pair==3 && m_pair_last;
    always_ff @(posedge clk)begin
        if(rst)begin
            state<=IDLE;active_frame<=0;input_pair<=0;join_pair<=0;input_index<=0;join_index<=0;
            hold_valid<=0;held[0]<='0;held[1]<='0;
            status_valid<=0;status_frame_id<=0;status_error<=0;status_error_code<=0;error_sticky<=0;
            accepted_observations<=0;emitted_observations<=0;cancelled_engine_observations<=0;
        end else begin
            if(consume)begin hold_valid<=0;emitted_observations<=emitted_observations+13'd2;end
            if(status_valid && status_ready)status_valid<=0;
            if(s_upstream_error)begin
                error_sticky<=1;
                if(state==IDLE || state==FINISH)state<=HALT;
            end
            if(state==IDLE && frame_start_valid && frame_start_ready)begin
                state<=RUN;active_frame<=frame_start_id;input_pair<=0;join_pair<=0;input_index<=0;join_index<=0;
                hold_valid<=0;status_valid<=0;status_frame_id<=frame_start_id;status_error<=0;status_error_code<=0;
                accepted_observations<=0;emitted_observations<=0;cancelled_engine_observations<=0;error_sticky<=0;
            end else if(state==RUN)begin
                if(admit)begin
                    accepted_observations<=accepted_observations+13'd2;
                    if(input_index==1638)begin input_index<=0;input_pair<=input_pair+1'b1;end
                    else input_index<=input_index+11'd2;
                end
                if(join_fire)begin
                    held[0]<=lane_output[0];held[1]<=lane_output[1];hold_valid<=1;
                    if(join_index==1638)begin join_index<=0;join_pair<=join_pair+1'b1;end
                    else join_index<=join_index+11'd2;
                end
                if(error_event)begin
                    state<=HALT;error_sticky<=1;status_valid<=1;status_error<=1;status_error_code<=error_code;
                    cancelled_engine_observations<={5'd0,lane_pending[0]}+{5'd0,lane_pending[1]};
                end else if(consume && m_last)begin state<=FINISH;status_valid<=1;status_error<=0;status_error_code<=0;end
            end else if(state==FINISH && !status_valid && !hold_valid && !s_upstream_error)state<=IDLE;
        end
    end
    // synthesis translate_off
    always @(posedge clk)if(!rst)begin
        if(admit && (!lane_ready[0] || !lane_ready[1]))$fatal(1,"OBS2 non-atomic input");
        if(join_fire && (!lane_valid[0] || !lane_valid[1] || join_tag_error))$fatal(1,"OBS2 non-atomic output");
        if(state==RUN && !error_event && (pending_pair_beats>129 ||
            {1'b0,accepted_observations}!={1'b0,emitted_observations}+{4'd0,pending_pair_beats,1'b0}))$fatal(1,"OBS2 credit accounting");
        if(state==RUN && consume && m_last && !error_event && (accepted_observations!=6560 || emitted_observations!=6558 ||
            lane_pending[0]!=0 || lane_pending[1]!=0 || join_fire))$fatal(1,"OBS2 false normal completion");
        if(state==IDLE && (hold_valid || lane_pending[0]!=0 || lane_pending[1]!=0))$fatal(1,"OBS2 stale frame boundary");
    end
    // synthesis translate_on
endmodule
