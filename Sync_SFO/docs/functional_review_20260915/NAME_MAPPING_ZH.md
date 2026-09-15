# 功能目录与名称映射

基线：V5_Final `dd5e8f7a642625f06c4996d17e3642bbadc7d557`。完整可机读文件、标识符、实例类型/名字映射见 [rename_plan.json](rename_plan.json)。厂商 IP 标识保持；T 编号保留在历史来源及测试证据标识中。

| 目录 | 功能 |
|---|---|
| initial_estimation | 训练符号处理、相位与加权拟合、首次 SFO |
| first_resampling | 第一遍描述符、帧调度和重采样 |
| residual_estimation | 74 个窗口/点、残余 SFO 拟合 |
| second_resampling | 第二遍描述符和重采样 |
| resampling | 两遍共用 FIR/Farrow 与保护样点处理 |
| buffering | 原始环、中间 bank、输出和同步/跨域 FIFO |
| fft_service | 首次/残余 FFT、IFFT 服务与仲裁 |
| control | 两遍顶层、传输调度和域复位 |
| common | 记录类型与自有算术适配层 |

## 文件迁移

| 原路径 | 当前路径 |
|---|---|
| `rtl/common/bistatic_stream_pkg.sv` | `rtl/common/sfo_stream_pkg.sv` |
| `rtl/t07/farrow_microbench.sv` | `rtl/resampling/sfo_farrow_arithmetic.sv` |
| `rtl/t07/g3_down15_top.sv` | `rtl/resampling/sfo_fir_down15.sv` |
| `rtl/t07/g3_down47_top.sv` | `rtl/resampling/sfo_fir_down47.sv` |
| `rtl/t07/g3_farrow_guard_stream.sv` | `rtl/resampling/sfo_guarded_farrow_stream.sv` |
| `rtl/t07/g3_up15_top.sv` | `rtl/resampling/sfo_fir_up15.sv` |
| `rtl/t07/g3_up47_top.sv` | `rtl/resampling/sfo_fir_up47.sv` |
| `rtl/common/t03_main_fft_service.sv` | `rtl/fft_service/sfo_initial_fft_service.sv` |
| `rtl/common/t03_uram_frame_bank.sv` | `rtl/buffering/sfo_uram_frame_bank.sv` |
| `rtl/common/t05_local_capture_buffer.sv` | `rtl/buffering/sfo_training_capture_buffer.sv` |
| `rtl/common/t05_phase_increment_controller.sv` | `rtl/initial_estimation/sfo_cfo_phase_increment.sv` |
| `rtl/common/t05_vendor_multiplier_adapters.sv` | `rtl/common/sfo_vendor_multiplier_adapters.sv` |
| `rtl/t06/t06_cfo_derotate_s16_4lane.sv` | `rtl/initial_estimation/sfo_initial_cfo_derotate_s16_4lane.sv` |
| `rtl/t06/t06_dds_phase_4lane.sv` | `rtl/initial_estimation/sfo_initial_dds_phase_4lane.sv` |
| `rtl/t06/t06_derotate_wide_4lane.sv` | `rtl/initial_estimation/sfo_initial_derotate_wide_4lane.sv` |
| `rtl/t06/t06_fft_pair_extractor.sv` | `rtl/initial_estimation/sfo_initial_fft_pair_extractor.sv` |
| `rtl/t06/t06_fft_pair_extractor_fifo.sv` | `rtl/initial_estimation/sfo_initial_fft_pair_extractor_fifo.sv` |
| `rtl/t06/t06_fft_pair_extractor_memory.sv` | `rtl/initial_estimation/sfo_initial_fft_pair_extractor_memory.sv` |
| `rtl/t06/t06_fft_swls_backend.sv` | `rtl/initial_estimation/sfo_initial_fft_swls_backend.sv` |
| `rtl/t06/t06_five_sum_accumulator.sv` | `rtl/initial_estimation/sfo_initial_five_sum_accumulator.sv` |
| `rtl/t06/t06_frame_context_join.sv` | `rtl/initial_estimation/sfo_initial_frame_context_join.sv` |
| `rtl/t06/t06_initial_sfo_service.sv` | `rtl/initial_estimation/sfo_initial_estimation_service.sv` |
| `rtl/t06/t06_initial_sfo_standalone.sv` | `rtl/initial_estimation/sfo_initial_estimator.sv` |
| `rtl/t06/t06_main_fft_exclusive_owner.sv` | `rtl/fft_service/sfo_initial_fft_arbiter.sv` |
| `rtl/t06/t06_observation_engine.sv` | `rtl/initial_estimation/sfo_initial_observation_engine.sv` |
| `rtl/t06/t06_observation_engine_2lane.sv` | `rtl/initial_estimation/sfo_initial_observation_engine_2lane.sv` |
| `rtl/t06/t06_observation_engine_fifo.sv` | `rtl/initial_estimation/sfo_initial_observation_engine_fifo.sv` |
| `rtl/t06/t06_observation_store.sv` | `rtl/initial_estimation/sfo_initial_observation_store.sv` |
| `rtl/t06/t06_observation_store_bank.sv` | `rtl/initial_estimation/sfo_initial_observation_store_bank.sv` |
| `rtl/t06/t06_pair_max_tracker_2lane.sv` | `rtl/initial_estimation/sfo_initial_pair_max_tracker_2lane.sv` |
| `rtl/t06/t06_pair_phasor_bfp.sv` | `rtl/initial_estimation/sfo_initial_pair_phasor_bfp.sv` |
| `rtl/t06/t06_ps3_ps10_job_sequencer.sv` | `rtl/initial_estimation/sfo_initial_ps3_ps10_job_sequencer.sv` |
| `rtl/t06/t06_raw_reader_4lane.sv` | `rtl/initial_estimation/sfo_initial_raw_reader_4lane.sv` |
| `rtl/t06/t06_raw_reader_local_capture.sv` | `rtl/initial_estimation/sfo_initial_raw_reader_local_capture.sv` |
| `rtl/t06/t06_raw_to_fft_frontend.sv` | `rtl/initial_estimation/sfo_initial_raw_to_fft_frontend.sv` |
| `rtl/t06/t06_regression_tail.sv` | `rtl/initial_estimation/sfo_initial_regression_tail.sv` |
| `rtl/t06/t06_shared_gain_s16_4lane.sv` | `rtl/initial_estimation/sfo_initial_shared_gain_s16_4lane.sv` |
| `rtl/t06/t06_shared_gain_s16_lane.sv` | `rtl/initial_estimation/sfo_initial_shared_gain_s16_lane.sv` |
| `rtl/t06/t06_swls_weighted_backend.sv` | `rtl/initial_estimation/sfo_initial_swls_weighted_backend.sv` |
| `rtl/t06/t06_unsigned_divider_service.sv` | `rtl/initial_estimation/sfo_initial_unsigned_divider_service.sv` |
| `rtl/t06/t06_unsigned_divider_service_fifo.sv` | `rtl/initial_estimation/sfo_initial_unsigned_divider_service_fifo.sv` |
| `rtl/t06/t06_weight_pack.sv` | `rtl/initial_estimation/sfo_initial_weight_pack.sv` |
| `rtl/t07/t07_guard_frame_core.sv` | `rtl/resampling/sfo_guarded_resampling_core.sv` |
| `rtl/t07/t07_nominal_pack4_rev02.sv` | `rtl/resampling/sfo_nominal_pack4.sv` |
| `rtl/t07/t07_sync_fifo.sv` | `rtl/buffering/sfo_sync_fifo.sv` |
| `rtl/t08/t08_descriptor.sv` | `rtl/first_resampling/sfo_first_pass_descriptor.sv` |
| `rtl/t08/t08_first_sfo_resampler.sv` | `rtl/first_resampling/sfo_first_resampler.sv` |
| `rtl/t08/t08_frame_engine.sv` | `rtl/first_resampling/sfo_first_frame_scheduler.sv` |
| `rtl/t09/t09_aux_ifft_service4.sv` | `rtl/fft_service/sfo_residual_ifft_service4.sv` |
| `rtl/t09/t09_div_u80_u49_rne.sv` | `rtl/residual_estimation/sfo_residual_div_u80_u49_rne.sv` |
| `rtl/t09/t09_dtp_frame_backend4.sv` | `rtl/residual_estimation/sfo_residual_delay_backend4.sv` |
| `rtl/t09/t09_fft_grid_stage4.sv` | `rtl/residual_estimation/sfo_residual_fft_grid_stage4.sv` |
| `rtl/t09/t09_grid_packet_queue2.sv` | `rtl/residual_estimation/sfo_residual_grid_packet_queue2.sv` |
| `rtl/t09/t09_main_fft_service4.sv` | `rtl/fft_service/sfo_residual_fft_service4.sv` |
| `rtl/t09/t09_main_fft_window4.sv` | `rtl/fft_service/sfo_residual_fft_window4.sv` |
| `rtl/t09/t09_nominal_window_reader4.sv` | `rtl/residual_estimation/sfo_residual_nominal_window_reader4.sv` |
| `rtl/t09/t09_peak_interpolate.sv` | `rtl/residual_estimation/sfo_residual_peak_interpolate.sv` |
| `rtl/t09/t09_peak_triplet4.sv` | `rtl/residual_estimation/sfo_residual_peak_triplet4.sv` |
| `rtl/t09/t09_pilot_front2.sv` | `rtl/residual_estimation/sfo_residual_pilot_front2.sv` |
| `rtl/t09/t09_pilot_grid4.sv` | `rtl/residual_estimation/sfo_residual_pilot_grid4.sv` |
| `rtl/t09/t09_pilot_rotate2.sv` | `rtl/residual_estimation/sfo_residual_pilot_rotate2.sv` |
| `rtl/t09/t09_pilot_select_phase4.sv` | `rtl/residual_estimation/sfo_residual_pilot_select_phase4.sv` |
| `rtl/t09/t09_power4.sv` | `rtl/residual_estimation/sfo_residual_power4.sv` |
| `rtl/t09/t09_residual_sfo_pipeline4.sv` | `rtl/residual_estimation/sfo_residual_estimator4.sv` |
| `rtl/t09/t09_sfo_ls74.sv` | `rtl/residual_estimation/sfo_residual_ls74.sv` |
| `rtl/t10/t10_cdc_fifo.sv` | `rtl/buffering/sfo_record_cdc_fifo.sv` |
| `rtl/t10/t10_domain_reset.sv` | `rtl/control/sfo_domain_reset.sv` |
| `rtl/t10/t10_output_buffer.sv` | `rtl/buffering/sfo_output_buffer.sv` |
| `rtl/t10/t10_r1_bank.sv` | `rtl/buffering/sfo_intermediate_frame_bank.sv` |
| `rtl/t10/t10_raw_ring.sv` | `rtl/buffering/sfo_raw_frame_ring.sv` |
| `rtl/t10/t10_second_descriptor.sv` | `rtl/second_resampling/sfo_second_pass_descriptor.sv` |
| `rtl/t10/t10_second_sfo_resampler.sv` | `rtl/second_resampling/sfo_second_resampler.sv` |
| `rtl/t10/t10_two_pass_system.sv` | `rtl/control/sync_sfo_top.sv` |
| `rtl/t10/t10_two_pass_transport.sv` | `rtl/control/sfo_two_pass_transport.sv` |
| `rtl/include/t06_observation_engine_ip_config.svh` | `rtl/include/initial_observation_ip_config.svh` |
| `rtl/include/t06_pair_max_tracker_2lane_ip_config.svh` | `rtl/include/initial_pair_max_tracker_ip_config.svh` |
| `rtl/include/t06_shared_gain_ip_config.svh` | `rtl/include/initial_shared_gain_ip_config.svh` |
| `sim/tb/t10_full023_tb.sv` | `sim/tb/sync_sfo_full_frame_tb.sv` |
| `sim/tb/t10_full023_fifo_observer.sv` | `sim/tb/sfo_fifo_history_observer.sv` |
| `constraints/t10_root_clocks.xdc` | `constraints/sync_sfo_clocks.xdc` |
| `sim/data/t09_pilot_phase.mem` | `sim/data/residual_pilot_phase.mem` |
| `wrapper/t10_sfo_manual_wrapper.vhd` | `wrapper/sync_sfo_manual_wrapper.vhd` |

## 实例命名

187 个实例逐一归档，27 个模糊/编号实例改成功能名，其余保留已有功能名。完整上下文及类型在 JSON 的 instances 字段，避免按局部同名误改。`sfo_farrow_parallel` 保留泛化 LANES 参数及原默认值 16；FIR up15/up47/down15/down47 沿用滤波器身份，不把名称中的数字解释成重采样倍率。
