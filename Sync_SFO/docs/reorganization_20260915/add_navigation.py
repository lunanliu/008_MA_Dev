from pathlib import Path
import json
R=Path('D:/008_MA_Dev');A=R/'Sync_SFO/docs/reorganization_20260915';edits=[]
def append_preserving(path,text,position='suffix'):
 p=R/path;old=p.read_bytes();add=text.encode('utf-8');p.write_bytes(add+old if position=='prefix' else old+add);edits.append({'path':path,'position':position,'added_utf8':text})
append_preserving('README_ZH.md','''# 三模块当前入口（2026-09-15 目录整理）

| 模块 | 日常 GUI / 说明入口 | 实际范围 |
|---|---|---|
| 同步前端 | [Sync_Frontend.xpr](Sync_Frontend/Sync_Frontend.xpr) · [README](Sync_Frontend/README_ZH.md) | sync_frontend_top；旧用户 GUI 保持原位 |
| 两级 SFO | [Sync_SFO.xpr](Sync_SFO/Sync_SFO.xpr) · [README](Sync_SFO/README_ZH.md) | t10_two_pass_system，原默认输出参数 150 MHz |
| CFO | [九个真实阶段工程](Sync_CFO/README_ZH.md) | 完整 CFO 整链顶层尚未交付 |

[旧新路径映射](PATH_MAPPING_ZH.md) · [整理验证与边界](Sync_SFO/docs/reorganization_20260915/REORGANIZATION_RESULT_ZH.md) · [Git 与原有修改](Sync_SFO/docs/reorganization_20260915/GIT_REORGANIZATION_ZH.md) · [独立 I16 示例](Sync_Frontend/examples/README_ZH.md)。

本轮仅整理路径：不改算法或接口，不启动新的综合、实现、仿真或 MATLAB，不生成新网表、CLIP XML 或 LabVIEW 工程。前端与 I16 保留独立 Git；SFO/CFO 继续使用根 Git。

以下原 README 内容完整保留用于追溯，其中旧相对路径按上方映射进入 Sync_SFO；日常入口以上表为准。

---

''','prefix')
append_preserving('AGENTS.md','''# 2026-09-15 目录映射补充（原规则全文保留）

本轮用户批准的三模块入口与路径整理按 D:/007 Dev/OTA_RTL_0829/docs/operations/SYNC_SFO_DIRECTORY_REORGANIZATION_AUTHORIZATION_20260915_ZH.md 执行。新增位置见 [PATH_MAPPING_ZH.md](PATH_MAPPING_ZH.md)。下方旧规则中的根目录 docs、tools、rtl、ip、constraints、sim、matlab、vivado、handoff、work 均已归入 Sync_SFO；T11_CFO 对应 Sync_CFO。Sync_Frontend 保持原位，I16 示例在其 examples 内且保持独立身份。

本补充只解释搬迁后的路径，不扩大算法、实验、配对或交付授权。用户打开的旧前端 GUI 状态保持；旧规则原文和已有用户修改均保留如下。

---

''','prefix')
append_preserving('.gitignore','''
# 2026-09-15 module relocation: preserved originals and local generated products.
/Sync_SFO/archive/
/Sync_CFO/archive/
/Sync_SFO/work/
/Sync_SFO/results/
/Sync_SFO/vivado/**/*.cache/
/Sync_SFO/vivado/**/*.runs/
/Sync_SFO/vivado/**/*.sim/
/Sync_SFO/vivado/**/*.gen/
/Sync_SFO/vivado/**/*.hw/
/Sync_SFO/vivado/**/*.ip_user_files/
/Sync_SFO/vivado/**/webtalk*
/Sync_SFO/vivado/**/usage_statistics_webtalk*
/Sync_SFO/*.cache/
/Sync_SFO/*.runs/
/Sync_SFO/*.sim/
/Sync_SFO/*.gen/
/Sync_SFO/*.hw/
/Sync_SFO/*.ip_user_files/
/Sync_CFO/vivado/**/*.cache/
/Sync_CFO/vivado/**/*.runs/
/Sync_CFO/vivado/**/*.sim/
/Sync_CFO/vivado/**/*.gen/
/Sync_CFO/vivado/**/*.hw/
/Sync_CFO/vivado/**/*.ip_user_files/
/Sync_SFO/ip/**/synth/
/Sync_SFO/ip/**/sim/
/Sync_SFO/ip/**/hdl/
/Sync_SFO/ip/**/doc/
/Sync_SFO/ip/**/simulation/
/Sync_SFO/ip/**/ipstatic/
/Sync_SFO/ip/**/constraints/
/Sync_SFO/ip/**/cmodel/
/Sync_SFO/ip/**/example_design/
/Sync_SFO/ip/**/impl/
/Sync_SFO/ip/**/*.veo
/Sync_SFO/ip/**/*.vho
/Sync_SFO/ip/config/*/*.xml
/Sync_SFO/docs/reorganization_20260915/*.index.before
/Sync_SFO/docs/reorganization_20260915/report_clock.json
''')
append_preserving('Sync_Frontend/.gitignore','''
# New root GUI uses isolated generated products; imported XCI remain versioned.
/Sync_Frontend.cache/
/Sync_Frontend.gen/
/Sync_Frontend.hw/
/Sync_Frontend.ip_user_files/
/Sync_Frontend.runs/
/Sync_Frontend.sim/
/examples/I16_AddSub_CLIP/
/examples/archive/
''')
(A/'additive_navigation_edits.json').write_text(json.dumps(edits,ensure_ascii=False,indent=2),encoding='utf-8')
mapping=json.loads((A/'path_mapping.json').read_text(encoding='utf-8-sig'))
s='# 旧新路径映射（2026-09-15）\n\n根目录 D:/008_MA_Dev。旧 D:/007 Dev/OTA_RTL_0829 中央工作区保持原位，本任务未修改其状态或绑定。\n\n| 原路径 | 当前路径 | 原件归档 |\n|---|---|---|\n'
for m in mapping:
 def rel(v):return Path(v).relative_to(R).as_posix()
 s+=f'| `{rel(m["old"])}` | [{rel(m["current"])}]({rel(m["current"])}) | `{rel(m["archive"])}` |\n'
