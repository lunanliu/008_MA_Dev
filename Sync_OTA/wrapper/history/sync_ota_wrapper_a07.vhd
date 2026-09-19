library ieee;
use ieee.std_logic_1164.all;

-- Transparent wiring only. The separately delivered sync_ota_top is the algorithm core.
-- Multiword vectors use w0 = least-significant 64 bits; unused output bits are zero.
entity sync_ota_wrapper is
  port (
    clk125 : in std_logic;
    clk150 : in std_logic;
    clk500 : in std_logic;
    reset_request : in std_logic;
    start_valid : in std_logic;
    start_ready : out std_logic;
    capture_base_word : in std_logic_vector(63 downto 0);
    capture_words : in std_logic_vector(31 downto 0);
    cancel : in std_logic;
    s_valid : in std_logic;
    s_ready : out std_logic;
    s_data_w0 : in std_logic_vector(63 downto 0);
    s_data_w1 : in std_logic_vector(63 downto 0);
    done : out std_logic;
    done_ready : in std_logic;
    busy : out std_logic;
    stage125 : out std_logic_vector(7 downto 0);
    error125 : out std_logic_vector(7 downto 0);
    accepted_words125 : out std_logic_vector(31 downto 0);
    committed_words125 : out std_logic_vector(31 downto 0);
    replay_words125 : out std_logic_vector(31 downto 0);
    raw_stalls125 : out std_logic_vector(31 downto 0);
    frame125 : out std_logic_vector(31 downto 0);
    generation125 : out std_logic_vector(31 downto 0);
    nominal_absolute125 : out std_logic_vector(63 downto 0);
    frontend_record125_w0 : out std_logic_vector(63 downto 0);
    frontend_record125_w1 : out std_logic_vector(63 downto 0);
    frontend_record125_w2 : out std_logic_vector(63 downto 0);
    frontend_record125_w3 : out std_logic_vector(63 downto 0);
    frontend_record125_w4 : out std_logic_vector(31 downto 0);
    ddr_cmd_valid : out std_logic;
    ddr_cmd_ready : in std_logic;
    ddr_cmd_write : out std_logic;
    ddr_cmd_address : out std_logic_vector(63 downto 0);
    ddr_cmd_tag_w0 : out std_logic_vector(63 downto 0);
    ddr_cmd_tag_w1 : out std_logic_vector(7 downto 0);
    ddr_cmd_data_w0 : out std_logic_vector(63 downto 0);
    ddr_cmd_data_w1 : out std_logic_vector(63 downto 0);
    ddr_rsp_valid : in std_logic;
    ddr_rsp_ready : out std_logic;
    ddr_rsp_tag_w0 : in std_logic_vector(63 downto 0);
    ddr_rsp_tag_w1 : in std_logic_vector(7 downto 0);
    ddr_rsp_data_w0 : in std_logic_vector(63 downto 0);
    ddr_rsp_data_w1 : in std_logic_vector(63 downto 0);
    ddr_rsp_error : in std_logic;
    ddr_idle125 : out std_logic;
    ddr_error125 : out std_logic_vector(7 downto 0);
    ddr_commands125 : out std_logic_vector(31 downto 0);
    ddr_responses125 : out std_logic_vector(31 downto 0);
    ddr_stale125 : out std_logic_vector(31 downto 0);
    ddr_request_level125 : out std_logic_vector(7 downto 0);
    ddr_response_level125 : out std_logic_vector(7 downto 0);
    m_valid : out std_logic;
    m_ready : in std_logic;
    m_record_w0 : out std_logic_vector(63 downto 0);
    m_record_w1 : out std_logic_vector(63 downto 0);
    m_record_w2 : out std_logic_vector(63 downto 0);
    m_record_w3 : out std_logic_vector(63 downto 0);
    cfo_stage150 : out std_logic_vector(7 downto 0);
    cfo_error150 : out std_logic_vector(7 downto 0);
    coarse_beats150 : out std_logic_vector(31 downto 0);
    final_beats150 : out std_logic_vector(31 downto 0);
    coarse_saturations150 : out std_logic_vector(31 downto 0);
    final_saturations150 : out std_logic_vector(31 downto 0);
    observation_windows150 : out std_logic_vector(7 downto 0);
    cfo_result150_w0 : out std_logic_vector(63 downto 0);
    cfo_result150_w1 : out std_logic_vector(63 downto 0);
    cfo_result150_w2 : out std_logic_vector(63 downto 0);
    cfo_result150_w3 : out std_logic_vector(63 downto 0);
    cfo_result150_w4 : out std_logic_vector(63 downto 0);
    cfo_result150_w5 : out std_logic_vector(63 downto 0);
    cfo_result150_w6 : out std_logic_vector(63 downto 0);
    cfo_result150_w7 : out std_logic_vector(63 downto 0);
    cfo_committed150 : out std_logic_vector(31 downto 0);
    cfo_read150 : out std_logic_vector(31 downto 0);
    cfo_stalls150 : out std_logic_vector(31 downto 0);
    cfo_window_fifo_level150 : out std_logic_vector(7 downto 0);
    cfo_observation_fifo_level150 : out std_logic_vector(7 downto 0);
    cfo_fifo_error150 : out std_logic_vector(7 downto 0);
    sfo_error125 : out std_logic_vector(7 downto 0);
    sfo_error150 : out std_logic_vector(7 downto 0);
    context_error150 : out std_logic_vector(7 downto 0);
    sfo_diagnostic150_w0 : out std_logic_vector(63 downto 0);
    sfo_diagnostic150_w1 : out std_logic_vector(63 downto 0);
    sfo_diagnostic150_w2 : out std_logic_vector(63 downto 0);
    sfo_diagnostic150_w3 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w0 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w1 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w2 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w3 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w4 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w5 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w6 : out std_logic_vector(63 downto 0);
    sfo_monitor125_w7 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w0 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w1 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w2 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w3 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w4 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w5 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w6 : out std_logic_vector(63 downto 0);
    sfo_monitor150_w7 : out std_logic_vector(63 downto 0);
    first_step150 : out std_logic_vector(31 downto 0);
    second_step150 : out std_logic_vector(31 downto 0);
    frontend_accepted_samples125 : out std_logic_vector(63 downto 0);
    frontend_candidates125 : out std_logic_vector(31 downto 0);
    frontend_rejected125 : out std_logic_vector(31 downto 0);
    frontend_drop125 : out std_logic_vector(31 downto 0);
    frontend_duplicate125 : out std_logic_vector(31 downto 0);
    frontend_confirmed125 : out std_logic_vector(31 downto 0);
    frontend_error125 : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of sync_ota_wrapper is
  component sync_ota_top is
    port (
      clk125 : in std_logic;
      clk150 : in std_logic;
      clk500 : in std_logic;
      reset_request : in std_logic;
      start_valid : in std_logic;
      start_ready : out std_logic;
      capture_base_word : in std_logic_vector(63 downto 0);
      capture_words : in std_logic_vector(31 downto 0);
      cancel : in std_logic;
      s_valid : in std_logic;
      s_ready : out std_logic;
      s_data : in std_logic_vector(127 downto 0);
      done : out std_logic;
      done_ready : in std_logic;
      busy : out std_logic;
      stage125 : out std_logic_vector(5 downto 0);
      error125 : out std_logic_vector(7 downto 0);
      accepted_words125 : out std_logic_vector(31 downto 0);
      committed_words125 : out std_logic_vector(31 downto 0);
      replay_words125 : out std_logic_vector(31 downto 0);
      raw_stalls125 : out std_logic_vector(31 downto 0);
      frame125 : out std_logic_vector(31 downto 0);
      generation125 : out std_logic_vector(31 downto 0);
      nominal_absolute125 : out std_logic_vector(63 downto 0);
      frontend_record125 : out std_logic_vector(287 downto 0);
      ddr_cmd_valid : out std_logic;
      ddr_cmd_ready : in std_logic;
      ddr_cmd_write : out std_logic;
      ddr_cmd_address : out std_logic_vector(63 downto 0);
      ddr_cmd_tag : out std_logic_vector(64 downto 0);
      ddr_cmd_data : out std_logic_vector(127 downto 0);
      ddr_rsp_valid : in std_logic;
      ddr_rsp_ready : out std_logic;
      ddr_rsp_tag : in std_logic_vector(64 downto 0);
      ddr_rsp_data : in std_logic_vector(127 downto 0);
      ddr_rsp_error : in std_logic;
      ddr_idle125 : out std_logic;
      ddr_error125 : out std_logic_vector(7 downto 0);
      ddr_commands125 : out std_logic_vector(31 downto 0);
      ddr_responses125 : out std_logic_vector(31 downto 0);
      ddr_stale125 : out std_logic_vector(31 downto 0);
      ddr_request_level125 : out std_logic_vector(5 downto 0);
      ddr_response_level125 : out std_logic_vector(5 downto 0);
      m_valid : out std_logic;
      m_ready : in std_logic;
      m_record : out std_logic_vector(224 downto 0);
      cfo_stage150 : out std_logic_vector(4 downto 0);
      cfo_error150 : out std_logic_vector(7 downto 0);
      coarse_beats150 : out std_logic_vector(31 downto 0);
      final_beats150 : out std_logic_vector(31 downto 0);
      coarse_saturations150 : out std_logic_vector(31 downto 0);
      final_saturations150 : out std_logic_vector(31 downto 0);
      observation_windows150 : out std_logic_vector(6 downto 0);
      cfo_result150 : out std_logic_vector(498 downto 0);
      cfo_committed150 : out std_logic_vector(31 downto 0);
      cfo_read150 : out std_logic_vector(31 downto 0);
      cfo_stalls150 : out std_logic_vector(31 downto 0);
      cfo_window_fifo_level150 : out std_logic_vector(5 downto 0);
      cfo_observation_fifo_level150 : out std_logic_vector(4 downto 0);
      cfo_fifo_error150 : out std_logic_vector(3 downto 0);
      sfo_error125 : out std_logic_vector(7 downto 0);
      sfo_error150 : out std_logic_vector(7 downto 0);
      context_error150 : out std_logic_vector(7 downto 0);
      sfo_diagnostic150 : out std_logic_vector(255 downto 0);
      sfo_monitor125 : out std_logic_vector(511 downto 0);
      sfo_monitor150 : out std_logic_vector(511 downto 0);
      first_step150 : out std_logic_vector(31 downto 0);
      second_step150 : out std_logic_vector(31 downto 0);
      frontend_accepted_samples125 : out std_logic_vector(63 downto 0);
      frontend_candidates125 : out std_logic_vector(31 downto 0);
      frontend_rejected125 : out std_logic_vector(31 downto 0);
      frontend_drop125 : out std_logic_vector(31 downto 0);
      frontend_duplicate125 : out std_logic_vector(31 downto 0);
      frontend_confirmed125 : out std_logic_vector(31 downto 0);
      frontend_error125 : out std_logic_vector(15 downto 0)
    );
  end component;
  signal core_clk125 : std_logic;
  signal core_clk150 : std_logic;
  signal core_clk500 : std_logic;
  signal core_reset_request : std_logic;
  signal core_start_valid : std_logic;
  signal core_start_ready : std_logic;
  signal core_capture_base_word : std_logic_vector(63 downto 0);
  signal core_capture_words : std_logic_vector(31 downto 0);
  signal core_cancel : std_logic;
  signal core_s_valid : std_logic;
  signal core_s_ready : std_logic;
  signal core_s_data : std_logic_vector(127 downto 0);
  signal core_done : std_logic;
  signal core_done_ready : std_logic;
  signal core_busy : std_logic;
  signal core_stage125 : std_logic_vector(5 downto 0);
  signal core_error125 : std_logic_vector(7 downto 0);
  signal core_accepted_words125 : std_logic_vector(31 downto 0);
  signal core_committed_words125 : std_logic_vector(31 downto 0);
  signal core_replay_words125 : std_logic_vector(31 downto 0);
  signal core_raw_stalls125 : std_logic_vector(31 downto 0);
  signal core_frame125 : std_logic_vector(31 downto 0);
  signal core_generation125 : std_logic_vector(31 downto 0);
  signal core_nominal_absolute125 : std_logic_vector(63 downto 0);
  signal core_frontend_record125 : std_logic_vector(287 downto 0);
  signal core_ddr_cmd_valid : std_logic;
  signal core_ddr_cmd_ready : std_logic;
  signal core_ddr_cmd_write : std_logic;
  signal core_ddr_cmd_address : std_logic_vector(63 downto 0);
  signal core_ddr_cmd_tag : std_logic_vector(64 downto 0);
  signal core_ddr_cmd_data : std_logic_vector(127 downto 0);
  signal core_ddr_rsp_valid : std_logic;
  signal core_ddr_rsp_ready : std_logic;
  signal core_ddr_rsp_tag : std_logic_vector(64 downto 0);
  signal core_ddr_rsp_data : std_logic_vector(127 downto 0);
  signal core_ddr_rsp_error : std_logic;
  signal core_ddr_idle125 : std_logic;
  signal core_ddr_error125 : std_logic_vector(7 downto 0);
  signal core_ddr_commands125 : std_logic_vector(31 downto 0);
  signal core_ddr_responses125 : std_logic_vector(31 downto 0);
  signal core_ddr_stale125 : std_logic_vector(31 downto 0);
  signal core_ddr_request_level125 : std_logic_vector(5 downto 0);
  signal core_ddr_response_level125 : std_logic_vector(5 downto 0);
  signal core_m_valid : std_logic;
  signal core_m_ready : std_logic;
  signal core_m_record : std_logic_vector(224 downto 0);
  signal core_cfo_stage150 : std_logic_vector(4 downto 0);
  signal core_cfo_error150 : std_logic_vector(7 downto 0);
  signal core_coarse_beats150 : std_logic_vector(31 downto 0);
  signal core_final_beats150 : std_logic_vector(31 downto 0);
  signal core_coarse_saturations150 : std_logic_vector(31 downto 0);
  signal core_final_saturations150 : std_logic_vector(31 downto 0);
  signal core_observation_windows150 : std_logic_vector(6 downto 0);
  signal core_cfo_result150 : std_logic_vector(498 downto 0);
  signal core_cfo_committed150 : std_logic_vector(31 downto 0);
  signal core_cfo_read150 : std_logic_vector(31 downto 0);
  signal core_cfo_stalls150 : std_logic_vector(31 downto 0);
  signal core_cfo_window_fifo_level150 : std_logic_vector(5 downto 0);
  signal core_cfo_observation_fifo_level150 : std_logic_vector(4 downto 0);
  signal core_cfo_fifo_error150 : std_logic_vector(3 downto 0);
  signal core_sfo_error125 : std_logic_vector(7 downto 0);
  signal core_sfo_error150 : std_logic_vector(7 downto 0);
  signal core_context_error150 : std_logic_vector(7 downto 0);
  signal core_sfo_diagnostic150 : std_logic_vector(255 downto 0);
  signal core_sfo_monitor125 : std_logic_vector(511 downto 0);
  signal core_sfo_monitor150 : std_logic_vector(511 downto 0);
  signal core_first_step150 : std_logic_vector(31 downto 0);
  signal core_second_step150 : std_logic_vector(31 downto 0);
  signal core_frontend_accepted_samples125 : std_logic_vector(63 downto 0);
  signal core_frontend_candidates125 : std_logic_vector(31 downto 0);
  signal core_frontend_rejected125 : std_logic_vector(31 downto 0);
  signal core_frontend_drop125 : std_logic_vector(31 downto 0);
  signal core_frontend_duplicate125 : std_logic_vector(31 downto 0);
  signal core_frontend_confirmed125 : std_logic_vector(31 downto 0);
  signal core_frontend_error125 : std_logic_vector(15 downto 0);
begin
  core_clk125 <= clk125;
  core_clk150 <= clk150;
  core_clk500 <= clk500;
  core_reset_request <= reset_request;
  core_start_valid <= start_valid;
  start_ready <= core_start_ready;
  core_capture_base_word(63 downto 0) <= capture_base_word;
  core_capture_words(31 downto 0) <= capture_words;
  core_cancel <= cancel;
  core_s_valid <= s_valid;
  s_ready <= core_s_ready;
  core_s_data(63 downto 0) <= s_data_w0;
  core_s_data(127 downto 64) <= s_data_w1;
  done <= core_done;
  core_done_ready <= done_ready;
  busy <= core_busy;
  stage125 <= (7 downto 6 => '0') & core_stage125(5 downto 0);
  error125 <= core_error125(7 downto 0);
  accepted_words125 <= core_accepted_words125(31 downto 0);
  committed_words125 <= core_committed_words125(31 downto 0);
  replay_words125 <= core_replay_words125(31 downto 0);
  raw_stalls125 <= core_raw_stalls125(31 downto 0);
  frame125 <= core_frame125(31 downto 0);
  generation125 <= core_generation125(31 downto 0);
  nominal_absolute125 <= core_nominal_absolute125(63 downto 0);
  frontend_record125_w0 <= core_frontend_record125(63 downto 0);
  frontend_record125_w1 <= core_frontend_record125(127 downto 64);
  frontend_record125_w2 <= core_frontend_record125(191 downto 128);
  frontend_record125_w3 <= core_frontend_record125(255 downto 192);
  frontend_record125_w4 <= core_frontend_record125(287 downto 256);
  ddr_cmd_valid <= core_ddr_cmd_valid;
  core_ddr_cmd_ready <= ddr_cmd_ready;
  ddr_cmd_write <= core_ddr_cmd_write;
  ddr_cmd_address <= core_ddr_cmd_address(63 downto 0);
  ddr_cmd_tag_w0 <= core_ddr_cmd_tag(63 downto 0);
  ddr_cmd_tag_w1 <= (7 downto 1 => '0') & core_ddr_cmd_tag(64 downto 64);
  ddr_cmd_data_w0 <= core_ddr_cmd_data(63 downto 0);
  ddr_cmd_data_w1 <= core_ddr_cmd_data(127 downto 64);
  core_ddr_rsp_valid <= ddr_rsp_valid;
  ddr_rsp_ready <= core_ddr_rsp_ready;
  core_ddr_rsp_tag(63 downto 0) <= ddr_rsp_tag_w0;
  core_ddr_rsp_tag(64 downto 64) <= ddr_rsp_tag_w1(0 downto 0);
  core_ddr_rsp_data(63 downto 0) <= ddr_rsp_data_w0;
  core_ddr_rsp_data(127 downto 64) <= ddr_rsp_data_w1;
  core_ddr_rsp_error <= ddr_rsp_error;
  ddr_idle125 <= core_ddr_idle125;
  ddr_error125 <= core_ddr_error125(7 downto 0);
  ddr_commands125 <= core_ddr_commands125(31 downto 0);
  ddr_responses125 <= core_ddr_responses125(31 downto 0);
  ddr_stale125 <= core_ddr_stale125(31 downto 0);
  ddr_request_level125 <= (7 downto 6 => '0') & core_ddr_request_level125(5 downto 0);
  ddr_response_level125 <= (7 downto 6 => '0') & core_ddr_response_level125(5 downto 0);
  m_valid <= core_m_valid;
  core_m_ready <= m_ready;
  m_record_w0 <= core_m_record(63 downto 0);
  m_record_w1 <= core_m_record(127 downto 64);
  m_record_w2 <= core_m_record(191 downto 128);
  m_record_w3 <= (63 downto 33 => '0') & core_m_record(224 downto 192);
  cfo_stage150 <= (7 downto 5 => '0') & core_cfo_stage150(4 downto 0);
  cfo_error150 <= core_cfo_error150(7 downto 0);
  coarse_beats150 <= core_coarse_beats150(31 downto 0);
  final_beats150 <= core_final_beats150(31 downto 0);
  coarse_saturations150 <= core_coarse_saturations150(31 downto 0);
  final_saturations150 <= core_final_saturations150(31 downto 0);
  observation_windows150 <= (7 downto 7 => '0') & core_observation_windows150(6 downto 0);
  cfo_result150_w0 <= core_cfo_result150(63 downto 0);
  cfo_result150_w1 <= core_cfo_result150(127 downto 64);
  cfo_result150_w2 <= core_cfo_result150(191 downto 128);
  cfo_result150_w3 <= core_cfo_result150(255 downto 192);
  cfo_result150_w4 <= core_cfo_result150(319 downto 256);
  cfo_result150_w5 <= core_cfo_result150(383 downto 320);
  cfo_result150_w6 <= core_cfo_result150(447 downto 384);
  cfo_result150_w7 <= (63 downto 51 => '0') & core_cfo_result150(498 downto 448);
  cfo_committed150 <= core_cfo_committed150(31 downto 0);
  cfo_read150 <= core_cfo_read150(31 downto 0);
  cfo_stalls150 <= core_cfo_stalls150(31 downto 0);
  cfo_window_fifo_level150 <= (7 downto 6 => '0') & core_cfo_window_fifo_level150(5 downto 0);
  cfo_observation_fifo_level150 <= (7 downto 5 => '0') & core_cfo_observation_fifo_level150(4 downto 0);
  cfo_fifo_error150 <= (7 downto 4 => '0') & core_cfo_fifo_error150(3 downto 0);
  sfo_error125 <= core_sfo_error125(7 downto 0);
  sfo_error150 <= core_sfo_error150(7 downto 0);
  context_error150 <= core_context_error150(7 downto 0);
  sfo_diagnostic150_w0 <= core_sfo_diagnostic150(63 downto 0);
  sfo_diagnostic150_w1 <= core_sfo_diagnostic150(127 downto 64);
  sfo_diagnostic150_w2 <= core_sfo_diagnostic150(191 downto 128);
  sfo_diagnostic150_w3 <= core_sfo_diagnostic150(255 downto 192);
  sfo_monitor125_w0 <= core_sfo_monitor125(63 downto 0);
  sfo_monitor125_w1 <= core_sfo_monitor125(127 downto 64);
  sfo_monitor125_w2 <= core_sfo_monitor125(191 downto 128);
  sfo_monitor125_w3 <= core_sfo_monitor125(255 downto 192);
  sfo_monitor125_w4 <= core_sfo_monitor125(319 downto 256);
  sfo_monitor125_w5 <= core_sfo_monitor125(383 downto 320);
  sfo_monitor125_w6 <= core_sfo_monitor125(447 downto 384);
  sfo_monitor125_w7 <= core_sfo_monitor125(511 downto 448);
  sfo_monitor150_w0 <= core_sfo_monitor150(63 downto 0);
  sfo_monitor150_w1 <= core_sfo_monitor150(127 downto 64);
  sfo_monitor150_w2 <= core_sfo_monitor150(191 downto 128);
  sfo_monitor150_w3 <= core_sfo_monitor150(255 downto 192);
  sfo_monitor150_w4 <= core_sfo_monitor150(319 downto 256);
  sfo_monitor150_w5 <= core_sfo_monitor150(383 downto 320);
  sfo_monitor150_w6 <= core_sfo_monitor150(447 downto 384);
  sfo_monitor150_w7 <= core_sfo_monitor150(511 downto 448);
  first_step150 <= core_first_step150(31 downto 0);
  second_step150 <= core_second_step150(31 downto 0);
  frontend_accepted_samples125 <= core_frontend_accepted_samples125(63 downto 0);
  frontend_candidates125 <= core_frontend_candidates125(31 downto 0);
  frontend_rejected125 <= core_frontend_rejected125(31 downto 0);
  frontend_drop125 <= core_frontend_drop125(31 downto 0);
  frontend_duplicate125 <= core_frontend_duplicate125(31 downto 0);
  frontend_confirmed125 <= core_frontend_confirmed125(31 downto 0);
  frontend_error125 <= core_frontend_error125(15 downto 0);
  algorithm : sync_ota_top
    port map (
      clk125 => core_clk125,
      clk150 => core_clk150,
      clk500 => core_clk500,
      reset_request => core_reset_request,
      start_valid => core_start_valid,
      start_ready => core_start_ready,
      capture_base_word => core_capture_base_word,
      capture_words => core_capture_words,
      cancel => core_cancel,
      s_valid => core_s_valid,
      s_ready => core_s_ready,
      s_data => core_s_data,
      done => core_done,
      done_ready => core_done_ready,
      busy => core_busy,
      stage125 => core_stage125,
      error125 => core_error125,
      accepted_words125 => core_accepted_words125,
      committed_words125 => core_committed_words125,
      replay_words125 => core_replay_words125,
      raw_stalls125 => core_raw_stalls125,
      frame125 => core_frame125,
      generation125 => core_generation125,
      nominal_absolute125 => core_nominal_absolute125,
      frontend_record125 => core_frontend_record125,
      ddr_cmd_valid => core_ddr_cmd_valid,
      ddr_cmd_ready => core_ddr_cmd_ready,
      ddr_cmd_write => core_ddr_cmd_write,
      ddr_cmd_address => core_ddr_cmd_address,
      ddr_cmd_tag => core_ddr_cmd_tag,
      ddr_cmd_data => core_ddr_cmd_data,
      ddr_rsp_valid => core_ddr_rsp_valid,
      ddr_rsp_ready => core_ddr_rsp_ready,
      ddr_rsp_tag => core_ddr_rsp_tag,
      ddr_rsp_data => core_ddr_rsp_data,
      ddr_rsp_error => core_ddr_rsp_error,
      ddr_idle125 => core_ddr_idle125,
      ddr_error125 => core_ddr_error125,
      ddr_commands125 => core_ddr_commands125,
      ddr_responses125 => core_ddr_responses125,
      ddr_stale125 => core_ddr_stale125,
      ddr_request_level125 => core_ddr_request_level125,
      ddr_response_level125 => core_ddr_response_level125,
      m_valid => core_m_valid,
      m_ready => core_m_ready,
      m_record => core_m_record,
      cfo_stage150 => core_cfo_stage150,
      cfo_error150 => core_cfo_error150,
      coarse_beats150 => core_coarse_beats150,
      final_beats150 => core_final_beats150,
      coarse_saturations150 => core_coarse_saturations150,
      final_saturations150 => core_final_saturations150,
      observation_windows150 => core_observation_windows150,
      cfo_result150 => core_cfo_result150,
      cfo_committed150 => core_cfo_committed150,
      cfo_read150 => core_cfo_read150,
      cfo_stalls150 => core_cfo_stalls150,
      cfo_window_fifo_level150 => core_cfo_window_fifo_level150,
      cfo_observation_fifo_level150 => core_cfo_observation_fifo_level150,
      cfo_fifo_error150 => core_cfo_fifo_error150,
      sfo_error125 => core_sfo_error125,
      sfo_error150 => core_sfo_error150,
      context_error150 => core_context_error150,
      sfo_diagnostic150 => core_sfo_diagnostic150,
      sfo_monitor125 => core_sfo_monitor125,
      sfo_monitor150 => core_sfo_monitor150,
      first_step150 => core_first_step150,
      second_step150 => core_second_step150,
      frontend_accepted_samples125 => core_frontend_accepted_samples125,
      frontend_candidates125 => core_frontend_candidates125,
      frontend_rejected125 => core_frontend_rejected125,
      frontend_drop125 => core_frontend_drop125,
      frontend_duplicate125 => core_frontend_duplicate125,
      frontend_confirmed125 => core_frontend_confirmed125,
      frontend_error125 => core_frontend_error125
    );
end architecture;
