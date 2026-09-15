from pathlib import Path
import re,json,hashlib,xml.etree.ElementTree as ET
R=Path('D:/008_MA_Dev'); A=R/'Sync_SFO/docs/reorganization_20260915'; changes=[]
def sha(b):return hashlib.sha256(b).hexdigest()
def write_new(p,text):
 if p.exists():raise RuntimeError('Existing target '+str(p))
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8',newline='\n')
def entry(src,dst,replacements,hook=None):
 old=src.read_bytes(); s=old.decode('utf-8-sig')
 for a,b in replacements:s=s.replace(a,b)
 s,n=re.subn(r'(<Project\b[^>]* Path=")[^"]*',lambda m:m[1]+dst.as_posix(),s,count=1);assert n==1
 if hook:
  s=re.sub(r'(<Step Id="[^"]+")(/>)',lambda m:m[1]+' PreStepTclHook="'+hook+'"'+m[2],s)
  s=s.replace('Name="xsim.elaborate.mt_level" Val="2"','Name="xsim.elaborate.mt_level" Val="16"')
 if dst!=src and dst.exists():raise RuntimeError('Existing XPR '+str(dst))
 dst.write_bytes(s.encode('utf-8'));ET.parse(dst)
 changes.append({'source':src.as_posix(),'target':dst.as_posix(),'before_sha256':sha(old),'after_sha256':sha(dst.read_bytes()),'replacements':replacements,'thread_hooks':hook})
sfo=R/'Sync_SFO';front=R/'Sync_Frontend';cfo=R/'Sync_CFO'
entry(sfo/'handoff/T10_SFO_20260915_manual/core_project/vivado/T10_SFO/T10_SFO.xpr',sfo/'Sync_SFO.xpr',[('$PPRDIR/../../','$PPRDIR/')],'$PPRDIR/tools/vivado/run_threads.tcl')
entry(front/'vivado/Sync_Frontend/Sync_Frontend.xpr',front/'Sync_Frontend.xpr',[('$PPRDIR/../../','$PPRDIR/'),('D:/008_MA_Dev/Sync_Frontend/sim/data/','../../../../sim/data/')])
for p in sorted((cfo/'vivado').glob('*/*.xpr')):
 rep=[]
 for n in ('cdc','fifo','memory'):
  rep.append((f'C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/xpm_{n}/hdl/xpm_{n}.sv',f'$PPRDIR/../../rtl/vendor/vivado_2021_1_xpm/xpm_{n}.sv'))
 entry(p,p,rep)
i16=front/'examples/I16_AddSub_CLIP';entry(i16/'vivado/I16_AddSub/I16_AddSub.xpr',i16/'I16_AddSub.xpr',[('$PPRDIR/../../','$PPRDIR/')])
(A/'xpr_path_changes.json').write_text(json.dumps(changes,indent=2),encoding='utf-8')
write_new(sfo/'tools/vivado/open_sync_sfo.tcl','''# Navigation only: no synthesis, implementation, simulation or IP generation.
set module_root [file normalize [file join [file dirname [info script]] ../..]]
if {[llength [get_projects -quiet]]} {error "Use an empty Vivado session; preserve any open GUI project."}
open_project [file join $module_root Sync_SFO.xpr]
if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Part mismatch"}
if {[get_property TOP [get_filesets sources_1]] ne "t10_two_pass_system"} {error "Core top mismatch"}
puts "Opened Sync_SFO. No run started."
''')
write_new(front/'tools/open_sync_frontend.tcl','''# Navigation only. Preserve the user's existing GUI session.
set module_root [file normalize [file join [file dirname [info script]] ..]]
if {[llength [get_projects -quiet]]} {error "Use an empty Vivado session; preserve any open GUI project."}
open_project [file join $module_root Sync_Frontend.xpr]
if {[get_property TOP [get_filesets sources_1]] ne "sync_frontend_top"} {error "Core top mismatch"}
puts "Opened Sync_Frontend. No run started."
''')
write_new(sfo/'README_ZH.md','''# Sync_SFO：两级采样频偏估计与补偿

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
''')
write_new(cfo/'docs/DIRECTORY_ENTRY_20260915_ZH.md','''# Sync_CFO 工程入口与目录迁移

原 T11_CFO 已整体归入 Sync_CFO；文件内容和历史证据保留。此模块尚无已交付的完整 CFO 整链顶层，因此不创建名为 Sync_CFO.xpr 的假整链。请从模块 README 的九个真实阶段工程选择所需范围，不能将阶段通过写成 T11～T13 整链通过。

`rtl/`、`ip/`、`constraints/`、`sim/`、`matlab/`、`docs/`、`tools/`、`vivado/` 保持原内部结构。`work/` 和 `reports/` 保留每次尝试的身份。`archive/pre_reorganization_T11_CFO/` 保存切换前原件。

CFO_LINK010R1 原 XPR 显式引用的三个 Vivado 2021.1 XPM 文件，原样复制到 `rtl/vendor/vivado_2021_1_xpm/`，仅调整 XPR 文件路径；库名、编译标志、RTL、测试台、IP 参数保持不变。其余阶段 XPR 只更新工程自身位置。

冻结审查包、source lock、历史 Tcl/runner 和报告内的旧绝对路径保留原文；它们用于追溯，不能直接作为搬迁后的启动许可或复现实验入口。下一次获准运行前，原任务应依据本轮路径映射另行冻结派单，不能自行更新旧锁来掩盖差异。此前审批受阻的交接与实验不借本轮恢复或转发。

完整 CFO 核心、与其匹配的独立 VHDL Wrapper、最终 Host 接口尚未交付。这里只提供已有阶段的输入与预期数据导航，没有添加占位 RTL 或临时连接。
''')
# Preserve the original CFO narrative verbatim beneath the new current navigation.
stages=[]
for p in sorted((cfo/'vivado').glob('*/*.xpr')):
 x=ET.parse(p).getroot();top=x.find('./FileSets/FileSet[@Name="sources_1"]/Config/Option[@Name="TopModule"]').get('Val');stages.append((p,top))
