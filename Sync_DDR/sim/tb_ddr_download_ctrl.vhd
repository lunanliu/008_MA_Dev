-- VHDL-93, self-checking NI interface model. No vendor simulation libraries.
-- This tests controller/protocol behavior, not the physical DDR PHY or NI VI.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ddr_download_ctrl_case is
  generic (DDR_WIDTH_BITS : positive := 1280; SMOKE_ONLY : boolean := false);
  port (case_done : out boolean);
end entity;

architecture test of tb_ddr_download_ctrl_case is
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

  signal dma_sink_enabled, host_drain : std_logic := '1';
  signal dma_ready_raw : std_logic := '0';
  signal host_every_cycle : boolean := false;
  signal dma_buffered, host_received : natural := 0;

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
  checked_samples <= (others=>'0');
  mismatch_count <= (others=>'0');
  dut : entity work.ddr_download_ctrl
    generic map (DDR_WIDTH_BITS => DDR_WIDTH_BITS)
    port map (
      clk                          => clk,
      reset                        => reset,
      run_enable                   => run_enable,
      download_command             => read_command,
      rearm_command                => rearm_command,
      abort_command                => abort_command,
      new_session_safe             => new_session_safe,
      dram_ready                   => dram_ready,
      sample_count                 => sample_count,
      ddr_word_count               => ddr_word_count,
      ddr_capacity_words           => ddr_capacity_words,
      ddr_request_ready_now        => ddr_request_ready_now,
      prefetch_write_ready_now     => prefetch_write_ready_now,
      ddr_retrieve_valid           => ddr_retrieve_valid,
      prefetch_read_valid          => prefetch_read_valid,
      dma_ready_now                => stream_ready,
      request_valid                => request_valid,
      request_address              => request_address,
      retrieve_ready               => retrieve_ready,
      prefetch_write_valid         => prefetch_write_valid,
      prefetch_read_enable         => prefetch_read_enable,
      current_load                 => current_load,
      current_clear                => current_clear,
      unpack_offset                => stream_offset,
      dma_valid                    => stream_valid,
      dma_fire                     => stream_fire,
      dma_first                    => stream_first,
      dma_last                     => stream_last,
      download_state               => read_state,
      download_busy                => read_busy,
      download_done                => read_done,
      download_fault               => read_fault,
      fault_code                   => fault_code,
      download_generation          => read_generation,
      command_rejected             => command_rejected,
      requested_words              => requested_words,
      returned_words               => returned_words,
      enqueued_words               => enqueued_words,
      popped_words                 => popped_words,
      downloaded_samples           => sent_samples,
      total_cycles                 => total_cycles,
      download_cycles              => replay_cycles,
      transfer_cycles              => transfer_cycles,
      no_data_cycles               => no_data_cycles,
      sink_stall_cycles            => sink_stall_cycles,
      pause_cycles                 => pause_cycles);

  clock_generator : process
  begin
    while not finished loop
      clk <= '0'; wait for 3.333333 ns;
      clk <= '1'; wait for 3.333333 ns;
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

  dma_host_model : process(clk)
    type group_t is array(0 to 3) of word_t;
    type dma_t is array(0 to 7) of group_t;
    variable fifo : dma_t := (others=>(others=>(others=>'0')));
    variable head, tail, count, received, cycles : natural := 0;
  begin
    if rising_edge(clk) then
      cycles:=cycles+1;
      if reset='1' or model_clear='1' then
        head:=0; tail:=0; count:=0; received:=0;
        stream_ready<='0'; dma_ready_raw<='0';
      else
        stream_ready<=dma_ready_raw;
        if host_drain='1' and count>0 and (host_every_cycle or cycles mod 3=0) then
          for j in 0 to 3 loop
            assert fifo(head)(j)=memory_word((received+j)/K,(received+j) mod K,
              model_sample_count,model_seed,corrupt_index,swap_blocks)
              report "Host FIFO received duplicate/missing/reordered data" severity failure;
          end loop;
          received:=received+4; head:=(head+1) mod 8; count:=count-1;
        end if;
        if stream_fire='1' then
          assert count<8 report "Target-to-Host DMA overflow" severity failure;
          fifo(tail):=(stream_word0,stream_word1,stream_word2,stream_word3);
          tail:=(tail+1) mod 8; count:=count+1;
        end if;
        -- At most two further groups can use the registered ready credits.
        if count<=6 and dma_sink_enabled='1' then dma_ready_raw<='1';
        else dma_ready_raw<='0'; end if;
      end if;
      dma_buffered<=count; host_received<=received;
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
      dma_sink_enabled <= '1'; return_hold <= '0';
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
                         checker : boolean := false; ideal : boolean := false) is
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
    reset<='1'; run_enable<='1'; new_session_safe<='1'; dram_ready<='1'; dma_sink_enabled<='1';
    tick(3); reset<='0'; tick(4);
    host_every_cycle<=true;
    prepare(4000,1024); start_read; await_done(4000,0,false,true);
    for j in 1 to 100 loop exit when host_received=4000; tick; end loop;
    assert host_received=4000 and dma_buffered=0 report "Ideal DMA Host count" severity failure;
    report "DOWNLOAD_4000_SAMPLES_1000_CYCLES_PASS" severity note;

    host_every_cycle<=false; host_drain<='0';
    prepare(604,8192); start_read; await_running;
    tick(24);
    assert stream_valid='1' and stream_ready='0' and dma_buffered>0
      report "Finite DMA did not backpressure when Host stopped" severity failure;
    count_before:=as_natural(sent_samples); tick(9);
    assert as_natural(sent_samples)=count_before and read_done='0'
      report "DMA full changed playback position" severity failure;
    sample_count<=x"00000004"; ddr_word_count<=x"00000001"; ddr_capacity_words<=(others=>'0');
    host_drain<='1'; await_done(604);
    assert host_received<604 and dma_buffered>0
      report "Test did not distinguish DMA submission from Host receipt" severity failure;
    for j in 1 to 100 loop exit when host_received=604; tick; end loop;
    assert host_received=604 and dma_buffered=0 report "Host missed/repeated/reordered result samples" severity failure;
    report "DOWNLOAD_DMA_STALL_HOST_DRAIN_AND_TAIL_PASS" severity note;

    prepare(4,16384); dma_sink_enabled<='0'; start_read; await_running; tick(8);
    assert stream_valid='1' and stream_first='1' and stream_last='1' and read_done='0'
      report "One-group result metadata failed under stall" severity failure;
    dma_sink_enabled<='1'; await_done(4);
    for j in 1 to 100 loop exit when host_received=4; tick; end loop;
    assert host_received=4 report "One-group Host receive failed" severity failure;

    prepare(44,32768); ddr_capacity_words<=x"00000001";
    read_command<='1'; tick(3);
    assert read_fault='1' and fault_code=x"01" and model_requests=0
      report "Download invalid capacity issued a request" severity failure;
    safe_rearm;

    prepare(12000,65536); host_drain<='0'; start_read; await_running;
    return_hold<='1'; tick(10);
    assert model_inflight>0 and model_fifo_count>0 report "Abort lacked live DDR/FIFO traffic" severity failure;
    abort_command<='1'; tick;
    count_before:=as_natural(sent_samples);
    assert read_state=x"04" and fault_code=x"03" report "Download abort did not drain" severity failure;
    abort_command<='0'; return_hold<='0'; run_enable<='0';
    for j in 1 to 1000 loop exit when read_fault='1'; tick; end loop;
    assert read_fault='1' and model_inflight=0 and model_fifo_count=0 and
           as_natural(sent_samples)=count_before report "Download abort drain escaped data" severity failure;
    -- External cleanup owns already submitted DMA data; explicitly discard
    -- the partial session before permitting another result descriptor.
    model_clear<='1'; tick; model_clear<='0'; host_drain<='1'; safe_rearm;
    prepare(44,131072); start_read; await_done(44);
    for j in 1 to 100 loop exit when host_received=44; tick; end loop;
    assert host_received=44 report "Download recovery Host count" severity failure;
    report "DDR_DOWNLOAD_CTRL_TEST_PASS" severity note;
    finished<=true; wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity tb_ddr_download_ctrl is end entity;
architecture test of tb_ddr_download_ctrl is
  signal done : boolean := false;
begin
  only_case : entity work.tb_ddr_download_ctrl_case port map (case_done=>done);
end architecture;
