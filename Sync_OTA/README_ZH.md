# Sync OTA：完整同步链路开发入口

目标：Sync_OTA.xpr / sync_ota_top，Vivado2021.1，xcvu11p-flgb2104-2-e。当前处于真实RTL集成阶段，完整工程与DCP尚未生成。

- [冻结任务书](docs/PROJECT_SPEC_ZH.md)
- [首版处理顺序、存储生命周期、正式握手和时钟合同](docs/architecture/ARCHITECTURE_A01_ZH.md)
- [首批原生短检查OTA001](docs/jobs/OTA001_ZH.md)
- [已复制源身份](docs/provenance/BASELINE_SOURCE_LOCK.json)：准确RTL及CFO ROM135项，原三工程只读；厂商IP支持闭合待完成。
- 新部件：rtl/buffer/ota_frame_store.sv；rtl/control/ota_frontend_descriptor.sv。对应短TB在sim/tb，仅测试NI事务服务使用模型。

首版有限离线回放：统一DDR区域先保存RAW，再在最后raw读者退出后重用于粗CFO整帧；SFO原内部bank保持原所有权。两次CFO旋转各自S16舍入饱和。时钟125/150/500MHz由NI提供，DDR物理控制器由NI拥有。

下一步：OTA001短检查；正式SFO实际参数发布；完整CFO窗口/估计/双旋转连接及必要复位CDC；完整核心工程、短片段/74观测和核心综合；独立VHDL及Host/Target手工上板资料。没有宣布整链PASS、持续吞吐或板测通过。不生成CLIP XML/NI工程，不推云端。
