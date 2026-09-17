# OTA003/A01 Luna 执行 Receipt

## 身份与范围

- job/revision：`OTA003/A01`
- grant：`SYNC_OTA_OTA003_A01_20260916T232929Z`
- Astra：`01a0ac17-f298-7201-848c-58d09e90ebb4`；Luna：`01a0ac17-4f21-7be3-8690-540c11497b1e`
- 工程根：`D:/008_MA_Dev/Sync_OTA`
- 冻结入口：`D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota003.tcl`
- 实际首启：`2026-09-16T23:31:25.6226973Z`；包级硬截止：`2026-09-17T00:31:25.6226973Z`
- 范围：`bridge -> capture -> dual_rotation` 串行；1 Vivado、0 MATLAB；无综合、实现、长全帧、NI、板测或 OTA002/74 后端重跑。
- 器件/工具：`xcvu11p-flgb2104-2-e` / Vivado 2021.1；general/synth=8，xelab=16。

## 源锁与资源

- 源锁 28 项；manifest SHA256：`E3EA6D3FE2EE0DEC000082050E44FAFE77DF30EB920AFF98562D984C77CDDCF9`。
- 启动前与结束后均为 28/28 字节数及 SHA256 匹配，0 mismatch；冻结 RTL、TB、向量、原始入口和门槛未改。
- 成功阶段均使用冻结 `tools/monitor_native_job.ps1`，累计 PID+创建时间、工作集、最低可用内存和树关闭均持久化。
- 收尾实际工具进程扫描：`2026-09-16T23:45:00.6637609Z`，Vivado/XSim/Xelab/Xvlog/XVhdl/MATLAB 等 0 个。
- 资源最低采样：bridge `11097968 KiB`、capture `12763764 KiB`、dual `11838232 KiB`；未触发 8 GiB 保护线。

## 原生阶段结果

| 阶段 | top/TB；时间 | 唯一 marker 与计数 | 进程证据 |
|---|---|---|---|
| bridge | `ota_ddr_bridge / ota_ddr_bridge_tb`；`23:31:25.623–23:31:59.892Z` | `OTA003_DDR_BRIDGE_PASS commands=4 matched=4 stale_drained=1 owners=2 independent_clocks=2` | launcher 16800，Vivado 2852，退出 0；16 个身份；树关闭 `23:32:00.4130953Z` |
| capture | `ota_capture_controller / ota_capture_controller_tb`；`23:42:06.485–23:42:56.814Z` | `OTA003_CAPTURE_CONTROL_PASS captured=334215 scan_reads=334215 preload_reads=334215 cancel_pending_credit=1 descriptors_after_release=1 services_only=1` | launcher 32320，Vivado 23568，退出 0；19 个身份；树关闭 `23:42:57.2970936Z` |
| dual_rotation | `cfo_rotate4 / ota_dual_rotation_tb`；`23:43:48.371–23:44:20.527Z` | `OTA003_DUAL_ROTATION_PASS samples=5120 symbols=2 coarse_and_final_exact=1 nonzero_origin=1 nonunity_steps=2` | launcher 8112，Vivado 43448，退出 0；21 个身份；树关闭 `23:44:21.0946449Z` |

三阶段原生日志均有唯一 marker、`$finish`、`OTA003_NATIVE_DONE`，未检出 `ERROR:`、`FATAL:`、`AssertionError`、`Traceback` 或 `$fatal`。bridge 的 binding 为 `PRIVATE_XPM_EXACT_BINDING_PASS(required_instances=fifo)`；capture/dual 为 `PRIVATE_XPM_EXACT_BINDING_PASS(required_instances=none, actual_vendor=[])`，均未绑定安装版 `xpm.xpm_*`。

实际 source set 数量（`sources_1/sim_1/utils_1`）分别为 bridge 5/4/1、capture 6/4/1、dual 6/8/1。capture/dual 的 `services_only`、`none` 模式和双旋转专项注入边界均保持，不支持完整 OTA 算法或持续吞吐结论。

## 首错与执行包装修复

- `capture_a01`：Vivado 编译/展开成功，但冻结 `verify_xpm_binding.py` 在 `required=none` 时仍期待三份私有 XPM，报 `AssertionError: ([], [xpm_cdc,xpm_fifo,xpm_memory])`；未运行 TB 刺激，退出 1，完整日志/树保留。
- `repair_a02`：生成的修复 verifier 因外层 PowerShell 引号破坏而失败；未启动 attempt。
- `repair_a03`：比较运算符被包装过程破坏为单等号；未启动 attempt。
- `repair_a04`：none 逻辑正确，但搬移 verifier 后工程根仍按原目录推导；只读回放触发路径断言，未启动 attempt。
- `capture_a05`：搬移 Tcl 后相对工程根落到 `work/`，Vivado 报找不到 `work/rtl/vendor/xpm/xpm_cdc.sv`，退出 1；无编译/仿真刺激，日志/树保留。
- `repair_a06`：另存 Tcl/verifier；Tcl 固定工程根为 `D:/008_MA_Dev/Sync_OTA`，verifier 修正搬移路径并按任务书对 capture/dual 执行 `none` 绑定检查。AST 与 capture_a01 已有展开目录只读回放均通过；之后 capture_a06、dual_rotation_a01 通过。a06 Tcl SHA256：`D44B21DA8754CC5A0832FC7346A6D50BBF9155EFB7AE665BFEDFE910B204B289`；a06 verifier SHA256：`BAF5998306AFB23BFC07165B6DBC5189F983C2D8F8E41B114DB32C3317961B17`。
- 原始入口 SHA256：`7BB63C6A99F71FE8E94921678BEC7EC85CF86EC2EB08B98C4447A4BA898AE3C5`；原始 verifier SHA256：`5E345096BD957F7F618218656055ECC070D92AD27C321B99A04AA2F20FC123B6`；均未改。

## 限定结论

- bridge、capture、dual_rotation：均为冻结专项边界内原生候选 PASS。
- capture 验证的是真实地址范围、调度/租约和服务接口计数，FE/SFO/CFO 为服务模型；dual 验证两符号真实短双旋转坐标与 oracle 精确比较，不声称实际估出生产 SFO/CFO。
- 本包不支持完整 OTA 顶层、最终 XPR/DCP、综合/实现时序、持续吞吐、500 MS/s、NI 或板测结论。
- 交接时请 Astra 复核 a01/a05 包装失败与 a06 修复边界；Luna 不修改中央资源槽。

主要证据目录：`work/OTA003/bridge_a01/`、`work/OTA003/capture_a06/`、`work/OTA003/dual_rotation_a01/`、`work/OTA003/repair_a02/`–`repair_a06/`。
