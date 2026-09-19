`timescale 1ns/1ps
// V5.1 dual-bank coarse/final CFO pipeline. No intermediate DDR transactions.
// All control and final IQ run at150; the unchanged window FFT runs at500.
// Final output has no ready input: every m_valid is irrevocably transferred.
module ota_cfo_chain_onchip(
 input wire clk150,clk500,reset_request,cancel150,
 input wire context_valid,output wire context_ready,input wire [213:0] context_record,
 input wire s_valid,output wire s_ready,input wire [224:0] s_record,
 output wire m_valid,output wire [224:0] m_record,output wire done,
 output logic [31:0] done_frame,done_generation,
 output wire busy,output logic fault,output logic [7:0] error_code,
 output logic [31:0] completed_frames,coarse_beats,final_beats,coarse_saturations,final_saturations,
 output wire [12:0] window_buffered_words,output wire [6:0] observation_windows,
 output logic [498:0] estimator_result
);
 localparam [2:0] FREE=0,FILL=1,SEALED=2,READING=3;
 localparam [2:0] C_IDLE=0,C_COORD=1,C_WAIT=2,C_FEED=3,C_CFG=4;
 localparam [2:0] F_IDLE=0,F_COORD=1,F_WAIT=2,F_READ=3,F_CFG=4;
 wire rst150,rst500;
 logic compute_cancel;
 sfo_domain_reset reset_slow(.clk(clk150),.reset_request(reset_request),.reset_active(rst150));
 always_ff @(posedge clk150)begin
  if(rst150)compute_cancel<=0;else compute_cancel<=cancel150||fault;
 end
 xpm_cdc_async_rst #(.DEST_SYNC_FF(4),.INIT_SYNC_FF(0),.RST_ACTIVE_HIGH(1)) reset_fast(
  .src_arst(reset_request||compute_cancel),.dest_clk(clk500),.dest_arst(rst500));
 wire stopped=rst150||cancel150||fault;
 logic [2:0] bank_state[0:1];
 logic [31:0] bank_frame[0:1],bank_gen[0:1],bank_step1[0:1],bank_step2[0:1];
 logic signed [53:0] bank_origin[0:1];
 logic signed [31:0] bank_coarse[0:1],bank_residual[0:1];
 logic [1:0] bank_estimated;
 logic [31:0] coarse_phase[0:1],coarse_step[0:1],final_phase[0:1],final_step[0:1];
 logic next_write,next_final,wb,fb;
 logic [2:0] cs,fs;
 wire qcfg_ready,qsample_ready,qfault;
 wire [7:0] qerror;
 assign context_ready=!stopped&&cs==C_IDLE&&bank_state[next_write]==FREE&&qcfg_ready;
 wire context_take=context_valid&&context_ready;
 logic [1:0] input_count;
 logic input_closed;
 logic [224:0] input_head,input_tail;
 wire r1_sr,r1_v,r2_sr,r2_v,r1_cfg_ready,r2_cfg_ready,r1_fault,r2_fault;
 wire [224:0] r1_record,r2_record;wire [7:0] sat1,sat2;wire [3:0] r1_error,r2_error;
 assign s_ready=!stopped&&cs==C_FEED&&!input_closed&&input_count<2;
 wire input_push=s_valid&&s_ready;
 wire input_pop=!stopped&&cs==C_FEED&&input_count!=0&&r1_sr;
 always_ff @(posedge clk150)begin
  if(stopped||cs!=C_FEED)begin input_count<=0;input_closed<=0;end
  else begin
   case({input_push,input_pop})2'b10:input_count<=input_count+1'b1;2'b01:input_count<=input_count-1'b1;default:begin end endcase
   if(input_push)begin
    if(input_count==0||(input_count==1&&input_pop))input_head<=s_record;else input_tail<=s_record;
    if(s_record[128])input_closed<=1;
   end
   if(input_pop&&input_count==2)input_head<=input_tail;
  end
 end
 // Only this owner register selects coordinate results. Final requests have
 // priority; neither requester can issue another while its prior job is active.
 logic coordinate_busy,coordinate_owner,coordinate_bank;
 wire request_final=fs==F_COORD;
 wire request_coarse=cs==C_COORD;
 wire selected_bank=request_final?fb:wb;
 wire coord_sr,coord_v,coord_r,coord_ok,coord_residual;
 wire [31:0] coord_frame,coord_gen,phase0,phase_step;wire [3:0] coord_error;
 wire coord_start=!stopped&&!coordinate_busy&&(request_final||request_coarse);
 wire coord_identity=coord_frame==bank_frame[coordinate_bank]&&coord_gen==bank_gen[coordinate_bank]&&coord_residual==coordinate_owner;
 assign coord_r=!stopped&&coordinate_busy;
 wire coarse_cfg=!stopped&&cs==C_CFG;
 wire final_cfg=!stopped&&fs==F_CFG;
 cfo_coordinate_control coordinate(
  .clk(clk150),.rst(rst150),.abort_sync(cancel150||fault),
  .s_valid(coord_start),.s_ready(coord_sr),.s_frame(bank_frame[selected_bank]),.s_generation(bank_gen[selected_bank]),
  .s_residual(request_final),.s_frequency_code(request_final?bank_residual[selected_bank]:bank_coarse[selected_bank]),
  .s_step1_q28(bank_step1[selected_bank]),.s_step2_q28(bank_step2[selected_bank]),.s_raw_origin_q28(bank_origin[selected_bank]),
  .m_valid(coord_v),.m_ready(coord_r),.m_frame(coord_frame),.m_generation(coord_gen),.m_residual(coord_residual),
  .m_ok(coord_ok),.m_error(coord_error),.m_step(phase_step),.m_phase0(phase0),.m_step48(),.m_phase48(),.m_origin_output_q16());
 cfo_rotate4 coarse_rotation(
  .clk(clk150),.rst(rst150),.abort_sync(cancel150||fault),
  .cfg_valid(coarse_cfg),.cfg_ready(r1_cfg_ready),.cfg_frame(bank_frame[wb]),.cfg_generation(bank_gen[wb]),
  .cfg_phase0(coarse_phase[wb]),.cfg_step(coarse_step[wb]),.cfg_sample_count(32'd1336320),
  .s_valid(!stopped&&cs==C_FEED&&input_count!=0),.s_ready(r1_sr),.s_record(input_head),
  .m_valid(r1_v),.m_ready(qsample_ready&&cs==C_FEED&&!stopped),.m_record(r1_record),.m_saturation(sat1),.fault(r1_fault),.first_error(r1_error));
 wire coarse_fire=r1_v&&qsample_ready&&cs==C_FEED&&!stopped;
 wire fast_v,fast_r;wire [134:0] fast_record;
 ota_cfo_window_queue windows(
  .clk150(clk150),.clk500(clk500),.reset_request(reset_request),.poison150(cancel150||fault),
  .cfg_valid(context_take),.cfg_ready(qcfg_ready),.cfg_frame(context_record[213:182]),.cfg_generation(context_record[181:150]),
  .s_valid(r1_v&&cs==C_FEED&&!stopped),.s_ready(qsample_ready),.s_record(r1_record),
  .m_valid(fast_v),.m_ready(fast_r),.m_record(fast_record),.buffered_words150(window_buffered_words),
  .windows_captured(observation_windows),.fault150(qfault),.error150(qerror));
 wire [31:0] obs_frame,obs_gen;wire [6:0] obs_window;wire signed [37:0] obs_i,obs_q;
 wire [9:0] obs_pilots;wire [15:0] obs_sat;wire [3:0] front_error,link_error,link_front_error;
 wire front_v,front_r,link_v;wire [498:0] link_record;
 wire observation_overflow,observation_underflow;
 cfo_front2048_window observation_front(
  .clk(clk500),.rst(rst500),.abort_sync(1'b0),.s_valid(fast_v),.s_ready(fast_r),
  .s_frame(fast_record[134:103]),.s_generation(fast_record[102:71]),.s_window(fast_record[70:64]),
  .s_index(fast_record[63:53]),.s_last(fast_record[52]),.s_i(fast_record[51:26]),.s_q(fast_record[25:0]),
  .m_valid(front_v),.m_ready(front_r),.m_frame(obs_frame),.m_generation(obs_gen),.m_window(obs_window),
  .m_z_i(obs_i),.m_z_q(obs_q),.m_pilot_count(obs_pilots),.m_fft_saturations(obs_sat),.m_error(front_error));
 cfo_estimator_link estimator(
  .clk_fast(clk500),.clk_slow(clk150),.reset_async(reset_request),.abort_async(compute_cancel),
  .s_valid(front_v),.s_ready(front_r),.s_frame(obs_frame),.s_generation(obs_gen),.s_window(obs_window),
  .s_z_i(obs_i),.s_z_q(obs_q),.s_pilot_count(obs_pilots),.s_fft_saturations(obs_sat),.s_front_error(front_error),
  .m_valid(link_v),.m_ready(!stopped),.m_backend_word(link_record),.m_link_error(link_error),.m_front_error(link_front_error),
  .m_fft_saturation_sum(),.fifo_write_count(),.fifo_read_count(),.fifo_full(),.fifo_empty(),
  .fifo_overflow(observation_overflow),.fifo_underflow(observation_underflow),.fast_reset_busy(),.slow_reset_busy(),
  .read_audit_valid(),.read_audit_word(),.normal_audit_valid(),.normal_audit_index(),.fft_audit_valid(),.fft_audit_index());
 wire match0=bank_state[0]!=FREE&&bank_frame[0]==link_record[498:467]&&bank_gen[0]==link_record[466:435];
 wire match1=bank_state[1]!=FREE&&bank_frame[1]==link_record[498:467]&&bank_gen[1]==link_record[466:435];
 wire backend_good=(match0^match1)&&!bank_estimated[match1]&&link_error==0&&link_front_error==0&&link_record[434:431]==0&&link_record[428];
 // Final read port: every issued word reserves a FIFO entry until consumed by
 // r2. These counters are local to the final job and independent of coarse IQ.
 logic [31:0] issued,returned,consumed;
 logic [18:0] emitted_in_job;
 logic [1:0] rv;
 wire fq_sr,fq_v,fq_busy,fq_error;wire [127:0] fq_data;
 logic [6:0] outstanding;
 wire issue=!stopped&&fs==F_READ&&issued<334080&&outstanding<64&&fq_sr&&!fq_busy;
 wire pop=!stopped&&fs==F_READ&&fq_v&&r2_sr;
 wire [127:0] bank_data[0:1];
 genvar b;
 generate for(b=0;b<2;b=b+1)begin : coarse_banks
  sfo_uram_frame_bank #(.DEPTH_BEATS(335872),.ADDR_WIDTH(19)) memory(
   .clk(clk150),.rst(rst150),.wr_en(coarse_fire&&wb==b),.wr_addr(r1_record[147:129]),.wr_data(r1_record[127:0]),
   .rd_en(issue&&fb==b),.rd_addr(issued[18:0]),.rd_data(bank_data[b]));
 end endgenerate
 sfo_sync_fifo #(.WIDTH(128),.DEPTH(64)) final_responses(
  .clk(clk150),.rst(rst150),.s_valid(rv[1]),.s_ready(fq_sr),.s_data(bank_data[fb]),
  .m_valid(fq_v),.m_ready(pop),.m_data(fq_data),.level(),.high_water(),.reset_busy(fq_busy),.error_sticky(fq_error));
 wire [224:0] final_input={bank_frame[fb],bank_gen[fb],consumed,(consumed==334079),fq_data};
 cfo_rotate4 final_rotation(
  .clk(clk150),.rst(rst150),.abort_sync(cancel150||fault),
  .cfg_valid(final_cfg),.cfg_ready(r2_cfg_ready),.cfg_frame(bank_frame[fb]),.cfg_generation(bank_gen[fb]),
  .cfg_phase0(final_phase[fb]),.cfg_step(final_step[fb]),.cfg_sample_count(32'd1336320),
  .s_valid(!stopped&&fs==F_READ&&fq_v),.s_ready(r2_sr),.s_record(final_input),
  .m_valid(r2_v),.m_ready(1'b1),.m_record(r2_record),.m_saturation(sat2),.fault(r2_fault),.first_error(r2_error));
 logic [1:0] output_valid;logic [224:0] output0,output1;logic [7:0] saturation0,saturation1;
 assign m_valid=output_valid[1]&&!stopped;assign m_record=output1;
 logic done_q;
 wire tail_event=m_valid&&m_record[128];
 wire tail_good=fs==F_READ&&bank_state[fb]==READING&&emitted_in_job==334079&&issued==334080&&returned==334080&&consumed==334080&&outstanding==0&&m_record[224:193]==bank_frame[fb]&&m_record[192:161]==bank_gen[fb]&&m_record[160:129]==334079;
 // Success is a registered event after the tail has passed integrity checks.
 // Its identity is independent of subsequent IQ bus contents.
 assign done=done_q&&!stopped;
 logic [7:0] detected_error;
 always_comb begin
  detected_error=0;
  if(cancel150)detected_error=8'h01;
  else if(r1_fault||r2_fault)detected_error=r1_fault?8'h30:8'h31;
  else if(qfault)detected_error=8'h40;
  else if(fq_error||(rv[1]&&!fq_sr)||outstanding>64||consumed>returned||returned>issued)detected_error=8'h50;
  else if(coord_v&&coord_r&&(!coord_ok||!coord_identity))detected_error=8'h60;
  else if(link_v&&!backend_good)detected_error=8'h70;
  else if(coarse_fire&&bank_state[wb]!=FILL)detected_error=8'h71;
  else if(tail_event&&!tail_good)detected_error=8'h72;
 end
 assign busy=cs!=C_IDLE||fs!=F_IDLE||bank_state[0]!=FREE||bank_state[1]!=FREE;
 function automatic [3:0] pop8(input [7:0] v);integer j;begin pop8=0;for(j=0;j<8;j=j+1)pop8=pop8+v[j];end endfunction
 integer k;
 always_ff @(posedge clk150)begin
  if(rst150)begin
   for(k=0;k<2;k=k+1)begin
    bank_state[k]<=FREE;bank_frame[k]<=0;bank_gen[k]<=0;bank_step1[k]<=0;bank_step2[k]<=0;
    bank_origin[k]<=0;bank_coarse[k]<=0;bank_residual[k]<=0;
    coarse_phase[k]<=0;coarse_step[k]<=0;final_phase[k]<=0;final_step[k]<=0;
   end
   bank_estimated<=0;next_write<=0;next_final<=0;wb<=0;fb<=0;cs<=C_IDLE;fs<=F_IDLE;
   coordinate_busy<=0;coordinate_owner<=0;coordinate_bank<=0;
   issued<=0;returned<=0;consumed<=0;outstanding<=0;emitted_in_job<=0;rv<=0;output_valid<=0;
   done_q<=0;done_frame<=0;done_generation<=0;
   fault<=0;error_code<=0;completed_frames<=0;coarse_beats<=0;final_beats<=0;
   coarse_saturations<=0;final_saturations<=0;estimator_result<=0;
  end else begin
   done_q<=0;
   rv<={rv[0],issue};
   if(stopped)output_valid<=0;
   else begin
    output_valid<={output_valid[0],r2_v};
    if(r2_v)begin output0<=r2_record;saturation0<=sat2;end
    if(output_valid[0])begin output1<=output0;saturation1<=saturation0;end
    if(context_take)begin
     wb<=next_write;next_write<=!next_write;cs<=C_COORD;bank_state[next_write]<=FILL;bank_estimated[next_write]<=0;
     {bank_frame[next_write],bank_gen[next_write],bank_step1[next_write],bank_step2[next_write],bank_origin[next_write],bank_coarse[next_write]}<=context_record;
    end
    if(fs==F_IDLE&&bank_state[next_final]==SEALED&&bank_estimated[next_final]&&!fq_v&&!fq_busy&&rv==0)begin
     fb<=next_final;fs<=F_COORD;bank_state[next_final]<=READING;
     issued<=0;returned<=0;consumed<=0;outstanding<=0;emitted_in_job<=0;
    end
    if(coord_start&&coord_sr)begin
     coordinate_busy<=1;coordinate_owner<=request_final;coordinate_bank<=selected_bank;
     if(request_final)fs<=F_WAIT;else cs<=C_WAIT;
    end
    if(coord_v&&coord_r)begin
     coordinate_busy<=0;
     if(coordinate_owner)begin final_phase[coordinate_bank]<=phase0;final_step[coordinate_bank]<=phase_step;fs<=F_CFG;end
     else begin coarse_phase[coordinate_bank]<=phase0;coarse_step[coordinate_bank]<=phase_step;cs<=C_CFG;end
    end
    if(coarse_cfg&&r1_cfg_ready)cs<=C_FEED;
    if(final_cfg&&r2_cfg_ready)fs<=F_READ;
    if(coarse_fire)begin
     coarse_beats<=coarse_beats+1'b1;coarse_saturations<=coarse_saturations+pop8(sat1);
     if(r1_record[128])begin bank_state[wb]<=SEALED;cs<=C_IDLE;end
    end
    if(link_v)begin
     estimator_result<=link_record;
     if(backend_good)begin bank_estimated[match1]<=1;bank_residual[match1]<=link_record[427:396];end
    end
    case({issue,pop})2'b10:outstanding<=outstanding+1'b1;2'b01:outstanding<=outstanding-1'b1;default:begin end endcase
    if(issue)issued<=issued+1'b1;
    if(rv[1])returned<=returned+1'b1;
    if(pop)consumed<=consumed+1'b1;
    if(m_valid)begin emitted_in_job<=emitted_in_job+1'b1;final_beats<=final_beats+1'b1;final_saturations<=final_saturations+pop8(saturation1);end
    if(tail_event&&detected_error==0)begin
     bank_state[fb]<=FREE;bank_estimated[fb]<=0;fs<=F_IDLE;next_final<=!next_final;completed_frames<=completed_frames+1'b1;
     done_q<=1;done_frame<=m_record[224:193];done_generation<=m_record[192:161];
    end
   end
   if(!fault&&detected_error!=0)begin fault<=1;error_code<=detected_error;end
  end
 end
endmodule
