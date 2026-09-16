# Sync OTA：完整同步链路开发入口

目标：Sync_OTA.xpr / sync_ota_top，Vivado2021.1，xcvu11p-flgb2104-2-e。当前处于真实RTL集成阶段，完整工程与DCP尚未生成。

- [冻结任务书](docs/PROJECT_SPEC_ZH.md)
- [统一存储生命周期、坐标和时钟合同](docs/architecture/ARCHITECTURE_A01_ZH.md)
- [最新实现进度A03](docs/architecture/IMPLEMENTATION_A03_ZH.md)：完整CFO链RTL与正式SFO参数发布已写出，主OTA调度仍待连接。
- [OTA001限定验收](reports/OTA001/ASTRA_REVIEW_ZH.md)：store PASS；descriptor PASS_WITH_TB_WARNING；资源已归还，成功计算不重跑。
- [OTA002冻结短检查](docs/jobs/OTA002_ZH.md)：实际descriptor/CDC、4×74观测、真实CFO树展开/取消控制；等待新的具体资源准入。
- [基线源身份](docs/provenance/BASELINE_SOURCE_LOCK.json)与[OTA002支持源身份](docs/provenance/OTA002_REUSED_INPUTS.json)。原三工程保持只读，Frontend/SFO厂商IP完整闭合待完成。

生产新增部件在rtl/buffer、rtl/control、rtl/common及rtl/cfo/ota_cfo_chain.sv。两级SFO上下文发布修改仅位于本工程rtl/sfo副本。对应测试在sim/tb；NI外存响应模型与修订的XPM仿真断言只在sim源集，官方XPM原件用于综合。

有限离线回放统一DDR区域先保存RAW，再在最后raw读者退出后复用于粗CFO整帧；SFO原内部bank保持所有权。两次CFO旋转各自保留S16舍入饱和。NI提供125/150/500MHz时钟和DDR物理控制器，RTL提供事务口；不生成CLIP XML/NI工程，不推云端。

剩余交付：完整OTA控制/外存桥/前端与SFO连接及离线服务预算，真实核心IP/XPR/约束，必要实际IQ分段验证，核心综合/DCP，独立明文VHDL Wrapper和完整Host/Target上板资料。没有整链PASS、持续吞吐或板测通过结论。
