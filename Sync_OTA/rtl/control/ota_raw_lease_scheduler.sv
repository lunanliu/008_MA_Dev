`timescale 1ns/1ps
// Ordered raw control events, all ports in clk150. Event bit208 selects a
// frame lease; payload {frame32,generation32,raw_first64,fine32,hz32,quality16}.
// A watermark event carries an absolute 128-bit-word ordinal in bits63:0.
// Caller enqueues lease creation before any watermark that stops protecting it.
module ota_raw_lease_scheduler(
 input wire clk,rst,poison,
 input wire s_valid,output wire s_ready,input wire [208:0] s_event,
 output wire floor_valid,output wire [63:0] retire_floor,
 input wire frame_launch,input wire [31:0] launch_frame,launch_generation,
 input wire [63:0] launch_first,
 output wire launch_matches,output wire lease_head_valid,
 output wire train_valid,input wire train_ready,output wire [207:0] train_record,
 output logic fault,output logic [7:0] error_code
);
 wire is_frame=s_event[208];
 wire [63:0] event_first=s_event[143:80];
 wire lsr,lsv,tsr,le,te,lb,tb;
 wire [127:0] ld;
 logic [5:0] lease_count;
 logic [63:0] observed_floor,held_pin,last_first;
 logic have_previous;
 wire stopped=poison||fault;
 assign s_ready=!rst&&!stopped&&(!is_frame||(lsr&&tsr));
 wire take=s_valid&&s_ready,create=take&&is_frame;
 assign lease_head_valid=!rst&&!stopped&&lsv;
 assign launch_matches=!rst&&!stopped&&lsv&&ld=={launch_frame,launch_generation,launch_first};
 wire release_lease=frame_launch&&launch_matches;
 sfo_sync_fifo #(.WIDTH(128),.DEPTH(32)) frame_leases(
  .clk(clk),.rst(rst),.s_valid(create),.s_ready(lsr),
  .s_data({s_event[207:144],event_first}),.m_valid(lsv),.m_ready(release_lease),.m_data(ld),
  .level(),.high_water(),.reset_busy(lb),.error_sticky(le));
 wire tv;
 sfo_sync_fifo #(.WIDTH(208),.DEPTH(32)) training_jobs(
  .clk(clk),.rst(rst),.s_valid(create),.s_ready(tsr),.s_data(s_event[207:0]),
  .m_valid(tv),.m_ready(train_ready&&!stopped),.m_data(train_record),
  .level(),.high_water(),.reset_busy(tb),.error_sticky(te));
 assign train_valid=tv&&!rst&&!stopped;
 // A stale lower pin is safe during FWFT presentation latency. Never replace
 // an absent head by infinity while the registered lease count is nonzero.
 assign retire_floor=observed_floor<held_pin?observed_floor:held_pin;
 assign floor_valid=!rst&&!stopped&&!lb&&!tb;
 always_ff @(posedge clk)begin
  if(rst)begin
   fault<=0;error_code<=0;lease_count<=0;observed_floor<=0;held_pin<=0;last_first<=0;have_previous<=0;
  end else if(!stopped)begin
   if(le||te)begin fault<=1;error_code<=8'h11;end
   else if(frame_launch&&!launch_matches)begin fault<=1;error_code<=8'h12;end
   else if(take&&!is_frame&&s_event[63:0]<observed_floor)begin fault<=1;error_code<=8'h13;end
   else if(create&&(event_first<observed_floor||(have_previous&&event_first<=last_first)))begin fault<=1;error_code<=8'h14;end
   if(take&&!is_frame)observed_floor<=s_event[63:0];
   if(create)begin have_previous<=1;last_first<=event_first;end
   case({create,release_lease})
    2'b10:lease_count<=lease_count+1'b1;
    2'b01:lease_count<=lease_count-1'b1;
    default:begin end
   endcase
   if(lease_count==0)held_pin<=create?event_first:64'hffffffffffffffff;
   else if(lsv)held_pin<=ld[63:0];
   // On release the old head pin is retained until the next head is visible.
   // The raw-store active reader takes ownership on exactly frame_launch.
  end
 end
endmodule
