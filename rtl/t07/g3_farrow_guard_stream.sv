`timescale 1ns/1ps
// 053 guard-aware finite research transaction: C14 D16 M8 R28, 16 temporal complex lanes.
module g3_farrow_guard_stream #(
 // Historical parameter name: this is target_count, including requested guard.
 // In053 E1 target_count=4168; the nominal payload remains4096.
 parameter integer NOMINAL_SAMPLES=4096
)(
 input wire clk, reset, start,
 input wire [31:0] cfg_step,
 input wire signed [63:0] cfg_phase0,
 input wire [31:0] cfg_request_beats,
 input wire s_valid, output wire s_ready, input wire [511:0] s_data,
 output wire m_valid, input wire m_ready,
 output wire [511:0] m_data, output wire [31:0] m_tag,
 output wire issue_valid, output wire [31:0] issue_tag,
 output reg [2175:0] issue_window,
 output wire signed [63:0] issue_phase0,
 output reg [511:0] issue_base, output reg [127:0] issue_mu,
 output reg [6:0] credit_used, output reg [6:0] fifo_count,
 output wire [6:0] inflight, output reg [31:0] write_count,
 output wire done
);
 localparam [31:0] REQUEST_BEATS=(NOMINAL_SAMPLES+32)/4;
 reg started;
 reg [31:0] step, request_beats, issued, returned, popped;
 reg signed [63:0] phase0;
 // One setup adder fills the bank; steady state advances all lanes in parallel.
 reg signed [63:0] lane_phase [0:15];
 reg signed [63:0] init_phase;
 reg [3:0] init_lane;
 reg phase_ready;
 wire signed [63:0] step64=$signed({32'd0,step});
 wire signed [63:0] beat_step=step64<<<4;
 wire signed [63:0] init_next=init_phase+step64;
 reg [31:0] ring [0:63];
 reg [511:0] data_fifo [0:63];
 reg [31:0] tag_fifo [0:63];
 reg [5:0] wr_ptr, rd_ptr;
 wire core_ready, core_valid;
 wire [511:0] core_data;
 wire [31:0] core_tag;
 wire pending=started && (issued<request_beats);
 wire pop=m_valid && m_ready;
 wire push=core_valid && !reset;
 wire [32:0] next_write={1'b0,write_count}+33'd16;
 wire signed [63:0] written=$signed({32'd0,write_count});
 wire signed [63:0] oldest=(write_count>32'd64)?written-64'sd64:64'sd0;
 wire signed [63:0] oldest_after_write=(next_write>33'd64)?
     $signed({31'd0,next_write})-64'sd64:64'sd0;
 reg signed [63:0] min_index, max_index;
 reg signed [63:0] lane_base, address;
 reg [27:0] frac;
 reg [8:0] rounded_mu;
 reg round_up, windows_available;
 reg [31:0] sample_word;
 integer lane, tap;
 always @* begin
   issue_window=2176'd0;issue_base=512'd0;issue_mu=128'd0;
   min_index=64'sh7fffffffffffffff;max_index=-64'sd1;
   lane_base=64'sd0;address=64'sd0;
   frac=28'd0;rounded_mu=9'd0;round_up=1'b0;sample_word=32'd0;
   windows_available=1'b1;
   for(lane=0;lane<16;lane=lane+1)begin
     lane_base=lane_phase[lane]>>>28;
     frac=lane_phase[lane][27:0];
     round_up=(frac[19:0]>20'h80000) ||
              ((frac[19:0]==20'h80000) && frac[20]);
     rounded_mu={1'b0,frac[27:20]}+{8'd0,round_up};
     if(rounded_mu==9'd256)begin lane_base=lane_base+64'sd1;rounded_mu=9'd0;end
     issue_base[lane*32+:32]=lane_base[31:0];
     issue_mu[lane*8+:8]=rounded_mu[7:0];
     issue_window[2048+lane*8+:8]=rounded_mu[7:0];
     if(lane==0)min_index=lane_base-64'sd1;
     if(lane==15)max_index=lane_base+64'sd2;
     for(tap=0;tap<4;tap=tap+1)begin
       address=lane_base-64'sd1+tap;
       // Only committed, retained samples may appear in an accepted request.
       if(address<oldest || address>=written || address<0 || address>64'shffffffff)
         windows_available=1'b0;
       sample_word=ring[address[5:0]];
       issue_window[((lane*2)*4+tap)*16+:16]=sample_word[15:0];
       issue_window[((lane*2+1)*4+tap)*16+:16]=sample_word[31:16];
     end
     // Positive phase step and monotone RNE make endpoint bounds exact.
   end
 end
 // Conservative on a simultaneous issue/write: protect the old request until
 // its accepting edge. Both core sampling and ring reads see pre-NBA contents.
 assign s_ready=!reset && started && phase_ready && !next_write[32] &&
                 (!pending || oldest_after_write<=min_index);
 wire input_fire=s_valid && s_ready;
 assign issue_valid=!reset && phase_ready && pending && windows_available &&
                    (credit_used<7'd64) && core_ready;
 assign issue_tag=issued;
 assign issue_phase0=phase0;
 assign m_valid=!reset && (fifo_count!=0);
 assign m_data=m_valid?data_fifo[rd_ptr]:512'd0;
 assign m_tag=m_valid?tag_fifo[rd_ptr]:32'd0;
 assign inflight=credit_used-fifo_count;
 assign done=!reset && started && (popped==request_beats);
 farrow_microbench #(.C(14),.D(16),.M(8),.LANES(16)) arithmetic (
   .clk(clk),.reset(reset),.input_valid(issue_valid),
   .input_tag(issue_tag),.input_data(issue_window),.input_ready(core_ready),
   .output_valid(core_valid),.output_tag(core_tag),.output_data(core_data),
   .trace_data(),.saturation(),.trace_valid(),.trace_tag()
 );
 integer write_lane, phase_lane;
 always @(posedge clk)begin
   if(reset)begin
     started<=0;step<=0;request_beats<=0;phase0<=0;
     phase_ready<=0;init_phase<=0;init_lane<=0;
     for(phase_lane=0;phase_lane<16;phase_lane=phase_lane+1)
       lane_phase[phase_lane]<=0;
     issued<=0;returned<=0;popped<=0;write_count<=0;
     credit_used<=0;fifo_count<=0;wr_ptr<=0;rd_ptr<=0;
   end else begin
     if(start && !started)begin
       started<=1;step<=cfg_step;phase0<=cfg_phase0;request_beats<=cfg_request_beats;
       lane_phase[0]<=cfg_phase0;init_phase<=cfg_phase0;
       init_lane<=4'd1;phase_ready<=0;
     end else if(started && !phase_ready)begin
       lane_phase[init_lane]<=init_next;init_phase<=init_next;
       if(init_lane==4'd15)phase_ready<=1;
       else init_lane<=init_lane+4'd1;
     end
     if(input_fire)begin
       for(write_lane=0;write_lane<16;write_lane=write_lane+1)
         ring[(write_count[5:0]+write_lane)&63]<=s_data[write_lane*32+:32];
       write_count<=write_count+32'd16;
     end
     if(issue_valid)begin
       issued<=issued+32'd1;
       phase0<=phase0+beat_step;
       for(phase_lane=0;phase_lane<16;phase_lane=phase_lane+1)
         lane_phase[phase_lane]<=lane_phase[phase_lane]+beat_step;
     end
     if(push)begin
       data_fifo[wr_ptr]<=core_data;tag_fifo[wr_ptr]<=core_tag;
       wr_ptr<=wr_ptr+6'd1;returned<=returned+32'd1;
     end
     if(pop)begin rd_ptr<=rd_ptr+6'd1;popped<=popped+32'd1;end
     case({issue_valid,pop})
       2'b10:credit_used<=credit_used+7'd1;
       2'b01:credit_used<=credit_used-7'd1;
       default:credit_used<=credit_used;
     endcase
     case({push,pop})
       2'b10:fifo_count<=fifo_count+7'd1;
       2'b01:fifo_count<=fifo_count-7'd1;
       default:fifo_count<=fifo_count;
     endcase
   end
 end
 // synthesis translate_off
 initial if(NOMINAL_SAMPLES!=4096 && NOMINAL_SAMPLES!=4168 && NOMINAL_SAMPLES!=5120 && NOMINAL_SAMPLES!=5192 &&
            NOMINAL_SAMPLES!=1336320 && NOMINAL_SAMPLES!=1336392)
   $fatal(1,"Unsupported target sample count");
 integer check_lane;
 reg stalled;
 reg [511:0] held_data;
 reg [31:0] held_tag;
 always @(posedge clk)begin
   if(reset)begin stalled<=0;held_data<=0;held_tag<=0;end
   else begin
     if(start)begin
       if($isunknown({cfg_step,cfg_phase0,cfg_request_beats}))
         $fatal(1,"Unknown start configuration");
       if(started)$fatal(1,"Only one start is supported between initial resets");
       if(cfg_request_beats!=REQUEST_BEATS)
         $fatal(1,"Request count must match selected target profile");
       // T10 production callers validate the full first-pass +/-150 ppm range;
       // the second-pass descriptor additionally enforces +/-3 ppm and context.
       // The historical five fixture values were never a synthesized mux/table.
       if(cfg_step<32'd268395191 || cfg_step>32'd268475721)
         $fatal(1,"R28 step outside the production descriptor range +/-150 ppm");
       if(cfg_phase0<64'sd268435456 || cfg_phase0>64'sh0000ffffffffffff)
         $fatal(1,"Finite initial phase outside reviewed coordinate headroom");
     end
     if(!phase_ready && (issue_valid || s_ready))
       $fatal(1,"Handshake before phase initialization completed");
     if(phase_ready)begin
       if(step64<=0 || lane_phase[0]!==phase0)
         $fatal(1,"Lookahead origin or positive-step invariant");
       for(check_lane=0;check_lane<16;check_lane=check_lane+1)begin
         if($isunknown(lane_phase[check_lane]) || lane_phase[check_lane]<0 ||
            lane_phase[check_lane]>64'sh7fffffffffffffff-beat_step)
           $fatal(1,"Lookahead signed64 headroom");
         if(lane_phase[check_lane]!==phase0+check_lane*step64)
           $fatal(1,"Lookahead lane phase identity");
         if(check_lane>0 && issue_base[check_lane*32+:32]<issue_base[(check_lane-1)*32+:32])
           $fatal(1,"Rounded lane bases are not monotone");
       end
     end
     if(credit_used>64 || fifo_count>credit_used || credit_used!=(issued-popped) ||
        fifo_count!=(returned-popped) || returned>issued)
       $fatal(1,"Output reservation accounting violated");
     if(push && (fifo_count==64 || core_tag!==returned))
       $fatal(1,"Unreserved or reordered Farrow return");
     if(pop && m_tag!==popped)$fatal(1,"Output tag order violated");
     if(issue_valid && (min_index<oldest || max_index>=written || $isunknown(issue_window)))
       $fatal(1,"Farrow issued absent or overwritten samples");
     if(stalled && (!m_valid || m_data!==held_data || m_tag!==held_tag))
       $fatal(1,"Output changed while stalled");
     stalled<=m_valid && !m_ready;held_data<=m_data;held_tag<=m_tag;
   end
 end
 // synthesis translate_on
endmodule

