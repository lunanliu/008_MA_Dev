# Sync OTA：完整同步链路开发入口

目标：Sync_OTA.xpr / sync_ota_top，Vivado2021.1，xcvu11p-flgb2104-2-e。当前处于真实RTL集成阶段，完整工程与DCP尚未生成。

- [冻结任务书](docs/PROJECT_SPEC_ZH.md)
- [统一存储生命周期、坐标和时钟合同](docs/architecture/ARCHITECTURE_A01_ZH.md)
- [最新实现进度A05](docs/architecture/IMPLEMENTATION_A05_ZH.md)：主OTA调度、DDR桥、真实三段核心连接及45个厂商IP配置已写入，尚待完整原生工程验证。
- [OTA001限定验收](reports/OTA001/ASTRA_REVIEW_ZH.md)：store PASS；descriptor PASS_WITH_TB_WARNING；资源已归还，成功计算不重跑。
- [OTA002限定接收](reports/OTA002/ASTRA_REVIEW_ZH.md)：三阶段冻结功能范围PASS，backend74历史进程树缺口保留；资源已归还。
- [基线源身份](docs/provenance/BASELINE_SOURCE_LOCK.json)与[OTA002支持源身份](docs/provenance/OTA002_REUSED_INPUTS.json)。原三工程保持只读，厂商IP来源与移植差异见[IP源锁](docs/provenance/OTA_IP_SOURCE_LOCK.json)。

生产新增部件在rtl/buffer、rtl/control、rtl/common及rtl/cfo/ota_cfo_chain.sv。两级SFO上下文发布修改仅位于本工程rtl/sfo副本。对应测试在sim/tb；NI外存响应模型与修订的XPM仿真断言只在sim源集，官方XPM原件用于综合。

有限离线回放统一DDR区域先保存RAW，再在最后raw读者退出后复用于粗CFO整帧；SFO原内部bank保持所有权。两次CFO旋转各自保留S16舍入饱和。NI提供125/150/500MHz时钟和DDR物理控制器，RTL提供事务口；不生成CLIP XML/NI工程，不推云端。

剩余交付：新连接原生验证、真实核心XPR/约束，必要实际IQ分段验证，核心综合/DCP，独立明文VHDL Wrapper和完整Host/Target上板资料。没有整链PASS、持续吞吐或板测通过结论。

- [OTA003限定接收](reports/OTA003/ASTRA_REVIEW_ZH.md)：三项专项通过，资源已归还。
- [独立VHDL Wrapper](wrapper/sync_ota_wrapper.vhd)与[完整端口合同](docs/PORTS_AND_RECORDS_ZH.md)：75个核心端口/111个Wrapper端口，等待原生语法核验。
- [OTA004/A04冻结包](docs/jobs/OTA004_A04_ZH.md)：补齐三份已发布SFO头文件及工程依赖审计，完整真实工程/短冒烟/一次核心综合仍待新具体资源授权。A01/A02未准入；A03 prepare因XCI移植元数据损坏与TSV尾空列解析失败，旧grant已归还；A04只修复未完成阶段，旧输入与失败证据保留，12GiB仍只告警。
