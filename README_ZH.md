# 四工程统一仓库（2026-09-17）

用户已明确授权将 D:/008_MA_Dev 的四个现有工程一并发布到私有 GitHub 仓库 `lunanliu/008_MA_Dev`；该授权覆盖历史“仅本地、不推云端”记录。开发、仿真、综合和测试继续暂停。本次只保存、整理仓库入口及上传当前状态，不代表新增验收。

| 工程 | 首选入口 | 当前状态 |
|---|---|---|
| Sync_OTA | [Sync_OTA.xpr](Sync_OTA/Sync_OTA.xpr) · [设计复盘](Sync_OTA/docs/SYNC_OTA_REMAINING_20260917_ZH.md) | A07静态整改；新版未编译/仿真/综合，持续500 MS/s不达标 |
| Sync_Frontend | [Sync_Frontend.xpr](Sync_Frontend/Sync_Frontend.xpr) · [README](Sync_Frontend/README_ZH.md) | 自主同步前端及现有手工交付资料 |
| Sync_SFO | [Sync_SFO.xpr](Sync_SFO/Sync_SFO.xpr) · [README](Sync_SFO/README_ZH.md) | 两级SFO工程及现有数据、交付资料 |
| Sync_CFO | [README](Sync_CFO/README_ZH.md) | CFO各阶段工程；完整集成链位于Sync_OTA |

保留根仓库V5_Final的既有提交历史。前端以当前文件快照直接纳入本仓库，克隆后能取得实际RTL和工程文件，无需另拉子模块；其独立本地Git历史原位保留。版本中包含必要IP配置、系数、参考数据及现有交付证据；可重建工作目录、缓存和未纳入版本的运行现场继续留在本机，不因上传删除。

本仓库用于整体代码审查。历史文档中的工作状态、绝对本机路径及旧交付结论需结合[目录映射](PATH_MAPPING_ZH.md)与各工程当前README解释，不能将历史通过结论套到最新集成版本。旧原生入口不会因发布自动运行。

---

以下为历史入口与迁移记录，原文保留。

# 当前工程入口（2026-09-16）

| 工程 | 入口 | 当前用途 |
|---|---|---|
| Sync_OTA | [README](Sync_OTA/README_ZH.md) · [任务书](Sync_OTA/docs/PROJECT_SPEC_ZH.md) | 新授权完整同步系统，正在设计；尚未交付可用XPR或网表 |
| Sync_Frontend | [工程](Sync_Frontend/Sync_Frontend.xpr) · [README](Sync_Frontend/README_ZH.md) | 自主TO/CFO同步前端 |
| Sync_SFO | [工程](Sync_SFO/Sync_SFO.xpr) · [README](Sync_SFO/README_ZH.md) | sync_sfo_top，两级SFO |
| Sync_CFO | [阶段入口](Sync_CFO/README_ZH.md) | 已验证子核与待补全CFO链 |

Sync_OTA是新的并列集成工程；三个原工程及以下历史说明保留。新的状态以各工程README和集成任务书为准。

---


# 三模块当前入口（2026-09-15 目录整理）

| 模块 | 日常 GUI / 说明入口 | 实际范围 |
|---|---|---|
| 同步前端 | [Sync_Frontend.xpr](Sync_Frontend/Sync_Frontend.xpr) · [README](Sync_Frontend/README_ZH.md) | sync_frontend_top；旧用户 GUI 保持原位 |
| 两级 SFO | [Sync_SFO.xpr](Sync_SFO/Sync_SFO.xpr) · [README](Sync_SFO/README_ZH.md) | t10_two_pass_system，原默认输出参数 150 MHz |
| CFO | [九个真实阶段工程](Sync_CFO/README_ZH.md) | 完整 CFO 整链顶层尚未交付 |

[旧新路径映射](PATH_MAPPING_ZH.md) · [整理验证与边界](Sync_SFO/docs/reorganization_20260915/REORGANIZATION_RESULT_ZH.md) · [Git 与原有修改](Sync_SFO/docs/reorganization_20260915/GIT_REORGANIZATION_ZH.md) · [独立 I16 示例](Sync_Frontend/examples/README_ZH.md)。

本轮仅整理路径：不改算法或接口，不启动新的综合、实现、仿真或 MATLAB，不生成新网表、CLIP XML 或 LabVIEW 工程。前端与 I16 保留独立 Git；SFO/CFO 继续使用根 Git。

