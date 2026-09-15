library ieee;
use ieee.std_logic_1164.all;

-- Combinational adapter only: no clock generator, reset logic, buffering or CDC.
-- Core OUTPUT_CLOCK_MHZ is frozen at its verified RTL default of 150.
-- No generic is declared for the component: an exported fixed netlist has no runtime parameter.
-- All vector ports carry bits; signed values use two's-complement representation.
entity sync_sfo_manual_wrapper is
  port (
    clk125 : in std_logic;
    clk150 : in std_logic;
    clk500 : in std_logic;
    reset_request : in std_logic;
    abort125 : in std_logic;
    s_valid : in std_logic;
    s_ready : out std_logic;
    frame_valid : in std_logic;
    frame_ready : out std_logic;
    cfo_valid : in std_logic;
    cfo_ready : out std_logic;
    fine_valid : in std_logic;
    fine_ready : out std_logic;
    s_iq0 : in std_logic_vector(31 downto 0);
    s_iq1 : in std_logic_vector(31 downto 0);
    s_iq2 : in std_logic_vector(31 downto 0);
    s_iq3 : in std_logic_vector(31 downto 0);
    s_frame_id : in std_logic_vector(31 downto 0);
    s_absolute_index : in std_logic_vector(31 downto 0);
    s_lane_valid : in std_logic_vector(7 downto 0);
    frame_id : in std_logic_vector(31 downto 0);
    frame_generation : in std_logic_vector(31 downto 0);
    frame_raw_first_word_lo : in std_logic_vector(31 downto 0);
    frame_raw_first_word_hi : in std_logic_vector(31 downto 0);
    frame_nominal_absolute : in std_logic_vector(31 downto 0);
    frame_q0_q28 : in std_logic_vector(31 downto 0);
    cfo_value_hz : in std_logic_vector(31 downto 0);
    cfo_quality : in std_logic_vector(15 downto 0);
    cfo_status : in std_logic_vector(15 downto 0);
    cfo_frame_id : in std_logic_vector(31 downto 0);
    fine_start_samples : in std_logic_vector(31 downto 0);
    fine_quality : in std_logic_vector(15 downto 0);
    fine_status : in std_logic_vector(15 downto 0);
    fine_frame_id : in std_logic_vector(31 downto 0);
    m_valid : out std_logic;
    m_ready : in std_logic;
    m_reset : out std_logic;
    m_fault : out std_logic;
    m_iq0 : out std_logic_vector(31 downto 0);
    m_iq1 : out std_logic_vector(31 downto 0);
    m_iq2 : out std_logic_vector(31 downto 0);
    m_iq3 : out std_logic_vector(31 downto 0);
    m_frame_id : out std_logic_vector(31 downto 0);
    m_generation : out std_logic_vector(31 downto 0);
    m_beat : out std_logic_vector(31 downto 0);
    m_last : out std_logic;
    fault : out std_logic;
    error_code125 : out std_logic_vector(7 downto 0);
    error_code150 : out std_logic_vector(7 downto 0);
    diag_w00 : out std_logic_vector(31 downto 0);
    diag_w01 : out std_logic_vector(31 downto 0);
    diag_w02 : out std_logic_vector(31 downto 0);
    diag_w03 : out std_logic_vector(31 downto 0);
    diag_w04 : out std_logic_vector(31 downto 0);
    diag_w05 : out std_logic_vector(31 downto 0);
    diag_w06 : out std_logic_vector(31 downto 0);
    diag_w07 : out std_logic_vector(31 downto 0);
    debug125_w00 : out std_logic_vector(31 downto 0);
    debug125_w01 : out std_logic_vector(31 downto 0);
    debug125_w02 : out std_logic_vector(31 downto 0);
    debug125_w03 : out std_logic_vector(31 downto 0);
    debug125_w04 : out std_logic_vector(31 downto 0);
    debug125_w05 : out std_logic_vector(31 downto 0);
    debug125_w06 : out std_logic_vector(31 downto 0);
    debug125_w07 : out std_logic_vector(31 downto 0);
    debug125_w08 : out std_logic_vector(31 downto 0);
    debug125_w09 : out std_logic_vector(31 downto 0);
    debug125_w10 : out std_logic_vector(31 downto 0);
    debug125_w11 : out std_logic_vector(31 downto 0);
    debug125_w12 : out std_logic_vector(31 downto 0);
    debug125_w13 : out std_logic_vector(31 downto 0);
    debug125_w14 : out std_logic_vector(31 downto 0);
    debug125_w15 : out std_logic_vector(31 downto 0);
    debug150_w00 : out std_logic_vector(31 downto 0);
    debug150_w01 : out std_logic_vector(31 downto 0);
    debug150_w02 : out std_logic_vector(31 downto 0);
    debug150_w03 : out std_logic_vector(31 downto 0);
    debug150_w04 : out std_logic_vector(31 downto 0);
    debug150_w05 : out std_logic_vector(31 downto 0);
    debug150_w06 : out std_logic_vector(31 downto 0);
    debug150_w07 : out std_logic_vector(31 downto 0);
    debug150_w08 : out std_logic_vector(31 downto 0);
    debug150_w09 : out std_logic_vector(31 downto 0);
    debug150_w10 : out std_logic_vector(31 downto 0);
    debug150_w11 : out std_logic_vector(31 downto 0);
    debug150_w12 : out std_logic_vector(31 downto 0);
    debug150_w13 : out std_logic_vector(31 downto 0);
    debug150_w14 : out std_logic_vector(31 downto 0);
    debug150_w15 : out std_logic_vector(31 downto 0);
    residual_point_valid : out std_logic;
    point_w0 : out std_logic_vector(31 downto 0);
    point_w1 : out std_logic_vector(31 downto 0);
    point_w2 : out std_logic_vector(31 downto 0);
    point_w3 : out std_logic_vector(31 downto 0);
    point_w4 : out std_logic_vector(31 downto 0);
    debug_e1_valid : out std_logic;
    debug_e1_beat : out std_logic_vector(31 downto 0);
    debug_e1_last : out std_logic;
    debug_e1_iq0 : out std_logic_vector(31 downto 0);
    debug_e1_iq1 : out std_logic_vector(31 downto 0);
    debug_e1_iq2 : out std_logic_vector(31 downto 0);
    debug_e1_iq3 : out std_logic_vector(31 downto 0)
  );
