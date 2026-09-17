from pathlib import Path
import hashlib,json,csv,shutil,xml.etree.ElementTree as ET,re
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
release=root/"release/Sync_Frontend_SF003_20260915_rev01"
package=release/"clip_edif"
source=root/"work/SF003_attempt_20260914T211953Z/export_check_synthesis_retry2/package"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
xmlpaths=[x.attrib["Name"] for x in ET.parse(package/"sync_frontend_clip.xml").getroot().findall("./ImplementationList/Path")]
assert len(xmlpaths)==46
for name in xmlpaths: assert (package/name).is_file()
edns=sorted(package.glob("*.edn"))
assert len(edns)==43
for p in edns: assert sha(p)==sha(source/p.name)
for name in ["sync_frontend_top.edf","sync_frontend_clip.vhd","ports.json"]: assert sha(package/name)==sha(source/name)
assert not any(re.match(r"\s*(if|create_clock|set_input_delay|set_output_delay|set_false_path)\b",line) for line in (package/"sync_frontend_clip.xdc").read_text().splitlines())
s=(root/"tools/check_dcp_release.tcl").read_text()
assert chr(92)+chr(34) not in s,"Unexpected escaped literal quotes"
with (root/"reports/design/SF003_DCP_RELEASE_CHECK_files.csv").open(encoding="utf-8",newline="") as f:
    for row in csv.DictReader(f): assert sha(root/row["path"])==row["sha256"]
result={"status":"PASS_STATIC_EDIF_PACKAGE","xml_dependency_paths":46,"same_attempt_edn_count":43,"edif_vhdl_ports_unchanged":True,"native_edif_wrapper_link":"PASS_PRESERVED","original_clock_xdc_assertions":"NOT_EXECUTED_UNSUPPORTED_IF","release_xdc":"NI_clock_ownership_only_no_unsupported_commands","dcp_direct_wrapper_check":"PENDING_NEW_RESOURCE_GRANT","ni_target_compile":"NOT_RUN","source_core_commit":"2e968f6e33a82a000326be9e6d9c7c97da9342bc"}
(root/"reports/SF003_RELEASE_STATIC_CHECK.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
shutil.copy2(root/"reports/SF003_RELEASE_STATIC_CHECK.json",release/"reports/SF003_RELEASE_STATIC_CHECK.json")
shutil.copy2(root/"reports/SF003_ASTRA_STATIC_AUDIT.json",release/"reports/SF003_ASTRA_STATIC_AUDIT.json")
lock=release/"SHA256SUMS.csv"
with lock.open("w",encoding="utf-8",newline="") as f:
    w=csv.writer(f);w.writerow(["path","bytes","sha256"])
    for p in sorted(release.rglob("*")):
        if p.is_file() and p!=lock:w.writerow([p.relative_to(release).as_posix(),p.stat().st_size,sha(p)])
with lock.open(encoding="utf-8",newline="") as f:
    rows=list(csv.DictReader(f))
for row in rows:assert sha(release/row["path"])==row["sha256"]
print(json.dumps({"release_files":len(rows),"manifest_sha256":sha(lock),"dcp_lock_sha256":sha(root/"reports/design/SF003_DCP_RELEASE_CHECK_files.csv"),"status":"STATIC_PACKAGE_VERIFIED_NATIVE_DCP_CHECK_PENDING"}))