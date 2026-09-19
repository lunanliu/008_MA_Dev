> **2026-09-19：500 MS/s版本封存。** 保持125/150/500 MHz，未实现400 MS/s配置。此前常规时序已通过，20%余量尚未通过；新margin20实现结果待完成。当前身份及证据边界见 [封存说明](docs/v51/ARCHIVE_500MSPS_20260919_ZH.md)。以下旧阶段记录按各自日期解释。

> **2026-09-18最新：20%余量RTL重构已完成静态交付。** 27份活动RTL修改、129份选源一致、顶层绑定0错误；新物理时序尚未验收。125/150/500MHz普通同域目标为+1.600/+1.333333334/+0.400ns，CDC按实际约束20%。[本轮设计、预算及手动实现入口](docs/v51/TIMING_MARGIN20_DESIGN_ZH.md)。以下旧快照仅保留历史身份。

> **2026-09-18 最新：CFO 系数 ROM 方案 A 已应用。** 前一轮17:48 CEST布线报告已收敛至1条500 MHz违例（−0.057 ns）；本次采用零增拍分页及局部读命令寄存，60680项系数零差异，静态绑定0错误。**分页新版尚未综合、实现或仿真，不宣称时序已经通过。** 见[修改、周期、缓存与GUI运行说明](docs/v51/CFO_COEFFICIENT_ROM_PLAN_A_ZH.md)及[前一轮报告复核](reports/v51/routed_review_20260918_1748/REVIEW_ZH.md)。

> 以下保留此前冻结记录。第二轮9份RTL整改及3336端点归因见[历史整改报告](docs/v51/ROUTED_REDESIGN_20260918_ZH.md)；其中“未运行”描述的是该记录发布时状态。

# Sync OTA：完整同步链路开发入口

> 2026-09-18后续更新：用户GUI原生综合在XPM参数类型展开处失败；两个自有封装已作最小兼容修复，尚未重跑原生综合。见[根因、修复与证据](docs/v51/XPM_PARAMETER_COMPATIBILITY_FIX_ZH.md)。下文静态审查与NOT_RUN状态是此前冻结快照，不代表这次原生综合通过。

当前工作分支为 **V5.1_System_Modify**，生产入口 [Sync_OTA.xpr](Sync_OTA.xpr)，top `sync_ota_top`，实际选源 [sources_v51.f](rtl/sources_v51.f)。本轮已接入共享raw环、训练回读、SFO逐窗供数、CFO片内双bank及**最终无背压输出**。最终端口没有ready或中间DDR事务；Target VI接受每个150MHz valid拍。

- [本轮静态交付：架构、周期、缓存、数值与分层资源/时序](docs/v51/STATIC_DELIVERY_ZH.md)
- [设计选择与备选方案](docs/v51/REFACTOR_DESIGN_ZH.md)
- [46端口与Target VI合同](docs/v51/INTERFACE_CONTRACT_ZH.md)、[独立VHDL Wrapper](wrapper/sync_ota_wrapper.vhd)
- [FPGA工程师 agents.md](<FPGA工程师 agents.md>)

129 RTL、3 XPM、45 IP的选源与全工程静态覆盖已完成；实际生产语法与绑定0错误，警告保留。SFO两份和CFO四份算术补丁已获明确批准并应用，输入/IP合同下多帧预算闭合。**未启动仿真/综合/实现；不宣称新版数值、实测持续吞吐或物理时序通过。** 当前证据为reports/v51/full_static_20260918与static_binding_07。 sim_1没有获准的新测试台，旧A06测试台从该源集移出但文件保留。旧DCP/报告均有旧身份。

---

## 历史A07及此前记录（下文不描述当前生产源集/端口）


当前工作版本为 A07 静态设计整改版；唯一工程入口 [Sync_OTA.xpr](Sync_OTA.xpr)，真实算法顶层 **sync_ota_top**，Vivado 2021.1，器件 xcvu11p-flgb2104-2-e。保持现有功能目录和 RTL 层级；[统一设计复盘、整改与剩余隐患](docs/SYNC_OTA_REMAINING_20260917_ZH.md)为本轮主入口。**本轮测试暂停，新版尚未编译、仿真或综合，不按旧DCP宣称新版通过。**

在 Vivado 中打开根目录 Sync_OTA.xpr，在 Sources → Hierarchy → Design Sources 下展开 sync_ota_top，即可按 frontend、sfo、cfo、control、ddr 等实例查看完整设计源。生产选源为 [rtl/sources_a07.f](rtl/sources_a07.f)，同名历史版本保留在原目录但不同时加入工程。sim_1只存历史测试台；Wrapper是用户手工NI集成入口，生产top仍为算法核心。查看本轮代码应选择RTL源层级，旧综合结果属于A06。

A07主要改动：完整CFO估计结果寄存及等价阈值比较、CFO两槽弹性入口、500 MHz索引/ROM地址分拍，以及会话恢复/取消边界修正。有限离线帧与持续500 MS/s目标分开；当前单信用DDR和串行会话架构不满足持续流。

当前完整帧输入合同：capture_words为334215..524288个128位字；小于下界在start时以错误10提前拒绝，具体检测位置和尾部保护仍继续核查。旧端口文档/短smoke的过短负路径属于历史版本。

