-- VHDL-93, self-checking NI interface model. No vendor simulation libraries.
-- This tests controller/protocol behavior, not the physical DDR PHY or NI VI.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ddr_read_ctrl_case is
  generic (DDR_WIDTH_BITS : positive := 1280; SMOKE_ONLY : boolean := false);
  port (case_done : out boolean);
end entity;

architecture test of tb_ddr_read_ctrl_case is
  constant K : positive := DDR_WIDTH_BITS/32;
  subtype word_t is std_logic_vector(31 downto 0);
  type block_t is array (0 to K-1) of word_t;
  type fifo_t is array (0 to 255) of block_t;
  type address_queue_t is array (0 to 63) of natural;
  constant ZERO_BLOCK : block_t := (others => (others => '0'));
  signal clk : std_logic := '0';
  signal finished : boolean := false;
  signal reset, run_enable, read_command, rearm_command : std_logic := '0';
  signal abort_command, new_session_safe, dram_ready : std_logic := '0';
  signal pattern_check_enable : std_logic := '1';
  signal sample_count, ddr_word_count, pattern_seed : word_t := (others => '0');
  signal ddr_capacity_words : word_t := x"00020000";
  signal stream_first, stream_last : std_logic;
  signal ddr_request_ready_now, prefetch_write_ready_now : std_logic := '0';
  signal request_ready_raw, fifo_write_ready_raw : std_logic := '0';
  signal ddr_retrieve_valid, prefetch_read_valid, stream_ready : std_logic := '0';
  signal stream_word0, stream_word1, stream_word2, stream_word3 : word_t;
  signal request_valid, retrieve_ready, prefetch_write_valid : std_logic;
  signal prefetch_read_enable, current_load, current_clear : std_logic;
  signal stream_valid, stream_fire, read_busy, read_done, read_fault : std_logic;
  signal command_rejected : std_logic;
  signal request_address, stream_offset, read_generation : word_t;
  signal requested_words, returned_words, enqueued_words, popped_words : word_t;
  signal sent_samples, checked_samples, mismatch_count : word_t;
  signal first_error_index, first_error_expected, first_error_actual : word_t;
  signal read_state, fault_code : std_logic_vector(7 downto 0);
  signal total_cycles, replay_cycles, transfer_cycles, no_data_cycles : std_logic_vector(63 downto 0);
  signal sink_stall_cycles, pause_cycles : std_logic_vector(63 downto 0);
  signal current_block, fifo_block_data, ddr_block_data : block_t := ZERO_BLOCK;
  -- Model settings are independent of the live DUT configuration. This permits
  -- checking configuration latching while Host controls change mid-session.
  signal model_sample_count : natural := 0;
  signal model_seed : unsigned(31 downto 0) := (others => '0');
  signal model_mode : natural := 0;
  signal corrupt_index : integer := -1;
  signal swap_blocks : boolean := false;
  signal return_hold, model_clear : std_logic := '0';
  signal model_requests, model_returns, model_pushes, model_pops : natural := 0;
  signal model_sent, model_inflight, model_fifo_count : natural := 0;
  signal model_tail_words : natural := 0;

  function as_natural(v : std_logic_vector) return natural is
  begin
    return to_integer(unsigned(v));
  end function;

  function memory_word(address, lane, n : natural;
                       seed : unsigned(31 downto 0);
                       damage : integer; swapped : boolean) return word_t is
    variable effective_address, index : natural;
    variable value : unsigned(31 downto 0);
  begin
    effective_address := address;
    if swapped then
      if address = 1 then effective_address := 2;
      elsif address = 2 then effective_address := 1;
      end if;
    end if;
    index := effective_address * K + lane;
    if index >= n then return x"00000000"; end if;
    value := seed + to_unsigned(index, 32);
    if index = damage then value := value xor to_unsigned(1, 32); end if;
    return std_logic_vector(value);
  end function;
