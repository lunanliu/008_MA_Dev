# Sync_DDR

独立VHDL DDR写入/读取控制器工程。cwd D:/008_MA_Dev，工程根 D:/008_MA_Dev/Sync_DDR，与其他四个Sync工程平级。本任务单独设计、执行、自审；原配对已停止，不创建执行任务或worktree，不改其他工程，不推送远端。

## 最新：零基础接入与完整透明回环（已完成资源收口）

四个生产RTL保持不变，本轮新增四核串联604点透明行为回环已PASS：Host实际模拟接收604点、错误0，两个DDR各16元素、两个输出端各151组；包含结果FIFO/DMA背压。Sync用直通替代，未做真实NI/板测。

从[零基础完整教程](docs/tutorial/LABVIEW_ZERO_TO_ROUNDTRIP_ZH.md)开始，按CLIP导入、资源配置、四段分支接线、会话控制、Host运行和逐点比较顺序操作。[测试数据](examples/roundtrip_604/metadata.json)、[实际仿真接收文件](examples/roundtrip_604/simulated_host_received_u32.csv)、[本轮验证报告](reports/review/DDR_ROUNDTRIP_VALIDATION_ZH.md)可交叉核对。

新工程work/roundtrip_v1/attempt_01_create/project/DDR_Control.xpr含4RTL/5TB/两时钟约束集，仅sim_roundtrip本轮执行；21输入+5工具冻结，新窗口固定截止21:25:38 CEST，最后原生作业21:16:59 CEST关闭。其他四个已成功角色测试不重跑。真实NI写可见性/版本接线仍需远端对齐，不能用模型代替平台保证。

## 最新：用户要求的四段控制器（2026-09-17）

四个交付文件：

| 文件 | 方向 | SCTL时钟 |
|---|---|---|
| [ddr_upload_ctrl.vhd](rtl/ddr_upload_ctrl.vhd) | H2T DMA -> 输入DDR | 150MHz |
| [ddr_read_ctrl.vhd](rtl/ddr_read_ctrl.vhd) | 输入DDR -> Sync四点回放 | 125MHz |
| [ddr_capture_ctrl.vhd](rtl/ddr_capture_ctrl.vhd) | Sync结果Target FIFO -> 结果DDR | 150MHz |
| [ddr_download_ctrl.vhd](rtl/ddr_download_ctrl.vhd) | 结果DDR -> T2H DMA -> Host | 150MHz |

新增capture依赖upload，download依赖read；新增两文件是无附加流水的角色封装，导入时应包含对应内核。每次成功交接四个U32，数据数组和NI资源仍由LabVIEW实现。原两核与两TB保持原哈希，本轮不重跑既有成功仿真。

[四段硬件设计与吞吐预算](docs/DDR_FOUR_STAGE_DESIGN_ZH.md)；[完整反向逐线接法及33/46新增端口](docs/tutorial/LABVIEW_FOUR_STAGE_WIRING_ZH.md)。默认1280位DDR时，两个150MHz写入器理想40点/11拍=545.45MSample/s，不能据此声称实际持续吞吐已通过；640位只达500MSample/s。回放125MHz四点，下载150MHz四点，均按有效握手计数。

本轮新入口 scripts/create_four_stage_project.tcl 与 scripts/run_reverse.ps1；4 RTL/4 TB/两个独立约束集，四个sim filesets。旧工程及旧证据保留原两核身份。新冻结FROZEN_FOUR_STAGE_V1.json，create/capture/download均PASS；见[四段短验证报告](reports/review/FOUR_STAGE_VALIDATION_20260917_ZH.md)。所有原生作业于20:48:41 CEST关闭，本轮不再启动EDA。总管家已于20:51:39 CEST归还窗口、关闭grant。[四文件接入包](delivery/Sync_DDR_Four_Controllers_20260917.zip)包含源码、接线指南及短测证据。输入区和结果区各自整段写完后读，处理时可以读输入区同时写结果区；尚无物理DDR带宽或NI跨域实现证据。

## 上一轮两核实现（2026-09-17，用户已批准）

