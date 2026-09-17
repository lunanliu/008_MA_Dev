from pathlib import Path
import hashlib,json,csv,shutil,re,zipfile,xml.etree.ElementTree as ET
from datetime import datetime,timezone
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
old=root/"release/Sync_Frontend_SF003_20260915_rev01"
out=root/"release/Sync_Frontend_SF003_20260915_rev02"
native=root/"work/SF003_DCP_check_20260914T223135Z"
core=native/"clip_dcp/sync_frontend_top.dcp"
original=root/"work/SF003_attempt_20260914T211953Z/sync_frontend_synth.dcp"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(core)=="553debe94bd9b187f15fb9ee8069ed0258b7976b57ff8e98609588139746cfad"
assert sha(original)=="eee1c76628ea07e6d1324fc14d2621f88cef810e046e6f3d83f4ce0011133d89"
old_manifest_sha=sha(old/"SHA256SUMS.csv")
with (old/"SHA256SUMS.csv").open(encoding="utf-8",newline="") as f:
 old_rows=list(csv.DictReader(f))
for row in old_rows: assert sha(old/row["path"])==row["sha256"],row["path"]
assert not out.exists(),"Use a new release revision; preserve existing snapshots."
out.mkdir()
def copy(src,rel):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,p);return p
def write(rel,text):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding="utf-8");return p
# Update current guides, while preserving the previous release snapshot.
update="当前发布（2026-09-15）：release/Sync_Frontend_SF003_20260915_rev02 为唯一当前交付。原算法顶层核心 DCP、独立明文 VHDL wrapper 与 XML 分别提供，由 NI Target 编译关联；不要求预先生成 wrapper 顶层 DCP。核心原生重开通过；NI 实际导入、整体编译及板测未执行。"
for name in ["PROJECT_GUI_ZH.md","CLIP_INTERFACE_BOARD_TEST_ZH.md"]:
 p=root/"docs"/name;s=p.read_text(encoding="utf-8")
 s=re.sub(r"当前更新（2026-09-15）：[^\n]*",update,s,count=1)
 if name=="PROJECT_GUI_ZH.md":
  s=s.replace("release候选由成功合成的完整EDIF、纯连线VHDL、CLIP XML和继承时钟检查XDC构成。独立重新读取EDIF、编译VHDL连线并检查无黑盒后，才标为导出检查通过。","当前 release 的 clip 目录提供核心 DCP、独立纯连线 VHDL、CLIP XML 和说明 NI 时钟所有权的 XDC。核心 DCP 已独立重开、零黑盒；发布文件另做静态端口、依赖及哈希检查。自建 wrapper 回填诊断不是发布前置门槛。")
 p.write_text(s,encoding="utf-8")
copy(core,"clip/sync_frontend_top.dcp")
vhdl=(old/"clip_edif/sync_frontend_clip.vhd").read_bytes()
vhdl=vhdl.replace(b"Pure wiring wrapper around the complete EDIF core.",b"Pure wiring wrapper around the complete synthesized core supplied by DCP.")
p=out/"clip/sync_frontend_clip.vhd";p.write_bytes(vhdl)
copy(old/"clip_edif/ports.json","clip/ports.json")
xml=ET.parse(old/"clip_dcp_template/sync_frontend_clip.xml")
xml.getroot().set("Name","Autonomous TO CFO frontend SF003 rev02 125MHz FLGB")
xml.getroot().find("Description").text="Core DCP plus independent VHDL wrapper. Raw-IQ autonomous capture, coarse TO/CFO and fine TO. NI Target compile and board qualification pending."
xml.write(out/"clip/sync_frontend_clip.xml",encoding="utf-8",xml_declaration=True)
write("clip/sync_frontend_clip.xdc","# The NI target supplies and constrains the free-running 125 MHz clk125.\n# Use that same clock for CLIP I/O and its LabVIEW SCTL.\n# This package does not impose standalone I/O delays, pin LOCs or false paths.\n# Verify real clock propagation, reset/CDC and all interface timing in the NI Target compile.\n")
# Runtime data and comparison paths are preserved.
for dirname in ["input","reference","sim","matlab"]:
 shutil.copytree(old/dirname,out/dirname)
for dirname in ["reference","provenance"]:
 shutil.copytree(old/"reports"/dirname,out/"reports"/dirname)
copy(old/"tools/compare_readback.py","tools/compare_readback.py")
for name in ["LABVIEW_TARGET_INTEGRATION_ZH.md","PROJECT_GUI_ZH.md","CLIP_INTERFACE_BOARD_TEST_ZH.md","CLIP_NETLIST_INTEGRATION_DECISION_20260915_ZH.md"]:
 copy(root/"docs"/name,"docs/"+name)
