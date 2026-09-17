# 原始证据的阅读边界
本目录只作溯源，不加入 CLIP 的 ImplementationList。实际导入仅使用 ../clip/sync_frontend_clip.xml。
original_synthesis 是原算法顶层综合 DCP，含独立工程时钟/输出预算，原样保留；clip 中的 DCP 是同次综合网表的 OOC 重导出版本，已独立重开，不包含 wrapper。
core_dcp_check/native_vivado.log 在 CORE 与 SAVED_DCP 阶段通过；随后额外 wrapper 手工回填失败。必须保留整个失败，不把此日志称为整份检查 PASS。该额外诊断已撤回为交付门槛。
reviews 中 Luna 原始报告保持原样；其断言、DRC等级、重试顺序等修正见 SF003_ASTRA_REVIEW_ZH.md。
physical 是历史独立实现：WNS2.087ns、WHS0.024ns、TNS/THS0、5BUFG；133个同步输入漏 input delay，reset_n另计1个异步输入。时序只覆盖已约束路径，不代表本包/NI整体接口时序通过。
provenance/check_dcp_release_HISTORICAL_NOT_AN_ENTRYPOINT.tcl 是历史冻结脚本，不是本包执行入口，不要运行以生成 wrapper 顶层 DCP。
