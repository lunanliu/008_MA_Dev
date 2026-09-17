from pathlib import Path
import xml.etree.ElementTree as ET,hashlib,json,csv,re,zipfile,struct
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
out=root/"handoff/Sync_Frontend_20260915_manual"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
# Read-only verification of the published handoff; never modifies the project or package.
xpr=root/"vivado/Sync_Frontend/Sync_Frontend.xpr"
xp=ET.parse(xpr).getroot()
conf={o.attrib["Name"]:o.attrib.get("Val") for o in xp.findall("./Configuration/Option")}
assert conf["Part"]=="xcvu11p-flgb2104-2-e"
fs={f.attrib["Name"]:f for f in xp.findall("./FileSets/FileSet")}
tops={n:next((o.attrib["Val"] for o in f.findall("./Config/Option") if o.attrib["Name"]=="TopModule"),None) for n,f in fs.items()}
assert tops["sources_1"]=="sync_frontend_top"
assert tops["sim_autonomous"]=="sync_frontend_tb"
macros={"$PPRDIR":xpr.parent,"$PSRCDIR":xpr.parent/"Sync_Frontend.srcs"}
records=[]
for name,fset in fs.items():
 for f in fset.findall("File"):
  s=f.attrib["Path"]
  for macro,p in macros.items():s=s.replace(macro,p.as_posix())
  assert "$" not in s,s
  p=Path(s).resolve()
  assert p.is_relative_to(root.resolve()) and p.is_file(),s
  records.append(dict(fileset=name,path=p.relative_to(root).as_posix(),bytes=p.stat().st_size,sha256=sha(p)))
sv=[r for r in records if r["fileset"]=="sources_1" and r["path"].endswith(".sv")]
ip=[r for r in records if r["path"].endswith(".xci")]
assert len(sv)==34 and len(ip)==15
assert not any("sync_frontend_clip.vhd" in r["path"] for r in records)
frozen=list(csv.DictReader((root/"reports/design/SF003_files.csv").open(encoding="utf-8-sig")))
for r in frozen:assert sha(root/r["path"]).lower()==r["sha256"].lower(),r["path"]
assert {r["path"] for r in sv}=={r["path"] for r in frozen if r["path"].startswith("rtl/") and r["path"].endswith(".sv")}
stored_records=list(csv.DictReader((out/"PROJECT_FILES.csv").open(encoding="utf-8")))
assert [{**r,"bytes":int(r["bytes"])} for r in stored_records]==records
# Static comparison of the explicit core interface, independent VHDL declaration and external ports.
v=(out/"sync_frontend_clip.vhd").read_text()
original_v=(root/"release/Sync_Frontend_SF003_20260915_rev01/clip_edif/sync_frontend_clip.vhd").read_text()
strip=lambda s:re.sub(r"\s+","",re.sub(r"--[^\n]*","",s)).lower()
assert strip(v)==strip(original_v)
def ports(s):
 return {m[1].lower():(m[2].lower(),int(m[3])+1 if m[3] else 1) for m in re.finditer(r"(\w+)\s*:\s*(in|out)\s+std_logic(?:_vector\s*\(\s*(\d+)\s+downto\s+0\s*\))?",s,re.I)}
external=ports(v.split("architecture rtl")[0])
component=ports(v.split("component sync_frontend_top is")[1].split("end component")[0])
dcp=root/"work/SF003_attempt_20260914T211953Z/sync_frontend_synth.dcp"
with zipfile.ZipFile(dcp) as z:
 stub=z.read("sync_frontend_top_stub.vhdl").decode()
meta_ports=ports(stub)
assert component==meta_ports and len(component)==22
metadata=json.loads((out/"ports.json").read_text())
assert external=={p["name"]:(p["direction"],p["bits"]) for p in metadata} and len(external)==32
port_map=dict(re.findall(r"(\w+)\s*=>\s*(\w+)",v.split("port map")[1]))
assert set(port_map)==set(component) and len(port_map)==22
assert port_map["clk"]=="clk125" and port_map["s_data"]=="raw_iq" and port_map["m_result"]=="result_bundle"
# Reversible input conversion only, no simulated or synthesized work.
raw=(out/"input/iq_u32_le.bin").read_bytes()
words=list(struct.unpack("<"+"I"*(len(raw)//4),raw))
hex_words=[int(s,16) for s in (out/"input/iq_u32_hex.txt").read_text().splitlines()]
assert words==hex_words and len(words)==60324
source=(root/"sim/data/autonomous_stream.mem").read_text().splitlines()
assert len(source)==15081
assert all("".join(f"{w:08x}" for w in reversed(words[4*i:4*i+4]))==s.lower() for i,s in enumerate(source))
assert sha(out/"input/autonomous_stream.mem")==sha(root/"sim/data/autonomous_stream.mem")
assert sha(out/"expected/autonomous_results.csv")==sha(root/"reports/reference/autonomous_results.csv")
assert not list(out.rglob("*.xml")) and not list(out.rglob("*.dcp"))
result={"status":"PASS_STATIC_MANUAL_HANDOFF","source_project":str(root),"xpr":str(xpr),"xpr_sha256":sha(xpr),"part":conf["Part"],"synthesis_top":tops["sources_1"],"default_simulation_set":conf["ActiveSimSet"],"autonomous_simulation_set":"sim_autonomous","autonomous_simulation_top":tops["sim_autonomous"],"selected_file_count":len(records),"hardware_sv_count":len(sv),"managed_ip_count":len(ip),"selected_files_exist_inside_project":True,"frozen_files_verified":len(frozen),"core_ports":22,"wrapper_ports":32,"wrapper_functional_text_unchanged":True,"wrapper_in_algorithm_synthesis_sources":False,"input_u32_count":len(words),"input_bytes":len(raw),"input_conversion_roundtrip":"PASS","expected_records":4,"new_clip_xml_count":0,"included_core_dcp_count":0,"native_runs_started":0,"ni_target_compile":"NOT_RUN","board":"NOT_RUN","sustained_throughput":"NOT_QUALIFIED"}
assert json.loads((out/"STATIC_HANDOFF_VALIDATION.json").read_text())==result
rows=list(csv.DictReader((out/"SHA256SUMS.csv").open(encoding="utf-8")))
for r in rows:assert sha(out/r["path"])==r["sha256"]
print(json.dumps(result,ensure_ascii=False))
print(json.dumps({"handoff_files":len(rows),"manifest_sha256":sha(out/"SHA256SUMS.csv"),"wrapper_sha256":sha(out/"sync_frontend_clip.vhd")},ensure_ascii=False))
