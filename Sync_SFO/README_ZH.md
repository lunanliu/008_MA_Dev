# Sync_SFO：两级采样频偏估计与补偿

本轮只整理工程入口和文件路径。唯一日常 GUI 入口：[Sync_SFO.xpr](Sync_SFO.xpr)。Vivado 2021.1，器件 `xcvu11p-flgb2104-2-e`，核心 top `t10_two_pass_system`，仿真 top `t10_full023_tb`，核心输出时钟参数保持原默认 150 MHz。

| 内容 | 位置 |
|---|---|
| 核心源码、IP、约束 | [rtl](rtl/) · [ip](ip/) · [constraints](constraints/) |
| 独立 VHDL Wrapper | [t10_sfo_manual_wrapper.vhd](wrapper/t10_sfo_manual_wrapper.vhd) · [端口表](wrapper/ports.csv) |
| 测试输入与预期输出 | [sim/data](sim/data/) · [case6001 设值](handoff/T10_SFO_20260915_manual/data/case6001_settings.json) |
| MATLAB 波形和参考模型 | [matlab/README_ZH.md](matlab/README_ZH.md) |
| Host 喂数和读回 | [手工操作](handoff/T10_SFO_20260915_manual/docs/HOST_TEST_ZH.md) |
| 前端到 SFO 的边界 | [接口对照说明](docs/SFO_SYNC_MODULE_GUI_ZH.md) |
| 完整帧已有证据 | [RUN03 独立复核](handoff/T10_SFO_20260915_manual/evidence/T10_RUN03_INDEPENDENT_REVIEW_20260915_ZH.md) |
| 路径与版本检查 | [本次整理记录](docs/reorganization_20260915/) |

新入口明确复用 2026-09-15 手工交付包的完整版本，74 核心 RTL、34 XCI、约束、测试台及数据逐字节比对；不按同名或修改时间选源。Wrapper 独立存放，不加入核心综合源集。PRE 钩子沿用既有 run_threads.tcl，general/synth 请求 8，xelab 设置 16；后续实际 jobs 仍需按资源核算。

原 `vivado/T10_SFO*` 是历史工程；`handoff/T10_SFO_20260915_manual` 保持原包及清单身份。日常操作从根 XPR 开始，历史源码、实验结果和报告不要重新解释成新实验。`archive/pre_reorganization_root` 是旧根原件保留区，不能作为新主入口的依赖。

已有 case6001 全帧行为证据不等于实现时序、持续吞吐、NI 编译或板测通过。前端联合结果到 SFO 的适配器尚未实现。本轮没有启动综合、实现、仿真或 MATLAB，没有生成新的网表、CLIP XML 或 LabVIEW 工程。
