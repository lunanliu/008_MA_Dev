from pathlib import Path
import json,hashlib,re
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915'
(A/'REORGANIZATION_RESULT_ZH.md').write_text('''# 三模块工程入口与路径整理结果

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
| 前端原有文件 | 1,750 个既有非 Git 文件保持；README/忽略规则的本轮导航追加单独记录 | final_verification.json |
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
''',encoding='utf-8')
(A/'GIT_REORGANIZATION_ZH.md').write_text('''# Git 整理与用户修改保留

根仓库原 HEAD：2d49cf0b402fcc9109e16d1431b6ca8ca9be697a。前端原 HEAD：9b3bb262834b4f752fdb8fe2d2d50954935fd4d8。I16 原 HEAD：194b378f80cbe6d7be72efa11c0dd165d7db8bf6。三个仓库均保持原历史，不合并历史、不设置或推送远端。

本轮以原 index 中已跟踪的文件身份做路径迁移：根的 T10 目录归 Sync_SFO，T11_CFO 归 Sync_CFO。搬迁对应的 index 使用原已跟踪 blob，不将工作区中原有改动全部暂存。根 README、AGENTS、.gitignore 的本轮改动只有独立记录的前置/末尾追加，暂存时应用于原 index 内容；原已有修改仍留在工作区。原 T10 XPR 的未提交修改保留于 Sync_SFO/vivado/T10_SFO/T10_SFO.xpr。

本轮新入口、相对路径修订、导航、核对记录、已核验Wrapper/IP副本作为结构变更纳入本地提交。复用的核心、Wrapper、XPM和阶段XPR明确来自已存在版本，不作为本任务新的算法设计。其他原有未跟踪文件继续保留，不用 git add -A 混入本轮。

前端和 I16 分别在自己的仓库只提交本轮新入口和导航。I16原 README及历史XPR修改保持未提交。原件归档中的Git目录同样保留；它们仅作归档，不作为活动仓库。

最终提交号和保留差异核对见 git_completion.json。没有 reset、clean、删除Git、强制覆盖或推送云端。目录记录脚本是本次操作证据，其中切换前路径已归档，禁止将其当作可重复执行的实验或再次搬迁入口。
''',encoding='utf-8')
# Current primary guide: path-only edits, backed by the unchanged archive original.
p=R/'Sync_SFO/docs/SFO_SYNC_MODULE_GUI_ZH.md';s=p.read_text(encoding='utf-8-sig');s=s.replace('../handoff/T10_SFO_20260915_manual/core_project/vivado/T10_SFO/T10_SFO.xpr','../Sync_SFO.xpr').replace('打开 T10_SFO.xpr','打开 Sync_SFO.xpr').replace('完整复制 `T10_SFO_20260915_manual` 文件夹，保留内部相对目录。','完整复制 `Sync_SFO` 模块文件夹，保留内部相对目录。');p.write_text(s,encoding='utf-8')
# Give module-local data/docs links current relative locations without editing history reports or locks.
for name in ('DELIVERY_BOUNDARY_20260915_ZH.md','CFO_STAGE_ENTRY_DATA_20260915_ZH.md'):
 p=R/'Sync_CFO/docs'/name;s=p.read_text(encoding='utf-8-sig');s=s.replace('D:/008_MA_Dev/T11_CFO/','../');p.write_text(s,encoding='utf-8')
p=R/'Sync_CFO/rtl/vendor/vivado_2021_1_xpm/README_ZH.md';lines=['# 显式 XPM 依赖来源','', '这三份文件原样复制自 CFO_LINK010R1 原XPR显式引用的 Vivado 2021.1 安装目录；未改RTL内容或 cfo_xpm 库属性。','', '| 文件 | SHA-256 |','|---|---|']
for f in sorted(p.parent.glob('*.sv')):lines.append(f'| {f.name} | {hashlib.sha256(f.read_bytes()).hexdigest()} |')
p.write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('RESULT_AND_GIT_NOTES_READY')
