from pathlib import Path
import json,hashlib,shutil,xml.etree.ElementTree as ET,re,csv
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
attempt=root/"work/SF003_attempt_20260914T211953Z"
export=attempt/"export_check_synthesis_retry2"
release=root/"release/Sync_Frontend_SF003_20260915_rev01"
assert not release.exists(),"Release already exists"
package=release/"clip_edif"
shutil.copytree(export/"package",package)
edns=sorted(p.name for p in package.glob("*.edn"))
assert len(edns)==43
tree=ET.parse(package/"sync_frontend_clip.xml")
impl=tree.getroot().find("ImplementationList")
for name in edns:
    elem=ET.SubElement(impl,"Path",Name=name)
    sim=ET.SubElement(elem,"SimulationFileList")
    ET.SubElement(sim,"SimulationModelType").text="Exclude from simulation model"
ET.indent(tree,space="  ")
tree.write(package/"sync_frontend_clip.xml",encoding="utf-8",xml_declaration=True)
(package/"edn_files.txt").write_text("\n".join(edns)+"\n",encoding="utf-8")
xdc="""# CLIP clock is supplied and constrained by the NI target through clk125.
# Select the same free-running 125 MHz clock for the CLIP and its SCTL.
# ASYNC_REG attributes and IP structure are preserved in the core netlist.
# No standalone IO budget, LOC, clock creation, or blanket false path belongs here.
# Runtime assertions use ordinary Tcl in check_dcp_release.tcl, not XDC if commands.
"""
(package/"sync_frontend_clip.xdc").write_text(xdc,encoding="utf-8")
dcp_template=release/"clip_dcp_template"
dcp_template.mkdir()
tree=ET.parse(package/"sync_frontend_clip.xml")
impl=tree.getroot().find("ImplementationList")
for child in list(impl):
    name=child.attrib["Name"]
    if name.endswith(".edn"): impl.remove(child)
    elif name=="sync_frontend_top.edf": child.set("Name","sync_frontend_top.dcp")
tree.getroot().set("Name","Autonomous TO CFO frontend 125MHz FLGB DCP")
ET.indent(tree,space="  ")
tree.write(dcp_template/"sync_frontend_clip.xml",encoding="utf-8",xml_declaration=True)
for folder in ["checkpoints","physical_evidence","reports","docs","input","reference","tools"]:
    (release/folder).mkdir()
shutil.copy2(attempt/"sync_frontend_synth.dcp",release/"checkpoints/sync_frontend_synth_original.dcp")
shutil.copy2(attempt/"sync_frontend_routed.dcp",release/"physical_evidence/sync_frontend_routed.dcp")
for name in ["physical_summary.txt","route_timing.txt","route_status.txt","route_utilization.txt","check_timing.txt","clocks.txt","cdc.txt","drc.txt","methodology.txt"]:
    shutil.copy2(attempt/name,release/"physical_evidence"/name)
for name in ["synth_utilization.txt","reference_rom_init.txt","synthesis_complete.txt"]:
    shutil.copy2(attempt/name,release/"reports"/name)
for name in ["core_utilization.txt","wrapper_utilization.txt","port_comparison.json","port_comparison.txt","export_check_complete.txt"]:
    shutil.copy2(export/name,release/"reports"/("edif_"+name))
for name in ["SF003_completion.json","SF001_ASTRA_REVIEW_ZH.md","SF002_ASTRA_REVIEW_ZH.md"]:
    shutil.copy2(root/"reports"/name,release/"reports"/name)
for name in ["PROJECT_GUI_ZH.md","CLIP_INTERFACE_BOARD_TEST_ZH.md","LABVIEW_TARGET_INTEGRATION_ZH.md"]:
    shutil.copy2(root/"docs"/name,release/"docs"/name)
shutil.copytree(root/"matlab",release/"matlab")
for name in ["autonomous_stream.mem","autonomous_manifest.json"]:
    shutil.copy2(root/"sim/data"/name,release/"input"/name)
shutil.copy2(root/"sim/data/autonomous_truth.mem",release/"reference/autonomous_truth.mem")
shutil.copy2(root/"reports/reference/autonomous_results.csv",release/"reference/autonomous_results.csv")
for name in ["compare_readback.py","check_dcp_release.tcl"]:
    shutil.copy2(root/"tools"/name,release/"tools"/name)
# Package source reads remain explicit; stale original package manifests are provenance only.
(package/"PROVENANCE_NOTE.txt").write_text("Original manifests describe Luna's immutable export package. This release adds all 43 EDN entries to XML and removes unsupported XDC assertions. The release-level manifest is authoritative for release bytes.\n",encoding="utf-8")
(release/"README_ZH.md").write_text("""# 同步前端 SF003 综合交付
状态：综合与EDF/EDN+VHDL独立链接已完成；本目录正在完成DCP直接关联复核，暂未宣布最终发布通过。
本机日期2026-09-15；冻结核心提交2e968f6e33a82a000326be9e6d9c7c97da9342bc，器件xcvu11p-flgb2104-2-e，Vivado2021.1。
用户已明确新增BUFG无需为0；不为此重实现。

clip_edif保存完整EDF、同次43 EDN、VHDL、补齐依赖的XML、端口表和平台边界XDC。
clip_dcp_template仅是DCP包XML模板，等待DCP只读导出/关联完成，不应把该单文件当完整包导入。
checkpoints保留原综合DCP；physical_evidence保存已有route及全部限制，供证据查看，不作为NI直接实例化网表。
独立core_relinked.dcp含非OOC链接产生的物理I/O缓冲，未放入交付核心；完整EDIF+EDN的OOC wrapper没有这些缓冲。
原生报告中的时钟XDC if断言没有执行，新的DCP收尾脚本将在普通Tcl中检查真实继承时钟。不得宣称原有断言已通过。

架构、全部端口、Host DMA输入和结果打包见docs/LABVIEW_TARGET_INTEGRATION_ZH.md。
四个lane是同一复数流的四个连续样点。输入是未同步I16/Q16，每U32高Q低I；Host不发送truth。
input/autonomous_stream.mem为板测输入；reference中的truth仅给Host比较，不进入FPGA。
matlab提供本地历史参考及包装入口，新增MATLAB包装未在本工程原生执行；其原有repo相对路径布局须依docs说明定位，后续将提供release适配入口。

实现证据：WNS2.087ns/WHS0.024ns、TNS/THS0，只覆盖已约束路径。133个同步输入漏input delay，另reset_n异步；OOC未验证NI外部路由。5BUFG仅作实际资源记录。DRC20条Warning+158条Advisory（合178），不是178条同等级Warning。
NI整个Target VI编译、板测、持续吞吐及整帧补偿不包含在本地验收内。不要将standalone_io_budget.xdc搬入NI。
""",encoding="utf-8")
for name in ["sync_frontend_clip.xml"]:
    paths=ET.parse(package/name).getroot().findall("./ImplementationList/Path")
    assert len(paths)==46
    for item in paths: assert (package/item.attrib["Name"]).is_file()
print("PREPARED",release,"EDN_XML_PATHS",len(paths))