end entity sync_sfo_manual_wrapper;

architecture wiring of sync_sfo_manual_wrapper is
  component sync_sfo_top is
    port (
    clk125 : in std_logic;
    clk150 : in std_logic;
    clk500 : in std_logic;
    reset_request : in std_logic;
    abort125 : in std_logic;
    s_valid : in std_logic;
    s_ready : out std_logic;
    s_data : in std_logic_vector(127 downto 0);
    s_frame_id : in std_logic_vector(31 downto 0);
    s_absolute_index : in std_logic_vector(31 downto 0);
    s_lane_valid : in std_logic_vector(3 downto 0);
    frame_valid : in std_logic;
    frame_ready : out std_logic;
    frame_record : in std_logic_vector(187 downto 0);
    cfo_valid : in std_logic;
    cfo_ready : out std_logic;
    cfo_record : in std_logic_vector(95 downto 0);
    fine_valid : in std_logic;
    fine_ready : out std_logic;
    fine_record : in std_logic_vector(95 downto 0);
    m_valid : out std_logic;
    m_ready : in std_logic;
    m_record : out std_logic_vector(224 downto 0);
    m_reset : out std_logic;
    m_fault : out std_logic;
    fault : out std_logic;
    error_code125 : out std_logic_vector(7 downto 0);
    error_code150 : out std_logic_vector(7 downto 0);
    diagnostic : out std_logic_vector(255 downto 0);
    residual_point_valid : out std_logic;
    residual_point_record : out std_logic_vector(128 downto 0);
    debug125 : out std_logic_vector(511 downto 0);
    debug150 : out std_logic_vector(511 downto 0);
    debug_e1_valid : out std_logic;
    debug_e1_data : out std_logic_vector(127 downto 0);
    debug_e1_beat : out std_logic_vector(31 downto 0);
    debug_e1_last : out std_logic
    );
  end component;
  signal core_m_record : std_logic_vector(224 downto 0);
  signal core_diagnostic : std_logic_vector(255 downto 0);
  signal core_debug125 : std_logic_vector(511 downto 0);
  signal core_debug150 : std_logic_vector(511 downto 0);
  signal core_residual_point_record : std_logic_vector(128 downto 0);
  signal core_debug_e1_data : std_logic_vector(127 downto 0);
