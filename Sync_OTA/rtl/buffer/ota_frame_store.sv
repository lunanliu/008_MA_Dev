`timescale 1ns/1ps
// Finite offline store. One accepted command is one credit; response is mandatory.
// rst is a platform-wide reset/drain boundary; cancel drains the current credit.
module ota_frame_store (
 input logic clk,rst,cancel,
 input logic start_valid, output logic start_ready,
 input logic [63:0] start_base_word, input logic [31:0] start_capacity,
 input logic s_valid, output logic s_ready, input logic [127:0] s_data,
 input logic seal,
 input logic replay_valid,output logic replay_ready,
 input logic [31:0] replay_first,replay_count,
 input logic release_frame,
 output logic m_valid,input logic m_ready,output logic [127:0] m_data,
 output logic [31:0] m_index,output logic m_last,
 output logic cmd_valid,input logic cmd_ready,output logic cmd_write,
 output logic [63:0] cmd_address,cmd_tag,output logic [127:0] cmd_data,
 input logic rsp_valid,output logic rsp_ready,input logic [63:0] rsp_tag,
 input logic [127:0] rsp_data,input logic rsp_error,
 output logic [31:0] generation,committed_words,read_words,
 output logic sealed,busy,output logic [7:0] error_code,
 output logic [31:0] stall_cycles
);
 typedef enum logic [3:0] {IDLE,CAPTURE,WRITE_WAIT,SEALED,READ_REQ,READ_WAIT,OUTPUT_WORD,DRAIN,FAILED} state_t;
 state_t state;
 logic [63:0] base;
 logic [31:0] capacity,serial,first_word,remaining;
 logic seal_pending;
 wire credit_pending=(state==WRITE_WAIT || state==READ_WAIT || state==DRAIN);
 assign start_ready=!rst&&!cancel&&state==IDLE;
 assign replay_ready=!rst&&!cancel&&state==SEALED;
 assign sealed=state==SEALED;
 assign busy=state!=IDLE;
 assign cmd_valid=!rst&&!cancel&&((state==CAPTURE&&s_valid&&!seal&&!seal_pending&&committed_words<capacity)||state==READ_REQ);
 assign cmd_write=state==CAPTURE;
 assign cmd_address=base+(cmd_write?{32'd0,committed_words}:{32'd0,first_word}+{32'd0,read_words});
 assign cmd_tag={generation,serial};
 assign cmd_data=s_data;
 assign s_ready=!rst&&!cancel&&state==CAPTURE&&!seal&&!seal_pending&&committed_words<capacity&&cmd_ready;
 assign rsp_ready=!rst&&credit_pending;
 assign m_valid=!rst&&!cancel&&state==OUTPUT_WORD;
 assign m_index=read_words;
 assign m_last=remaining==1;
 always_ff @(posedge clk) begin
  if(rst) begin
   state<=IDLE;base<=0;capacity<=0;serial<=0;generation<=0;
   committed_words<=0;read_words<=0;first_word<=0;remaining<=0;
   seal_pending<=0;m_data<=0;error_code<=0;stall_cycles<=0;
  end else begin
   if((cmd_valid&&!cmd_ready)||(m_valid&&!m_ready))stall_cycles<=stall_cycles+1'b1;
   if(seal&&(state==CAPTURE||state==WRITE_WAIT))seal_pending<=1;
   if(cancel) begin
    // A same-edge response returns the credit even when its data is discarded.
    if(credit_pending && !(rsp_valid&&rsp_ready&&rsp_tag=={generation,serial}))state<=DRAIN;
    else state<=IDLE;
    seal_pending<=0;
   end else if(rsp_valid&&rsp_ready&&(rsp_tag!={generation,serial} || rsp_error)) begin
    // Unmatched responses do NOT return our outstanding credit. Stay draining.
    error_code<=rsp_error?8'h21:8'h22;
    state<=(rsp_tag!={generation,serial})?DRAIN:FAILED;
   end else case(state)
    IDLE: if(start_valid&&start_ready) begin
     if(start_capacity==0 || start_base_word+{32'd0,start_capacity}<start_base_word || generation==32'hffffffff)begin
      state<=FAILED;error_code<=8'h10;
     end else begin
      base<=start_base_word;capacity<=start_capacity;generation<=generation+1'b1;
      committed_words<=0;read_words<=0;serial<=0;seal_pending<=0;error_code<=0;stall_cycles<=0;state<=CAPTURE;
     end
    end
    CAPTURE: if(seal||seal_pending)state<=SEALED;
     else if(cmd_valid&&cmd_ready)state<=WRITE_WAIT;
    WRITE_WAIT: if(rsp_valid&&rsp_ready)begin
     committed_words<=committed_words+1'b1;serial<=serial+1'b1;
     state<=(seal_pending||seal)?SEALED:CAPTURE;
    end
    SEALED: if(release_frame)state<=IDLE;
     else if(replay_valid&&replay_ready)begin
      if(replay_count==0 || replay_first>committed_words || replay_count>committed_words-replay_first)begin
       state<=FAILED;error_code<=8'h11;
      end else begin
       first_word<=replay_first;remaining<=replay_count;read_words<=0;state<=READ_REQ;
      end
     end
    READ_REQ: if(cmd_valid&&cmd_ready)state<=READ_WAIT;
    READ_WAIT: if(rsp_valid&&rsp_ready)begin m_data<=rsp_data;serial<=serial+1'b1;state<=OUTPUT_WORD;end
    OUTPUT_WORD: if(m_valid&&m_ready)begin
     read_words<=read_words+1'b1;remaining<=remaining-1'b1;
     state<=(remaining==1)?SEALED:READ_REQ;
    end
    DRAIN: if(rsp_valid&&rsp_ready)begin serial<=serial+1'b1;state<=IDLE;end
    FAILED: if(release_frame)state<=IDLE;
    default:begin state<=FAILED;error_code<=8'hff;end
   endcase
  end
 end
endmodule

