# 当前工程入口（2026-09-15 整理）

日常打开 [Sync_Frontend.xpr](Sync_Frontend.xpr)。[路径与 GUI 保留说明](docs/DIRECTORY_ENTRY_20260915_ZH.md) · [独立 Wrapper](wrapper/sync_frontend_clip.vhd) · [I16 示例](examples/README_ZH.md)。原 GUI 工程保留原位，以下历史说明保持来源身份。

---

# Sync_Frontend 自主同步前端
用户最新交付范围（2026-09-15）：仅交付完整 Vivado 核心 RTL 工程（top=sync_frontend_top）、独立明文 VHDL wrapper、可复现输入/预期输出及中文手工操作说明。CLIP XML 与 LabVIEW CLIP 配置由用户亲自创建；Agent 不新增/生成/修补 XML，不创建 LabVIEW 项目，不做 wrapper 回填或独立 wrapper 网表验证，不为交付重跑冻结实验。

**手工操作从这里开始：[把同步前端接入 LabVIEW：从选文件到读回四帧结果](D:/008_MA_Dev/Sync_Frontend/handoff/Sync_Frontend_20260915_manual/README_ZH.md)。** 新版按选文件、CLIP 向导、32 个端口设置、FPGA VI 接线和 Host 回放的顺序说明。
- 完整工程：vivado/Sync_Frontend/Sync_Frontend.xpr；top=sync_frontend_top；xcvu11p-flgb2104-2-e；Vivado2021.1。
- 独立VHDL：handoff/Sync_Frontend_20260915_manual/sync_frontend_clip.vhd。
- 输入/预期：同交接目录input/及expected/；逐端口：PORT_SETTINGS_ZH.md。
- 架构和技术历史参考：docs/LABVIEW_TARGET_INTEGRATION_ZH.md；首次接线以上述逐步指南为准。
- 已完成：SF001基座迁移、SF002四帧自主捕获限定短测试、SF003核心综合；原独立实现仅覆盖已约束路径。NI整体编译/接口时序/板测/持续吞吐尚未验收。
- MATLAB入口：matlab/waveform/load_frontend_waveform.m、matlab/golden/frontend_reference_catalog.m、matlab/comparison/compare_frontend_readback.m；新增包装未原生执行。
- Python读回比较：tools/compare_readback.py。
旧release rev01和未完成rev02保留历史；自动XML打包及wrapper回填已停止，旧包不是最终使用入口。历史失败不能改为通过，也不能据此认定NI不支持核心DCP。
本地Git无remote；旧工程/T10/T11只读；本轮不启动、打断或重跑冻结实验。
