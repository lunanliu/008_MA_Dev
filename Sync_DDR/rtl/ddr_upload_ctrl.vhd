-- VHDL-93 control-only CLIP. The K x U32 data array stays in LabVIEW.
-- DDR_WIDTH_BITS is compile-time; ddr_capacity_words is a runtime word count.
-- load_done means all writes accepted, not a physical DDR write fence.
-- NI DDR Write Ready for Input MUST be delayed once in LabVIEW before
-- connecting ddr_write_ready_now. Do not add another delay inside this core.
-- All CLIP I/O in this contract uses the SAME clock as the SCTL, with no
-- additional synchronization registers. reset is synchronous, active HIGH.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ddr_upload_ctrl is
  generic (DDR_WIDTH_BITS : positive := 1280);
  port (
    clk                   : in  std_logic;
    reset                 : in  std_logic;
    run_enable            : in  std_logic;
    load_command          : in  std_logic;
    rearm_command         : in  std_logic;
    abort_command         : in  std_logic;
    new_session_safe      : in  std_logic;
    dram_ready            : in  std_logic;
    sample_count          : in  std_logic_vector(31 downto 0);
    ddr_word_count        : in  std_logic_vector(31 downto 0);
    ddr_capacity_words        : in  std_logic_vector(31 downto 0);
    fifo_output_valid     : in  std_logic;
    ddr_write_ready_now   : in  std_logic;
    fifo_read_enable      : out std_logic;
    pack_offset           : out std_logic_vector(31 downto 0);
    pack_clear            : out std_logic;
    ddr_write_valid       : out std_logic;
    ddr_write_address     : out std_logic_vector(31 downto 0);
    loaded_samples        : out std_logic_vector(31 downto 0);
    load_state            : out std_logic_vector(7 downto 0);
    load_busy             : out std_logic;
    load_done             : out std_logic;
    load_fault            : out std_logic;
    fault_code            : out std_logic_vector(7 downto 0);
    load_generation       : out std_logic_vector(31 downto 0);
    command_rejected      : out std_logic;
    load_cycles           : out std_logic_vector(63 downto 0);
    data_window_cycles    : out std_logic_vector(63 downto 0);
    receive_cycles        : out std_logic_vector(63 downto 0);
    write_cycles          : out std_logic_vector(63 downto 0);
    fifo_empty_cycles     : out std_logic_vector(63 downto 0);
    ddr_stall_cycles      : out std_logic_vector(63 downto 0);
    pause_cycles          : out std_logic_vector(63 downto 0)
  );
end entity;

architecture rtl of ddr_upload_ctrl is
  function group_bits(groups : positive) return positive is
    variable v : natural := groups - 1;
    variable bits : positive := 1;
  begin
    while v > 1 loop v := v / 2; bits := bits + 1; end loop;
    return bits;
  end function;
  constant SAMPLES_PER_WORD : positive := DDR_WIDTH_BITS / 32;
  constant GROUPS_PER_WORD : positive := SAMPLES_PER_WORD / 4;
  type state_t is (WAIT_LOAD, LOADING, DONE, FAULT, CONFIG_CALC, CONFIG_CHECK);
  signal state_q       : state_t := WAIT_LOAD;
  signal group_q       : unsigned(group_bits(GROUPS_PER_WORD)-1 downto 0) := (others => '0');
  signal loaded_q      : unsigned(31 downto 0) := (others => '0');
  signal address_q     : unsigned(31 downto 0) := (others => '0');
  signal samples_q     : unsigned(31 downto 0) := (others => '0');
  signal words_q       : unsigned(31 downto 0) := (others => '0');
  signal pending_q     : std_logic := '0';
  signal prev_load_q   : std_logic := '0';
  signal prev_rearm_q  : std_logic := '0';
  signal fault_q       : std_logic_vector(7 downto 0) := x"00";
  signal generation_q  : unsigned(31 downto 0) := (others => '0');
  signal rejected_q    : std_logic := '0';
  signal load_edge, rearm_edge, params_ok : std_logic;
  signal load_context, start_accept, rearm_accept : std_logic;
  signal read_enable_i, read_fire, write_fire : std_logic;
  signal capacity_q : unsigned(31 downto 0) := (others => '0');
  signal end_sample_q, word_samples_q : unsigned(63 downto 0) := (others => '0');
  signal load_cycles_q, window_q, receive_q, write_q, empty_q, stall_q, pause_q :
    unsigned(63 downto 0) := (others => '0');
  signal first_read_q : std_logic := '0';
