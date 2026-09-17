-- Sync result Target-Scoped FIFO -> dedicated result DDR; 150 MHz SCTL.
-- Control-only role wrapper: compile together with ddr_upload_ctrl.vhd.
-- No added registers/latency. Four U32 per accepted FIFO read; K-U32 pack
-- array stays in LabVIEW. Known output sample_count, a positive multiple of 4.
-- At width=1280: 10 receive cycles + 1 DDR write cycle = 40 samples/11 cycles.
-- Do not connect Sync ready directly to result_fifo_read_enable; the result
-- FIFO write side supplies the producer ready in the producer clock domain.
-- capture_done means requests ACCEPTED, not physical DDR write completion.
library ieee;
use ieee.std_logic_1164.all;

entity ddr_capture_ctrl is
  generic (DDR_WIDTH_BITS : positive := 1280);
  port (
    clk                          : in  std_logic;
    reset                        : in  std_logic;
    run_enable                   : in  std_logic;
    capture_command              : in  std_logic;
    rearm_command                : in  std_logic;
    abort_command                : in  std_logic;
    new_session_safe             : in  std_logic;
    dram_ready                   : in  std_logic;
    sample_count                 : in  std_logic_vector(31 downto 0);
    ddr_word_count               : in  std_logic_vector(31 downto 0);
    ddr_capacity_words           : in  std_logic_vector(31 downto 0);
    result_fifo_output_valid     : in  std_logic;
    ddr_write_ready_now          : in  std_logic;
    result_fifo_read_enable      : out std_logic;
    pack_offset                  : out std_logic_vector(31 downto 0);
    pack_clear                   : out std_logic;
    ddr_write_valid              : out std_logic;
    ddr_write_address            : out std_logic_vector(31 downto 0);
    captured_samples             : out std_logic_vector(31 downto 0);
    capture_state                : out std_logic_vector(7 downto 0);
    capture_busy                 : out std_logic;
    capture_done                 : out std_logic;
    capture_fault                : out std_logic;
    fault_code                   : out std_logic_vector(7 downto 0);
    capture_generation           : out std_logic_vector(31 downto 0);
    command_rejected             : out std_logic;
    capture_cycles               : out std_logic_vector(63 downto 0);
    data_window_cycles           : out std_logic_vector(63 downto 0);
    receive_cycles               : out std_logic_vector(63 downto 0);
    write_cycles                 : out std_logic_vector(63 downto 0);
    fifo_empty_cycles            : out std_logic_vector(63 downto 0);
    ddr_stall_cycles             : out std_logic_vector(63 downto 0);
    pause_cycles                 : out std_logic_vector(63 downto 0)
  );
end entity;

architecture rtl of ddr_capture_ctrl is
begin
  core : entity work.ddr_upload_ctrl
    generic map (DDR_WIDTH_BITS => DDR_WIDTH_BITS)
    port map (
      clk                          => clk,
      reset                        => reset,
      run_enable                   => run_enable,
      load_command                 => capture_command,
      rearm_command                => rearm_command,
      abort_command                => abort_command,
      new_session_safe             => new_session_safe,
      dram_ready                   => dram_ready,
      sample_count                 => sample_count,
      ddr_word_count               => ddr_word_count,
      ddr_capacity_words           => ddr_capacity_words,
      fifo_output_valid            => result_fifo_output_valid,
      ddr_write_ready_now          => ddr_write_ready_now,
      fifo_read_enable             => result_fifo_read_enable,
      pack_offset                  => pack_offset,
      pack_clear                   => pack_clear,
      ddr_write_valid              => ddr_write_valid,
      ddr_write_address            => ddr_write_address,
      loaded_samples               => captured_samples,
      load_state                   => capture_state,
      load_busy                    => capture_busy,
      load_done                    => capture_done,
      load_fault                   => capture_fault,
      fault_code                   => fault_code,
      load_generation              => capture_generation,
      command_rejected             => command_rejected,
      load_cycles                  => capture_cycles,
      data_window_cycles           => data_window_cycles,
      receive_cycles               => receive_cycles,
      write_cycles                 => write_cycles,
      fifo_empty_cycles            => fifo_empty_cycles,
      ddr_stall_cycles             => ddr_stall_cycles,
      pause_cycles                 => pause_cycles);
end architecture;
