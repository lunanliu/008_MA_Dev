`timescale 1ns / 1ps
// Testbench-only passive monitor. Leaves every vendor assertion and DUT signal unchanged.
module sfo_fifo_history_observer (
    input wire wr_clk,
    input wire rd_clk,
    input wire rst,
    input wire wr_rst_busy,
    input wire rd_rst_busy,
    input wire wr_en,
    input wire rd_en,
    input wire full,
    input wire empty,
    input wire sleep,
    input wire overflow,
    input wire underflow
);
  string identity;
  logic [9:0] previous[0:1], older[0:1];
  real previous_time[0:1], older_time[0:1];
  integer count[0:1], tail[0:1];
  initial begin
    identity = $sformatf("%m");
    count[0] = 0;
    count[1] = 0;
    tail[0] = 0;
    tail[1] = 0;
    previous[0] = 'x;
    previous[1] = 'x;
    older[0] = 'x;
    older[1] = 'x;
    previous_time[0] = 0;
    previous_time[1] = 0;
    older_time[0] = 0;
    older_time[1] = 0;
  end
  task automatic sample (input integer domain);
    logic [9:0] v;
    logic enable, busy, blocked;
    real  now_ps;
    logic changed;
    begin
      v = {rst, wr_rst_busy, rd_rst_busy, wr_en, rd_en, full, empty, sleep, overflow, underflow};
      now_ps = $realtime * 1000;
      enable = domain == 0 ? wr_en : rd_en;
      busy = domain == 0 ? (rst || wr_rst_busy) : rd_rst_busy;
      blocked = domain == 0 ? full : empty;
      if (sleep === 1'b1 || overflow === 1'b1 || underflow === 1'b1)
        $fatal(1, "FULL023 FIFO sleep/overflow/underflow %s", identity);
      if (enable === 1'b1 && (busy !== 1'b0 || blocked !== 1'b0))
        $fatal(1, "FULL023 illegal FIFO access %s domain=%0d", identity, domain);
      if (now_ps > 1000000 && ($isunknown(
              enable
          ) || sleep !== 1'b0 || overflow !== 1'b0 || underflow !== 1'b0))
        $fatal(1, "FULL023 undefined FIFO control after startup %s", identity);
      changed = v[9:7] !== previous[domain][9:7] || v[2:0] !== previous[domain][2:0];
      // Dense first2us, then exact three-edge history around reset/busy/diagnostic changes.
      if (changed) begin
        if (count[domain] >= 2)
          sync_sfo_full_frame_tb.fifo_row(identity, domain, older_time[domain], older[domain]);
        if (count[domain] >= 1)
          sync_sfo_full_frame_tb.fifo_row(identity, domain, previous_time[domain],
                                          previous[domain]);
        tail[domain] = 3;
      end
      if (now_ps <= 2000000 || tail[domain] > 0)
        sync_sfo_full_frame_tb.fifo_row(identity, domain, now_ps, v);
      if (tail[domain] > 0) tail[domain] = tail[domain] - 1;
      older[domain] = previous[domain];
      older_time[domain] = previous_time[domain];
      previous[domain] = v;
      previous_time[domain] = now_ps;
      count[domain] = count[domain] + 1;
    end
  endtask
  always @(posedge wr_clk) sample (0);
  always @(posedge rd_clk) sample (1);
endmodule
bind xpm_fifo_base sfo_fifo_history_observer sfo_history_observer (.*);
