library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ddr_upload_ctrl is end;
architecture test of tb_ddr_upload_ctrl is
  signal clk : std_logic := '0';
  signal finished : boolean := false;
  signal reset : std_logic := '1';
  signal run_enable, new_session_safe, dram_ready : std_logic := '1';
  signal load_command, rearm_command, abort_command : std_logic := '0';
  signal sample_count, ddr_word_count : std_logic_vector(31 downto 0) := (others=>'0');
  signal fifo_output_valid, ddr_write_ready_now : std_logic := '0';
  signal fifo_read_enable, pack_clear, ddr_write_valid : std_logic;
  signal pack_offset, ddr_write_address, loaded_samples, load_generation : std_logic_vector(31 downto 0);
  signal load_state, fault_code : std_logic_vector(7 downto 0);
  signal load_busy, load_done, load_fault, command_rejected : std_logic;
  signal source_on, sink_on : std_logic := '1';
  signal fifo_available, raw_ready : std_logic := '0';
  signal stall_pattern : boolean := true;
  signal cycle : natural := 0;
  signal data_base : natural := 1000;
  signal expected_n : natural := 0;
  type words_t is array(0 to 39) of unsigned(31 downto 0);
  signal pack : words_t := (others=>(others=>'0'));
  signal writes_checked : natural := 0;
  signal load_cycles, data_window_cycles, receive_cycles, write_cycles,
         fifo_empty_cycles, ddr_stall_cycles, pause_cycles : std_logic_vector(63 downto 0);
