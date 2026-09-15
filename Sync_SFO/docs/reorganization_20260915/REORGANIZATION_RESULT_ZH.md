# 三模块工程入口与路径整理结果

## 完成范围

D:/008_MA_Dev 根目录已收敛为 Sync_Frontend、Sync_SFO、Sync_CFO 三个业务目录及 Git、规则、总入口、路径映射文件。[总入口](../../../README_ZH.md) · [路径映射](../../../PATH_MAPPING_ZH.md)。

- 前端日常入口为 Sync_Frontend/Sync_Frontend.xpr；原 GUI 打开的 vivado/Sync_Frontend/Sync_Frontend.xpr、其缓存及原文件保持原位。新入口使用独立的 15 个导入 XCI 副本和独立生成路径。
- SFO 日常入口为 Sync_SFO/Sync_SFO.xpr；t10_two_pass_system、t10_full023_tb、OUTPUT_CLOCK_MHZ 默认 150、74 核心 RTL 与34 XCI保持原版。独立 Wrapper 位于 Sync_SFO/wrapper。
- CFO 保留九个实际阶段 XPR。尚无最终整链 top，未创建冒充整链的 Sync_CFO.xpr。LINK010R1 的三个显式官方 XPM 依赖原样复制到模块内并保持库名与指纹。
- I16 和原 ZIP 进入前端 examples，I16 独立 Git、原未提交修改和历史入口保留。新增根 I16_AddSub.xpr 仍以 i16_addsub_clip 为原示例 top，不加入生产前端。

## 验证证据

| 检查 | 结果 | 证据 |
|---|---|---|
| 开工冻结 | 7,049 文件、三个本地 Git 状态 | files_before.json、git_before.json、各仓库差异快照 |
| 全量迁移副本 | 4,757 文件 SHA-256 一致，0 差异 | copy_verification.json |
| 保留归档原件 | 4,757 文件移动后仍与开工指纹一致 | archive_verification.json |
| 前端原有文件 | 1,749 个既有非 Git 文件保持；README/忽略规则及 Git 属性的追加单独记录，原内容保留 | final_verification.json |
| 工程静态源集 | 12 个 XPR，直接依赖全部位于自身模块，无缺失 | static_entry_checks.json |
| SFO 同版本 | 120 项显式引用与手工包逐项指纹一致；包含74核心 RTL、34 XCI | static_entry_checks.json 的 sfo_pairs |
| Vivado 实际打开 | Vivado 2021.1 独立只读打开12个 XPR，全部 part/top 正确，正常退出 | native_open.log、native_open_summary.tsv |
| 实际源集比对 | 所有显式成员均存在；SFO额外163项为已冻结IP配套文件，逐项核对原指纹；其余11工程无额外成员 | native_files_1～12.tsv、final_verification.json |
| 用户 GUI | 原进程14300保留；本轮检查会话已退出 | switch_checkpoint.json、现场进程核对 |

只读打开日志中的 IP locked 原因明确为 read-only project；新根工程的生成目录及旧运行结果未复制到新运行位置，因此有生成目录/GeneratedRun 缺失提示。这些不是缺失 RTL/XCI，也不是综合或IP输出生成已经验证。本轮没有为消除这些提示生成输出或重跑计算。

本记录只证明源身份、路径闭合和工程管理器可打开；不证明新仿真、综合、实现时序、持续吞吐、NI集成或板测。已有SFO完整帧证据保持既定单用例范围。

## 保留与未完成项

旧根原件在 Sync_SFO/archive/pre_reorganization_root、Sync_CFO/archive/pre_reorganization_T11_CFO、Sync_Frontend/examples/archive。它们不是新主入口依赖，不删除、不覆盖。旧运行脚本、历史报告和 source lock 保留旧路径身份，后续获准执行前由所属任务基于新路径另行冻结具体作业。

前端原 GUI 若含未保存编辑，新根入口不包含这些内存状态；本轮没有保存或关闭它。CFO完整链、最终Wrapper/Host资料仍未交付。前端到SFO的新结果适配器未实现。实现时序、持续多帧吞吐、NI工程及板测没有新增结论。

模型/推理/速度设置未改；未新建Luna或委托原T10。本轮没有启动综合、布局布线、仿真、MATLAB，没有生成新DCP/EDIF、CLIP XML、配置包或LabVIEW工程。

自动审批曾拒绝整段重写根规则与导航；该命令没有执行。随后采用保留原文的局部追加，已完成导航，无待用户批准的规则覆盖操作。

Git 暂存审阅额外核对25个新增硬件/工程文件的原始字节，以及42个当前导航链接；全部通过。新增前端工程的Git换行归一化问题已在提交前按精确文件范围修正，未改变磁盘源文件。