p=cfo/'README_ZH.md';old=p.read_text(encoding='utf-8-sig')
nav='# Sync_CFO：阶段工程导航\n\n**完整 CFO 整链顶层尚未交付。** 下列 XPR 保留各自阶段身份；入口整理不增加任何通过结论。\n\n| GUI 入口 | 实际核心 top |\n|---|---|\n'
for p0,top in stages:nav+=f'| [{p0.name}]({p0.relative_to(cfo).as_posix()}) | `{top}` |\n'
nav+='\n[目录整理边界](docs/DIRECTORY_ENTRY_20260915_ZH.md) · [阶段测试数据说明](docs/CFO_STAGE_ENTRY_DATA_20260915_ZH.md) · [MATLAB 模型](matlab/) · [输入/预期数据](sim/) · [Wrapper 状态](wrapper/README_ZH.md)\n\n以下为原 T11～T13 说明和历史状态；其中旧绝对路径用根目录路径映射定位。\n\n---\n\n'
p.write_text(nav+old,encoding='utf-8',newline='\n')
write_new(cfo/'wrapper/README_ZH.md','# CFO Wrapper 状态\n\n完整 CFO 整链核心和对应 VHDL Wrapper 尚未交付。当前九个 XPR 是阶段工程，不能用阶段核或临时连接替代最终核心。目录整理没有新增 RTL、Wrapper 或 CLIP 配置。\n')
write_new(front/'docs/DIRECTORY_ENTRY_20260915_ZH.md','''# 前端根目录工程入口

新的日常 GUI 入口为 [Sync_Frontend.xpr](../Sync_Frontend.xpr)，核心 top 保持 sync_frontend_top，器件保持 xcvu11p-flgb2104-2-e。由原 vivado/Sync_Frontend/Sync_Frontend.xpr 的磁盘版本复制，仅改变位置和相对路径。

用户已打开的原工程原位保留，本轮没有关闭、保存或替换其 GUI 状态。新入口使用独立的根目录 Sync_Frontend.srcs 副本及独立生成目录；RTL、约束和原工具保持相同源版本。用户在原 GUI 中尚未保存的编辑不包含在新入口中，保存后若需转移应另行比较，不能覆盖。

仿真输入路径改为相对默认 XSim 工作目录（Sync_Frontend.sim/<simset>/behav/xsim）的 ../../../../sim/data。输入文件、测试参数与测试含义不变。本轮未运行仿真。

独立 Wrapper 位于 [wrapper/sync_frontend_clip.vhd](../wrapper/sync_frontend_clip.vhd)；手工输入、预期和端口说明仍在 [原手工交付入口](../handoff/Sync_Frontend_20260915_manual/README_ZH.md)。

[I16 示例](../examples/README_ZH.md)独立管理，与生产同步核心源集完全分离。此前 release、失败记录、XML 历史文件均保留身份；本轮不生成或修补 CLIP XML。
''')
p=front/'README_ZH.md';old=p.read_text(encoding='utf-8-sig');p.write_text('# 当前工程入口（2026-09-15 整理）\n\n日常打开 [Sync_Frontend.xpr](Sync_Frontend.xpr)。[路径与 GUI 保留说明](docs/DIRECTORY_ENTRY_20260915_ZH.md) · [独立 Wrapper](wrapper/sync_frontend_clip.vhd) · [I16 示例](examples/README_ZH.md)。原 GUI 工程保留原位，以下历史说明保持来源身份。\n\n---\n\n'+old,encoding='utf-8',newline='\n')
write_new(front/'examples/README_ZH.md','# 前端硬件连通性示例\n\n[I16_AddSub_CLIP](I16_AddSub_CLIP/README_ZH.md) 是独立示例仓库，保留其 .git、原未提交修改及测试输入。新的示例入口为 [I16_AddSub.xpr](I16_AddSub_CLIP/I16_AddSub.xpr)，原顶层 i16_addsub_clip 保持不变。它不属于生产同步核心。\n\n原 [源工程 ZIP](I16_AddSub_CLIP_Source_Project.zip) 原样保存。archive 保存搬迁前原目录，禁止把示例 RTL 加入前端生产工程。\n')
write_new(i16/'DIRECTORY_ENTRY_20260915_ZH.md','# I16 独立示例入口\n\n当前打开 [I16_AddSub.xpr](I16_AddSub.xpr)。原 vivado/I16_AddSub/I16_AddSub.xpr 保留未提交编辑和历史身份；本轮新增根入口只修相对路径，原顶层 i16_addsub_clip 和测试台 i16_addsub_tb 不变。示例不加入前端生产源集。本仓库原 Git 历史和未提交修改保留。\n')
print('ENTRY_AND_NAVIGATION_CREATED',len(changes))