- [冻结任务书](docs/PROJECT_SPEC_ZH.md)
- [统一存储生命周期、坐标和时钟合同](docs/architecture/ARCHITECTURE_A01_ZH.md)
- [历史实现进度A05](docs/architecture/IMPLEMENTATION_A05_ZH.md)：主OTA调度、DDR桥、真实三段核心连接及45个厂商IP配置已写入，尚待完整原生工程验证。
- [OTA001限定验收](reports/OTA001/ASTRA_REVIEW_ZH.md)：store PASS；descriptor PASS_WITH_TB_WARNING；资源已归还，成功计算不重跑。
- [OTA002限定接收](reports/OTA002/ASTRA_REVIEW_ZH.md)：三阶段冻结功能范围PASS，backend74历史进程树缺口保留；资源已归还。
- [基线源身份](docs/provenance/BASELINE_SOURCE_LOCK.json)与[OTA002支持源身份](docs/provenance/OTA002_REUSED_INPUTS.json)。原三工程保持只读，厂商IP来源与移植差异见[IP源锁](docs/provenance/OTA_IP_SOURCE_LOCK.json)。

生产集成部件位于rtl/buffer、rtl/control、rtl/common及rtl/cfo；实际版本以根XPR和sources_a07.f为准。两级SFO上下文发布修改仅位于本工程rtl/sfo副本。对应测试在sim/tb；NI外存响应模型与修订的XPM仿真断言只在sim源集，官方XPM原件用于综合。

有限离线回放统一DDR区域先保存RAW，再在最后raw读者退出后复用于粗CFO整帧；SFO原内部bank保持所有权。两次CFO旋转各自保留S16舍入饱和。NI提供125/150/500MHz时钟和DDR物理控制器，RTL提供事务口；不生成CLIP XML/NI工程，不推云端。

剩余交付：根据本轮设计复盘由用户安排受影响验证；新版本编译/GUI展开、时序和CDC复核、NI集成与板测保持未验证。完整依赖当前在同一工程内，既有IP生成物与失败现场保留。独立VHDL Wrapper和端口表沿用；连续流若作为下一阶段目标，需要先完成DDR访问与多会话架构调整。

- [OTA003限定接收](reports/OTA003/ASTRA_REVIEW_ZH.md)：三项专项通过，资源已归还。
- [独立VHDL Wrapper](wrapper/sync_ota_wrapper.vhd)与[完整端口合同](docs/PORTS_AND_RECORDS_ZH.md)：75个核心端口/111个Wrapper端口，A04原生VHDL语法通过；A05接口保持不变。
- [OTA004/A04阶段复核](reports/OTA004/A04_STAGE_REVIEW.json)：准备阶段限定通过（45 IP、4 MIF、Wrapper）；smoke有18条运行期XPM复位错误，未通过且未启动综合。资源已归还，成功准备不重跑。
- [OTA004/A05冻结包](docs/jobs/OTA004_A05_ZH.md)：同一短smoke严格通过，核心OOC综合完成；成功结果保留，CDC风险与时序边界见下方独立复核，旧槽已归还。

- [A05完整核心综合复核](reports/OTA004/A05_SYNTH_ASTRA_REVIEW_ZH.md)：0黑盒、DCP/EDIF完整；LUT 23.70%、URAM 57.50%、DSP 22.23%。综合WNS -2.357ns，CDC风险需修，非时序或板测通过。
- [A06最小CDC修订冻结包](docs/jobs/OTA004_A06_ZH.md)：4份RTL与同一短TB的定向扩充、单一官方XPM综合注册、绝对截止监管；285项锁定输入含45个已成功IP DCP。无新时间/资源准入，不能复用A05旧grant。

- [A06R1脚本修订冻结包](docs/jobs/OTA004_A06R1_ZH.md)：严格启动参数、45 IP完成且NEEDS_REFRESH=false、CDC摘要/明细闭合、24个Gray宏逐位有效约束。原A06 285项和A05 216项输入未变；离线检查不代替原生验证，仍待总管家新grant。

- [A06R1静态接收与时序边界](reports/OTA004/A06R1_ASTRA_STATIC_REVIEW_20260917.json)：成功smoke/core保留，完整进程树已关闭；150/500MHz综合时序仍失败。
- [A06R2报告恢复冻结包](docs/jobs/OTA004_A06R2_ZH.md)：只读已有DCP，严格保留scope与C/D pin证据，24宏/128位Gray审计以及最多116条有界时序路径；不重跑成功smoke/IP/核心。

- [A06R3新验证任务](docs/jobs/OTA004_A06R3_ZH.md)：科学输入与执行修订分开；各报告阶段独立留证；完整、部分及失败回执均先接收再科学复核。[通信实际状态](reports/OTA004/A06R3_COMMUNICATION_PREFLIGHT.json)。

- [本次 A06R3 执行补充](docs/jobs/OTA004_A06R3_CONTINUATION_ZH.md)与[剩余设计/验证/交付清单](docs/SYNC_OTA_REMAINING_20260917_ZH.md)：本地报告、科学验收、消息审批分别记录；普通执行修复保留版本与成功阶段。

- [A06R3本轮接收和离线复核](reports/OTA004/A06R3_ASTRA_REVIEW_ZH.md)：完整回传成功，证据已核验；原总闸失败不改写，进入A07真实时序修复准备。