- Host通过U32端口ddr_capacity_words声明允许使用的DDR逻辑元素容量，不再写死2048或65536；实际容量仍由LabVIEW资源分配决定。
- 编译参数DDR_WIDTH_BITS默认1280，必须为128的正整数倍；每拍四个32位复样点保持。位宽不是Host运行时开关。
- 启动沿锁存N/M/C，再用两拍完成计算/检查；busy包含初始化。运行中Host改配置不改变当前段。
- 整段上传后再回放；单段地址从0开始。Target VI拥有互斥和有效段描述符，不能用两个独立Host启动按钮绕过控制。
- stream_first/stream_last与数据一起握手，背压时保持；read_done仅表示最后四点已交给下游。
- 原单打包寄存器、256块预取FIFO保留；无整帧片上RAM、无双缓冲、无同段边写边读。

## 用户入口

1. [已批准硬件设计记录](docs/DDR_RUNTIME_CONFIG_DESIGN_ZH.md)
2. [新版Host参数、Target会话与接线补充](docs/tutorial/LABVIEW_RUNTIME_CONFIG_AND_SESSION_ZH.md)
3. [LabVIEW数据通路逐根接线](docs/tutorial/LABVIEW_TARGET_VI_STEP_BY_STEP_ZH.md)（默认1280bit）
4. [当前33/57端口清单](reports/DDR_CURRENT_PORTS_ZH.md)
5. [本次静态自审](reports/review/RUNTIME_CONFIG_SELF_REVIEW_20260917_ZH.md)
6. [两核相对原始版本差异](reports/review/RUNTIME_CONFIG_RTL.diff)
7. [原完整帧容量核算](reports/review/DDR_FULL_FRAME_CAPACITY_REVIEW_20260917_ZH.md)（帧长依据仍有效；其中固定MAX容量建议已被运行时C替代）

当前SFO窗口N=1336860，默认K=40时M=33422；65536元素/10MiB是容量起点建议，不是RTL上限。N仍受U32及下游Sync合同限制。

## 上一轮两核验证与执行（已关闭资源）

**本轮create、写行为、读行为均PASS**。详见[修改与短验证报告](reports/review/DDR_RUNTIME_CONFIG_VALIDATION_20260917_ZH.md)。最后一次原生作业于2026-09-17 19:41:11 CEST（UTC+02:00）关闭；此后不再启动EDA。

本轮新工程已create PASS，实际2 RTL/2 TB/1 XDC、sources_1及sim_write/sim_read顶层均核对。路径：
work/runtime_config_v1/attempt_01_create/project/DDR_Control.xpr

首次write的xvhdl成功，xelab因Vivado自动线程参数与附加参数重复而失败，行为仿真当次未开始。已按本机Vivado属性定义修正mt_level=16并清空额外mt；失败日志保存在attempt_02_write。后续最终结果以本轮验证报告及原生attempt/result.json为准，不能把编译通过或create通过当作功能PASS。

scripts/run_functional.ps1为当前受资源窗口约束的入口；-ValidateOnly不启动EDA。真实运行必须先有匹配冻结清单的总管家grant，逐阶段create/write/read，成功阶段禁止重跑。新入口根路径相对脚本定位，Vivado位置/输出由RESOURCE_REQUEST定义，迁移后须重新冻结。
阶段180/300/300秒，首次启动后总预算固定900秒，本轮固定截止为2026-09-17 19:46:29 CEST（内部UTC日志保持原值）；旧grant不可复用。原历史执行失败只发生create，不是旧RTL功能失败。

本轮不运行综合、实现、NI编译、板测、MATLAB，不生成CLIP XML。实际1280bit逻辑元素映射、NI写后读可见性及远端跨域接线仍须平台对齐；仿真模型不能替代这些保证。

## 证据保留

history/、docs/imported/、matlab/保留原始身份；修改前哈希及本轮V1/V2冻结、资源申请、准入与实际结果分别留档。原入口见[接管任务书](docs/PROJECT_SPEC_ZH.md)、[迁移记录](docs/MIGRATION_STATUS_ZH.md)、[硬件规范](docs/RTL_HARDWARE_DESIGN_STANDARD_ZH.md)。

资源收口：总管家已于2026-09-17 19:44:55 CEST归还窗口，旧V1/V2 grant失效；本轮交付完成，不再启动EDA。

本轮最终交付：[四模块及604点回环接入包](delivery/Sync_DDR_LabVIEW_Roundtrip_604_20260917.zip)，[离线图文教程](docs/tutorial/LABVIEW_ZERO_TO_ROUNDTRIP_ZH.html)。资源已于21:19:18 CEST正式归还，旧grant均不可复用；后续仅交付整理。
