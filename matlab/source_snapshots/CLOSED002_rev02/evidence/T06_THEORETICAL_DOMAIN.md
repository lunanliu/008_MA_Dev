# T06 SFO 理论验收域调整决策（10 dB 基准）

Date: 2026-09-01  
State: `ACCEPTED_BY_EXPLICIT_USER_DECISION`  
Applies to: T06 MATLAB floating-point / theoretical-algorithm subgate only

## 决策

用户明确决定保留当前冻结的 Tsai-SWLS 候选，并把 TDL-D 10 dB 作为带噪
多径理论验收的最低已测试基准。当前冻结矩阵实际纳入 10 dB 和 20 dB 两个
离散测试档位。TDL-D -5/0/5 dB 继续完整保存和报告，但只作为困难
信道、捕获边界和退化特性表征，不再阻止 T06 理论算法子门通过。

任务书原文保留不改；本文件记录用户对当前工程验收域的显式覆盖决定。

## 冻结算法

`symmetric_full_span_1640|pair_stack_principal|tsai_amplitude`

- PS3--PS10 四组相邻符号对；
- 每对使用全部 1640 个活动子载波；
- `pair_stack_principal`；
- `Scaled_Radians/Q3.45` 相位合同；
- Tsai amplitude simplified weight；
- 完整 `S0/S1/S2/T0/T1` 五和斜率/截距回归。

formula-WLS run05 作为研究对照保留，但未取得总体或低 SNR 优势，因此不替换
冻结 SWLS。

## 新的理论保证域

逐 case 门槛仍为 `absolute SFO error <= 2 ppm`。

| 条件 | case 数 | 可评估 | RMSE (ppm) | 最大绝对误差 (ppm) | >2 ppm | 结论 |
|---|---:|---:|---:|---:|---:|---|
| Deterministic / Inf | 28 | 28 | 0.0439698184 | 0.0855504696 | 0 | PASS |
| Paper fixture / 15 dB | 10 | 10 | 0.3478864421 | 0.6946460145 | 0 | PASS |
| TDL-D / 10 dB | 10 | 10 | 1.0851600258 | 1.6161297119 | 0 | PASS |
| TDL-D / 20 dB | 10 | 10 | 0.3460682695 | 0.5344057503 | 0 | PASS |

合并保证域为 58/58 可评估、58/58 在 2 ppm 内；MAE
`0.285122965738 ppm`，RMSE `0.495457620438 ppm`，最大绝对误差
`1.616129711878 ppm`。

## 表征域

| 条件 | 处置 |
|---|---|
| TDL-D -5/0/5 dB | 保留所有结果、outage 和误差；只作 characterization，不进入理论 PASS 判决 |
| 3 个 stress case | 只作 characterization |
| 无噪声 residual-CFO/SFO 121 点网格 | 支撑灵敏度和符号正确性，不单独替代带噪保证域 |

表征数据不得删除、改写为 PASS 或从 case 矩阵中静默移除。

## 边界

本决策只把 `T06_THEORETICAL_FLOATING_10DB` 子门置为 PASS。它不表示：

- T04 或 T05 的独立完整验收自动 PASS；
- T06 fixed-point、bit-true、RTL、Behavioral、OOC、时序、资源、PSF、
  MATLAB/RTL compare 或 cycle budget 已通过；
- 整个 T06 已 PASS；
- T07 自动启动条件已经满足。

完整 T06 仍须完成剩余硬件开发与验收门。若以后在冻结算法、冻结参考和
TDL-D 10/20 dB 已测试保证域中出现任一有效 case 超过 2 ppm，应 controlled reopen
本理论子门。

本决策不对未测试的 10--20 dB 中间点、20 dB 以上连续区域、其他多径
profile 或其他 seed 作数学外推。

## 主要证据

- `config/t06_initial_sfo_acceptance_domain_v2.json`
- `reports/T06_initial_sfo/cp_aware_fixed_candidate_gate_run04/attempt_20260901T154741631Z_28952_04831e3a/fixed_candidate_case_results.csv`
- `reports/T06_initial_sfo/cp_aware_fixed_candidate_gate_run04/attempt_20260901T154741631Z_28952_04831e3a/t06_cp_aware_fixed_candidate_gate_summary.json`
- `reports/T06_initial_sfo/fixed_tsai_swls_full1640_cfo_sfo_grid_run01/attempt_20260901T114842963Z_31972_9145bfbc/grid_summary.json`
- `reports/T06_initial_sfo/tsai_swls_vs_wls_run04_quick_compare_run01/attempt_20260901T170437548Z_8180_e2af77a9/t06_swls_vs_wls_summary.json`
