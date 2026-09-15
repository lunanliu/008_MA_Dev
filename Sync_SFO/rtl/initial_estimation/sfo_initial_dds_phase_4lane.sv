`timescale 1ns / 1ps
// Four official cores: fixed PINC=0, reset accumulator=0, streamed 32-bit POFF.
// Vivado 2021.1's LUT-only/Taylor mode rejects a 32-bit phase, so the approved
// equivalent mapping uses official 0+POFF modulo 2^32, with no phase truncation.
module sfo_initial_dds_phase_4lane (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         s_valid,
    output logic         s_ready,
    input  logic [127:0] s_phase,
    input  logic [ 31:0] s_tag,
    output logic         m_valid,
    input  logic         m_ready,
    output logic [ 71:0] m_cosine,
    output logic [ 71:0] m_sine,
    output logic [ 31:0] m_tag,
    output logic         protocol_error_sticky
);
  logic [1:0] reset_release;
  logic ip_aresetn, launch, retire, launch_dummy, held_dummy;
  logic real_input_fire, real_output_fire, native_input_fire, native_output_fire;
  logic [15:0] outstanding_real;
  logic [3:0] ready_lane, valid_lane;
  logic [47:0] data_lane[0:3];
  logic [32:0] tag_lane[0:3];
  logic tag_agrees;
  assign ip_aresetn = rst_n && reset_release[1];
  assign tag_agrees = tag_lane[0] == tag_lane[1] && tag_lane[0] == tag_lane[2] &&
      tag_lane[0] == tag_lane[3];
  // Native 2021.1 finite-burst experiment leaves 11 real transactions inside
  // the pipeline. Explicitly marked dummy phases advance that tail. They are
  // not logical requests and their coefficients never leave this wrapper.
  // Hold a stalled dummy transaction even if a real request arrives later.
  assign launch_dummy = held_dummy || (!s_valid && outstanding_real != 0);
  assign s_ready = ip_aresetn && !protocol_error_sticky && (&ready_lane) && !launch_dummy;
  // AXI valid must not wait for ready, and output ready must not wait for
  // valid: the official core may stall its pipeline while output ready=0.
  // Uniform-lane guards fail closed on a lane-control disagreement.
  assign launch = (s_valid || launch_dummy) && ip_aresetn && !protocol_error_sticky &&
      ((ready_lane == 4'b0000) || (ready_lane == 4'b1111));
  assign m_valid = ip_aresetn && !protocol_error_sticky && (&valid_lane) && tag_agrees &&
      tag_lane[0][32];
  assign retire = ip_aresetn && !protocol_error_sticky &&
      ((valid_lane == 4'b0000) || ((&valid_lane) && tag_agrees && (!tag_lane[0][32] || m_ready)));
  assign m_tag = tag_lane[0][31:0];
  assign real_input_fire = s_valid && s_ready;
  assign real_output_fire = m_valid && m_ready;
  assign native_input_fire = launch && (&ready_lane);
  assign native_output_fire = retire && (&valid_lane);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      reset_release <= 2'b00;
      protocol_error_sticky <= 1'b0;
      held_dummy <= 1'b0;
      outstanding_real <= '0;
    end else begin
      reset_release <= {reset_release[0], 1'b1};
      if (ip_aresetn) begin
        if (launch && launch_dummy) held_dummy <= !native_input_fire;
        case ({
          real_input_fire, real_output_fire
        })
          2'b10:   outstanding_real <= outstanding_real + 1'b1;
          2'b01:   outstanding_real <= outstanding_real - 1'b1;
          default: outstanding_real <= outstanding_real;
        endcase
        if ((real_input_fire && !real_output_fire && outstanding_real == 16'hffff) ||
            (real_output_fire && outstanding_real == 0))
          protocol_error_sticky <= 1'b1;
      end
      if (ip_aresetn &&
          ((valid_lane != 4'b0000 && valid_lane != 4'b1111) ||
           (ready_lane != 4'b0000 && ready_lane != 4'b1111) || ((&valid_lane) && !tag_agrees)))
        protocol_error_sticky <= 1'b1;
    end
  end
  for (genvar lane = 0; lane < 4; lane++) begin : g_dds
    t06_dds_phase_s32_sincos18 u_dds (
        .aclk               (clk),
        .aresetn            (ip_aresetn),
        .s_axis_phase_tvalid(launch),
        .s_axis_phase_tready(ready_lane[lane]),
        .s_axis_phase_tdata (launch_dummy ? 32'b0 : s_phase[32*lane+:32]),
        .s_axis_phase_tuser (launch_dummy ? 33'b0 : {1'b1, s_tag}),
        .m_axis_data_tvalid (valid_lane[lane]),
        .m_axis_data_tready (retire),
        .m_axis_data_tdata  (data_lane[lane]),
        .m_axis_data_tuser  (tag_lane[lane])
    );
    assign m_cosine[18*lane+:18] = data_lane[lane][17:0];
    assign m_sine[18*lane+:18]   = data_lane[lane][41:24];
  end
endmodule