begin
  case_done <= finished;
  dut : entity work.ddr_read_ctrl
    generic map (DDR_WIDTH_BITS => DDR_WIDTH_BITS)
    port map (
      clk => clk, reset => reset, run_enable => run_enable,
      read_command => read_command, rearm_command => rearm_command,
      abort_command => abort_command, new_session_safe => new_session_safe,
      dram_ready => dram_ready, sample_count => sample_count,
      ddr_word_count => ddr_word_count, ddr_capacity_words => ddr_capacity_words, pattern_seed => pattern_seed,
      pattern_check_enable => pattern_check_enable,
      ddr_request_ready_now => ddr_request_ready_now,
      prefetch_write_ready_now => prefetch_write_ready_now,
      ddr_retrieve_valid => ddr_retrieve_valid,
      prefetch_read_valid => prefetch_read_valid,
      stream_ready => stream_ready,
      stream_word0 => stream_word0, stream_word1 => stream_word1,
      stream_word2 => stream_word2, stream_word3 => stream_word3,
      request_valid => request_valid, retrieve_ready => retrieve_ready,
      prefetch_write_valid => prefetch_write_valid,
      prefetch_read_enable => prefetch_read_enable,
      current_load => current_load, current_clear => current_clear,
      stream_valid => stream_valid, stream_fire => stream_fire,
      stream_first => stream_first, stream_last => stream_last,
      request_address => request_address, stream_offset => stream_offset,
      read_generation => read_generation, requested_words => requested_words,
      returned_words => returned_words, enqueued_words => enqueued_words,
      popped_words => popped_words, sent_samples => sent_samples,
      checked_samples => checked_samples, mismatch_count => mismatch_count, first_error_index => first_error_index,
      first_error_expected => first_error_expected,
      first_error_actual => first_error_actual, read_state => read_state,
      fault_code => fault_code, read_busy => read_busy, read_done => read_done,
      read_fault => read_fault, command_rejected => command_rejected,
      total_cycles => total_cycles, replay_cycles => replay_cycles,
      transfer_cycles => transfer_cycles, no_data_cycles => no_data_cycles,
      sink_stall_cycles => sink_stall_cycles, pause_cycles => pause_cycles);

  clock_generator : process
  begin
    while not finished loop
      clk <= '0'; wait for 4 ns;
      clk <= '1'; wait for 4 ns;
    end loop;
    wait;
  end process;

  watchdog : process
  begin
    wait for 20 ms;
    assert finished report "DDR read TB exceeded 20 ms simulation budget" severity failure;
    wait;
  end process;

  -- The two delays below are precisely the LabVIEW Feedback(initial=False)
  -- on NI Request.Ready for Input and FIFO.Write.Ready for Input.
  ni_ready_feedback : process(clk)
  begin
    if rising_edge(clk) then
      if reset = '1' or model_clear = '1' then
        ddr_request_ready_now <= '0';
        prefetch_write_ready_now <= '0';
      else
        ddr_request_ready_now <= request_ready_raw;
        prefetch_write_ready_now <= fifo_write_ready_raw;
      end if;
    end if;
  end process;

  -- Equivalent to LV left Current_Array -> Array Subset(index, length=4).
  stream_data : process(current_block, stream_offset)
    variable offset : natural;
  begin
    offset := 0;
    if not is_x(stream_offset) then offset := as_natural(stream_offset); end if;
    if offset > K-4 then offset := 0; end if;
    stream_word0 <= current_block(offset);
    stream_word1 <= current_block(offset + 1);
    stream_word2 <= current_block(offset + 2);
    stream_word3 <= current_block(offset + 3);
  end process;

  -- Values are prepared on falling edges, then consumed at the next rising
  -- edge. No artificial extra output register is added to FIFO.Read: its
  -- Output Valid acknowledges this SAME cycle's Ready for Output.
  ni_model : process(clk)
    variable addresses, due : address_queue_t := (others => 0);
    variable fifo : fifo_t := (others => ZERO_BLOCK);
    variable qhead, qtail, qcount : natural := 0;
    variable fhead, ftail, fcount : natural := 0;
    variable cycles, requests, returns, pushes, pops, sent, tail_words : natural := 0;
    variable address, offset : natural;
    variable expected, actual : word_t;
  begin
    if falling_edge(clk) then
      request_ready_raw <= '0';
      fifo_write_ready_raw <= '0';
      ddr_retrieve_valid <= '0';
      prefetch_read_valid <= '0';
      if reset = '0' and model_clear = '0' then
        -- Spare locations allow the one-cycle-old ready credit to be used.
        if qcount < 62 and (model_mode = 0 or cycles mod 5 /= 0) then
          request_ready_raw <= '1';
        end if;
        if fcount < 254 and (model_mode = 0 or cycles mod 7 /= 0) then
          fifo_write_ready_raw <= '1';
        end if;
        if qcount > 0 and return_hold = '0' then
          if due(qhead) <= cycles and retrieve_ready = '1' and
             (model_mode = 0 or cycles mod 23 = 0) then
            ddr_retrieve_valid <= '1';
            for j in 0 to K-1 loop
              ddr_block_data(j) <= memory_word(addresses(qhead), j,
                model_sample_count, model_seed, corrupt_index, swap_blocks);
            end loop;
          end if;
        end if;
        if fcount > 0 and prefetch_read_enable = '1' then
          prefetch_read_valid <= '1';
          fifo_block_data <= fifo(fhead);
        end if;
      end if;
    elsif rising_edge(clk) then
      cycles := cycles + 1;
      if reset = '1' or model_clear = '1' then
        qhead := 0; qtail := 0; qcount := 0;
        fhead := 0; ftail := 0; fcount := 0;
        requests := 0; returns := 0; pushes := 0; pops := 0;
        sent := 0; tail_words := 0;
        current_block <= ZERO_BLOCK;
      else
        -- Check the old Current_Array before a simultaneous next-block load.
        if stream_fire = '1' then
          assert stream_valid = '1' and stream_ready = '1' and run_enable = '1'
            report "Stream transfer without valid/ready/run permission" severity failure;
          if sent=0 then
            assert stream_first='1' report "Missing first marker" severity failure;
          else
            assert stream_first='0' report "Repeated first marker" severity failure;
          end if;
          if sent+4=model_sample_count then
            assert stream_last='1' report "Missing last marker" severity failure;
          else
            assert stream_last='0' report "Early last marker" severity failure;
          end if;
          assert sent + 4 <= model_sample_count
            report "Padding or excess real samples reached stream sink" severity failure;
          assert as_natural(stream_offset) <= K-4 and as_natural(stream_offset) mod 4 = 0
            report "Invalid four-lane stream offset" severity failure;
          for j in 0 to 3 loop
            case j is
              when 0 => actual := stream_word0;
              when 1 => actual := stream_word1;
              when 2 => actual := stream_word2;
              when others => actual := stream_word3;
            end case;
            expected := memory_word((sent + j) / K, (sent + j) mod K,
              model_sample_count, model_seed, corrupt_index, swap_blocks);
            assert actual = expected
              report "Stream order/data error at sample " & integer'image(sent + j)
              severity failure;
          end loop;
          sent := sent + 4;
        end if;
        if current_clear = '1' then
          current_block <= ZERO_BLOCK;
        elsif current_load = '1' then
          assert prefetch_read_valid = '1'
            report "Current_Array load without successful FIFO read" severity failure;
          current_block <= fifo_block_data;
        end if;
        if prefetch_read_valid = '1' then
          assert prefetch_read_enable = '1' and fcount > 0
            report "NI FIFO read protocol violation" severity failure;
          fhead := (fhead + 1) mod 256;
          fcount := fcount - 1; pops := pops + 1;
        end if;
        if prefetch_write_valid = '1' then
          assert ddr_retrieve_valid = '1' and prefetch_write_ready_now = '1'
            report "NI FIFO write lacked valid returned block or delayed ready" severity failure;
          assert fcount < 256 report "Model target FIFO overflow" severity failure;
          fifo(ftail) := ddr_block_data;
          ftail := (ftail + 1) mod 256;
          fcount := fcount + 1; pushes := pushes + 1;
        end if;
        if ddr_retrieve_valid = '1' then
          assert retrieve_ready = '1' and qcount > 0
            report "NI Retrieve protocol violation" severity failure;
          address := addresses(qhead);
          if not swap_blocks then
            for j in 0 to K-1 loop
              if address * K + j >= model_sample_count then
                assert ddr_block_data(j) = x"00000000"
                  report "Final DDR block padding is not zero" severity failure;
                tail_words := tail_words + 1;
              end if;
            end loop;
          end if;
          qhead := (qhead + 1) mod 64;
          qcount := qcount - 1; returns := returns + 1;
        end if;
        if request_valid = '1' then
          assert ddr_request_ready_now = '1'
            report "Request lacks delayed NI ready credit" severity failure;
          assert qcount < 64 report "Request queue overflow" severity failure;
          assert as_natural(request_address) = requests
            report "DDR request address duplicate, missing or reordered" severity failure;
          assert requests < (model_sample_count + K-1) / K
            report "Controller requested beyond configured DDR length" severity failure;
          addresses(qtail) := as_natural(request_address);
          due(qtail) := cycles + 3;
          qtail := (qtail + 1) mod 64;
          qcount := qcount + 1; requests := requests + 1;
        end if;
      end if;
      model_requests <= requests; model_returns <= returns;
      model_pushes <= pushes; model_pops <= pops; model_sent <= sent;
      model_inflight <= qcount; model_fifo_count <= fcount;
      model_tail_words <= tail_words;
    end if;
  end process;

  -- Checks payload and sideband at the actual sink boundary, including the
  -- edge where ready returns high. Abort/reset/run pause are separate controls.
  hold_monitor : process(clk)
    variable held : boolean := false;
    variable payload : std_logic_vector(127 downto 0);
    variable first_bit, last_bit : std_logic;
    variable offset : word_t;
  begin
    if rising_edge(clk) then
      if reset='0' and run_enable='1' and abort_command='0' and dram_ready='1' then
        if held then
          assert stream_valid='1' and
                 (stream_word3 & stream_word2 & stream_word1 & stream_word0)=payload and
                 stream_first=first_bit and stream_last=last_bit and stream_offset=offset
            report "Backpressure changed valid/payload/metadata" severity failure;
        end if;
        held := stream_valid='1' and stream_ready='0';
        payload := stream_word3 & stream_word2 & stream_word1 & stream_word0;
        first_bit:=stream_first; last_bit:=stream_last; offset:=stream_offset;
      else held:=false;
      end if;
    end if;
  end process;

  stimulus : process
    procedure tick(count : positive := 1) is
    begin
      for k in 1 to count loop
        wait until rising_edge(clk);
        wait for 1 ns;
      end loop;
    end procedure;

    procedure prepare(n : positive; seed : natural; mode : natural := 0;
                      damaged : integer := -1; reordered : boolean := false;
                      checker : std_logic := '1') is
    begin
      assert read_busy = '0'
        report "TB attempted external cleanup while read controller active" severity failure;
      assert model_inflight = 0 and model_fifo_count = 0
        report "Completed session left stale request/FIFO data" severity failure;
      read_command <= '0'; rearm_command <= '0'; abort_command <= '0';
      run_enable <= '1'; new_session_safe <= '1'; dram_ready <= '1';
      stream_ready <= '1'; return_hold <= '0';
      ddr_capacity_words <= x"00020000";
      sample_count <= std_logic_vector(to_unsigned(n, 32));
      ddr_word_count <= std_logic_vector(to_unsigned((n + K-1) / K, 32));
      pattern_seed <= std_logic_vector(to_unsigned(seed, 32));
      pattern_check_enable <= checker;
      model_sample_count <= n; model_seed <= to_unsigned(seed, 32);
      model_mode <= mode; corrupt_index <= damaged; swap_blocks <= reordered;
      model_clear <= '1'; tick;
      model_clear <= '0'; tick;
    end procedure;

    procedure start_read is
      variable generation_before : natural;
    begin
      generation_before := as_natural(read_generation);
      read_command <= '1'; tick(3);
      assert as_natural(read_generation) = generation_before + 1
        report "Valid read command not acknowledged by generation" severity failure;
      assert read_state = x"01" and command_rejected = '0'
        report "Valid command did not enter PREFETCH" severity failure;
      -- Deliberately leave read_command HIGH; a level must not retrigger.
    end procedure;

    procedure await_running is
    begin
      for k in 1 to 15000 loop
        exit when read_state = x"03";
        assert read_fault = '0' report "Fault before first replay sample" severity failure;
        tick;
      end loop;
      assert read_state = x"03" report "Never reached RUN" severity failure;
    end procedure;

    procedure await_done(n : positive; errors : natural := 0;
                         checker : boolean := true; ideal : boolean := false) is
      variable m : natural;
    begin
      m := (n + K-1) / K;
      for k in 1 to 4*(n/4+m)+15000 loop
        exit when read_done = '1';
        assert read_fault = '0' report "Unexpected controller fault during replay" severity failure;
        tick;
      end loop;
      assert read_done = '1' and read_state = x"05"
        report "Replay failed to complete" severity failure;
      assert as_natural(sent_samples) = n and model_sent = n
        report "Real sample count differs from requested N" severity failure;
      assert as_natural(requested_words) = m and as_natural(returned_words) = m and
             as_natural(enqueued_words) = m and as_natural(popped_words) = m
        report "Successful replay request/return/FIFO word counts disagree" severity failure;
      assert model_requests = m and model_returns = m and
             model_pushes = m and model_pops = m and
             model_inflight = 0 and model_fifo_count = 0
        report "External NI model counts disagree or queues not empty" severity failure;
      assert as_natural(transfer_cycles) = n / 4
        report "Transfer-cycle count is not exactly N/4" severity failure;
      assert unsigned(replay_cycles) = unsigned(transfer_cycles) + unsigned(no_data_cycles) +
             unsigned(sink_stall_cycles) + unsigned(pause_cycles)
        report "Replay cycle categories are not exhaustive and exclusive" severity failure;
      assert unsigned(total_cycles) >= unsigned(replay_cycles)
        report "Total cycles smaller than measured replay interval" severity failure;
      assert as_natural(mismatch_count) = errors
        report "Pattern mismatch count incorrect" severity failure;
      if checker then
        assert as_natural(checked_samples) = n
          report "Enabled pattern checker did not inspect every real sample" severity failure;
      else
        assert as_natural(checked_samples) = 0
          report "Disabled pattern checker counted inspected samples" severity failure;
      end if;
      if not swap_blocks then
        assert model_tail_words = m * K - n
          report "Final DDR block tail-padding coverage incorrect" severity failure;
      end if;
      if ideal then
        assert as_natural(replay_cycles) = n / 4 and
               as_natural(no_data_cycles) = 0 and as_natural(sink_stall_cycles) = 0 and
               as_natural(pause_cycles) = 0
          report "Ideal replay contains bubbles; cannot claim four samples per cycle" severity failure;
      end if;
    end procedure;

    procedure safe_rearm is
      variable generation_before : natural;
    begin
      generation_before := as_natural(read_generation);
      read_command <= '0'; rearm_command <= '0'; abort_command <= '0';
      run_enable <= '1'; new_session_safe <= '1'; tick;
      rearm_command <= '1'; tick;
      assert read_state = x"00" and read_fault = '0' and fault_code = x"00"
        report "Safe rearm failed to return WAIT" severity failure;
      assert as_natural(read_generation) = generation_before
        report "Rearm must not count as a new read generation" severity failure;
      rearm_command <= '0'; tick;
    end procedure;

    variable g, count_before, cycles_before : natural;
    variable first_actual : unsigned(31 downto 0);
  begin
    report "DDR read TB: reset/held-command and normal full-length replay" severity note;
    reset <= '1'; read_command <= '1'; run_enable <= '1';
    new_session_safe <= '1'; dram_ready <= '1'; stream_ready <= '1';
    tick(3); reset <= '0'; tick(4);
    assert read_state = x"00" and as_natural(read_generation) = 0
      report "Command held during reset spuriously started a session" severity failure;
    if SMOKE_ONLY then
      prepare(K+4,1024); start_read; await_done(K+4,0,true,true);
      prepare(4,2048); start_read; await_done(4,0,true,true);
      report "READ_ALT_WIDTH_CASE_PASS" severity note;
      finished<=true; wait;
    end if;
    prepare(60324, 16#12340000#);
    start_read;
    await_done(60324, 0, true, true);
    g := as_natural(read_generation); tick(8);
    assert read_done = '1' and as_natural(read_generation) = g
      report "Held read command retriggered from DONE" severity failure;

    report "DDR read TB: direct second read without reset and partial final block" severity note;
    prepare(604, 16#1000#);
    start_read;
    -- These live Host edits must not affect the latched active configuration.
    sample_count <= std_logic_vector(to_unsigned(4, 32));
    ddr_word_count <= std_logic_vector(to_unsigned(1, 32));
    pattern_seed <= x"DEADBEEF"; pattern_check_enable <= '0'; ddr_capacity_words <= (others=>'0');
    await_done(604, 0, true, true);
    assert model_tail_words = 36 report "604 sample test did not preserve 36 zero pad words" severity failure;

    report "DDR read TB: unsafe, paused and conflicting start commands" severity note;
    prepare(160, 64);
    g := as_natural(read_generation);
    new_session_safe <= '0'; read_command <= '1'; tick;
    assert command_rejected = '1' and as_natural(read_generation) = g and read_done = '1'
      report "Unsafe start should be rejected without abandoning DONE" severity failure;
    read_command <= '0'; new_session_safe <= '1'; run_enable <= '0'; tick;
    read_command <= '1'; tick;
    assert command_rejected = '1' and as_natural(read_generation) = g
      report "Paused start command should be rejected" severity failure;
    read_command <= '0'; run_enable <= '1'; tick;
    read_command <= '1'; rearm_command <= '1'; tick;
    assert command_rejected = '1' and as_natural(read_generation) = g
      report "Simultaneous read/rearm edges should be rejected" severity failure;
    read_command <= '0'; rearm_command <= '0'; tick;
    start_read;
    await_done(160, 0, true, true);

    report "DDR read TB: busy-command rejection and sink/pause cycle accounting" severity note;
    prepare(600, 256); start_read; await_running;
    tick(5);
    g := as_natural(read_generation);
    read_command <= '0'; tick; read_command <= '1'; tick;
    assert command_rejected = '1' and as_natural(read_generation) = g
      report "Busy read command must not restart current waveform" severity failure;
    stream_ready <= '0'; count_before := as_natural(sent_samples);
    cycles_before := as_natural(sink_stall_cycles); tick(7);
    assert as_natural(sent_samples) = count_before and
           as_natural(sink_stall_cycles) = cycles_before + 7
      report "Sink backpressure changed data count or stall classification" severity failure;
    run_enable <= '0'; cycles_before := as_natural(pause_cycles); tick(5);
    assert as_natural(sent_samples) = count_before and
           as_natural(pause_cycles) = cycles_before + 5
      report "Pause did not retain position or count exactly five cycles" severity failure;
    stream_ready <= '1'; run_enable <= '1';
    await_done(600);
    assert as_natural(sink_stall_cycles) = 7 and as_natural(pause_cycles) = 5
      report "Pause/sink cycles overlapped or were lost" severity failure;

    report "DDR read TB: delayed/multiple outstanding requests and FIFO stalls" severity note;
    prepare(12000, 512, 1); start_read;
    await_done(12000);
    assert as_natural(no_data_cycles) > 0
      report "Slow-return scenario did not exercise replay underflow/recovery" severity failure;
    assert as_natural(replay_cycles) > 3000
      report "Slow-return replay unexpectedly reported ideal throughput" severity failure;

    report "DDR read TB: checker disabled; external scoreboard still checks all lanes" severity note;
    prepare(164, 1024, 0, -1, false, '0'); start_read;
    await_done(164, 0, false, true);

    report "DDR read TB: unsigned 32-bit pattern wraps through FFFFFFFF" severity note;
    prepare(80, 0);
    pattern_seed <= x"FFFFFFF0"; model_seed <= x"FFFFFFF0";
    tick; start_read;
    await_done(80, 0, true, true);
    report "DDR read TB: injected one-word corruption and first-error metadata" severity note;
    prepare(164, 4096, 0, 83); start_read;
    await_done(164, 1, true, true);
    first_actual := to_unsigned(4096 + 83, 32) xor to_unsigned(1, 32);
    assert as_natural(first_error_index) = 83 and
           as_natural(first_error_expected) = 4096 + 83 and
           unsigned(first_error_actual) = first_actual
      report "Single corruption first-error metadata is incorrect" severity failure;

    report "DDR read TB: injected block reordering is detected" severity note;
    prepare(160, 8192, 0, -1, true); start_read;
    await_done(160, 80, true, true);
    assert as_natural(first_error_index) = 40 and
           as_natural(first_error_expected) = 8192 + 40 and
           as_natural(first_error_actual) = 8192 + 80
      report "Block-reorder first-error metadata is incorrect" severity failure;

    report "DDR read TB: abort with live requests and FIFO data; drain then restart" severity note;
    prepare(12000, 16384); start_read; await_running;
    return_hold <= '1'; tick(10);
    assert model_inflight > 0 and model_fifo_count > 0
      report "Abort test did not have both outstanding requests and buffered blocks" severity failure;
    abort_command <= '1'; tick;
    assert read_state = x"04" and fault_code = x"03"
      report "Abort did not enter DRAIN" severity failure;
    count_before := as_natural(sent_samples);
    g := as_natural(read_generation);
    read_command <= '0'; rearm_command <= '1'; run_enable <= '0'; tick;
    assert command_rejected = '1' and read_state = x"04" and
           as_natural(read_generation) = g
      report "Rearm during DRAIN was not rejected" severity failure;
    abort_command <= '0'; rearm_command <= '0'; return_hold <= '0';
    for k in 1 to 1000 loop
      exit when read_fault = '1'; tick;
    end loop;
    assert read_fault = '1' and fault_code = x"03" and
           model_inflight = 0 and model_fifo_count = 0 and
           requested_words = returned_words and enqueued_words = popped_words
      report "Abort failed to drain all old physical data while paused" severity failure;
    assert as_natural(sent_samples) = count_before
      report "Aborted samples escaped during DRAIN" severity failure;
    run_enable <= '1'; new_session_safe <= '0'; rearm_command <= '1'; tick;
    assert read_fault = '1' and command_rejected = '1'
      report "Fault rearm must require external new-session safety" severity failure;
    safe_rearm;
    prepare(600, 32768); start_read; await_done(600, 0, true, true);

    report "DDR read TB: invalid parameters do not issue DDR requests" severity note;
    prepare(604, 65536);
    ddr_word_count <= std_logic_vector(to_unsigned(15, 32));
    g := as_natural(read_generation); read_command <= '1'; tick(3);
    assert read_fault = '1' and fault_code = x"01" and
           as_natural(read_generation) = g and model_requests = 0
      report "Undersized word-count configuration was accepted" severity failure;
    safe_rearm;
    prepare(604, 65536); sample_count <= std_logic_vector(to_unsigned(603, 32));
    read_command <= '1'; tick(3);
    assert read_fault = '1' and fault_code = x"01" and model_requests = 0
      report "Non-four-aligned sample count was accepted" severity failure;
    safe_rearm;

    report "DDR read TB: DRAM readiness loss freezes fault until external cleanup" severity note;
    prepare(12000, 131072); start_read; await_running;
    return_hold <= '1'; tick(8);
    assert model_inflight > 0 and model_fifo_count > 0
      report "DRAM-loss test did not contain outstanding/buffered data" severity failure;
    dram_ready <= '0'; tick;
    assert read_fault = '1' and fault_code = x"02"
      report "DRAM loss did not latch fault code 2" severity failure;
    count_before := model_inflight;
    new_session_safe <= '0'; dram_ready <= '1'; tick(4);
    assert read_fault = '1' and model_inflight = count_before
      report "Readiness return incorrectly pretended old physical requests were cleared" severity failure;
    -- This models verified external NI queue cleanup. It is deliberately NOT
    -- achieved by asserting only the controller's reset/rearm signals.
    model_clear <= '1'; tick; model_clear <= '0'; return_hold <= '0'; tick;
    safe_rearm;
    prepare(44, 262144); start_read; await_done(44, 0, true, true);

    report "DDR read TB: capacity zero/overflow and no traffic before validation" severity note;
    prepare(44,4096); ddr_capacity_words<=x"00000001";
    read_command<='1'; tick(3);
    assert read_fault='1' and fault_code=x"01" and model_requests=0
      report "Capacity overflow accepted" severity failure;
    safe_rearm;
    prepare(4,4096); ddr_capacity_words<=(others=>'0');
    read_command<='1'; tick(3);
    assert read_fault='1' and model_requests=0 report "Zero capacity accepted" severity failure;
    safe_rearm;

    -- Exactly one group: first+last must both remain valid throughout a stall.
    prepare(4,8192); stream_ready<='0'; start_read; await_running; tick(7);
    assert stream_valid='1' and stream_first='1' and stream_last='1' and
           read_done='0' and unsigned(sent_samples)=0
      report "Single group/last stall prematurely completed" severity failure;
    stream_ready<='1'; await_done(4);

    -- A multi-group tail held at the consumer, not just an interior group.
    prepare(44,16384); start_read; await_running;
    for j in 1 to 1000 loop
      exit when stream_valid='1' and stream_last='1'; tick;
    end loop;
    assert stream_last='1' report "No final group offered" severity failure;
    stream_ready<='0'; tick(9);
    assert read_done='0' and unsigned(sent_samples)=40
      report "Tail backpressure changed count" severity failure;
    stream_ready<='1'; await_done(44);

    -- Real sequential requests cross 65535; this is more than start acceptance.
    prepare(65537*K,32768); start_read; await_done(65537*K,0,true,true);
    assert unsigned(requested_words)=65537
      report "Address/count truncated at 65536" severity failure;
    report "READ_OVER_65536_WORDS_PASS" severity note;
    report "READ_DEFAULT_CASE_PASS" severity note;
    finished <= true;
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity tb_ddr_read_ctrl is end entity;
architecture test of tb_ddr_read_ctrl is
  signal main_done, alternate_done : boolean := false;
begin
  normal : entity work.tb_ddr_read_ctrl_case
    generic map (DDR_WIDTH_BITS=>1280, SMOKE_ONLY=>false)
    port map (case_done=>main_done);
  alternate : entity work.tb_ddr_read_ctrl_case
    generic map (DDR_WIDTH_BITS=>640, SMOKE_ONLY=>true)
    port map (case_done=>alternate_done);
  finish : process
  begin
    wait until main_done and alternate_done;
    report "DDR_READ_CTRL_TEST_PASS" severity note;
    wait;
  end process;
end architecture;
