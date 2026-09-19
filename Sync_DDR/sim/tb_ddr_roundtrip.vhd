-- Four real controller instances. LabVIEW/NI memories/FIFOs are behavioral.
-- Dual-clock FIFO contract is modeled; this is NOT a CDC/PHY implementation.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
entity tb_ddr_roundtrip is end entity;
architecture test of tb_ddr_roundtrip is
  constant N : positive := 604;
  constant K : positive := 40;
  constant M : positive := (N+K-1)/K;
  subtype word_t is std_logic_vector(31 downto 0);
  type group_t is array(0 to 3) of word_t;
  type block_t is array(0 to K-1) of word_t;
  constant ZB : block_t := (others=>(others=>'0'));
  signal clk150, clk125 : std_logic := '0';
  signal reset : std_logic := '1';
  signal finished : boolean := false;
  signal command_u, command_r, command_c, command_d : std_logic := '0';
  signal capture_run, host_drain : std_logic := '1';
  signal host_count, result_count, dma_count : natural := 0;
  signal input_visible, result_visible : std_logic := '0';
  signal in_pack, out_pack, in_current, out_current : block_t := ZB;
  signal r_fifo_data, r_mem_data, d_fifo_data, d_mem_data : block_t := ZB;
  signal c_four : group_t := (others=>(others=>'0'));
  signal u_ready_raw, c_ready_raw, r_request_raw, d_request_raw : std_logic := '0';
  signal r_prefetch_raw, d_prefetch_raw, result_ready_raw, dma_ready_raw : std_logic := '0';
  signal u_reset : std_logic := '0';
  signal u_run_enable : std_logic := '0';
  signal u_load_command : std_logic := '0';
  signal u_rearm_command : std_logic := '0';
  signal u_abort_command : std_logic := '0';
  signal u_new_session_safe : std_logic := '0';
  signal u_dram_ready : std_logic := '0';
  signal u_sample_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_ddr_word_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_ddr_capacity_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_fifo_output_valid : std_logic := '0';
  signal u_ddr_write_ready_now : std_logic := '0';
  signal u_fifo_read_enable : std_logic := '0';
  signal u_pack_offset : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_pack_clear : std_logic := '0';
  signal u_ddr_write_valid : std_logic := '0';
  signal u_ddr_write_address : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_loaded_samples : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_load_state : std_logic_vector(7 downto 0) := (others=>'0');
  signal u_load_busy : std_logic := '0';
  signal u_load_done : std_logic := '0';
  signal u_load_fault : std_logic := '0';
  signal u_fault_code : std_logic_vector(7 downto 0) := (others=>'0');
  signal u_load_generation : std_logic_vector(31 downto 0) := (others=>'0');
  signal u_command_rejected : std_logic := '0';
  signal u_load_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal u_data_window_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal u_receive_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal u_write_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal u_fifo_empty_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal u_ddr_stall_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal u_pause_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_reset : std_logic := '0';
  signal r_run_enable : std_logic := '0';
  signal r_read_command : std_logic := '0';
  signal r_rearm_command : std_logic := '0';
  signal r_abort_command : std_logic := '0';
  signal r_new_session_safe : std_logic := '0';
  signal r_dram_ready : std_logic := '0';
  signal r_sample_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_ddr_word_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_ddr_capacity_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_pattern_check_enable : std_logic := '0';
  signal r_pattern_seed : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_ddr_request_ready_now : std_logic := '0';
  signal r_prefetch_write_ready_now : std_logic := '0';
  signal r_ddr_retrieve_valid : std_logic := '0';
  signal r_prefetch_read_valid : std_logic := '0';
  signal r_stream_ready : std_logic := '0';
  signal r_stream_word0 : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_stream_word1 : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_stream_word2 : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_stream_word3 : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_request_valid : std_logic := '0';
  signal r_request_address : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_retrieve_ready : std_logic := '0';
  signal r_prefetch_write_valid : std_logic := '0';
  signal r_prefetch_read_enable : std_logic := '0';
  signal r_current_load : std_logic := '0';
  signal r_current_clear : std_logic := '0';
  signal r_stream_offset : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_stream_valid : std_logic := '0';
  signal r_stream_fire : std_logic := '0';
  signal r_stream_first : std_logic := '0';
  signal r_stream_last : std_logic := '0';
  signal r_read_state : std_logic_vector(7 downto 0) := (others=>'0');
  signal r_read_busy : std_logic := '0';
  signal r_read_done : std_logic := '0';
  signal r_read_fault : std_logic := '0';
  signal r_fault_code : std_logic_vector(7 downto 0) := (others=>'0');
  signal r_read_generation : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_command_rejected : std_logic := '0';
  signal r_requested_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_returned_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_enqueued_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_popped_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_sent_samples : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_total_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_replay_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_transfer_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_no_data_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_sink_stall_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_pause_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal r_checked_samples : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_mismatch_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_first_error_index : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_first_error_expected : std_logic_vector(31 downto 0) := (others=>'0');
  signal r_first_error_actual : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_reset : std_logic := '0';
  signal c_run_enable : std_logic := '0';
  signal c_capture_command : std_logic := '0';
  signal c_rearm_command : std_logic := '0';
  signal c_abort_command : std_logic := '0';
  signal c_new_session_safe : std_logic := '0';
  signal c_dram_ready : std_logic := '0';
  signal c_sample_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_ddr_word_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_ddr_capacity_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_result_fifo_output_valid : std_logic := '0';
  signal c_ddr_write_ready_now : std_logic := '0';
  signal c_result_fifo_read_enable : std_logic := '0';
  signal c_pack_offset : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_pack_clear : std_logic := '0';
  signal c_ddr_write_valid : std_logic := '0';
  signal c_ddr_write_address : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_captured_samples : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_capture_state : std_logic_vector(7 downto 0) := (others=>'0');
  signal c_capture_busy : std_logic := '0';
  signal c_capture_done : std_logic := '0';
  signal c_capture_fault : std_logic := '0';
  signal c_fault_code : std_logic_vector(7 downto 0) := (others=>'0');
  signal c_capture_generation : std_logic_vector(31 downto 0) := (others=>'0');
  signal c_command_rejected : std_logic := '0';
  signal c_capture_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal c_data_window_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal c_receive_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal c_write_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal c_fifo_empty_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal c_ddr_stall_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal c_pause_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal d_reset : std_logic := '0';
  signal d_run_enable : std_logic := '0';
  signal d_download_command : std_logic := '0';
  signal d_rearm_command : std_logic := '0';
  signal d_abort_command : std_logic := '0';
  signal d_new_session_safe : std_logic := '0';
  signal d_dram_ready : std_logic := '0';
  signal d_sample_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_ddr_word_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_ddr_capacity_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_ddr_request_ready_now : std_logic := '0';
  signal d_prefetch_write_ready_now : std_logic := '0';
  signal d_ddr_retrieve_valid : std_logic := '0';
  signal d_prefetch_read_valid : std_logic := '0';
  signal d_dma_ready_now : std_logic := '0';
  signal d_request_valid : std_logic := '0';
  signal d_request_address : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_retrieve_ready : std_logic := '0';
  signal d_prefetch_write_valid : std_logic := '0';
  signal d_prefetch_read_enable : std_logic := '0';
  signal d_current_load : std_logic := '0';
  signal d_current_clear : std_logic := '0';
  signal d_unpack_offset : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_dma_valid : std_logic := '0';
  signal d_dma_fire : std_logic := '0';
  signal d_dma_first : std_logic := '0';
  signal d_dma_last : std_logic := '0';
  signal d_download_state : std_logic_vector(7 downto 0) := (others=>'0');
  signal d_download_busy : std_logic := '0';
  signal d_download_done : std_logic := '0';
  signal d_download_fault : std_logic := '0';
  signal d_fault_code : std_logic_vector(7 downto 0) := (others=>'0');
  signal d_download_generation : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_command_rejected : std_logic := '0';
  signal d_requested_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_returned_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_enqueued_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_popped_words : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_downloaded_samples : std_logic_vector(31 downto 0) := (others=>'0');
  signal d_total_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal d_download_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal d_transfer_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal d_no_data_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal d_sink_stall_cycles : std_logic_vector(63 downto 0) := (others=>'0');
  signal d_pause_cycles : std_logic_vector(63 downto 0) := (others=>'0');

  function val(index : natural) return word_t is
  begin return std_logic_vector(to_unsigned(16#12340000#,32)+to_unsigned(index,32)); end;
  function num(v : std_logic_vector) return natural is
  begin if is_x(v) then return 0; else return to_integer(unsigned(v)); end if; end;
begin
  clock150: process
  begin
    while not finished loop clk150<='0'; wait for 3.333333 ns; clk150<='1'; wait for 3.333333 ns; end loop;
    wait;
  end process;
  clock125: process
  begin
    while not finished loop clk125<='0'; wait for 4 ns; clk125<='1'; wait for 4 ns; end loop;
    wait;
  end process;
  watchdog: process
  begin wait for 1 ms; assert finished report "Roundtrip watchdog" severity failure; wait; end process;
  u_dut : entity work.ddr_upload_ctrl
    port map (
      clk => clk150,
      reset => u_reset,
      run_enable => u_run_enable,
      load_command => u_load_command,
      rearm_command => u_rearm_command,
      abort_command => u_abort_command,
      new_session_safe => u_new_session_safe,
      dram_ready => u_dram_ready,
      sample_count => u_sample_count,
      ddr_word_count => u_ddr_word_count,
      ddr_capacity_words => u_ddr_capacity_words,
      fifo_output_valid => u_fifo_output_valid,
      ddr_write_ready_now => u_ddr_write_ready_now,
      fifo_read_enable => u_fifo_read_enable,
      pack_offset => u_pack_offset,
      pack_clear => u_pack_clear,
      ddr_write_valid => u_ddr_write_valid,
      ddr_write_address => u_ddr_write_address,
      loaded_samples => u_loaded_samples,
      load_state => u_load_state,
      load_busy => u_load_busy,
      load_done => u_load_done,
      load_fault => u_load_fault,
      fault_code => u_fault_code,
      load_generation => u_load_generation,
      command_rejected => u_command_rejected,
      load_cycles => u_load_cycles,
      data_window_cycles => u_data_window_cycles,
      receive_cycles => u_receive_cycles,
      write_cycles => u_write_cycles,
      fifo_empty_cycles => u_fifo_empty_cycles,
      ddr_stall_cycles => u_ddr_stall_cycles,
      pause_cycles => u_pause_cycles);
  u_reset <= reset;
  u_run_enable <= '1';
  u_load_command <= command_u;
  u_rearm_command <= '0';
  u_abort_command <= '0';
  u_new_session_safe <= '1';
  u_dram_ready <= '1';
  u_sample_count <= std_logic_vector(to_unsigned(N,32));
  u_ddr_word_count <= std_logic_vector(to_unsigned(M,32));
  u_ddr_capacity_words <= x"00010000";
  r_dut : entity work.ddr_read_ctrl
    port map (
      clk => clk125,
      reset => r_reset,
      run_enable => r_run_enable,
      read_command => r_read_command,
      rearm_command => r_rearm_command,
      abort_command => r_abort_command,
      new_session_safe => r_new_session_safe,
      dram_ready => r_dram_ready,
      sample_count => r_sample_count,
      ddr_word_count => r_ddr_word_count,
      ddr_capacity_words => r_ddr_capacity_words,
      pattern_check_enable => r_pattern_check_enable,
      pattern_seed => r_pattern_seed,
      ddr_request_ready_now => r_ddr_request_ready_now,
      prefetch_write_ready_now => r_prefetch_write_ready_now,
      ddr_retrieve_valid => r_ddr_retrieve_valid,
      prefetch_read_valid => r_prefetch_read_valid,
      stream_ready => r_stream_ready,
      stream_word0 => r_stream_word0,
      stream_word1 => r_stream_word1,
      stream_word2 => r_stream_word2,
      stream_word3 => r_stream_word3,
      request_valid => r_request_valid,
      request_address => r_request_address,
      retrieve_ready => r_retrieve_ready,
      prefetch_write_valid => r_prefetch_write_valid,
      prefetch_read_enable => r_prefetch_read_enable,
      current_load => r_current_load,
      current_clear => r_current_clear,
      stream_offset => r_stream_offset,
      stream_valid => r_stream_valid,
      stream_fire => r_stream_fire,
      stream_first => r_stream_first,
      stream_last => r_stream_last,
      read_state => r_read_state,
      read_busy => r_read_busy,
      read_done => r_read_done,
      read_fault => r_read_fault,
      fault_code => r_fault_code,
      read_generation => r_read_generation,
      command_rejected => r_command_rejected,
      requested_words => r_requested_words,
      returned_words => r_returned_words,
      enqueued_words => r_enqueued_words,
      popped_words => r_popped_words,
      sent_samples => r_sent_samples,
      total_cycles => r_total_cycles,
      replay_cycles => r_replay_cycles,
      transfer_cycles => r_transfer_cycles,
      no_data_cycles => r_no_data_cycles,
      sink_stall_cycles => r_sink_stall_cycles,
      pause_cycles => r_pause_cycles,
      checked_samples => r_checked_samples,
      mismatch_count => r_mismatch_count,
      first_error_index => r_first_error_index,
      first_error_expected => r_first_error_expected,
      first_error_actual => r_first_error_actual);
  r_reset <= reset;
  r_run_enable <= '1';
  r_read_command <= command_r;
  r_rearm_command <= '0';
  r_abort_command <= '0';
  r_new_session_safe <= '1';
  r_dram_ready <= '1';
  r_sample_count <= std_logic_vector(to_unsigned(N,32));
  r_ddr_word_count <= std_logic_vector(to_unsigned(M,32));
  r_ddr_capacity_words <= x"00010000";
  r_pattern_check_enable <= '1';
  r_pattern_seed <= x"12340000";
  r_stream_word0 <= in_current(num(r_stream_offset)+0);
  r_stream_word1 <= in_current(num(r_stream_offset)+1);
  r_stream_word2 <= in_current(num(r_stream_offset)+2);
  r_stream_word3 <= in_current(num(r_stream_offset)+3);
  c_dut : entity work.ddr_capture_ctrl
    port map (
      clk => clk150,
      reset => c_reset,
      run_enable => c_run_enable,
      capture_command => c_capture_command,
      rearm_command => c_rearm_command,
      abort_command => c_abort_command,
      new_session_safe => c_new_session_safe,
      dram_ready => c_dram_ready,
      sample_count => c_sample_count,
      ddr_word_count => c_ddr_word_count,
      ddr_capacity_words => c_ddr_capacity_words,
      result_fifo_output_valid => c_result_fifo_output_valid,
      ddr_write_ready_now => c_ddr_write_ready_now,
      result_fifo_read_enable => c_result_fifo_read_enable,
      pack_offset => c_pack_offset,
      pack_clear => c_pack_clear,
      ddr_write_valid => c_ddr_write_valid,
      ddr_write_address => c_ddr_write_address,
      captured_samples => c_captured_samples,
      capture_state => c_capture_state,
      capture_busy => c_capture_busy,
      capture_done => c_capture_done,
      capture_fault => c_capture_fault,
      fault_code => c_fault_code,
      capture_generation => c_capture_generation,
      command_rejected => c_command_rejected,
      capture_cycles => c_capture_cycles,
      data_window_cycles => c_data_window_cycles,
      receive_cycles => c_receive_cycles,
      write_cycles => c_write_cycles,
      fifo_empty_cycles => c_fifo_empty_cycles,
      ddr_stall_cycles => c_ddr_stall_cycles,
      pause_cycles => c_pause_cycles);
  c_reset <= reset;
  c_run_enable <= capture_run;
  c_capture_command <= command_c;
  c_rearm_command <= '0';
  c_abort_command <= '0';
  c_new_session_safe <= '1';
  c_dram_ready <= '1';
  c_sample_count <= std_logic_vector(to_unsigned(N,32));
  c_ddr_word_count <= std_logic_vector(to_unsigned(M,32));
  c_ddr_capacity_words <= x"00010000";
  d_dut : entity work.ddr_download_ctrl
    port map (
      clk => clk150,
      reset => d_reset,
      run_enable => d_run_enable,
      download_command => d_download_command,
      rearm_command => d_rearm_command,
      abort_command => d_abort_command,
      new_session_safe => d_new_session_safe,
      dram_ready => d_dram_ready,
      sample_count => d_sample_count,
      ddr_word_count => d_ddr_word_count,
      ddr_capacity_words => d_ddr_capacity_words,
      ddr_request_ready_now => d_ddr_request_ready_now,
      prefetch_write_ready_now => d_prefetch_write_ready_now,
      ddr_retrieve_valid => d_ddr_retrieve_valid,
      prefetch_read_valid => d_prefetch_read_valid,
      dma_ready_now => d_dma_ready_now,
      request_valid => d_request_valid,
      request_address => d_request_address,
      retrieve_ready => d_retrieve_ready,
      prefetch_write_valid => d_prefetch_write_valid,
      prefetch_read_enable => d_prefetch_read_enable,
      current_load => d_current_load,
      current_clear => d_current_clear,
      unpack_offset => d_unpack_offset,
      dma_valid => d_dma_valid,
      dma_fire => d_dma_fire,
      dma_first => d_dma_first,
      dma_last => d_dma_last,
      download_state => d_download_state,
      download_busy => d_download_busy,
      download_done => d_download_done,
      download_fault => d_download_fault,
      fault_code => d_fault_code,
      download_generation => d_download_generation,
      command_rejected => d_command_rejected,
      requested_words => d_requested_words,
      returned_words => d_returned_words,
      enqueued_words => d_enqueued_words,
      popped_words => d_popped_words,
      downloaded_samples => d_downloaded_samples,
      total_cycles => d_total_cycles,
      download_cycles => d_download_cycles,
      transfer_cycles => d_transfer_cycles,
      no_data_cycles => d_no_data_cycles,
      sink_stall_cycles => d_sink_stall_cycles,
      pause_cycles => d_pause_cycles);
  d_reset <= reset;
  d_run_enable <= '1';
  d_download_command <= command_d;
  d_rearm_command <= '0';
  d_abort_command <= '0';
  d_new_session_safe <= '1';
  d_dram_ready <= '1';
  d_sample_count <= std_logic_vector(to_unsigned(N,32));
  d_ddr_word_count <= std_logic_vector(to_unsigned(M,32));
  d_ddr_capacity_words <= x"00010000";

  -- Raw NI next-cycle ready is delayed exactly once in its owning domain.
  feedback150: process(clk150)
  begin
    if rising_edge(clk150) then
      if reset='1' then
        u_ddr_write_ready_now<='0'; c_ddr_write_ready_now<='0';
        d_ddr_request_ready_now<='0'; d_prefetch_write_ready_now<='0'; d_dma_ready_now<='0';
      else
        u_ddr_write_ready_now<=u_ready_raw; c_ddr_write_ready_now<=c_ready_raw;
        d_ddr_request_ready_now<=d_request_raw; d_prefetch_write_ready_now<=d_prefetch_raw;
        d_dma_ready_now<=dma_ready_raw;
      end if;
    end if;
  end process;
  feedback125: process(clk125)
  begin
    if rising_edge(clk125) then
      if reset='1' then
        r_ddr_request_ready_now<='0'; r_prefetch_write_ready_now<='0'; r_stream_ready<='0';
      else
        r_ddr_request_ready_now<=r_request_raw; r_prefetch_write_ready_now<=r_prefetch_raw;
        r_stream_ready<=result_ready_raw;
      end if;
    end if;
  end process;

  -- A single simulation-only owner serializes coincident model events. Read
  -- returns always come from memories actually written by upstream controllers.
  model: process(clk150,clk125,finished)
    type memory_t is array(0 to M-1) of block_t;
    type block_fifo_t is array(0 to 255) of block_t;
    type queue_t is array(0 to 63) of natural;
    type small_fifo_t is array(0 to 7) of group_t;
    variable mem_in, mem_out : memory_t := (others=>ZB);
    variable rf, df : block_fifo_t := (others=>ZB);
    variable ra, rdue, da, ddue : queue_t := (others=>0);
    variable results, dma : small_fifo_t := (others=>(others=>(others=>'0')));
    variable c150,c125,source_ix,in_writes,out_writes : natural := 0;
    variable in_due,out_due : natural := 0;
    variable rqh,rqt,rqn,rfh,rft,rfn,req_r,pop_r,ret_r,push_r,sent_r : natural := 0;
    variable dqh,dqt,dqn,dfh,dft,dfn,req_d,pop_d,ret_d,push_d,sent_d : natural := 0;
    variable rh,rt,rn,dh,dt,dn,received : natural := 0;
    variable off,addr,ix : natural;
    variable gp : group_t;
    variable pack : block_t;
    variable held_r,held_d : boolean := false;
    variable hold_r,hold_d : group_t := (others=>(others=>'0'));
    file host_file : text open write_mode is "host_received_u32.csv";
    variable line_out : line;
  begin
    if falling_edge(clk150) then
      u_fifo_output_valid<='0'; c_result_fifo_output_valid<='0';
      d_ddr_retrieve_valid<='0'; d_prefetch_read_valid<='0';
      u_ready_raw<='0'; c_ready_raw<='0'; d_request_raw<='0'; d_prefetch_raw<='0'; dma_ready_raw<='0';
      if reset='0' then
        if source_ix<N and u_fifo_read_enable='1' and c150 mod 5/=0 then u_fifo_output_valid<='1'; end if;
        if c150 mod 13/=0 then u_ready_raw<='1'; c_ready_raw<='1'; end if;
        if rn>0 and c_result_fifo_read_enable='1' then c_result_fifo_output_valid<='1'; c_four<=results(rh); end if;
        if dqn<62 then d_request_raw<='1'; end if;
        if dfn<254 then d_prefetch_raw<='1'; end if;
        if dn<6 then dma_ready_raw<='1'; end if;
        if dqn>0 and ddue(dqh)<=c150 and d_retrieve_ready='1' then
          d_ddr_retrieve_valid<='1'; d_mem_data<=mem_out(da(dqh));
        end if;
        if dfn>0 and d_prefetch_read_enable='1' then d_prefetch_read_valid<='1'; d_fifo_data<=df(dfh); end if;
      end if;
    end if;
    if falling_edge(clk125) then
      r_ddr_retrieve_valid<='0'; r_prefetch_read_valid<='0';
      r_request_raw<='0'; r_prefetch_raw<='0'; result_ready_raw<='0';
      if reset='0' then
        if rqn<62 then r_request_raw<='1'; end if;
        if rfn<254 then r_prefetch_raw<='1'; end if;
        if rn<6 then result_ready_raw<='1'; end if;
        if rqn>0 and rdue(rqh)<=c125 and r_retrieve_ready='1' then
          r_ddr_retrieve_valid<='1'; r_mem_data<=mem_in(ra(rqh));
        end if;
        if rfn>0 and r_prefetch_read_enable='1' then r_prefetch_read_valid<='1'; r_fifo_data<=rf(rfh); end if;
      end if;
    end if;
    if rising_edge(clk150) then
      c150:=c150+1;
      if reset='0' then
        -- Input DDR write: consume the OLD LabVIEW packing register.
        if u_ddr_write_valid='1' then
          addr:=num(u_ddr_write_address);
          assert u_ddr_write_ready_now='1' and addr=in_writes and addr<M report "Upload write address/permission" severity failure;
          for j in 0 to K-1 loop
            ix:=addr*K+j;
            if ix<N then assert in_pack(j)=val(ix) report "Input DDR payload" severity failure;
            else assert in_pack(j)=x"00000000" report "Input tail not zero" severity failure; end if;
          end loop;
          mem_in(addr):=in_pack; in_writes:=in_writes+1; in_due:=c150+3;
        end if;
        pack:=in_pack;
        if u_pack_clear='1' then pack:=ZB;
        elsif u_fifo_output_valid='1' then
          assert u_fifo_read_enable='1' and source_ix+4<=N report "Host FIFO over-read" severity failure;
          off:=num(u_pack_offset);
          for j in 0 to 3 loop pack(off+j):=val(source_ix+j); end loop;
          source_ix:=source_ix+4;
        end if;
        in_pack<=pack;
        if in_writes=M and c150>=in_due then input_visible<='1'; end if;

        -- Result capture sees ONLY data carried through the finite result FIFO.
        if c_ddr_write_valid='1' then
          addr:=num(c_ddr_write_address);
          assert c_ddr_write_ready_now='1' and addr=out_writes and addr<M report "Capture write address/permission" severity failure;
          for j in 0 to K-1 loop
            ix:=addr*K+j;
            if ix<N then assert out_pack(j)=val(ix) report "Result DDR payload changed" severity failure;
            else assert out_pack(j)=x"00000000" report "Result tail not zero" severity failure; end if;
          end loop;
          mem_out(addr):=out_pack; out_writes:=out_writes+1; out_due:=c150+3;
        end if;
        pack:=out_pack;
        if c_pack_clear='1' then pack:=ZB;
        elsif c_result_fifo_output_valid='1' then
          assert c_result_fifo_read_enable='1' and rn>0 report "Capture read empty result FIFO" severity failure;
          off:=num(c_pack_offset);
          for j in 0 to 3 loop pack(off+j):=c_four(j); end loop;
          rh:=(rh+1) mod 8; rn:=rn-1;
        end if;
        out_pack<=pack;
        if out_writes=M and c150>=out_due then result_visible<='1'; end if;

        -- Host drains an independently owned finite DMA queue intermittently.
        if host_drain='1' and dn>0 and c150 mod 3=0 then
          for j in 0 to 3 loop
            assert received<N and dma(dh)(j)=val(received) report "Host roundtrip mismatch/drop/duplicate/order" severity failure;
            write(line_out,to_integer(unsigned(dma(dh)(j)))); writeline(host_file,line_out);
            received:=received+1;
          end loop;
          dh:=(dh+1) mod 8; dn:=dn-1;
        end if;
        off:=num(d_unpack_offset);
        gp:=(out_current(off),out_current(off+1),out_current(off+2),out_current(off+3));
        if held_d then assert d_dma_valid='1' and gp=hold_d report "DMA stall payload changed" severity failure; end if;
        held_d:=d_dma_valid='1' and d_dma_ready_now='0'; hold_d:=gp;
        if d_dma_fire='1' then
          assert d_dma_ready_now='1' and dn<8 and sent_d+4<=N report "DMA overflow/extra points" severity failure;
          assert (d_dma_first='1')=(sent_d=0) and (d_dma_last='1')=(sent_d+4=N) report "Download first/last" severity failure;
          dma(dt):=gp; dt:=(dt+1) mod 8; dn:=dn+1; sent_d:=sent_d+4;
        end if;
        if d_current_clear='1' then out_current<=ZB;
        elsif d_current_load='1' then assert d_prefetch_read_valid='1' report "Download current load" severity failure; out_current<=d_fifo_data; end if;
        if d_prefetch_read_valid='1' then
          assert d_prefetch_read_enable='1' and dfn>0 report "Download prefetch pop" severity failure;
          dfh:=(dfh+1) mod 256; dfn:=dfn-1; pop_d:=pop_d+1;
        end if;
        if d_prefetch_write_valid='1' then
          assert d_ddr_retrieve_valid='1' and d_prefetch_write_ready_now='1' and dfn<256 report "Download prefetch push" severity failure;
          df(dft):=d_mem_data; dft:=(dft+1) mod 256; dfn:=dfn+1; push_d:=push_d+1;
        end if;
        if d_ddr_retrieve_valid='1' then assert d_retrieve_ready='1' and dqn>0 report "Download retrieve" severity failure; dqh:=(dqh+1) mod 64; dqn:=dqn-1; ret_d:=ret_d+1; end if;
        if d_request_valid='1' then
          assert result_visible='1' and c_capture_done='1' and d_ddr_request_ready_now='1' and dqn<64 report "Premature result read" severity failure;
          assert num(d_request_address)=req_d and req_d<M report "Download request order" severity failure;
          da(dqt):=req_d; ddue(dqt):=c150+3; dqt:=(dqt+1) mod 64; dqn:=dqn+1; req_d:=req_d+1;
        end if;
      end if;
    end if;
    if rising_edge(clk125) then
      c125:=c125+1;
      if reset='0' then
        off:=num(r_stream_offset);
        gp:=(in_current(off),in_current(off+1),in_current(off+2),in_current(off+3));
        if held_r then assert r_stream_valid='1' and gp=hold_r report "Result FIFO stall changed playback data" severity failure; end if;
        held_r:=r_stream_valid='1' and r_stream_ready='0'; hold_r:=gp;
        if r_stream_fire='1' then
          assert r_stream_ready='1' and rn<8 and sent_r+4<=N report "Result FIFO overflow/extra points" severity failure;
          assert (r_stream_first='1')=(sent_r=0) and (r_stream_last='1')=(sent_r+4=N) report "Replay first/last" severity failure;
          for j in 0 to 3 loop assert gp(j)=val(sent_r+j) report "Replay sample order" severity failure; end loop;
          results(rt):=gp; rt:=(rt+1) mod 8; rn:=rn+1; sent_r:=sent_r+4;
        end if;
        if r_current_clear='1' then in_current<=ZB;
        elsif r_current_load='1' then assert r_prefetch_read_valid='1' report "Replay current load" severity failure; in_current<=r_fifo_data; end if;
        if r_prefetch_read_valid='1' then
          assert r_prefetch_read_enable='1' and rfn>0 report "Replay prefetch pop" severity failure;
          rfh:=(rfh+1) mod 256; rfn:=rfn-1; pop_r:=pop_r+1;
        end if;
        if r_prefetch_write_valid='1' then
          assert r_ddr_retrieve_valid='1' and r_prefetch_write_ready_now='1' and rfn<256 report "Replay prefetch push" severity failure;
          rf(rft):=r_mem_data; rft:=(rft+1) mod 256; rfn:=rfn+1; push_r:=push_r+1;
        end if;
        if r_ddr_retrieve_valid='1' then assert r_retrieve_ready='1' and rqn>0 report "Replay retrieve" severity failure; rqh:=(rqh+1) mod 64; rqn:=rqn-1; ret_r:=ret_r+1; end if;
        if r_request_valid='1' then
          assert input_visible='1' and u_load_done='1' and r_ddr_request_ready_now='1' and rqn<64 report "Premature input read" severity failure;
          assert num(r_request_address)=req_r and req_r<M report "Replay request order" severity failure;
          ra(rqt):=req_r; rdue(rqt):=c125+3; rqt:=(rqt+1) mod 64; rqn:=rqn+1; req_r:=req_r+1;
        end if;
      end if;
    end if;
    host_count<=received; result_count<=rn; dma_count<=dn;
    if finished then
      assert source_ix=N and in_writes=M and out_writes=M and sent_r=N and sent_d=N and received=N report "Final end-to-end counts" severity failure;
      assert rqn=0 and dqn=0 and rfn=0 and dfn=0 and rn=0 and dn=0 report "Queues not empty at completion" severity failure;
    end if;
  end process;

  stimulus: process
    procedure t150(count : positive := 1) is
    begin for i in 1 to count loop wait until rising_edge(clk150); wait for 1 ns; end loop; end;
    procedure t125(count : positive := 1) is
    begin for i in 1 to count loop wait until rising_edge(clk125); wait for 1 ns; end loop; end;
    variable held : natural;
  begin
    t150(5); reset<='0'; t150(3);
    command_u<='1'; t150(3); command_u<='0';
    wait until u_load_done='1'; wait until input_visible='1'; t150;
    assert num(u_loaded_samples)=N and num(u_ddr_write_address)=M report "Upload count" severity failure;
    command_c<='1'; t150(3); command_c<='0';
    assert c_capture_busy='1' and c_capture_fault='0' report "Capture not armed before replay" severity failure;
    t125; command_r<='1'; t125(3); command_r<='0';
    wait until r_stream_valid='1';
    t150(5); capture_run<='0'; t150(45);
    assert r_stream_valid='1' and r_stream_ready='0' and result_count>0 report "Capture pause did not backpressure replay" severity failure;
    held:=num(r_sent_samples); t150(12);
    assert num(r_sent_samples)=held report "Replay advanced during full result FIFO" severity failure;
    capture_run<='1';
    wait until c_capture_done='1'; wait until result_visible='1'; t150;
    assert r_read_done='1' and num(r_sent_samples)=N and num(c_captured_samples)=N report "Replay/capture completion counts" severity failure;
    assert num(r_mismatch_count)=0 and num(r_checked_samples)=N report "Replay independent checker" severity failure;
    assert unsigned(r_sink_stall_cycles)>0 report "Replay backpressure was not covered" severity failure;
    host_drain<='0'; command_d<='1'; t150(3); command_d<='0';
    wait until d_dma_valid='1'; t150(24);
    assert d_dma_valid='1' and d_dma_ready_now='0' and dma_count>0 report "Host pause did not fill DMA" severity failure;
    held:=num(d_downloaded_samples); t150(9);
    assert num(d_downloaded_samples)=held and host_count=0 report "DMA full did not hold data" severity failure;
    host_drain<='1';
    wait until d_download_done='1'; t150;
    assert host_count<N and dma_count>0 report "Download done incorrectly treated as Host receipt" severity failure;
    for i in 1 to 100 loop exit when host_count=N; t150; end loop;
    assert host_count=N and dma_count=0 and result_count=0 report "Host final count/FIFO drain" severity failure;
    assert num(d_requested_words)=M and num(d_returned_words)=M and num(d_popped_words)=M report "Download DDR block counts" severity failure;
    assert num(r_requested_words)=M and num(r_returned_words)=M and num(r_popped_words)=M report "Replay DDR block counts" severity failure;
    assert num(r_transfer_cycles)=N/4 and num(d_transfer_cycles)=N/4 report "Four-point group counts" severity failure;
    assert u_load_fault='0' and r_read_fault='0' and c_capture_fault='0' and d_download_fault='0' report "Fault on successful roundtrip" severity failure;
    report "ROUNDTRIP_HOST_COUNT=604 MISMATCH=0 DDR_WORDS_EACH=16 GROUPS_EACH=151" severity note;
    report "ROUNDTRIP_RESULT_FIFO_AND_DMA_BACKPRESSURE_PASS" severity note;
    report "DDR_ROUNDTRIP_TEST_PASS" severity note;
    finished<=true; wait;
  end process;
end architecture;