# Source GUI instructions point to the original source project, not a fabricated XPR in this package.
p=out/"docs/PROJECT_GUI_ZH.md"
s=p.read_text(encoding="utf-8").replace("打开vivado/Sync_Frontend/Sync_Frontend.xpr。","源工程 GUI 入口是 D:/008_MA_Dev/Sync_Frontend/vivado/Sync_Frontend/Sync_Frontend.xpr；本交付包不复制整个源工程。")
p.write_text(s,encoding="utf-8")
copy(original,"evidence/original_synthesis/sync_frontend_synth_original.dcp")
for name in ["native_vivado.log","native_vivado.jou","saved_dcp_resources.txt","core_ooc_utilization.txt","core_ports.txt","core_export_constraints.xdc"]:
 copy(native/name,"evidence/core_dcp_check/"+name)
for name in ["SF003_completion.json","SF003_DCP_RELEASE_CHECK_wrapper_compatibility_blocked_20260915.json","SF003_ASTRA_REVIEW_ZH.md","SF002_completion.json","SF002_ASTRA_REVIEW_ZH.md"]:
 copy(root/"reports"/name,"evidence/reviews/"+name)
shutil.copytree(old/"physical_evidence",out/"evidence/physical")
for name in ["SF003_files.csv","SF003_DCP_RELEASE_CHECK_files.csv"]:
 copy(root/"reports/design"/name,"evidence/provenance/"+name)
copy(root/"tools/check_dcp_release.tcl","evidence/provenance/check_dcp_release_HISTORICAL_NOT_AN_ENTRYPOINT.tcl")
provenance={
 "release":"Sync_Frontend_SF003_20260915_rev02","core_top":"sync_frontend_top","clip_top":"sync_frontend_clip",
 "core_rtl_commit":"2e968f6e33a82a000326be9e6d9c7c97da9342bc","part":"xcvu11p-flgb2104-2-e","vivado":"2021.1",
 "selected_core":{"file":"clip/sync_frontend_top.dcp","sha256":sha(core),"source":str(core),"origin":"OOC relink/export of the complete EDF and 43 EDN from the accepted original core synthesis; no RTL/IP resynthesis; no VHDL wrapper included","native_reopen":"PASS","blackboxes":0,"device_pad_io":0},
 "original_synthesis":{"file":"evidence/original_synthesis/sync_frontend_synth_original.dcp","sha256":sha(original),"reason_not_primary_import":"Contains standalone create_clock and output-delay budgets; retained unchanged for provenance"},
 "source_edif":{"sha256":sha(old/"clip_edif/sync_frontend_top.edf"),"edn_count":43,"complete_original_package":str(old/"clip_edif")},
 "wrapper":{"file":"clip/sync_frontend_clip.vhd","changes":"One explanatory comment only; logic and ports unchanged"},
 "status":{"core_synthesis":"ACCEPTED","core_dcp_native_reopen":"PASS","custom_wrapper_diagnostic":"INCOMPLETE_NOT_RELEASE_GATE","ni_clip_import":"NOT_RUN","ni_target_compile":"NOT_RUN","ni_interface_timing":"NOT_RUN","board":"NOT_RUN","sustained_throughput":"NOT_QUALIFIED"},
 "old_release_manifest_sha256":old_manifest_sha,
 "native_runs_started_for_rev02":0}