begin
  dut: entity work.ddr_upload_ctrl
    port map(clk,reset,run_enable,load_command,rearm_command,abort_command,
      new_session_safe,dram_ready,sample_count,ddr_word_count,fifo_output_valid,
      ddr_write_ready_now,fifo_read_enable,pack_offset,pack_clear,ddr_write_valid,
      ddr_write_address,loaded_samples,load_state,load_busy,load_done,load_fault,
      fault_code,load_generation,command_rejected,load_cycles,data_window_cycles,
      receive_cycles,write_cycles,fifo_empty_cycles,ddr_stall_cycles,pause_cycles);
  clocking: process
  begin
    while not finished loop
      clk<='0'; wait for 5 ns; clk<='1'; wait for 5 ns;
    end loop;
    wait;
  end process;
  -- NI-style model: Read outputs only when current ready is true;
  -- DDR's raw write ready grants permission for the next iteration.
  fifo_available <= source_on when not stall_pattern or cycle mod 7 /= 2 else '0';
  raw_ready <= sink_on when not stall_pattern or (cycle mod 11 < 7) else '0';
  fifo_output_valid <= fifo_read_enable and fifo_available;
  model: process(clk)
    variable p : words_t;
    variable addr, offset, idx, expected : natural;
  begin
    if rising_edge(clk) then
      cycle <= cycle+1;
      ddr_write_ready_now <= raw_ready;
      assert not (fifo_output_valid='1' and pack_clear='1')
        report "FIFO read and Pack_Clear overlap" severity failure;
      assert not (fifo_output_valid='1' and ddr_write_valid='1')
        report "Single buffer read/write overlap" severity failure;
      if ddr_write_valid='1' then
        assert ddr_write_ready_now='1' report "Write without permission" severity failure;
        addr:=to_integer(unsigned(ddr_write_address));
        assert addr < (expected_n+39)/40 report "Excess DDR write" severity failure;
        for j in 0 to 39 loop
          idx:=addr*40+j;
          if idx<expected_n then expected:=data_base+idx; else expected:=0; end if;
          assert pack(j)=to_unsigned(expected,32)
            report "DDR payload mismatch at word " & integer'image(addr) &
                   " lane " & integer'image(j) severity failure;
        end loop;
        writes_checked<=writes_checked+1;
      end if;
      p:=pack;
      if pack_clear='1' then
        p:=(others=>(others=>'0'));
      elsif fifo_output_valid='1' then
        offset:=to_integer(unsigned(pack_offset));
        assert offset<=36 and offset mod 4=0 report "Invalid pack offset" severity failure;
        for j in 0 to 3 loop
          p(offset+j):=to_unsigned(data_base+to_integer(unsigned(loaded_samples))+j,32);
        end loop;
      end if;
      pack<=p;
    end if;
  end process;

  stimulus: process
    variable generation_before, held_count, checked_before : natural;
    procedure tick(constant count : positive := 1) is
    begin
      for k in 1 to count loop wait until rising_edge(clk); wait for 1 ns; end loop;
    end procedure;
    procedure low_commands is
    begin load_command<='0'; rearm_command<='0'; tick; end procedure;
    procedure rearm is
    begin
      low_commands; rearm_command<='1'; tick;
      assert load_state=x"00" and load_fault='0' and unsigned(loaded_samples)=0 and
             unsigned(ddr_write_address)=0 report "Rearm did not clear upload state" severity failure;
      rearm_command<='0'; tick;
    end procedure;
    procedure begin_upload(constant n,m,base : natural) is
    begin
      low_commands;
      expected_n<=n; data_base<=base;
      sample_count<=std_logic_vector(to_unsigned(n,32));
      ddr_word_count<=std_logic_vector(to_unsigned(m,32));
      tick;
      generation_before:=to_integer(unsigned(load_generation));
      load_command<='1'; tick;
      assert load_busy='1' and unsigned(load_generation)=generation_before+1
        report "Valid load command not accepted" severity failure;
      -- Intentionally leave load high to test no automatic repeat at DONE.
    end procedure;
    procedure await_done(constant n,m : natural) is
      variable reached : boolean := false;
    begin
      for k in 1 to 50000 loop
        tick;
        assert load_fault='0' report "Unexpected fault during upload" severity failure;
        if load_done='1' then reached:=true; exit; end if;
      end loop;
      assert reached report "Upload watchdog" severity failure;
      assert unsigned(loaded_samples)=n and unsigned(ddr_write_address)=m
        report "Completed counts mismatch" severity failure;
      assert unsigned(receive_cycles)=n/4 and unsigned(write_cycles)=m
        report "Write performance transfer counts wrong" severity failure;
      assert unsigned(load_cycles)=unsigned(receive_cycles)+unsigned(write_cycles)+
             unsigned(fifo_empty_cycles)+unsigned(ddr_stall_cycles)+unsigned(pause_cycles)
        report "Write cycle accounting not conserved" severity failure;
      assert unsigned(data_window_cycles)<=unsigned(load_cycles)
        report "Data window exceeds whole upload" severity failure;
      assert pack=(pack'range=>(others=>'0')) report "Pack not cleared after final write" severity failure;
    end procedure;
    procedure invalid_params(constant n,m : natural) is
    begin
      low_commands;
      sample_count<=std_logic_vector(to_unsigned(n,32));
      ddr_word_count<=std_logic_vector(to_unsigned(m,32)); tick;
      load_command<='1'; tick;
      assert load_fault='1' and fault_code=x"01" and command_rejected='1'
        report "Bad parameters not rejected" severity failure;
      rearm;
    end procedure;
  begin
    tick(3); reset<='0'; tick;
    invalid_params(0,1); invalid_params(6,1); invalid_params(44,1);
    invalid_params(44,3); invalid_params(81924,2049);
    report "CHECK parameter guards PASS" severity note;

    checked_before:=writes_checked;
    begin_upload(44,2,1000); await_done(44,2);
    assert writes_checked=checked_before+2 report "Write count 44/2" severity failure;
    held_count:=to_integer(unsigned(load_generation)); tick(20);
    assert load_done='1' and unsigned(load_generation)=held_count
      report "Held load command restarted completed job" severity failure;
    report "CHECK stall handling, tail zeros, held command PASS" severity note;

    begin_upload(40,1,2000); await_done(40,1);
    assert unsigned(load_generation)=held_count+1 report "Reload from DONE failed" severity failure;
    report "CHECK second upload without reset PASS" severity note;

    begin_upload(84,3,3000);
    for k in 1 to 30 loop tick; exit when unsigned(loaded_samples)>=8; end loop;
    run_enable<='0'; tick; held_count:=to_integer(unsigned(loaded_samples));
    -- Host changes cannot corrupt the latched length of the active upload.
    sample_count<=x"00000006"; ddr_word_count<=x"00000000";
    tick(7);
    assert unsigned(loaded_samples)=held_count and fifo_read_enable='0' and ddr_write_valid='0'
      report "Paused transfer progressed" severity failure;
    load_command<='0'; tick; load_command<='1'; tick;
    assert command_rejected='1' report "Paused command silently queued" severity failure;
    run_enable<='1'; await_done(84,3);
    report "CHECK pause/resume and locked parameters PASS" severity note;

    -- Reject a fresh load and rearm while busy, without disturbing payload.
    begin_upload(80,2,4000); source_on<='0'; tick(2);
    low_commands; load_command<='1'; tick;
    assert load_busy='1' and command_rejected='1' report "Busy command not rejected" severity failure;
    low_commands; rearm_command<='1'; tick;
    assert load_busy='1' report "Rearm destroyed active upload" severity failure;
    rearm_command<='0'; source_on<='1'; await_done(80,2);
    report "CHECK busy command rejection PASS" severity note;

    -- Prevent writing a completed pending buffer, then abort.
    sink_on<='0'; tick(3); begin_upload(40,1,5000);
    for k in 1 to 100 loop tick; exit when unsigned(loaded_samples)=40; end loop;
    assert unsigned(loaded_samples)=40 and unsigned(ddr_write_address)=0
      report "Could not establish pending block" severity failure;
    abort_command<='1'; tick;
    assert load_fault='1' and fault_code=x"03" and ddr_write_valid='0' and fifo_read_enable='0'
      report "Abort handling failed" severity failure;
    abort_command<='0'; low_commands; load_command<='1'; tick;
    assert load_fault='1' report "FAULT accepted load without rearm" severity failure;
    new_session_safe<='0'; low_commands; rearm_command<='1'; tick;
    assert load_fault='1' and command_rejected='1' report "Unsafe rearm accepted" severity failure;
    new_session_safe<='1'; rearm; sink_on<='1'; tick(3);
    begin_upload(4,1,6000); await_done(4,1);
    report "CHECK abort, cleanup gate, fault recovery PASS" severity note;

    begin_upload(80,2,7000); run_enable<='0'; dram_ready<='0'; tick;
    assert load_fault='1' and fault_code=x"02" report "DRAM loss during pause not faulted" severity failure;
    dram_ready<='1'; run_enable<='1'; tick(3);
    assert load_fault='1' report "Fault did not latch" severity failure;
    rearm;
    report "CHECK DRAM readiness loss PASS" severity note;

    low_commands; load_command<='1'; rearm_command<='1'; tick;
    assert load_state=x"00" and command_rejected='1' report "Conflicting commands accepted" severity failure;
    reset<='1'; tick(2); reset<='0'; tick(3);
    assert load_state=x"00" and unsigned(load_generation)=0
      report "Held command across reset generated a new request" severity failure;
    low_commands;
    new_session_safe<='0'; load_command<='1'; tick;
    assert load_state=x"00" and command_rejected='1' report "Unsafe start accepted" severity failure;
    new_session_safe<='1'; tick(3);
    assert load_state=x"00" report "Rejected command was implicitly queued" severity failure;
    report "CHECK command conflicts and reset edge semantics PASS" severity note;

    -- Independent endpoint measurement: 5 initial empty cycles, then 11
    -- receive/write cycles for one complete 40-point block.
    stall_pattern<=false; source_on<='0'; sink_on<='1'; tick(3);
    begin_upload(40,1,8000); tick(5); source_on<='1'; await_done(40,1);
    assert unsigned(data_window_cycles)=11 and unsigned(load_cycles)=16 and
           unsigned(fifo_empty_cycles)=5
      report "Write data-window endpoint measurement failed" severity failure;
    report "CHECK initial wait versus data window PASS" severity note;
    stall_pattern<=true;
    begin_upload(81920,2048,100000); await_done(81920,2048);
    report "CHECK capacity boundary PASS" severity note;
    report "DDR_UPLOAD_CTRL_TEST_PASS" severity note;
    finished<=true;
    wait;
  end process;
end architecture;