begin
  assert DDR_WIDTH_BITS mod 128 = 0
    report "DDR_WIDTH_BITS must be a positive multiple of 128" severity failure;
  -- Checks use the immutable command snapshot. The constant product and
  -- upper sample bound are registered in CONFIG_CALC before comparison.
  params_ok <= '1' when samples_q /= 0 and samples_q(1 downto 0) = "00" and
                        capacity_q /= 0 and words_q /= 0 and words_q <= capacity_q and
                        resize(samples_q,64) <= word_samples_q and
                        end_sample_q >= word_samples_q else '0';
  load_edge  <= load_command and not prev_load_q;
  rearm_edge <= rearm_command and not prev_rearm_q;

  -- A command held high never queues a second transfer. Simultaneous load
  -- and rearm edges are both rejected. FAULT requires explicit safe rearm.
  load_context <= '1' when reset = '0' and run_enable = '1' and
                          abort_command = '0' and load_edge = '1' and
                          rearm_edge = '0' and new_session_safe = '1' and
                          dram_ready = '1' and
                          (state_q = WAIT_LOAD or state_q = DONE) else '0';
  start_accept <= load_context;
  rearm_accept <= '1' when reset = '0' and run_enable = '1' and
                          abort_command = '0' and rearm_edge = '1' and
                          load_edge = '0' and new_session_safe = '1' and
                          (state_q = WAIT_LOAD or state_q = DONE or state_q = FAULT) else '0';

  read_enable_i <= '1' when reset = '0' and run_enable = '1' and
                          abort_command = '0' and state_q = LOADING and
                          dram_ready = '1' and pending_q = '0' and
                          loaded_q < samples_q else '0';
  read_fire <= read_enable_i and fifo_output_valid;
  write_fire <= '1' when reset = '0' and run_enable = '1' and
                       abort_command = '0' and state_q = LOADING and
                       dram_ready = '1' and pending_q = '1' and
                       ddr_write_ready_now = '1' else '0';

  fifo_read_enable  <= read_enable_i;
  pack_offset       <= std_logic_vector(shift_left(resize(group_q, 32), 2));
  -- On write_fire the Memory node consumes OLD Pack_Array and OLD address;
  -- the LabVIEW shift register stores zeros for the NEXT cycle.
  pack_clear        <= reset or start_accept or rearm_accept or write_fire;
  ddr_write_valid   <= write_fire;
  ddr_write_address <= std_logic_vector(address_q);
  loaded_samples   <= std_logic_vector(loaded_q);
  load_busy        <= '1' when state_q = LOADING or state_q = CONFIG_CALC or state_q = CONFIG_CHECK else '0';
  load_done        <= '1' when state_q = DONE else '0';
  load_fault       <= '1' when state_q = FAULT else '0';
  fault_code       <= fault_q;
  load_generation  <= std_logic_vector(generation_q);
  command_rejected <= rejected_q;
  load_cycles <= std_logic_vector(load_cycles_q);
  data_window_cycles <= std_logic_vector(window_q);
  receive_cycles <= std_logic_vector(receive_q);
  write_cycles <= std_logic_vector(write_q);
  fifo_empty_cycles <= std_logic_vector(empty_q);
  ddr_stall_cycles <= std_logic_vector(stall_q);
  pause_cycles <= std_logic_vector(pause_q);
  with state_q select load_state <=
    x"00" when WAIT_LOAD, x"01" when LOADING,
    x"02" when DONE, x"03" when FAULT,
    x"04" when CONFIG_CALC, x"05" when CONFIG_CHECK;

  -- Hardware cycle counters; Host polls only held results after DONE/FAULT.
  -- data_window excludes the initial wait for the first DMA sample.
  process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' or start_accept = '1' or rearm_accept = '1' then
        load_cycles_q <= (others => '0'); window_q <= (others => '0');
        receive_q <= (others => '0'); write_q <= (others => '0');
        empty_q <= (others => '0'); stall_q <= (others => '0');
        pause_q <= (others => '0'); first_read_q <= '0';
      elsif state_q = LOADING then
        load_cycles_q <= load_cycles_q + 1;
        if first_read_q = '1' or read_fire = '1' then window_q <= window_q + 1; end if;
        if read_fire = '1' then first_read_q <= '1'; end if;
        if run_enable = '0' then
          pause_q <= pause_q + 1;
        elsif read_fire = '1' then
          receive_q <= receive_q + 1;
        elsif write_fire = '1' then
          write_q <= write_q + 1;
        elsif read_enable_i = '1' then
          empty_q <= empty_q + 1;
        elsif pending_q = '1' and dram_ready = '1' and abort_command = '0' then
          stall_q <= stall_q + 1;
        end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      -- Sample buttons even while paused and during reset: a held-high
      -- command is not reinterpreted as a fresh edge when resuming.
      prev_load_q  <= load_command;
      prev_rearm_q <= rearm_command;
      if reset = '1' then
        state_q      <= WAIT_LOAD;
        group_q      <= (others => '0');
        loaded_q     <= (others => '0');
        address_q    <= (others => '0');
        samples_q    <= (others => '0');
        words_q      <= (others => '0');
        capacity_q <= (others => '0'); end_sample_q <= (others => '0'); word_samples_q <= (others => '0');
        pending_q    <= '0';
        fault_q      <= x"00";
        generation_q <= (others => '0');
        rejected_q   <= '0';
      else
        -- Sticky diagnostic; rejected commands never reset an active job.
        if load_edge = '1' or rearm_edge = '1' then
          rejected_q <= '1';
        end if;
        if start_accept = '1' then
          state_q      <= CONFIG_CALC;
          group_q      <= (others => '0');
          loaded_q     <= (others => '0');
          address_q    <= (others => '0');
          pending_q    <= '0';
          samples_q    <= unsigned(sample_count);
          words_q      <= unsigned(ddr_word_count);
          capacity_q   <= unsigned(ddr_capacity_words);
          fault_q      <= x"00";
          rejected_q   <= '0';
        elsif rearm_accept = '1' then
          state_q    <= WAIT_LOAD;
          group_q    <= (others => '0');
          loaded_q   <= (others => '0');
          address_q  <= (others => '0');
          samples_q  <= (others => '0');
          words_q    <= (others => '0');
          capacity_q <= (others => '0'); end_sample_q <= (others => '0'); word_samples_q <= (others => '0');
          pending_q  <= '0';
          fault_q    <= x"00";
          rejected_q <= '0';
        elsif state_q = CONFIG_CALC or state_q = CONFIG_CHECK then
          if abort_command = '1' then
            state_q <= FAULT; fault_q <= x"03";
          elsif dram_ready = '0' then
            state_q <= FAULT; fault_q <= x"02";
          elsif run_enable = '1' then
            if state_q = CONFIG_CALC then
              word_samples_q <= words_q * to_unsigned(SAMPLES_PER_WORD,32);
              end_sample_q <= resize(samples_q,64) + to_unsigned(SAMPLES_PER_WORD-1,64);
              state_q <= CONFIG_CHECK;
            elsif params_ok = '1' then
              state_q <= LOADING; generation_q <= generation_q + 1;
            else
              state_q <= FAULT; fault_q <= x"01"; rejected_q <= '1';
            end if;
          end if;
        elsif state_q = LOADING then
          -- Abort and loss of DRAM readiness invalidate the upload even if
          -- run_enable=0. Pausing must not hide a DRAM reset/recalibration.
          if abort_command = '1' then
            state_q <= FAULT;
            fault_q <= x"03";
          elsif dram_ready = '0' then
            state_q <= FAULT;
            fault_q <= x"02";
          elsif write_fire = '1' then
            address_q <= address_q + 1;
            group_q   <= (others => '0');
            pending_q <= '0';
            if address_q + 1 = words_q then
              state_q <= DONE;
            end if;
          elsif read_fire = '1' then
            loaded_q <= loaded_q + 4;
            if group_q = GROUPS_PER_WORD-1 or loaded_q + 4 = samples_q then
              pending_q <= '1';
            else
              group_q <= group_q + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;