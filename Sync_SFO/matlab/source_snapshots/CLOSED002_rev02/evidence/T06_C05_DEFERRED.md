# T06 C05 低偏移量精度问题暂缓处置

日期：2026-09-04（Europe/Berlin）

## 用户决定

用户明确要求暂时忽略 C05，继续推进 T06 的后续工程工作；低 SFO 偏移量下误差偏大的现象由用户研究后再单独测试。

## 执行边界

- C05 原始结果完整保留：TDL-D 10 dB、真实 SFO=0 ppm、residual CFO=0 kHz；MATLAB bit-true=-2.38689804077 ppm，RTL=-2.31292343140 ppm，MATLAB/RTL 差值为 0.073974609375 ppm。
- C05 不再阻塞 T06 的 OOC 综合、125/150 MHz 时序与资源检查、Post-Synthesis Functional Simulation、连续服务和证据封存。
- 本决定不把 C05 的 `FAIL` 改写为 `PASS`，也不授权修改固定 Tsai-SWLS 算法、T04 或 T05。
- “暂时忽略”不是永久放宽任务书的 `<=2 ppm` 验收线。因此在 C05 专项研究完成或用户另行给出最终处置前，T06 可以继续完成其余工程门，但不得声称无条件整体 PASS，T07 的条件自动启动也不触发。

## 恢复后的执行顺序

1. 复用已保存的 compact14 Behavioral、三帧连续服务和控制异常证据，不为 C05 重跑算法矩阵。
2. 完成完整 T06 consumer 的独立 OOC：125 MHz 为强制门，150 MHz 为优化尝试；检查资源、blackbox、DDR scratch port 和关键路径。
3. 使用同次 125 MHz 功能网表完成 Post-Synthesis Functional replay 和 MATLAB/RTL 自动比对。
4. 生成阶段证据清单与本科生版报告；C05 作为独立 deferred item 保留。

## 依据

- `reports/T06_initial_sfo/compact14_c13_c14/a20260903T185548969Z_47672/analysis_rev03/t06_compact14_review_summary.json`
- `reports/T06_initial_sfo/compact14_c13_c14/a20260903T185548969Z_47672/analysis_rev03/T06_C01_C14_RESULTS_REVIEW_UNDERGRADUATE_ZH.md`
- `docs/decisions/T06_COMPACT14_C05_ACCURACY_CONTROLLED_REOPEN_20260903.md`

