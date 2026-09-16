# OTA001/A01 Luna 执行 Receipt

## 身份与范围

- job：`OTA001` / revision `A01`
- grant：`SYNC_OTA_OTA001_A01_20260916T213951Z`
- Astra：`01a0ac17-f298-7201-848c-58d09e90ebb4`
- Luna：`01a0ac17-4f21-7be3-8690-540c11497b1e`
- 工程根：`D:/008_MA_Dev/Sync_OTA`
- 执行入口：`D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota001.tcl`
- 范围：一个 Vivado 主作业，`store` 后串行 `descriptor`；0 MATLAB；无综合、实现、全帧仿真、NI/板测或旧作业恢复。

## 启动前资源与输入

- 中央槽准入：`owner=SYNC_OTA`，`shared_slot_status=GRANTED_OTA001_A01`，准入记录为 `D:/007 Dev/OTA_RTL_0829/reports/operations/sync_ota/OTA001_A01_RESOURCE_GRANT_20260916.json`。
- grant 时可用内存：`14.137 GiB`；启动前刷新值：`FreePhysicalMemory=14711244 KiB`，约 `14.02 GiB`，高于要求的 `8 GiB`。
- 固定线程：Vivado `general.maxThreads=8`、`synth.maxThreads=8`；XSim/Xelab `16`。入口日志有参数回读。
- 源锁清单：8 项；manifest SHA256 为 `341d18aaef1c368a1dca728e646bf2acb235c3facc34b469f65c05b37cbb7866`。启动前与结束后 8/8 文件字节数和 SHA256 均匹配；未修改 RTL、TB、入口、输入或门槛。
- 输出目录：`work/OTA001/store_a01`、`work/OTA001/descriptor_a01`，独立且串行使用。

## 原生阶段记录

| 阶段 | 原生时间证据（UTC） | Vivado root PID | 身份与结果 | 退出 |
|---|---|---:|---|---:|
| store | `native.log` 创建 `2026-09-16T21:43:12Z`；日志结束 `2026-09-16T21:43:35Z` | 21940 | Vivado 2021.1；`xcvu11p-flgb2104-2-e`；top `ota_frame_store`；TB `ota_frame_store_tb`；`OTA001_STORE_PASS` | 0 |
| descriptor | `native.log` 创建 `2026-09-16T21:44:12Z`；日志结束 `2026-09-16T21:44:33Z` | 38988 | Vivado 2021.1；`xcvu11p-flgb2104-2-e`；top `ota_frontend_descriptor`；TB `ota_frontend_descriptor_tb`；`OTA001_DESCRIPTOR_PASS` | 0 |

两阶段的实际 source set 均由原生 Tcl 导出并与冻结 DUT/TB 输入一致。仿真时刻分别为 store `1456 ns`、descriptor `312 ns`；工具报告峰值分别为 `1131.324 MB`、`1129.926 MB`，这不是整棵进程树的总峰值。

证据目录：

- `work/OTA001/store_a01/native.log`、`native.jou`、`actual_sources.tsv`、`result.txt`、`project/OTA001_store.xpr`
- `work/OTA001/descriptor_a01/native.log`、`native.jou`、`actual_sources.tsv`、`result.txt`、`project/OTA001_descriptor.xpr`
- `ASTRA_REVIEW.json` 保存各阶段日志、XPR、结果和嵌套仿真日志指纹。

## 进程收尾

- 两次原生入口均在日志中出现 `exit 0` 和 `Exiting Vivado`。
- 每个阶段结束后均完成所属工具树扫描；最终独立快照 `PROCESS_SNAPSHOT.json` 于 `2026-09-16T21:48:05.4289642Z` 记录 `processes=[]`、`count=0`，未发现 Vivado/XSim/Xelab/Xvlog/Xvhdl/MATLAB。
- 历史子进程的完整创建时间树未被单独持久化，不能由当前空快照反推；本 receipt 不补造该证据。

## 执行包装修复

启动前第一次创建目录命令使用了当前 PowerShell 不支持的 `New-Item -LiteralPath`，命令报参数错误；此时没有启动 Vivado，也没有生成 native attempt。随后仅将包装参数修正为 `-Path`，确认两个冻结输出目录真实存在后按原命令启动。该修复未改变科学源、RTL、TB、输入或验收条件。

## 限定结论

- `store`：在冻结范围内 PASS。
- `descriptor`：`PASS_WITH_TB_WARNING`。TB 第 35 行辅助 Hz 溢出场景使用未定宽 `20000000000`，Vivado 报 VRFC 10-2659 并按 `-1474836480` 处理；主合法场景使用显式 `64'd20000000000`，实际通过 `absolute64=1`。该警告已保留，未原地修复或重跑。
- 原生日志未检出 ERROR、Fatal 或断言失败；exit 0 未被单独当作 PASS。
- 本记录不支持完整 OTA 算法、DDR 吞吐、综合/实现时序、持续 500 MS/s 或板测结论。