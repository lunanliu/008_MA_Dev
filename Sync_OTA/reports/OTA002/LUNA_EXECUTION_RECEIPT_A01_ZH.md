# OTA002/A01 Luna 执行 Receipt

## 身份与范围

- job/revision：`OTA002/A01`
- grant：`SYNC_OTA_OTA002_A01_20260916T221248Z`
- Astra：`01a0ac17-f298-7201-848c-58d09e90ebb4`；Luna：`01a0ac17-4f21-7be3-8690-540c11497b1e`
- 工程根：`D:/008_MA_Dev/Sync_OTA`；冻结入口：`D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota002.tcl`
- 范围：一个 Vivado 主作业，`context -> backend74 -> cfo_control` 串行；0 MATLAB；无综合、实现、长帧、NI 或板测。
- 包级实际首启：`2026-09-16T22:16:29.0001913Z`；硬截止：`2026-09-16T23:16:29.0001913Z`；最后一阶段树关闭：`2026-09-16T22:42:32.2264017Z`。

## 启动前与结束后核对

- 中央槽为 OTA002/A01、owner=SYNC_OTA、单 Vivado 主作业；未复用 OTA001 grant。
- grant 可用内存 11.29 GiB；启动前实际工具进程扫描通过 8 GiB 线。
- Vivado 2021.1，器件 `xcvu11p-flgb2104-2-e`；`general.maxThreads=8`、`synth.maxThreads=8`、XSim/Xelab=16，日志有回读。
- 源锁 41 项；manifest SHA256：`F0655DA779236DC40026C06E9B63B0A6F8E0B0769447321A0883DD2B1AE4EF95`。结束后 41/41 字节数和 SHA256 匹配，0 mismatch；冻结 RTL、TB、输入、原始入口和门槛未改。
- 三阶段 actual source 数分别 12、20、28；均为私有 XPM 绑定 PASS，实际 vendor 为 `sim/vendor/link010r1/{xpm_cdc,xpm_fifo,xpm_memory}.sv`，`ota_xpm` 优先于 `xpm`。
- 收尾实际扫描 `2026-09-16T22:47:05.1943852Z` 的受控工具进程数为 0。

## 原生阶段结果

| 阶段 | top/TB；时间 | 唯一 marker | 进程证据 |
|---|---|---|---|
| context | `ota_sfo_context_join / ota_context_boundary_tb`；native.log `22:31:25.845Z–22:31:57.748Z` | `OTA002_CONTEXT_PASS actual_descriptors=3 contexts_consumed=2 canceled=1 reset_edges=3`；result SHA256 `5FFF7B51FD50FD4DF3D399EA43AC356D2185A0B6F9BA35DC3E3BF1C90D606FF5` | launcher 34584，Vivado 44920，退出 0；树关闭 `22:31:58.9128272Z` |
| backend74 | `cfo_estimator_link / ota_backend74_tb`；native.log `22:36:16.141Z–22:36:50.859Z` | `OTA002_BACKEND74_PASS full_frames=4 observations=296 canceled_partial=9 outputs=4 reset_edges=3`；result SHA256 `BE6F3B6A2E18C815894C64F0F26446A1CD9E989D11428678080DFD8F059C9291` | Vivado 38164（native log 线程回读同为 38164），退出正常；历史树证据有缺口 |
| cfo_control | `ota_cfo_chain / ota_cfo_control_tb`；native.log `22:41:56.712Z–22:42:30.130Z` | `OTA002_CFO_CONTROL_PASS real_chain_elaborated=1 coarse_beats=3 cancel_pending_ddr=1 final_before_estimate=0`；result SHA256 `0D6E3608E846171A4251CA162DD0DF03752758FAB3AB1009BFC71428D89AE75F` | launcher 40656，Vivado 27652，退出 0；树关闭 `22:42:32.2264017Z`，累计 14 个身份 |

三阶段均有唯一 result marker、`$finish`、`OTA002_NATIVE_DONE`；原生日志无 `ERROR:`、`FATAL:`、`AssertionError`、`Traceback` 或 `$fatal`。backend 的 `SIM_ASSERT_CHK` 为 XPM 仿真提示，不是失败。

## backend74 过程树限定

首版 `monitor_stage_a01.ps1` 使用了与 PowerShell 自动变量大小写不敏感冲突的 `$pid/$PID`。其 `process_tree.jsonl` 只有监控 PowerShell 38504 与 launcher `cmd.exe` 30180，共 8 行；不能声称保存 Vivado 子树或完整历史关闭。独立扫描观察到 Vivado 38164、父 30180，另有 xsimk 25580、wbtcv 40876；创建时间按本机显示 `2026-09-17 00:36:15/00:36:44/00:36:49` 原样保留，未补造毫秒 UTC。

backend 未重跑；原生 PASS、包装错误和树缺口均保留。限定补录：`work/OTA002/backend74_a01/posthoc_process_receipt.json`。修复脚本 `monitor_stage_a02.ps1` SHA256 为 `3C55FD5FB577217F6B514B2BBF54F4F43D6CF49B66EBEB0313F51630C2213262`，仅用于 cfo_control；cfo 具有完整 `process_summary.json` 和树关闭记录。

## 执行包装修复

context 的 a01–a05 均为包装问题，未改 RTL、TB、输入或门槛，失败目录均保留：a01 未跳过 PRJ 注释；a02 未折叠 PRJ 续行；a03 verifier 文件名调用错误；a04 Python 反斜杠语法错误；a05 正则边界转义变控制字符而误报 `xpm_fifo_async`。a06 另存 Tcl/verifier 后通过：Tcl SHA256 `CE140810BC184CAEC40D11CD70B1A9A29B9502DAA4DA6D68210BE427376E77DC`，verifier SHA256 `371503F3F7BFD01D827D08A4F72D2654002FE29B98CC2B08B285ECBDF62C259E`；冻结入口/原 verifier 未改。

## 限定结论

- context：冻结阶段边界内原生候选 PASS。
- backend74：原生功能候选 PASS，但过程树历史证据有上述缺口，需 Astra 单独复核交接充分性。
- cfo_control：冻结阶段边界内原生候选 PASS。
- 整包不支持完整 OTA 数值闭环、最终调度、持续吞吐、综合/实现时序、500 MS/s 资格、NI 或板测；最终功能接收由 Astra 完成。

证据目录：`work/OTA002/context_a06/`、`work/OTA002/backend74_a01/`、`work/OTA002/cfo_control_a01/`、`work/OTA002/repair_a02/`–`repair_a06/`。
