`timescale 1ns/1ps
// clk125. Fill the existing T06 private training RAM before publishing its
// coarse/fine inputs, so the T06 compute watchdog never includes producer wait.
// cfg: {frame32,generation32,raw_first64,fine_local32,coarse_hz32,quality16}.
// data: {frame32,generation32,beat32,last1,IQ128}; exactly 5172 beats.
// The caller may reuse that RAM only after the returned release token.
module ota_training_dispatch(
 input wire clk,rst,poison,
 input wire cfg_valid,output wire cfg_ready,input wire [207:0] cfg_record,
 input wire s_valid,output wire s_ready,input wire [224:0] s_record,
 output wire tap_fire,output wire [127:0] tap_data,output wire [31:0] tap_frame,
 output wire signed [31:0] tap_absolute,
 output wire frame_valid,input wire frame_ready,output wire [187:0] frame_record,
 output wire coarse_valid,input wire coarse_ready,output wire [95:0] coarse_record,
 output wire fine_valid,input wire fine_ready,output wire [95:0] fine_record,
 output wire meta_valid,input wire meta_ready,output wire [149:0] meta_record,
 input wire initial_done_valid,output wire initial_done_ready,input wire [31:0] initial_done_frame,
 output wire release_valid,input wire release_ready,output wire [63:0] release_record,
 output logic fault,output logic [7:0] error_code
);
 localparam [2:0] IDLE=0,FILL=1,PUBLISH=2,WAIT_RESULT=3,RELEASE=4;
 logic [2:0] state;
 logic [207:0] context_record;
 logic [12:0] expected_beat;
 logic [3:0] pending;
 wire stopped=rst||poison||fault;
 wire [31:0] frame=context_record[207:176],generation=context_record[175:144];
 wire [31:0] fine=context_record[79:48],hz=context_record[47:16];
 wire [15:0] quality=context_record[15:0];
 wire take=s_valid&&s_ready;
 wire data_good=s_record[224:193]==frame&&s_record[192:161]==generation&&
                s_record[160:129]=={19'd0,expected_beat}&&s_record[128]==(expected_beat==5171);
 assign cfg_ready=!stopped&&state==IDLE;
 assign s_ready=!stopped&&state==FILL;
 assign tap_fire=take&&data_good;
 assign tap_data=s_record[127:0];assign tap_frame=frame;
 assign tap_absolute=32'sd5272+$signed({17'd0,expected_beat,2'b00});
 assign frame_valid=!stopped&&state==PUBLISH&&pending[0];
 assign coarse_valid=!stopped&&state==PUBLISH&&pending[1];
 assign fine_valid=!stopped&&state==PUBLISH&&pending[2];
 assign meta_valid=!stopped&&state==PUBLISH&&pending[3];
 assign frame_record={frame,generation,context_record[143:80],32'd0,28'd0};
 assign coarse_record={hz,quality,16'h2800,frame};
 assign fine_record={fine,quality,16'h3800,frame};
 assign meta_record={frame,generation,(hz<<8),24'd0,fine[1:0],28'd0};
 wire [3:0] sent={meta_valid&&meta_ready,fine_valid&&fine_ready,coarse_valid&&coarse_ready,frame_valid&&frame_ready};
 assign initial_done_ready=!stopped&&state==WAIT_RESULT;
 assign release_valid=!stopped&&state==RELEASE;
 assign release_record={frame,generation};
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;context_record<=0;expected_beat<=0;pending<=0;fault<=0;error_code<=0;end
  else if(!fault)begin
   if(poison)begin fault<=1;error_code<=8'h01;end
   else case(state)
    IDLE:if(cfg_valid&&cfg_ready)begin
     context_record<=cfg_record;expected_beat<=0;
     if(cfg_record[79:48]>3||$signed(cfg_record[47:16]) < -32'sd8388607||$signed(cfg_record[47:16])>32'sd8388607)begin fault<=1;error_code<=8'h02;end
     else state<=FILL;
    end
    FILL:if(take)begin
     if(!data_good)begin fault<=1;error_code<=8'h03;end
     else if(expected_beat==5171)begin pending<=4'b1111;state<=PUBLISH;end
     else expected_beat<=expected_beat+1'b1;
    end
    PUBLISH:begin pending<=pending&~sent;if((pending&~sent)==0)state<=WAIT_RESULT;end
    WAIT_RESULT:if(initial_done_valid&&initial_done_ready)begin
     if(initial_done_frame!=frame)begin fault<=1;error_code<=8'h04;end
     else state<=RELEASE;
    end
    RELEASE:if(release_ready)state<=IDLE;
    default:begin fault<=1;error_code<=8'h05;end
   endcase
  end
 end
endmodule
