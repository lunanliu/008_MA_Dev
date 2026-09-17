`timescale 1ns/1ps
// A07: cancel wins new starts; retained store errors do not poison a new lease.
// Finite, single-frame/session manager; every port belongs to clk125.
// Physical DDR lease ends only after replay consumption and all responses drain.
module ota_capture_controller #(
 parameter integer MAX_CAPTURE_WORDS=524288,
 parameter integer OFFLINE_WAIT_CYCLES=1073741824
)(
 input wire clk125,rst125,cancel,
 input wire start_valid,output wire start_ready,input wire [63:0] start_base_word,input wire [31:0] start_words,
 input wire s_valid,output wire s_ready,input wire [127:0] s_data,
 output wire done,input wire done_ready,output wire busy,
 output logic [5:0] stage,output logic [7:0] error_code,
 output logic [31:0] accepted_words,output wire [31:0] committed_words,read_words,memory_stalls,
 output wire [31:0] frame_id,generation,output wire [63:0] nominal_absolute_sample,
 output logic [287:0] frontend_record,
 output wire fe_session_start,output wire fe_session_abort,
 output wire fe_s_valid,input wire fe_s_ready,output wire [127:0] fe_s_data,
 input wire fe_m_valid,output wire fe_m_ready,input wire [287:0] fe_m_record,
 input wire [31:0] fe_epoch,input wire [15:0] fe_error,
 output wire sfo_reset,output wire sfo_s_valid,input wire sfo_s_ready,
 output wire [127:0] sfo_s_data,output wire signed [31:0] sfo_absolute_index,
 output wire frame_valid,input wire frame_ready,output wire [187:0] frame_record,
 output wire coarse_valid,input wire coarse_ready,output wire [95:0] coarse_record,
 output wire fine_valid,input wire fine_ready,output wire [95:0] fine_record,
 output wire meta_valid,input wire meta_ready,output wire [213:0] meta_record,
 input wire algorithm_error,
 output wire cfo_cancel,input wire cfo_busy,
 input wire cfo_done_valid,output wire cfo_done_ready,input wire [7:0] cfo_done_error,
 input wire bridge_idle,input wire [7:0] bridge_error,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire [63:0] cmd_address,cmd_tag,output wire [127:0] cmd_data,
 input wire rsp_valid,output wire rsp_ready,input wire [63:0] rsp_tag,input wire [127:0] rsp_data,input wire rsp_error
);
 localparam [5:0] IDLE=0,OPEN=1,CAPTURE=2,SEAL=3,SCAN_START=4,SCAN_REQUEST=5,SCAN=6,
 WAIT_FRONTEND=7,ADAPT=8,ADAPT_WAIT=9,PRELOAD_BOOT=10,PRELOAD_REQUEST=11,PRELOAD=12,
 RELEASE_RAW=13,PUBLISH=14,PROCESS=15,DONE_WAIT=16,COMPLETE=17,CANCEL_DRAIN=18,CANCEL_RELEASE=19;
 // A full nominal frame plus its fixed raw halo cannot fit below this size.
 localparam integer MIN_CAPTURE_WORDS=334215;
 logic [63:0] base_word;
 logic [31:0] capture_words,scan_epoch,wait_cycles;
 logic found,meta_sent,descriptors_sent,seen_completion;
 logic [6:0] boot_cycles;
 wire mem_start_ready,mem_sealed,mem_busy,mem_sr,mem_mv,mem_mr,mem_last,mem_replay_ready;
 wire [127:0] mem_data;wire [31:0] mem_index,lease_generation;wire [7:0] mem_error;
 wire desc_sr,desc_frame_valid,desc_coarse_valid,desc_fine_valid,desc_done;wire [7:0] desc_error;
 wire [63:0] replay_first_sample;wire [31:0] replay_sample_count;
 wire signed [31:0] coarse_hz;wire signed [53:0] raw_origin;
 wire cancel_phase=stage==CANCEL_DRAIN;
 wire scan_feed=stage==SCAN&&!found;
 wire active=stage!=IDLE&&stage!=COMPLETE;
 wire [63:0] reserved_words=(start_words<334080)?64'd334080:{32'd0,start_words};
 assign start_ready=!rst125&&!cancel&&stage==IDLE&&!cfo_busy&&bridge_idle&&bridge_error==0;
 assign busy=stage!=IDLE;
 assign done=stage==COMPLETE;
 assign s_ready=!rst125&&!cancel&&stage==CAPTURE&&mem_sr;
 assign fe_session_start=stage==SCAN_START;
 assign fe_session_abort=cancel_phase;
 assign fe_s_valid=scan_feed&&mem_mv&&!cancel;
 assign fe_s_data=mem_data;
 assign fe_m_ready=(stage==SCAN||stage==WAIT_FRONTEND)&&!cancel;
 assign sfo_reset=rst125||stage<=ADAPT_WAIT||stage==COMPLETE||stage==CANCEL_DRAIN||stage==CANCEL_RELEASE;
 assign sfo_s_valid=stage==PRELOAD&&mem_mv&&!cancel;
 assign sfo_s_data=mem_data;
 assign sfo_absolute_index=-32'sd172+$signed({mem_index[29:0],2'b00});
 assign frame_valid=stage==PUBLISH&&desc_frame_valid&&!cancel;
 assign coarse_valid=stage==PUBLISH&&desc_coarse_valid&&!cancel;
 assign fine_valid=stage==PUBLISH&&desc_fine_valid&&!cancel;
 assign meta_valid=stage==PUBLISH&&!meta_sent&&!cancel;
 assign meta_record={base_word,frame_id,generation,coarse_hz,raw_origin};
 assign cfo_cancel=cancel_phase;
 assign cfo_done_ready=stage==PROCESS||stage==CANCEL_DRAIN||stage==DONE_WAIT;
 assign mem_mr=stage==SCAN?(found||fe_s_ready):(stage==PRELOAD?sfo_s_ready:1'b0);
 ota_frame_store raw_store(
  .clk(clk125),.rst(rst125),.cancel(cancel_phase||cancel),
  .start_valid(stage==OPEN),.start_ready(mem_start_ready),.start_base_word(base_word),.start_capacity(capture_words),
  .s_valid(s_valid&&stage==CAPTURE&&!cancel),.s_ready(mem_sr),.s_data(s_data),.seal(stage==SEAL),
  .replay_valid(stage==SCAN_REQUEST||stage==PRELOAD_REQUEST),.replay_ready(mem_replay_ready),
  .replay_first(stage==SCAN_REQUEST?32'd0:replay_first_sample[33:2]),
  .replay_count(stage==SCAN_REQUEST?capture_words:replay_sample_count[31:2]),
  .release_frame(stage==RELEASE_RAW&&mem_sealed),
  .m_valid(mem_mv),.m_ready(mem_mr),.m_data(mem_data),.m_index(mem_index),.m_last(mem_last),
  .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_address(cmd_address),.cmd_tag(cmd_tag),.cmd_data(cmd_data),
  .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.rsp_tag(rsp_tag),.rsp_data(rsp_data),.rsp_error(rsp_error),
  .generation(lease_generation),.committed_words(committed_words),.read_words(read_words),
  .sealed(mem_sealed),.busy(mem_busy),.error_code(mem_error),.stall_cycles(memory_stalls));
 ota_frontend_descriptor descriptor(
  .clk(clk125),.rst(rst125),.cancel(stage==IDLE||cancel_phase),
  .s_valid(stage==ADAPT),.s_ready(desc_sr),.s_record(frontend_record),
  .capture_epoch(scan_epoch),.capture_generation(lease_generation),.capture_samples({30'd0,capture_words,2'b00}),
  .frame_valid(desc_frame_valid),.frame_ready(frame_ready&&stage==PUBLISH&&!cancel),.frame_record(frame_record),
  .cfo_valid(desc_coarse_valid),.cfo_ready(coarse_ready&&stage==PUBLISH&&!cancel),.cfo_record(coarse_record),
  .fine_valid(desc_fine_valid),.fine_ready(fine_ready&&stage==PUBLISH&&!cancel),.fine_record(fine_record),
  .replay_first_sample(replay_first_sample),.nominal_absolute_sample(nominal_absolute_sample),.replay_sample_count(replay_sample_count),
  .frame_id(frame_id),.generation(generation),.coarse_hz_q8(coarse_hz),.raw_origin_q28(raw_origin),.done(desc_done),.error_code(desc_error));
 wire timed_stage=stage>=SCAN_START&&stage<=PROCESS;
 wire timed_out=timed_stage&&wait_cycles>=OFFLINE_WAIT_CYCLES-1;
 // An old store error is held for diagnostics until its new start handshake.
 // OPEN performs that handshake; a new invalid-start error is seen in CAPTURE.
 wire memory_failed=mem_error!=0&&stage!=OPEN;
 wire fault=bridge_error!=0||memory_failed||desc_error!=0||algorithm_error||timed_out;
 logic [5:0] previous_stage;
 always_ff @(posedge clk125)begin
  if(rst125)begin
   stage<=IDLE;previous_stage<=IDLE;error_code<=0;base_word<=0;capture_words<=0;scan_epoch<=0;
   wait_cycles<=0;accepted_words<=0;found<=0;frontend_record<=0;meta_sent<=0;descriptors_sent<=0;
   seen_completion<=0;boot_cycles<=0;
  end else begin
   previous_stage<=stage;
   if(stage!=previous_stage)wait_cycles<=0;
   else if(timed_stage)wait_cycles<=wait_cycles+1'b1;
   if(fe_m_valid&&fe_m_ready&&!found)begin frontend_record<=fe_m_record;found<=1;end
   if(desc_done)descriptors_sent<=1;
   if(meta_valid&&meta_ready)meta_sent<=1;
   if(cfo_done_valid&&cfo_done_ready)begin
    seen_completion<=1;
    if(cfo_done_error!=0&&error_code==0)error_code<=cfo_done_error;
   end
   // Same-edge priority is deliberate: cancel > bridge > memory > descriptor
   // > algorithm > timeout; a completed child error is subordinate on that edge.
   if(active&&stage!=CANCEL_DRAIN&&stage!=CANCEL_RELEASE&&(cancel||fault))begin
    stage<=CANCEL_DRAIN;
    if(error_code==0)error_code<=cancel?8'h01:(bridge_error!=0?8'h72:(memory_failed?8'h23:(desc_error!=0?desc_error:(algorithm_error?8'h50:8'h51))));
   end else case(stage)
    IDLE:if(start_valid&&start_ready)begin
     base_word<=start_base_word;capture_words<=start_words;accepted_words<=0;found<=0;frontend_record<=0;
     meta_sent<=0;descriptors_sent<=0;seen_completion<=0;error_code<=0;boot_cycles<=0;
     if(start_words<MIN_CAPTURE_WORDS||start_words>MAX_CAPTURE_WORDS||start_base_word+reserved_words<start_base_word)begin error_code<=8'h10;stage<=COMPLETE;end
     else stage<=OPEN;
    end
    OPEN:if(mem_start_ready)stage<=CAPTURE;
    CAPTURE:if(s_valid&&s_ready)begin accepted_words<=accepted_words+1'b1;if(accepted_words==capture_words-1)stage<=SEAL;end
    SEAL:if(mem_sealed)begin
     if(committed_words!=capture_words)begin error_code<=8'h24;stage<=CANCEL_DRAIN;end
     else stage<=SCAN_START;
    end
    SCAN_START:stage<=SCAN_REQUEST;
    SCAN_REQUEST:if(mem_replay_ready)begin scan_epoch<=fe_epoch;stage<=SCAN;end
    SCAN:if(mem_mv&&mem_mr&&mem_last)stage<=WAIT_FRONTEND;
    WAIT_FRONTEND:if(found)stage<=ADAPT;
     else if(fe_error!=0||wait_cycles>=262143)begin error_code<=8'h30;stage<=CANCEL_DRAIN;end
    ADAPT:if(desc_sr)stage<=ADAPT_WAIT;
    ADAPT_WAIT:if(desc_frame_valid)begin boot_cycles<=0;stage<=PRELOAD_BOOT;end
    PRELOAD_BOOT:if(boot_cycles==127)stage<=PRELOAD_REQUEST;else boot_cycles<=boot_cycles+1'b1;
    PRELOAD_REQUEST:if(mem_replay_ready)stage<=PRELOAD;
    PRELOAD:if(mem_mv&&mem_mr&&mem_last)stage<=RELEASE_RAW;
    RELEASE_RAW:if(mem_sealed)stage<=PUBLISH;
    PUBLISH:if(meta_sent&&descriptors_sent)stage<=PROCESS;
    PROCESS:if(cfo_done_valid&&cfo_done_ready)stage<=DONE_WAIT;
    DONE_WAIT:if(!cfo_busy&&!mem_busy&&bridge_idle)stage<=COMPLETE;
    CANCEL_DRAIN:if(seen_completion&&!mem_busy&&bridge_idle)stage<=CANCEL_RELEASE;
    CANCEL_RELEASE:if(!cfo_busy&&!mem_busy&&bridge_idle)stage<=COMPLETE;
    COMPLETE:if(done_ready)stage<=IDLE;
    default:begin error_code<=8'hff;stage<=CANCEL_DRAIN;end
   endcase
  end
 end
endmodule