begin
  u_core : sync_sfo_top
    port map (
      clk125 => clk125,
      clk150 => clk150,
      clk500 => clk500,
      reset_request => reset_request,
      abort125 => abort125,
      s_valid => s_valid,
      s_ready => s_ready,
      s_data => s_iq3 & s_iq2 & s_iq1 & s_iq0,
      s_frame_id => s_frame_id,
      s_absolute_index => s_absolute_index,
      s_lane_valid => s_lane_valid(3 downto 0),
      frame_valid => frame_valid,
      frame_ready => frame_ready,
      frame_record => frame_id & frame_generation & frame_raw_first_word_hi & frame_raw_first_word_lo & frame_nominal_absolute & frame_q0_q28(27 downto 0),
      cfo_valid => cfo_valid,
      cfo_ready => cfo_ready,
      cfo_record => cfo_value_hz & cfo_quality & cfo_status & cfo_frame_id,
      fine_valid => fine_valid,
      fine_ready => fine_ready,
      fine_record => fine_start_samples & fine_quality & fine_status & fine_frame_id,
      m_valid => m_valid,
      m_ready => m_ready,
      m_record => core_m_record,
      m_reset => m_reset,
      m_fault => m_fault,
      fault => fault,
      error_code125 => error_code125,
      error_code150 => error_code150,
      diagnostic => core_diagnostic,
      residual_point_valid => residual_point_valid,
      residual_point_record => core_residual_point_record,
      debug125 => core_debug125,
      debug150 => core_debug150,
      debug_e1_valid => debug_e1_valid,
      debug_e1_data => core_debug_e1_data,
      debug_e1_beat => debug_e1_beat,
      debug_e1_last => debug_e1_last
    );
  m_iq0 <= core_m_record(31 downto 0);
  m_iq1 <= core_m_record(63 downto 32);
  m_iq2 <= core_m_record(95 downto 64);
  m_iq3 <= core_m_record(127 downto 96);
  m_frame_id <= core_m_record(224 downto 193);
  m_generation <= core_m_record(192 downto 161);
  m_beat <= core_m_record(160 downto 129);
  m_last <= core_m_record(128);
  diag_w00 <= core_diagnostic(31 downto 0);
  diag_w01 <= core_diagnostic(63 downto 32);
  diag_w02 <= core_diagnostic(95 downto 64);
  diag_w03 <= core_diagnostic(127 downto 96);
  diag_w04 <= core_diagnostic(159 downto 128);
  diag_w05 <= core_diagnostic(191 downto 160);
  diag_w06 <= core_diagnostic(223 downto 192);
  diag_w07 <= core_diagnostic(255 downto 224);
  debug125_w00 <= core_debug125(31 downto 0);
  debug125_w01 <= core_debug125(63 downto 32);
  debug125_w02 <= core_debug125(95 downto 64);
  debug125_w03 <= core_debug125(127 downto 96);
  debug125_w04 <= core_debug125(159 downto 128);
  debug125_w05 <= core_debug125(191 downto 160);
  debug125_w06 <= core_debug125(223 downto 192);
  debug125_w07 <= core_debug125(255 downto 224);
  debug125_w08 <= core_debug125(287 downto 256);
  debug125_w09 <= core_debug125(319 downto 288);
  debug125_w10 <= core_debug125(351 downto 320);
  debug125_w11 <= core_debug125(383 downto 352);
  debug125_w12 <= core_debug125(415 downto 384);
  debug125_w13 <= core_debug125(447 downto 416);
  debug125_w14 <= core_debug125(479 downto 448);
  debug125_w15 <= core_debug125(511 downto 480);
  debug150_w00 <= core_debug150(31 downto 0);
  debug150_w01 <= core_debug150(63 downto 32);
  debug150_w02 <= core_debug150(95 downto 64);
  debug150_w03 <= core_debug150(127 downto 96);
  debug150_w04 <= core_debug150(159 downto 128);
  debug150_w05 <= core_debug150(191 downto 160);
  debug150_w06 <= core_debug150(223 downto 192);
  debug150_w07 <= core_debug150(255 downto 224);
  debug150_w08 <= core_debug150(287 downto 256);
  debug150_w09 <= core_debug150(319 downto 288);
  debug150_w10 <= core_debug150(351 downto 320);
  debug150_w11 <= core_debug150(383 downto 352);
  debug150_w12 <= core_debug150(415 downto 384);
  debug150_w13 <= core_debug150(447 downto 416);
  debug150_w14 <= core_debug150(479 downto 448);
  debug150_w15 <= core_debug150(511 downto 480);
  point_w0 <= core_residual_point_record(31 downto 0);
  point_w1 <= core_residual_point_record(63 downto 32);
  point_w2 <= core_residual_point_record(95 downto 64);
  point_w3 <= core_residual_point_record(127 downto 96);
  point_w4 <= "0000000000000000000000000000000" & core_residual_point_record(128);
  debug_e1_iq0 <= core_debug_e1_data(31 downto 0);
  debug_e1_iq1 <= core_debug_e1_data(63 downto 32);
  debug_e1_iq2 <= core_debug_e1_data(95 downto 64);
  debug_e1_iq3 <= core_debug_e1_data(127 downto 96);
end architecture wiring;
