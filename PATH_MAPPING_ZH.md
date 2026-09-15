# 旧新路径映射（2026-09-15）

根目录 D:/008_MA_Dev。旧 D:/007 Dev/OTA_RTL_0829 中央工作区保持原位，本任务未修改其状态或绑定。

| 原路径 | 当前路径 | 原件归档 |
|---|---|---|
| `constraints` | [Sync_SFO/constraints](Sync_SFO/constraints) | `Sync_SFO/archive/pre_reorganization_root/constraints` |
| `docs` | [Sync_SFO/docs](Sync_SFO/docs) | `Sync_SFO/archive/pre_reorganization_root/docs` |
| `handoff` | [Sync_SFO/handoff](Sync_SFO/handoff) | `Sync_SFO/archive/pre_reorganization_root/handoff` |
| `ip` | [Sync_SFO/ip](Sync_SFO/ip) | `Sync_SFO/archive/pre_reorganization_root/ip` |
| `matlab` | [Sync_SFO/matlab](Sync_SFO/matlab) | `Sync_SFO/archive/pre_reorganization_root/matlab` |
| `rtl` | [Sync_SFO/rtl](Sync_SFO/rtl) | `Sync_SFO/archive/pre_reorganization_root/rtl` |
| `sim` | [Sync_SFO/sim](Sync_SFO/sim) | `Sync_SFO/archive/pre_reorganization_root/sim` |
| `tools` | [Sync_SFO/tools](Sync_SFO/tools) | `Sync_SFO/archive/pre_reorganization_root/tools` |
| `vivado` | [Sync_SFO/vivado](Sync_SFO/vivado) | `Sync_SFO/archive/pre_reorganization_root/vivado` |
| `work` | [Sync_SFO/work](Sync_SFO/work) | `Sync_SFO/archive/pre_reorganization_root/work` |
| `T11_CFO` | [Sync_CFO](Sync_CFO) | `Sync_CFO/archive/pre_reorganization_T11_CFO` |
| `I16_AddSub_CLIP` | [Sync_Frontend/examples/I16_AddSub_CLIP](Sync_Frontend/examples/I16_AddSub_CLIP) | `Sync_Frontend/examples/archive/I16_AddSub_CLIP` |
| `I16_AddSub_CLIP_Source_Project.zip` | [Sync_Frontend/examples/I16_AddSub_CLIP_Source_Project.zip](Sync_Frontend/examples/I16_AddSub_CLIP_Source_Project.zip) | `Sync_Frontend/examples/archive/I16_AddSub_CLIP_Source_Project.zip` |

## 日常主入口

- 原 T10 手工包核心入口 → [Sync_SFO/Sync_SFO.xpr](Sync_SFO/Sync_SFO.xpr)；原包在 [Sync_SFO/handoff](Sync_SFO/handoff)。
- 原前端 vivado/Sync_Frontend/Sync_Frontend.xpr → [Sync_Frontend/Sync_Frontend.xpr](Sync_Frontend/Sync_Frontend.xpr)。旧 GUI 与工程原位保留；新入口来自已保存磁盘版本，未保存编辑需由用户保存后另行比较。
- T11_CFO/vivado/阶段/阶段.xpr → Sync_CFO/vivado/阶段/阶段.xpr；[九个阶段名单](Sync_CFO/README_ZH.md)，完整链顶层尚未交付。
- 原 I16 示例 → [Sync_Frontend/examples/I16_AddSub_CLIP/I16_AddSub.xpr](Sync_Frontend/examples/I16_AddSub_CLIP/I16_AddSub.xpr)。独立 Git 与原未提交修改保留，不加入生产核心。
- 原性能工具 → [Sync_SFO/tools/vivado/configure_parallel_jobs.tcl](Sync_SFO/tools/vivado/configure_parallel_jobs.tcl)。

总管家可据此更新中央绑定中的路径，不能因目录更新恢复已停实验、转发受阻交接或改写历史 source lock。原报告保留旧路径和实验身份，通过本表定位当前副本及归档原件。

根 README、AGENTS 和 .gitignore 的既有内容完整保留，仅追加入口补充。原 T10 XPR 的既有未提交修改仍在 Sync_SFO/vivado/T10_SFO/T10_SFO.xpr；本轮提交只纳入可审阅的结构和导航差异。
