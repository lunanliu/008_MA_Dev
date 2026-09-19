-- Dedicated result DDR -> prefetch FIFO -> Target-to-Host DMA; 150 MHz SCTL.
-- Control-only role wrapper: compile together with ddr_read_ctrl.vhd.
-- Current_Array and actual four U32 data wires remain in LabVIEW.
-- dma_ready_now must promise acceptance of ALL FOUR U32 in this cycle.
-- For the contracted NI next-cycle Ready for Input interface, delay raw
-- ready ONCE in LabVIEW (initial False); do not add a second delay here.
-- Connect dma_fire to NI DMA.Write.Input Valid, not dma_valid alone.
-- No new pipeline: while stalled, Current_Array/offset/first/last hold.
-- download_done means all N samples entered FPGA-side DMA, not Host received.
-- Read on Host during download; drain/verify residual data before a new session.
library ieee;
use ieee.std_logic_1164.all;

entity ddr_download_ctrl is
  generic (DDR_WIDTH_BITS : positive := 1280);
  port (
    clk                          : in  std_logic;
    reset                        : in  std_logic;
    run_enable                   : in  std_logic;
    download_command             : in  std_logic;
    rearm_command                : in  std_logic;
    abort_command                : in  std_logic;
    new_session_safe             : in  std_logic;
    dram_ready                   : in  std_logic;
    sample_count                 : in  std_logic_vector(31 downto 0);
    ddr_word_count               : in  std_logic_vector(31 downto 0);
    ddr_capacity_words           : in  std_logic_vector(31 downto 0);
    ddr_request_ready_now        : in  std_logic;
    prefetch_write_ready_now     : in  std_logic;
    ddr_retrieve_valid           : in  std_logic;
    prefetch_read_valid          : in  std_logic;
    dma_ready_now                : in  std_logic;
    request_valid                : out std_logic;
    request_address              : out std_logic_vector(31 downto 0);
    retrieve_ready               : out std_logic;
    prefetch_write_valid         : out std_logic;
    prefetch_read_enable         : out std_logic;
    current_load                 : out std_logic;
    current_clear                : out std_logic;
    unpack_offset                : out std_logic_vector(31 downto 0);
    dma_valid                    : out std_logic;
    dma_fire                     : out std_logic;
    dma_first                    : out std_logic;
    dma_last                     : out std_logic;
    download_state               : out std_logic_vector(7 downto 0);
    download_busy                : out std_logic;
    download_done                : out std_logic;
    download_fault               : out std_logic;
    fault_code                   : out std_logic_vector(7 downto 0);
    download_generation          : out std_logic_vector(31 downto 0);
    command_rejected             : out std_logic;
    requested_words              : out std_logic_vector(31 downto 0);
    returned_words               : out std_logic_vector(31 downto 0);
    enqueued_words               : out std_logic_vector(31 downto 0);
    popped_words                 : out std_logic_vector(31 downto 0);
    downloaded_samples           : out std_logic_vector(31 downto 0);
    total_cycles                 : out std_logic_vector(63 downto 0);
    download_cycles              : out std_logic_vector(63 downto 0);
    transfer_cycles              : out std_logic_vector(63 downto 0);
    no_data_cycles               : out std_logic_vector(63 downto 0);
    sink_stall_cycles            : out std_logic_vector(63 downto 0);
    pause_cycles                 : out std_logic_vector(63 downto 0)
  );
end entity;

architecture rtl of ddr_download_ctrl is
begin
  core : entity work.ddr_read_ctrl
    generic map (DDR_WIDTH_BITS => DDR_WIDTH_BITS)
    port map (
      clk                          => clk,
      reset                        => reset,
      run_enable                   => run_enable,
      read_command                 => download_command,
      rearm_command                => rearm_command,
      abort_command                => abort_command,
      new_session_safe             => new_session_safe,
      dram_ready                   => dram_ready,
      sample_count                 => sample_count,
      ddr_word_count               => ddr_word_count,
      ddr_capacity_words           => ddr_capacity_words,
      pattern_check_enable         => '0',
      pattern_seed                 => (others => '0'),
      ddr_request_ready_now        => ddr_request_ready_now,
      prefetch_write_ready_now     => prefetch_write_ready_now,
      ddr_retrieve_valid           => ddr_retrieve_valid,
      prefetch_read_valid          => prefetch_read_valid,
      stream_ready                 => dma_ready_now,
      stream_word0                 => (others => '0'),
      stream_word1                 => (others => '0'),
      stream_word2                 => (others => '0'),
      stream_word3                 => (others => '0'),
      request_valid                => request_valid,
      request_address              => request_address,
      retrieve_ready               => retrieve_ready,
      prefetch_write_valid         => prefetch_write_valid,
      prefetch_read_enable         => prefetch_read_enable,
      current_load                 => current_load,
      current_clear                => current_clear,
      stream_offset                => unpack_offset,
      stream_valid                 => dma_valid,
      stream_fire                  => dma_fire,
      stream_first                 => dma_first,
      stream_last                  => dma_last,
      read_state                   => download_state,
      read_busy                    => download_busy,
      read_done                    => download_done,
      read_fault                   => download_fault,
      fault_code                   => fault_code,
      read_generation              => download_generation,
      command_rejected             => command_rejected,
      requested_words              => requested_words,
      returned_words               => returned_words,
      enqueued_words               => enqueued_words,
      popped_words                 => popped_words,
      sent_samples                 => downloaded_samples,
      total_cycles                 => total_cycles,
      replay_cycles                => download_cycles,
      transfer_cycles              => transfer_cycles,
      no_data_cycles               => no_data_cycles,
      sink_stall_cycles            => sink_stall_cycles,
      pause_cycles                 => pause_cycles,
      checked_samples              => open,
      mismatch_count               => open,
      first_error_index            => open,
      first_error_expected         => open,
      first_error_actual           => open);
end architecture;
