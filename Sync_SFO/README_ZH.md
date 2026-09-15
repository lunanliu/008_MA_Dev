# Sync_SFO：两级采样频偏估计与补偿

唯一日常 GUI 入口：[Sync_SFO.xpr](Sync_SFO.xpr)。Vivado 2021.1，器件 `xcvu11p-flgb2104-2-e`，综合顶层 `sync_sfo_top`，仿真顶层 `sync_sfo_full_frame_tb`。核心 `OUTPUT_CLOCK_MHZ=150` 保持不变。

| 交付内容 | 入口 |
|---|---|
| 完整核心工程与功能分区 | [工程](Sync_SFO.xpr) · [74 个核心源列表](rtl/sources.f) · [功能/名称映射](docs/functional_review_20260915/NAME_MAPPING_ZH.md) |
| 独立明文 VHDL Wrapper | [sync_sfo_manual_wrapper.vhd](wrapper/sync_sfo_manual_wrapper.vhd) · [102 个端口](wrapper/ports.csv) · [接口合同](wrapper/interface_contract.json) |
| 手工 CLIP、时钟、前端接口及测试步骤 | [当前交付指南](docs/SFO_SYNC_MODULE_GUI_ZH.md) |
| 输入设值、波形及预期输出 | [case6001 设值](handoff/T10_SFO_20260915_manual/data/case6001_settings.json) · [文件哈希和来源](handoff/T10_SFO_20260915_manual/data/data_manifest.json) |
| MATLAB 来源 | [参考入口](matlab/README_ZH.md) |
| 已有整帧行为证据 | [RUN03 独立复核](handoff/T10_SFO_20260915_manual/evidence/T10_RUN03_INDEPENDENT_REVIEW_20260915_ZH.md) |
| 本次变更证据 | [验证状态](docs/functional_review_20260915/REVIEW_STATUS_ZH.md) |

## 处理顺序

原始 I/Q、帧描述及 TO/CFO 记录 → 首次 SFO 估计 → 第一次重采样 → 残余 SFO 估计 → 第二次重采样 → 补偿后 I/Q 和元数据。包含原始环形缓存、中间 bank、输出缓冲和内部跨时钟通道。

本次从 V5_Final `dd5e8f7a642625f06c4996d17e3642bbadc7d557` 整理功能命名、端口声明和排版。74 个自有核心 RTL、2 个测试文件及 3 个头文件通过名称还原后的词法、语法结构和端口一致性检查；厂商 IP 名称、34 个 XCI、生成源码和算法保持。Wrapper 独立存放，不加入核心综合源集。

## 使用边界

输入/控制为 125 MHz，重采样和当前输出为 150 MHz，FFT 服务使用 500 MHz。时钟源、锁定顺序、DDR/DMA 和平台 CDC 由用户的 NI 工程负责；Wrapper 仅拼接和拆分位段。前端 288 位记录尚需适配，上层还须保留并回放完整原始波形。

`handoff/T10_SFO_20260915_manual`、`archive` 和旧 `vivado/T10_SFO*` 保留历史身份。历史包中的旧名字用于追溯；当前操作以本页及根 XPR 为准。已有 case6001 行为证据不等于实现时序、持续吞吐、NI 全目标编译或板测通过。本轮不生成 CLIP XML、配置包或 LabVIEW 工程；原生验证进度见验证状态页。
