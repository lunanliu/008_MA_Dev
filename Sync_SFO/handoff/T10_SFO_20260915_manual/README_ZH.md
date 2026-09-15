# T10 SFO 手工交付入口

交付日期2026-09-15。用于用户LabVIEW 2026Q1 / PXIe-7903工程；核心器件xcvu11p-flgb2104-2-e，源工具Vivado 2021.1。

**本次手工交付静态收尾已完成。** 已核对149个项目文件的指纹、XPR明确声明的120项依赖、37个核心端口与102个Wrapper端口，以及输入/参考文件的格式和内容。文件夹本身就是交付件，完整复制即可。

**已整理完整核心GUI工程副本、独立明文VHDL Wrapper、冻结输入/预期输出、全部端口和Host操作说明。** 核心37端口全部对应，Wrapper拆为102个标量或8/16/32位端口，仅做组合连线。

| 目的 | 推荐入口 |
|---|---|
| 打开核心工程 | [T10_SFO.xpr](core_project/vivado/T10_SFO/T10_SFO.xpr) |
| 查看独立封装 | [t10_sfo_manual_wrapper.vhd](wrapper/t10_sfo_manual_wrapper.vhd) |
| 综合、导出及搬迁 | [Vivado手工操作](docs/VIVADO_HANDOFF_ZH.md) |
| 接线和调试字段 | [全部接口说明](docs/INTERFACE_ZH.md) · [端口CSV](wrapper/ports.csv) |
| 数据装载、DDR回放、读回比较 | [Host测试操作](docs/HOST_TEST_ZH.md) |
| 全部输入设值 | [case6001_settings.json](data/case6001_settings.json) |
| 数据文件与指纹 | [data_manifest.json](data/data_manifest.json) |
| 全部交付文件 | [FILE_MANIFEST.csv](FILE_MANIFEST.csv) |
| 静态核对结果 | [STATIC_CHECKS.json](evidence/STATIC_CHECKS.json) |
| 已通过的完整帧证据 | [独立复核报告](evidence/T10_RUN03_INDEPENDENT_REVIEW_20260915_ZH.md) · [JSON](evidence/T10_RUN03_INDEPENDENT_REVIEW_20260915.json) |

## 已验证内容

冻结case6001：无噪声单径、工程SFO −150 ppm、CFO +100 kHz、精定时0。真实T06→E1→真实T09→E2输出完整1,336,320点，8,321,168个I/Q分量比较最大0 LSB，74个估计点一致，148个FFT窗口满足原门槛。CFO/fine/描述符是外部边界输入，不包含前端自主捕获。

核心top始终为t10_two_pass_system，OUTPUT_CLOCK_MHZ保持150；仿真top为t10_full023_tb。Wrapper不加入该核心工程，不取代综合top。用户需要网表时在副本中手动OOC综合核心，再与独立Wrapper用于NI集成。

本包复制批准的144项输入，另附来源记录和历史约束，共149项项目文件。IP生成输出由远程工具从34个冻结XCI建立；四个FIR系数内嵌。整个文件夹一起转移，保持core_project相对结构，不依赖旧work或原机缓存构建。

## 平台边界

必须外部提供125/150/500 MHz时钟；Wrapper不能从一个150 MHz输入自动生成其它时钟。125 MHz处理输入/配置，150 MHz处理输出，500 MHz送FFT服务。平台时钟、锁定复位、CLIP时钟声明、VI与DDR/DMA跨域连接由用户完成。

DMA端点、DDR地址、配置寄存器、快照和LabVIEW VI均待用户创建，操作说明给的是接线约定。本轮未运行新综合、仿真或NI编译，没有生成新的DCP/EDIF、CLIP XML或LabVIEW工程。

静态核对不替代混合语言编译/网表绑定；单帧行为通过不代表FLGB实现时序、持续500 MS/s、多帧、扩展背压或板测通过。副本内旧报告保留原路径与状态用于追溯；本README及其手工说明是当前交付入口。