write("CORE_DCP_PROVENANCE.json",json.dumps(provenance,ensure_ascii=False,indent=2)+"\n")
write("evidence/README_ZH.md","""# 原始证据的阅读边界
本目录只作溯源，不加入 CLIP 的 ImplementationList。实际导入仅使用 ../clip/sync_frontend_clip.xml。
original_synthesis 是原算法顶层综合 DCP，含独立工程时钟/输出预算，原样保留；clip 中的 DCP 是同次综合网表的 OOC 重导出版本，已独立重开，不包含 wrapper。
core_dcp_check/native_vivado.log 在 CORE 与 SAVED_DCP 阶段通过；随后额外 wrapper 手工回填失败。必须保留整个失败，不把此日志称为整份检查 PASS。该额外诊断已撤回为交付门槛。
reviews 中 Luna 原始报告保持原样；其断言、DRC等级、重试顺序等修正见 SF003_ASTRA_REVIEW_ZH.md。
physical 是历史独立实现：WNS2.087ns、WHS0.024ns、TNS/THS0、5BUFG；133个同步输入漏 input delay，reset_n另计1个异步输入。时序只覆盖已约束路径，不代表本包/NI整体接口时序通过。
provenance/check_dcp_release_HISTORICAL_NOT_AN_ENTRYPOINT.tcl 是历史冻结脚本，不是本包执行入口，不要运行以生成 wrapper 顶层 DCP。
""")
write("README_ZH.md","""# 同步前端 SF003 rev02：核心 DCP 与独立 VHDL CLIP 交付
唯一导入入口：**clip/sync_frontend_clip.xml**。选择该 CLIP 声明并保留整个 clip 目录，由 LabVIEW FPGA 的 Target 编译关联核心与 VHDL wrapper。
状态：核心综合已接受；交付 DCP 独立原生重开通过；本包静态依赖/端口/哈希核对见 STATIC_VALIDATION.json。NI 实际导入、Target整体编译、真实接口时序、板测及持续吞吐尚未验收。

## 导入文件
- clip/sync_frontend_top.dcp：原算法顶层 sync_frontend_top 的完整核心；正确 xcvu11p-flgb2104-2-e，Vivado2021.1，OOC，独立重开黑盒0、器件PAD I/O0。
- clip/sync_frontend_clip.vhd：独立明文纯连线 wrapper，CLIP 顶层 sync_frontend_clip，内部实例名 implementation，组件名 sync_frontend_top。
- clip/sync_frontend_clip.xml：端口与三项实现依赖；已经配齐实际文件，不是待填写模板。
- clip/sync_frontend_clip.xdc：说明 NI 时钟/边界所有权，不附加独立工程 IO 预算。ports.json 给出32个外部端口。
无需预先综合 wrapper 或手工回填后再交另一个 wrapper 顶层 DCP。核心网表绑定由 NI 完整编译完成。

## 核心来源
本包 DCP 采用原成功综合 EDF+43EDN 的 OOC 重导出文件，保持 top=sync_frontend_top，没有重综合 RTL/IP、没有包含 VHDL wrapper。其 SHA256 为553DEBE94BD9B187F15FB9EE8069ED0258B7976B57FF8E98609588139746CFAD。
原综合 DCP 含独立工程时钟/输出延迟预算，作为 evidence/original_synthesis 原样保留；不把它和当前 DCP 同时加入 CLIP。生成链与哈希见 CORE_DCP_PROVENANCE.json。
VHDL仅修订一条说明注释，端口及所有连接保持原样。XML资源声明依据当前综合核心；BUFG新增为0不是验收要求，历史独立实现有5个BUFG。
rev01及失败原始证据保留；当前版本替代其不完整DCP模板和“等待手工回填通过”的发布说明。

## Target VI 与 Host
完整架构、RTL层级、32端口接线、DMA格式和预期结果：docs/LABVIEW_TARGET_INTEGRATION_ZH.md。
125MHz单域，同一复数流四个连续时间样点/拍。Host-to-Target建议U32 FIFO，Q16高半字/I16低半字，每次四点组成输入beat，valid/ready握手。
Host发送未同步原始IQ，不发送frame_start、frame_id、true TO/CFO或truth。参考ROM已在核心里。
输入input/autonomous_stream.mem共15081行128bit；每行右侧U32为最早样点data0。共60324点。为对照已有仿真，FPGA每256个已接受beat暂停8000拍，结果每条背压128拍。
结果由VI原子保存后打包成建议的9个U32，通过Target-to-Host FIFO回Host；当前CLIP本身没有DMA端口，也没有整帧输出。
Host核对四个fine_absolute为15004、26373、37842、49311，CFO结果为-150022、0、150022、-149977Hz，并监视计数、drop、error_sticky和DMA溢出/超时。
首次reset后不额外start时参考epoch=0。具体控制脉冲/背压与清队列要求见接线指南。

## 比较与证据
tools/compare_readback.py <读回CSV路径> 是Host比较入口；CSV格式见reports/reference/autonomous_results.csv。无参数时只比较包内历史RTL结果，不是新板测。
matlab/waveform/load_frontend_waveform.m、matlab/golden/frontend_reference_catalog.m和matlab/comparison/compare_frontend_readback.m为MATLAB入口；历史参考与新增包装运行状态分开，新增包装未在本工程原生运行。
SHA256SUMS.csv覆盖本包除清单本身之外的全部文件。可运行tools/verify_release.py核对静态内容，不调用Vivado或MATLAB。
evidence保存原始通过/失败和历史独立实现边界；不把这些文件额外加入CLIP。
""")
# Point the workspace to this single current release.
p=root/"README_ZH.md";s=p.read_text(encoding="utf-8")
s=re.sub(r"- 当前综合交付目录：[^\n]*","- 当前完整交付：release/Sync_Frontend_SF003_20260915_rev02/README_ZH.md；唯一 CLIP 导入入口为其 clip/sync_frontend_clip.xml。rev01 保留为历史快照。",s)
s=s.replace("- 本包：docs/SF003_EXECUTION_ZH.md；clip/为包装源文件，完整EDF由成功综合导出。","- 当前发布包含核心 DCP + 独立 VHDL + XML；生成来源见 release/Sync_Frontend_SF003_20260915_rev02/CORE_DCP_PROVENANCE.json。")
p.write_text(s,encoding="utf-8")
for p in [root/"docs/LABVIEW_TARGET_INTEGRATION_ZH.md",root/"docs/CLIP_NETLIST_INTEGRATION_DECISION_20260915_ZH.md"]:
 s=p.read_text(encoding="utf-8")
 s+="\n当前完整发布：release/Sync_Frontend_SF003_20260915_rev02；唯一 CLIP 导入入口 clip/sync_frontend_clip.xml。rev01 为保留的旧快照，新的三项实现依赖已配齐。NI Target 编译仍未执行。\n"
 p.write_text(s,encoding="utf-8")
 copy(p,"docs/"+p.name)
assert sha(old/"SHA256SUMS.csv")==old_manifest_sha
print(json.dumps({"prepared_release":str(out),"old_snapshot_files_verified":len(old_rows),"old_manifest_unchanged":True,"core_sha256":sha(core),"next":"static port/dependency/hash verification"},ensure_ascii=False))