以下原 README 内容完整保留用于追溯，其中旧相对路径按上方映射进入 Sync_SFO；日常入口以上表为准。

---

# T10 两级SFO独立Vivado工程

本项目用于研究和调试“第一次采样频率偏差估计 → 第一次重采样 → 第二次估计 → 第二次重采样”。目标器件固定为 **xcvu11p-flgb2104-2-e**，开发工具为 **Vivado 2021.1**。本目录由本地Git管理，没有云端远程仓库。

最新手工交付（2026-09-15）：[唯一交付入口](handoff/T10_SFO_20260915_manual/README_ZH.md)。核心GUI工程、独立明文VHDL Wrapper、冻结输入/参考答案及Host/Target说明已完成静态收尾；RUN03单个全帧行为用例已独立复核通过。核心综合顶层仍为t10_two_pass_system；本轮未新增综合、仿真、网表、CLIP XML或LabVIEW工程，NI平台编译、实现时序和板测尚待完成。[规范与历史收尾清单](docs/T10_DELIVERY_RULES_20260915_ZH.md)保留早期记录。

## 第一次接手，按这个顺序读

1. [项目书](docs/PROJECT_SPEC_ZH.md)：先理解输入、输出、处理过程和验证边界。
2. [Vivado操作指南](docs/VIVADO_GUI_GUIDE_ZH.md)：打开工程、看层级、仿真和保存结果。
3. [MATLAB与参考数据指南](docs/MATLAB_REFERENCE_GUIDE_ZH.md)：找到波形来源、高精度参考和定点模型。
4. [迁移说明](docs/MIGRATION_ZH.md)：哪些内容从哪里复制、哪些内容因迁移而修改。
5. [本地Git指南](docs/LOCAL_GIT_ZH.md)：查看修改和建立自己的版本记录。

工具并行与资源分配统一遵循[性能规范](docs/TOOL_PERFORMANCE_ZH.md)，其中区分Vivado作业数、单作业线程数、仿真展开与MATLAB计算线程。

## 文件放在哪里

| 目录 | 内容 | 是否应手工修改 |
|---|---|---|
| `rtl/` | 按功能分组的74份T10核心RTL、公共定义和必要厂商模型 | 按接口合同修改；先查看Git差异 |
| `ip/` | 34个Xilinx IP的配置及必要输入 | 通过Vivado配置IP；保持算法参数可追溯 |
| `constraints/` | 当前启用的三路时钟约束，以及单独保留的旧跨时钟约束参考 | 必须理解时钟关系后修改 |
| `sim/tb/` | 测试台与被动观察器 | 可以扩展检查；不能用参考答案驱动应由RTL估计的量 |
| `sim/data/` | 冻结输入、参考答案、只读表 | 原样保留；新用例用新名字 |
| `sim/waves/` | 关键波形显示/记录配置 | 可按问题增加信号 |
| `matlab/` | 波形生成、算法及定点参考依赖 | 按说明使用，变更后单独验证 |
| `vivado/` | 可由GUI打开的工程文件 | 首选Vivado管理工程配置 |
| `tools/vivado/` | 少量原生Tcl工程入口 | 与GUI对应，不另建隐藏流程 |
| `tools/analysis/` | 必要的离线数值/诊断检查 | 检查含义须明确，不能忽略未知错误 |
| `docs/` | 项目书、操作、迁移来源和验证记录 | 随工程一起更新 |
| `work/` | 可重建临时工作与运行结果 | 不纳入Git；不能作为唯一参考来源 |

工程入口：[T10_SFO.xpr](vivado/T10_SFO/T10_SFO.xpr)。源级顶层为 `t10_two_pass_system`；完整行为测试台为 `t10_full023_tb`。精确命令和运行方式以GUI指南、RTL迁移说明及实际验证记录为准。

## 当前状态与边界

这是原T10冻结核心的独立迁移，不包含CLIP封装、LabVIEW工程或CFO后续链。原工程及全部历史试验留在原目录，没有被移动或清理。

本轮先完成安全复制、可维护目录和本地Git。工程创建、IP迁移、仿真、综合和布局布线的实际检查状态分别记录在[迁移验证记录](docs/verification/MIGRATION_CHECKS_ZH.md)，不得把“已经提交Git”或“工程能打开”当成完整硬件验收。

本项目只保证已明确复制的T10范围，不把T00–T11全部历史试验复制进来。原始来源通过文件映射与SHA-256指纹保留；同名不同版本没有混合进同一个源集。

