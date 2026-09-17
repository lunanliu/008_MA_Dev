-- VHDL-93 DDR1280 read/replay controller. Data stays in LabVIEW.
-- All ports use the same clock as the 125 MHz SCTL. NI write/request
-- Ready for Input is delayed ONCE in LabVIEW before the *_ready_now ports.
-- reset is synchronous active HIGH; it does not flush NI memory/FIFOs.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ddr_read_ctrl is
  port (
    clk                       : in  std_logic;
    reset                     : in  std_logic;
    run_enable                : in  std_logic;
    read_command              : in  std_logic;
    rearm_command             : in  std_logic;
    abort_command             : in  std_logic;
    new_session_safe          : in  std_logic;
    dram_ready                : in  std_logic;
    sample_count              : in  std_logic_vector(31 downto 0);
    ddr_word_count            : in  std_logic_vector(31 downto 0);
    pattern_check_enable      : in  std_logic;
    pattern_seed              : in  std_logic_vector(31 downto 0);
    ddr_request_ready_now     : in  std_logic;
    prefetch_write_ready_now  : in  std_logic;
    ddr_retrieve_valid        : in  std_logic;
    prefetch_read_valid       : in  std_logic;
    stream_ready              : in  std_logic;
    stream_word0              : in  std_logic_vector(31 downto 0);
    stream_word1              : in  std_logic_vector(31 downto 0);
    stream_word2              : in  std_logic_vector(31 downto 0);
    stream_word3              : in  std_logic_vector(31 downto 0);
    request_valid             : out std_logic;
    request_address           : out std_logic_vector(31 downto 0);
    retrieve_ready            : out std_logic;
    prefetch_write_valid      : out std_logic;
    prefetch_read_enable      : out std_logic;
    current_load              : out std_logic;
    current_clear             : out std_logic;
    stream_offset             : out std_logic_vector(31 downto 0);
    stream_valid              : out std_logic;
    stream_fire               : out std_logic;
    read_state                : out std_logic_vector(7 downto 0);
    read_busy                 : out std_logic;
    read_done                 : out std_logic;
    read_fault                : out std_logic;
    fault_code                : out std_logic_vector(7 downto 0);
    read_generation           : out std_logic_vector(31 downto 0);
    command_rejected          : out std_logic;
    requested_words           : out std_logic_vector(31 downto 0);
    returned_words            : out std_logic_vector(31 downto 0);
    enqueued_words            : out std_logic_vector(31 downto 0);
    popped_words              : out std_logic_vector(31 downto 0);
    sent_samples              : out std_logic_vector(31 downto 0);
    total_cycles              : out std_logic_vector(63 downto 0);
    replay_cycles             : out std_logic_vector(63 downto 0);
    transfer_cycles           : out std_logic_vector(63 downto 0);
    no_data_cycles            : out std_logic_vector(63 downto 0);
    sink_stall_cycles         : out std_logic_vector(63 downto 0);
    pause_cycles              : out std_logic_vector(63 downto 0);
    checked_samples           : out std_logic_vector(31 downto 0);
    mismatch_count            : out std_logic_vector(31 downto 0);
    first_error_index         : out std_logic_vector(31 downto 0);
    first_error_expected      : out std_logic_vector(31 downto 0);
    first_error_actual        : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of ddr_read_ctrl is
  type state_t is (WAIT_READ, PREFETCH, PRIME, STREAMING, DRAIN, DONE, FAULT);
  signal state_q : state_t := WAIT_READ;
  signal prev_read_q, prev_rearm_q : std_logic := '0';
  signal samples_q, words_q, threshold_q : unsigned(31 downto 0) := (others=>'0');
  signal requested_q, returned_q, enqueued_q, popped_q, sent_q : unsigned(31 downto 0) := (others=>'0');
  signal group_q : unsigned(3 downto 0) := (others=>'0');
  signal current_valid_q, replay_started_q : std_logic := '0';
  signal check_q : std_logic := '0';
  signal seed_q, generation_q : unsigned(31 downto 0) := (others=>'0');
  signal rejected_q : std_logic := '0';
  signal fault_q : std_logic_vector(7 downto 0) := x"00";
  signal total_q, replay_q, transfer_q, no_data_q, sink_stall_q, pause_q : unsigned(63 downto 0) := (others=>'0');
  signal checked_q, mismatch_q, first_index_q, first_expected_q, first_actual_q : unsigned(31 downto 0) := (others=>'0');
  signal n64, m40 : unsigned(63 downto 0);
  signal params_ok, read_edge, rearm_edge, read_context, start_accept, rearm_accept : std_logic;
  signal normal_active, any_active, drain_now : std_logic;
  signal request_fire_i, retrieve_ready_i, retrieve_fire_i, enqueue_fire_i : std_logic;
  signal fifo_read_i, pop_fire_i, current_load_i : std_logic;
  signal stream_valid_i, stream_fire_i, last_four_i : std_logic;
begin
  n64 <= resize(unsigned(sample_count),64);
  m40 <= shift_left(resize(unsigned(ddr_word_count),64),5) +
         shift_left(resize(unsigned(ddr_word_count),64),3);
  params_ok <= '1' when unsigned(sample_count)/=0 and sample_count(1 downto 0)="00" and
                        unsigned(ddr_word_count)/=0 and unsigned(ddr_word_count)<=2048 and
                        n64<=m40 and n64+39>=m40 else '0';
  read_edge <= read_command and not prev_read_q;
  rearm_edge <= rearm_command and not prev_rearm_q;
  read_context <= '1' when reset='0' and run_enable='1' and abort_command='0' and
                          read_edge='1' and rearm_edge='0' and new_session_safe='1' and
                          dram_ready='1' and (state_q=WAIT_READ or state_q=DONE) else '0';
  start_accept <= read_context and params_ok;
  rearm_accept <= '1' when reset='0' and run_enable='1' and abort_command='0' and
                          rearm_edge='1' and read_edge='0' and new_session_safe='1' and
                          (state_q=WAIT_READ or state_q=DONE or state_q=FAULT) else '0';
  normal_active <= '1' when state_q=PREFETCH or state_q=PRIME or state_q=STREAMING else '0';
  any_active <= '1' when normal_active='1' or state_q=DRAIN else '0';
  drain_now <= '1' when state_q=DRAIN or (normal_active='1' and abort_command='1') else '0';

  -- Credit counts both in-flight DDR responses and FIFO-resident blocks.
  -- The separately held Current_Array has already released its FIFO credit.
  request_fire_i <= '1' when reset='0' and normal_active='1' and run_enable='1' and
                            abort_command='0' and dram_ready='1' and
                            ddr_request_ready_now='1' and requested_q<words_q and
                            requested_q-popped_q<256 else '0';
  -- Pausing stops new requests and playback, but drains existing responses
  -- into the FIFO. Abort/DRAIN instead consumes and discards old responses.
  retrieve_ready_i <= '1' when reset='0' and any_active='1' and dram_ready='1' and
                              returned_q<requested_q and
                              (drain_now='1' or prefetch_write_ready_now='1') else '0';
  retrieve_fire_i <= retrieve_ready_i and ddr_retrieve_valid;
  enqueue_fire_i <= retrieve_fire_i and normal_active and not abort_command;
  stream_valid_i <= '1' when reset='0' and state_q=STREAMING and current_valid_q='1' and
                            run_enable='1' and abort_command='0' and dram_ready='1' and
                            sent_q<samples_q else '0';
  stream_fire_i <= stream_valid_i and stream_ready;
  last_four_i <= '1' when sent_q+4=samples_q else '0';
  fifo_read_i <= '1' when reset='0' and popped_q<enqueued_q and
                        (drain_now='1' or
                         (run_enable='1' and abort_command='0' and dram_ready='1' and
                          (state_q=PRIME or (state_q=STREAMING and stream_fire_i='1' and
                           group_q=9 and last_four_i='0')))) else '0';
  pop_fire_i <= fifo_read_i and prefetch_read_valid;
  current_load_i <= pop_fire_i and normal_active and not abort_command;

  request_valid <= request_fire_i;
  request_address <= std_logic_vector(requested_q);
  retrieve_ready <= retrieve_ready_i;
  prefetch_write_valid <= enqueue_fire_i;
  prefetch_read_enable <= fifo_read_i;
  current_load <= current_load_i;
  current_clear <= '1' when reset='1' or start_accept='1' or rearm_accept='1' or
                            (normal_active='1' and (abort_command='1' or dram_ready='0')) or
                            (stream_fire_i='1' and last_four_i='1') else '0';
  stream_offset <= std_logic_vector(shift_left(resize(group_q,32),2));
  stream_valid <= stream_valid_i;
  stream_fire <= stream_fire_i;
  read_busy <= any_active;
  read_done <= '1' when state_q=DONE else '0';
  read_fault <= '1' when state_q=FAULT else '0';
  fault_code <= fault_q;
  read_generation <= std_logic_vector(generation_q);
  command_rejected <= rejected_q;
  requested_words <= std_logic_vector(requested_q);
  returned_words <= std_logic_vector(returned_q);
  enqueued_words <= std_logic_vector(enqueued_q);
  popped_words <= std_logic_vector(popped_q);
  sent_samples <= std_logic_vector(sent_q);
  total_cycles <= std_logic_vector(total_q);
  replay_cycles <= std_logic_vector(replay_q);
  transfer_cycles <= std_logic_vector(transfer_q);
  no_data_cycles <= std_logic_vector(no_data_q);
  sink_stall_cycles <= std_logic_vector(sink_stall_q);
  pause_cycles <= std_logic_vector(pause_q);
  checked_samples <= std_logic_vector(checked_q);
  mismatch_count <= std_logic_vector(mismatch_q);
  first_error_index <= std_logic_vector(first_index_q);
  first_error_expected <= std_logic_vector(first_expected_q);
  first_error_actual <= std_logic_vector(first_actual_q);
  with state_q select read_state <=
    x"00" when WAIT_READ, x"01" when PREFETCH, x"02" when PRIME,
    x"03" when STREAMING, x"04" when DRAIN, x"05" when DONE, x"06" when FAULT;

  process(clk)
    variable rq, rt, enq, pop, sent_next : unsigned(31 downto 0);
    variable mismatches, expected, actual, index_value : unsigned(31 downto 0);
    variable first_found : boolean;
  begin
    if rising_edge(clk) then
      prev_read_q <= read_command;
      prev_rearm_q <= rearm_command;
      if reset='1' then
        state_q<=WAIT_READ; group_q<=(others=>'0'); current_valid_q<='0'; replay_started_q<='0';
        samples_q<=(others=>'0'); words_q<=(others=>'0'); threshold_q<=(others=>'0');
        requested_q<=(others=>'0'); returned_q<=(others=>'0'); enqueued_q<=(others=>'0');
        popped_q<=(others=>'0'); sent_q<=(others=>'0');
        check_q<='0'; seed_q<=(others=>'0'); generation_q<=(others=>'0'); rejected_q<='0'; fault_q<=x"00";
        total_q<=(others=>'0'); replay_q<=(others=>'0'); transfer_q<=(others=>'0');
        no_data_q<=(others=>'0'); sink_stall_q<=(others=>'0'); pause_q<=(others=>'0');
        checked_q<=(others=>'0'); mismatch_q<=(others=>'0'); first_index_q<=(others=>'0');
        first_expected_q<=(others=>'0'); first_actual_q<=(others=>'0');
      else
        if read_edge='1' or rearm_edge='1' then rejected_q<='1'; end if;
        if start_accept='1' or rearm_accept='1' then
          group_q<=(others=>'0'); current_valid_q<='0'; replay_started_q<='0';
          requested_q<=(others=>'0'); returned_q<=(others=>'0'); enqueued_q<=(others=>'0');
          popped_q<=(others=>'0'); sent_q<=(others=>'0');
          total_q<=(others=>'0'); replay_q<=(others=>'0'); transfer_q<=(others=>'0');
          no_data_q<=(others=>'0'); sink_stall_q<=(others=>'0'); pause_q<=(others=>'0');
          checked_q<=(others=>'0'); mismatch_q<=(others=>'0'); first_index_q<=(others=>'0');
          first_expected_q<=(others=>'0'); first_actual_q<=(others=>'0');
          rejected_q<='0'; fault_q<=x"00";
          if start_accept='1' then
            state_q<=PREFETCH; samples_q<=unsigned(sample_count); words_q<=unsigned(ddr_word_count);
            if unsigned(ddr_word_count)<128 then threshold_q<=unsigned(ddr_word_count);
            else threshold_q<=to_unsigned(128,32); end if;
            check_q<=pattern_check_enable; seed_q<=unsigned(pattern_seed);
            generation_q<=generation_q+1;
          else
            state_q<=WAIT_READ; samples_q<=(others=>'0'); words_q<=(others=>'0'); threshold_q<=(others=>'0');
            check_q<='0'; seed_q<=(others=>'0');
          end if;
        elsif read_context='1' and params_ok='0' then
          state_q<=FAULT; fault_q<=x"01";
        else
          -- Record physical handshakes even on the first abort cycle. Never
          -- clear these counters before all old responses/FIFO data drain.
          rq:=requested_q; rt:=returned_q; enq:=enqueued_q; pop:=popped_q; sent_next:=sent_q;
          if request_fire_i='1' then rq:=rq+1; end if;
          if retrieve_fire_i='1' then rt:=rt+1; end if;
          if enqueue_fire_i='1' then enq:=enq+1; end if;
          if pop_fire_i='1' then pop:=pop+1; end if;
          if stream_fire_i='1' then sent_next:=sent_next+4; end if;
          requested_q<=rq; returned_q<=rt; enqueued_q<=enq; popped_q<=pop; sent_q<=sent_next;
          if any_active='1' then total_q<=total_q+1; end if;

          -- Replay starts AFTER the initial PRIME has loaded Current_Array.
          -- Recovery PRIME cycles count as no_data; DRAIN is not replay.
          if replay_started_q='1' and (state_q=PRIME or state_q=STREAMING) and
             abort_command='0' and dram_ready='1' then
            replay_q<=replay_q+1;
            if run_enable='0' then pause_q<=pause_q+1;
            elsif stream_fire_i='1' then transfer_q<=transfer_q+1;
            elsif stream_valid_i='1' then sink_stall_q<=sink_stall_q+1;
            else no_data_q<=no_data_q+1; end if;
          end if;
          if stream_fire_i='1' and check_q='1' then
            checked_q<=checked_q+4;
            mismatches:=mismatch_q; first_found:=(mismatch_q/=0);
            for lane in 0 to 3 loop
              index_value:=sent_q+lane; expected:=seed_q+index_value;
              case lane is
                when 0 => actual:=unsigned(stream_word0);
                when 1 => actual:=unsigned(stream_word1);
                when 2 => actual:=unsigned(stream_word2);
                when others => actual:=unsigned(stream_word3);
              end case;
              if actual/=expected then
                mismatches:=mismatches+1;
                if not first_found then
                  first_index_q<=index_value; first_expected_q<=expected; first_actual_q<=actual;
                  first_found:=true;
                end if;
              end if;
            end loop;
            mismatch_q<=mismatches;
          end if;

          if any_active='1' and dram_ready='0' then
            -- Old NI requests cannot be assumed canceled by readiness loss.
            -- An external verified cleanup is mandatory before safe rearm.
            state_q<=FAULT; fault_q<=x"02"; current_valid_q<='0';
          elsif normal_active='1' and abort_command='1' then
            state_q<=DRAIN; fault_q<=x"03"; current_valid_q<='0';
          elsif state_q=DRAIN then
            if rq=rt and enq=pop then state_q<=FAULT; fault_q<=x"03"; end if;
          elsif run_enable='1' then
            case state_q is
              when PREFETCH =>
                if rt>=threshold_q then state_q<=PRIME; end if;
              when PRIME =>
                if current_load_i='1' then
                  state_q<=STREAMING; current_valid_q<='1'; group_q<=(others=>'0'); replay_started_q<='1';
                end if;
              when STREAMING =>
                if stream_fire_i='1' then
                  if last_four_i='1' then
                    state_q<=DONE; current_valid_q<='0'; group_q<=(others=>'0');
                  elsif group_q=9 then
                    group_q<=(others=>'0');
                    if current_load_i='1' then current_valid_q<='1';
                    else current_valid_q<='0'; state_q<=PRIME; end if;
                  else group_q<=group_q+1; end if;
                end if;
              when others => null;
            end case;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;