s+='''\n## 日常主入口

- 原 T10 手工包核心入口 → [Sync_SFO/Sync_SFO.xpr](Sync_SFO/Sync_SFO.xpr)；原包在 [Sync_SFO/handoff](Sync_SFO/handoff)。
- 原前端 vivado/Sync_Frontend/Sync_Frontend.xpr → [Sync_Frontend/Sync_Frontend.xpr](Sync_Frontend/Sync_Frontend.xpr)。旧 GUI 与工程原位保留；新入口来自已保存磁盘版本，未保存编辑需由用户保存后另行比较。
- T11_CFO/vivado/阶段/阶段.xpr → Sync_CFO/vivado/阶段/阶段.xpr；[九个阶段名单](Sync_CFO/README_ZH.md)，完整链顶层尚未交付。
- 原 I16 示例 → [Sync_Frontend/examples/I16_AddSub_CLIP/I16_AddSub.xpr](Sync_Frontend/examples/I16_AddSub_CLIP/I16_AddSub.xpr)。独立 Git 与原未提交修改保留，不加入生产核心。
- 原性能工具 → [Sync_SFO/tools/vivado/configure_parallel_jobs.tcl](Sync_SFO/tools/vivado/configure_parallel_jobs.tcl)。

总管家可据此更新中央绑定中的路径，不能因目录更新恢复已停实验、转发受阻交接或改写历史 source lock。原报告保留旧路径和实验身份，通过本表定位当前副本及归档原件。

根 README、AGENTS 和 .gitignore 的既有内容完整保留，仅追加入口补充。原 T10 XPR 的既有未提交修改仍在 Sync_SFO/vivado/T10_SFO/T10_SFO.xpr；本轮提交只纳入可审阅的结构和导航差异。
'''
p=R/'PATH_MAPPING_ZH.md';assert not p.exists();p.write_text(s,encoding='utf-8')
print('ADDITIVE_NAVIGATION_COMPLETE; original contents retained byte-for-byte')
