# Sync OTA：完整同步链路开发入口

目标：Sync_OTA.xpr / sync_ota_top，Vivado2021.1，xcvu11p-flgb2104-2-e。A06R1真实短测严格通过、核心综合成功；Gray报告适配和真实综合时序仍待修复，尚未完成上板交付。按用户最新要求，A06R3重新验证原Gray/CDC与关键时序路径功能，允许原Luna执行自修并完整交回；旧R2和未执行I1保留历史。新作业已静态就绪，按用户最新要求由原 Luna 先取得真实本地报告和严格检查结果；此前磁盘准入因具体派单被工具拒绝已由总管家撤回，当前没有可用原生准入；已通知原Luna停止新启动，保留本地准备。安全审批和科学门槛保持，既有消息拒绝不重试。

- [冻结任务书](docs/PROJECT_SPEC_ZH.md)
- [统一存储生命周期、坐标和时钟合同](docs/architecture/ARCHITECTURE_A01_ZH.md)
- [最新实现进度A05](docs/architecture/IMPLEMENTATION_A05_ZH.md)：主OTA调度、DDR桥、真实三段核心连接及45个厂商IP配置已写入，尚待完整原生工程验证。
- [OTA001限定验收](reports/OTA001/ASTRA_REVIEW_ZH.md)：store PASS；descriptor PASS_WITH_TB_WARNING；资源已归还，成功计算不重跑。
- [OTA002限定接收](reports/OTA002/ASTRA_REVIEW_ZH.md)：三阶段冻结功能范围PASS，backend74历史进程树缺口保留；资源已归还。
- [基线源身份](docs/provenance/BASELINE_SOURCE_LOCK.json)与[OTA002支持源身份](docs/provenance/OTA002_REUSED_INPUTS.json)。原三工程保持只读，厂商IP来源与移植差异见[IP源锁](docs/provenance/OTA_IP_SOURCE_LOCK.json)。

生产新增部件在rtl/buffer、rtl/control、rtl/common及rtl/cfo/ota_cfo_chain.sv。两级SFO上下文发布修改仅位于本工程rtl/sfo副本。对应测试在sim/tb；NI外存响应模型与修订的XPM仿真断言只在sim源集，官方XPM原件用于综合。

有限离线回放统一DDR区域先保存RAW，再在最后raw读者退出后复用于粗CFO整帧；SFO原内部bank保持所有权。两次CFO旋转各自保留S16舍入饱和。NI提供125/150/500MHz时钟和DDR物理控制器，RTL提供事务口；不生成CLIP XML/NI工程，不推云端。

剩余交付：A06R3原报告功能验证、真实时序最小RTL修复及受影响短验证/更新核心综合、稳定GUI工程依赖封装，以及上板波形、预期记录/比较脚本和Host/Target资料。独立VHDL Wrapper和端口表已具备。实现时序、持续吞吐和板测仍未验证。

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
