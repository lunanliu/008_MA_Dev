from pathlib import Path
import json,hashlib,csv,shutil,re,zipfile,datetime
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
release=root/"release/Sync_Frontend_SF003_20260915_rev01"
# Keep original reference layout inside the distributable tree; no MATLAB code edits/reruns.
(release/"sim/data").mkdir(parents=True)
for name in ["autonomous_stream.mem","autonomous_manifest.json","autonomous_truth.mem"]:
    shutil.copy2(root/"sim/data"/name,release/"sim/data"/name)
(release/"reports/reference").mkdir()
shutil.copy2(root/"reports/reference/autonomous_results.csv",release/"reports/reference/autonomous_results.csv")
(release/"reports/provenance").mkdir()
shutil.copy2(root/"reports/provenance/matlab_reference_import.csv",release/"reports/provenance/matlab_reference_import.csv")
for name in ["SF003_ASTRA_REVIEW_ZH.md"]:
    shutil.copy2(root/"reports"/name,release/"reports"/name)
shutil.copy2(root/"tools/check_dcp_release.tcl",release/"tools/check_dcp_release.tcl")
# Repair the audit parser to use the first, overall resource table, not later per-SLR tables.
p=root/"tools/audit_sf003_delivery.py"
s=p.read_text()
s=s.replace('parts[1] in ["CLB LUTs",','parts[1].rstrip("*") in ["CLB LUTs",')
s=s.replace('matches[parts[1]]=parts[2]','matches.setdefault(parts[1].rstrip("*"),parts[2])')
s=s.replace('"status":"PASS_STATIC_AUDIT"','"status":"IDENTITY_VERIFIED_XML_DEPENDENCIES_REQUIRE_RELEASE_FIX"')
p.write_text(s,encoding="utf-8")
# Preserve chronology in detailed guide, while making current status prominent.
status="""\n当前更新（2026-09-15）：SF003综合、EDF+43EDN和OOC VHDL链接已复核；原XML漏列EDN已在release修复。原XDC中的if时钟断言未执行，不能照搬clock inheritance PASS。DCP直接关联与普通Tcl继承检查等待总管家下一空槽；不重综合原RTL/IP或重实现。以reports/SF003_ASTRA_REVIEW_ZH.md为准。\n"""
for name in ["LABVIEW_TARGET_INTEGRATION_ZH.md","PROJECT_GUI_ZH.md","CLIP_INTERFACE_BOARD_TEST_ZH.md"]:
    p=root/"docs"/name
    s=p.read_text(encoding="utf-8")
    s=s.replace("未同步的四路I16/Q16样点","未同步的单条I16/Q16流的四个连续样点")
    s=s.replace("没有MMCM、额外BUFG或500MHz域。","核心与OOC包装网表未实例化MMCM/BUFG；独立布局阶段插入5个控制网络BUFG，不构成新采样时钟域，没有500MHz逻辑域。")
    title,tail=s.split("\n",1)
    p.write_text(title+"\n"+status+tail,encoding="utf-8")
    shutil.copy2(p,release/"docs"/name)
p=root/"README_ZH.md"
s=p.read_text()
s=s.replace("SF003综合、独立布局布线及完整CLIP导出复读执行包已冻结，结果待执行。","SF003综合与EDF/43EDN+VHDL链接已复核，独立布局布线已完成但外部IO时序受限；DCP直接关联与有效Tcl时钟检查待新资源槽。")
s += "\n- 当前综合交付目录：release/Sync_Frontend_SF003_20260915_rev01（DCP分支收尾中）。\n- 最新复核：reports/SF003_ASTRA_REVIEW_ZH.md；具体接线：docs/LABVIEW_TARGET_INTEGRATION_ZH.md。\n"
p.write_text(s,encoding="utf-8")
p=release/"README_ZH.md"
s=p.read_text().replace("其原有repo相对路径布局须依docs说明定位，后续将提供release适配入口。","包内sim/data、reports/reference和reports/provenance保留原相对路径，入口可定位。")
s += "\n计算槽现属T11_T13，本包没有新Vivado运行授权。DCP检查需总管家安排下一空阶段，当前不启动。\n"
p.write_text(s,encoding="utf-8")
# The final CSV itself is outside its own hash input set.
paths=sorted(list((release/"clip_edif").glob("*"))+[release/"clip_dcp_template/sync_frontend_clip.xml",root/"tools/check_dcp_release.tcl",root/"tools/run_threads.tcl",root/"docs/SF003_DCP_RELEASE_CHECK_ZH.md"])
paths=[p for p in paths if p.is_file()]
lock=root/"reports/design/SF003_DCP_RELEASE_CHECK_files.csv"
with lock.open("w",newline="",encoding="utf-8") as f:
    w=csv.writer(f);w.writerow(["path","bytes","sha256"])
    for p in paths:w.writerow([p.relative_to(root).as_posix(),p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest()])
print("DCP_CHECK_LOCK",len(paths),hashlib.sha256(lock.read_bytes()).hexdigest())
print("MATLAB_RELEASE_PATHS_PRESERVED")