# T10 独立 Vivado 工程迁移最终复核

2026-09-14，T10 Astra 独立复核。**工程创建、同版 IP 器件迁移和关闭后重新打开的范围通过；T10 全帧功能尚未通过验收。**

可打开的工程是 `vivado/T10_SFO/T10_SFO.xpr`，器件为 `xcvu11p-flgb2104-2-e`。硬件顶层为 `t10_two_pass_system`，行为仿真顶层为 `t10_full023_tb`。

| 核对内容 | 实际证据与结论 |
|---|---|
| 核心与输入 | 74 份核心 RTL 包含在 88 项冻结输入中，指纹均未改变。 |
| IP 参数 | 34 个 IP 保持相同 IPDEF；1,071 项用户参数在迁移前、迁移后、重新打开后完全一致。 |
| 迁移变化 | 34 个封装字段由 FLGC 改为 FLGB；两个 FFT 的 C_PART 同步更正；主 FFT 的首选 HDL 从 VHDL 变为 Verilog。算法参数和其余模型参数没有变化。 |
| 工程路径 | 120 个活动文件引用和两个 include 目录均相对工程目录，解析后全部位于新根目录且存在。 |
| 活动 IP 来源 | XPR 引用集合与 `ip/config/` 的 34 份 XCI 完全一致；MATLAB 中单独保留的历史 XCI 没有参与工程。 |
| 原生操作 | Vivado 2021.1 完成一次创建、原生迁移、关闭及重新打开检查；用时 48.942 秒。 |
| 范围 | 没有运行仿真、综合或实现。原生迁移自动生成了 34 份 VEO、34 份 VHO 实例模板与 34 份 XML 元数据，未生成完整 HDL/MIF/DCP 输出。 |

## 为什么退出码仍是 1

原生检查完成后，一次性 Tcl 在写最终 JSON 报告时少了一个左花括号，导致报告缺少外层括号，随后出现 `invalid command name "}"`。因此，**原始执行退出码 1 必须保留**，不能把它改成 0。

本次依据此前已经完整写出的参数 CSV、工程文件清单、IP 清单和重新打开日志，另存有效的恢复回执。修正后的 `puts` 语句与 `catch` 结构已在独立 Tcl 8.6.12 解释器中实际执行并成功解析 JSON；这项检查没有启动 Vivado。没有重做已完成的原生迁移。

旧冻结入口保留为失败证据，日常使用工程文件和 `tools/vivado/` 原生入口。原始退出记录证明本次自有进程组已归零，没有超时，也没有操作用户原有的 Vivado GUI 进程。

## 通过结论的边界

这次通过说明：指定核心和 IP 已在新器件工程中建立了可追溯的对应关系，且原生重新打开检查成功。它不能证明全帧数据正确、时序收敛、吞吐达标或板上运行正确。本次也没有实际操作 GUI 窗口或把目录搬到另一位置再打开；XPR 顶部仍保留创建位置的绝对路径元数据，活动源文件和 include 使用相对引用。

## 证据入口

- [最终机器可读结论](ASTRA_FINAL_REVIEW.json)
- [独立源文件、参数及路径审查](astra_review/IDENTITY_REVIEW_DRAFT.json)
- [真实 Tcl 报告语句检查](astra_review/TCL_ACTUAL_REPAIR_CHECK.json)
- [持久保存的原生证据清单](astra_review/native_evidence/MANIFEST.json)
- [Luna 离线恢复复核](astra_review/native_evidence/luna_review_summary.json)

`astra_review/native_evidence/` 保留原始日志、退出码、CSV、损坏的原始报告和另存的恢复报告，避免临时工作目录成为唯一证据来源。
