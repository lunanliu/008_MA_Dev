library ieee;
use ieee.std_logic_1164.all;
-- Pure wiring wrapper around the complete synthesized core supplied by DCP. No algorithm or clock generator.
entity sync_frontend_clip is
    port (
        clk125 : in std_logic;
        reset_n : in std_logic;
        session_start : in std_logic;
        session_abort : in std_logic;
        stream_gap : in std_logic;
        input_valid : in std_logic;
        input_ready : out std_logic;
        input_data0 : in std_logic_vector(31 downto 0);
        input_data1 : in std_logic_vector(31 downto 0);
        input_data2 : in std_logic_vector(31 downto 0);
        input_data3 : in std_logic_vector(31 downto 0);
        result_valid : out std_logic;
        result_ready : in std_logic;
        result_epoch : out std_logic_vector(31 downto 0);
        rx_frame_id : out std_logic_vector(31 downto 0);
        candidate_id : out std_logic_vector(31 downto 0);
        coarse_absolute : out std_logic_vector(63 downto 0);
        fine_absolute : out std_logic_vector(63 downto 0);
        cfo_hz : out std_logic_vector(31 downto 0);
        quality_q1_15 : out std_logic_vector(15 downto 0);
        result_status : out std_logic_vector(15 downto 0);
        accepted_samples : out std_logic_vector(63 downto 0);
        epoch : out std_logic_vector(31 downto 0);
        candidate_count : out std_logic_vector(31 downto 0);
        rejected_count : out std_logic_vector(31 downto 0);
        capture_drop_count : out std_logic_vector(31 downto 0);
        duplicate_count : out std_logic_vector(31 downto 0);
        confirmed_count : out std_logic_vector(31 downto 0);
        snapshot_occupancy : out std_logic_vector(7 downto 0);
        snapshot_peak : out std_logic_vector(7 downto 0);
        max_history_age : out std_logic_vector(15 downto 0);
        error_sticky : out std_logic_vector(15 downto 0)
    );
end entity;
architecture rtl of sync_frontend_clip is
    component sync_frontend_top is
        port (
            clk : in std_logic;
            reset_n : in std_logic;
            session_start : in std_logic;
            session_abort : in std_logic;
            stream_gap : in std_logic;
            s_valid : in std_logic;
            s_ready : out std_logic;
            s_data : in std_logic_vector(127 downto 0);
            m_valid : out std_logic;
            m_ready : in std_logic;
            m_result : out std_logic_vector(287 downto 0);
            accepted_samples : out std_logic_vector(63 downto 0);
            epoch : out std_logic_vector(31 downto 0);
            candidate_count : out std_logic_vector(31 downto 0);
            rejected_count : out std_logic_vector(31 downto 0);
            capture_drop_count : out std_logic_vector(31 downto 0);
            duplicate_count : out std_logic_vector(31 downto 0);
            confirmed_count : out std_logic_vector(31 downto 0);
            snapshot_occupancy : out std_logic_vector(1 downto 0);
            snapshot_peak : out std_logic_vector(1 downto 0);
            max_history_age : out std_logic_vector(15 downto 0);
            error_sticky : out std_logic_vector(15 downto 0)
        );
    end component;
    signal raw_iq : std_logic_vector(127 downto 0);
    signal result_bundle : std_logic_vector(287 downto 0);
    signal occupancy_bits, peak_bits : std_logic_vector(1 downto 0);
begin
    raw_iq <= input_data3 & input_data2 & input_data1 & input_data0;
    result_epoch <= result_bundle(287 downto 256);
    rx_frame_id <= result_bundle(255 downto 224);
    candidate_id <= result_bundle(223 downto 192);
    coarse_absolute <= result_bundle(191 downto 128);
    fine_absolute <= result_bundle(127 downto 64);
    cfo_hz <= result_bundle(63 downto 32);
    quality_q1_15 <= result_bundle(31 downto 16);
    result_status <= result_bundle(15 downto 0);
    snapshot_occupancy <= "000000" & occupancy_bits;
    snapshot_peak <= "000000" & peak_bits;
    implementation : sync_frontend_top port map (
            clk => clk125,
            reset_n => reset_n,
            session_start => session_start,
            session_abort => session_abort,
            stream_gap => stream_gap,
            s_valid => input_valid,
            s_ready => input_ready,
            s_data => raw_iq,
            m_valid => result_valid,
            m_ready => result_ready,
            m_result => result_bundle,
            accepted_samples => accepted_samples,
            epoch => epoch,
            candidate_count => candidate_count,
            rejected_count => rejected_count,
            capture_drop_count => capture_drop_count,
            duplicate_count => duplicate_count,
            confirmed_count => confirmed_count,
            snapshot_occupancy => occupancy_bits,
            snapshot_peak => peak_bits,
            max_history_age => max_history_age,
            error_sticky => error_sticky
    );
end architecture;
