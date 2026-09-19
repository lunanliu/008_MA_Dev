# 当前VHDL端口清单（源码提取，2026-09-17）

方向以VHDL为参照。std_logic在LabVIEW为Boolean，32位向量按U32位模式连接，64位诊断计数按U64。clk是时钟资源。所有输入输出都与各自SCTL同域，跨域适配在Target VI中完成。

本清单核对端口存在与宽度，连接语义见[新版接线说明](../docs/tutorial/LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md)。注意：数据数组不在VHDL，ReadCtrl.stream_word0..3是自检观察输入，不是四路数据输出。真实四点数据来自LabVIEW Current_Array。

## ddr_upload_ctrl

编译参数 DDR_WIDTH_BITS : positive := 1280；是128的正整数倍。

| 端口 | 方向 | LabVIEW类型 |
|---|---|---|
| clk | in | Clock |
| reset | in | Boolean |
| run_enable | in | Boolean |
| load_command | in | Boolean |
| rearm_command | in | Boolean |
| abort_command | in | Boolean |
| new_session_safe | in | Boolean |
| dram_ready | in | Boolean |
| sample_count | in | U32 |
| ddr_word_count | in | U32 |
| ddr_capacity_words | in | U32 |
| fifo_output_valid | in | Boolean |
| ddr_write_ready_now | in | Boolean |
| fifo_read_enable | out | Boolean |
| pack_offset | out | U32 |
| pack_clear | out | Boolean |
| ddr_write_valid | out | Boolean |
| ddr_write_address | out | U32 |
| loaded_samples | out | U32 |
| load_state | out | U8 |
| load_busy | out | Boolean |
| load_done | out | Boolean |
| load_fault | out | Boolean |
| fault_code | out | U8 |
| load_generation | out | U32 |
| command_rejected | out | Boolean |
| load_cycles | out | U64 |
| data_window_cycles | out | U64 |
| receive_cycles | out | U64 |
| write_cycles | out | U64 |
| fifo_empty_cycles | out | U64 |
| ddr_stall_cycles | out | U64 |
| pause_cycles | out | U64 |

## ddr_read_ctrl

编译参数 DDR_WIDTH_BITS : positive := 1280；是128的正整数倍。

| 端口 | 方向 | LabVIEW类型 |
|---|---|---|
| clk | in | Clock |
| reset | in | Boolean |
| run_enable | in | Boolean |
| read_command | in | Boolean |
| rearm_command | in | Boolean |
| abort_command | in | Boolean |
| new_session_safe | in | Boolean |
| dram_ready | in | Boolean |
| sample_count | in | U32 |
| ddr_word_count | in | U32 |
| ddr_capacity_words | in | U32 |
| pattern_check_enable | in | Boolean |
| pattern_seed | in | U32 |
| ddr_request_ready_now | in | Boolean |
| prefetch_write_ready_now | in | Boolean |
| ddr_retrieve_valid | in | Boolean |
| prefetch_read_valid | in | Boolean |
| stream_ready | in | Boolean |
| stream_word0 | in | U32 |
| stream_word1 | in | U32 |
| stream_word2 | in | U32 |
| stream_word3 | in | U32 |
| request_valid | out | Boolean |
| request_address | out | U32 |
| retrieve_ready | out | Boolean |
| prefetch_write_valid | out | Boolean |
| prefetch_read_enable | out | Boolean |
| current_load | out | Boolean |
| current_clear | out | Boolean |
| stream_offset | out | U32 |
| stream_valid | out | Boolean |
| stream_fire | out | Boolean |
| stream_first | out | Boolean |
| stream_last | out | Boolean |
| read_state | out | U8 |
| read_busy | out | Boolean |
| read_done | out | Boolean |
| read_fault | out | Boolean |
| fault_code | out | U8 |
| read_generation | out | U32 |
| command_rejected | out | Boolean |
| requested_words | out | U32 |
| returned_words | out | U32 |
| enqueued_words | out | U32 |
| popped_words | out | U32 |
| sent_samples | out | U32 |
| total_cycles | out | U64 |
| replay_cycles | out | U64 |
| transfer_cycles | out | U64 |
| no_data_cycles | out | U64 |
| sink_stall_cycles | out | U64 |
| pause_cycles | out | U64 |
| checked_samples | out | U32 |
| mismatch_count | out | U32 |
| first_error_index | out | U32 |
| first_error_expected | out | U32 |
| first_error_actual | out | U32 |

