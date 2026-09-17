from pathlib import Path
import hashlib,json,csv,re,xml.etree.ElementTree as ET,zipfile
root=Path(r"D:/008_MA_Dev/Sync_Frontend")
attempt=root/"work/SF003_attempt_20260914T211953Z"
export=attempt/"export_check_synthesis_retry2"
package=export/"package"
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest().upper()
completion=root/"reports/SF003_completion.json"
assert sha(completion)=="3CE37ADCEDA47DB7499C80A4875DB4ED24C8E2507A7865C9AB38CA17AA04D83B"
data=json.loads(completion.read_text(encoding="utf-8-sig"))
checked=[]
def visit(obj):
    if isinstance(obj,dict):
        if all(k in obj for k in ("path","bytes","sha256")):
            p=Path(obj["path"]); assert p.is_file(),str(p)
            assert p.stat().st_size==obj["bytes"],str(p)
            assert sha(p)==obj["sha256"].upper(),str(p)
            checked.append(str(p))
        for v in obj.values(): visit(v)
    elif isinstance(obj,list):
        for v in obj: visit(v)
visit(data)
rows=list(csv.DictReader((root/"reports/design/SF003_files.csv").open(encoding="utf-8-sig",newline="")))
for row in rows:
    p=root/row["path"]; assert sha(p)==row["sha256"].upper(),str(p)
edns=sorted(attempt.glob("*.edn"))
assert len(edns)==43
for p in edns:
    assert sha(p)==sha(package/p.name),p.name
xml=ET.parse(package/"sync_frontend_clip.xml").getroot()
listed=[p.attrib["Name"] for p in xml.findall("./ImplementationList/Path")]
missing=[p.name for p in edns if p.name not in listed]
for name in listed: assert (package/name).is_file(),name
print("XML_PATHS",len(listed),"EDN_UNLISTED",len(missing),missing)
ports=json.loads((package/"ports.json").read_text())
signals=xml.findall("./InterfaceList/Interface/SignalList/Signal")
assert len(signals)==len(ports)==32
vhdl=(package/"sync_frontend_clip.vhd").read_text()
entity=vhdl.split("architecture rtl")[0]
port_actual={}
for m in re.finditer(r"(\w+)\s*:\s*(in|out)\s+std_logic(?:_vector\((\d+)\s+downto\s+0\))?",entity,re.I):
    port_actual[m[1]]=(m[2],int(m[3])+1 if m[3] else 1)
assert len(port_actual)==32
for p in ports: assert port_actual[p["name"]]==(p["direction"],p["bits"])
resources={}
for key,path in [("core",export/"core_utilization.txt"),("wrapper",export/"wrapper_utilization.txt")]:
    s=path.read_text()
    matches={}
    for line in s.splitlines():
        parts=[v.strip() for v in line.split("|")]
        if len(parts)>3 and parts[1].rstrip("*") in ["CLB LUTs","CLB Registers","Block RAM Tile","RAMB36/FIFO*","RAMB18","DSPs","URAM","BUFGCTRL","BUFGCE"]:
            matches.setdefault(parts[1].rstrip("*"),parts[2])
    resources[key]=matches
print("RESOURCES",resources)
dcp_entries={}
for p in [attempt/"sync_frontend_synth.dcp",export/"core_relinked.dcp",export/"wrapper_linked.dcp"]:
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        dcp_entries[p.name]=z.namelist()
    print("DCP_CONTAINER",p.name,"members",len(dcp_entries[p.name]))
result={"status":"IDENTITY_VERIFIED_XML_DEPENDENCIES_REQUIRE_RELEASE_FIX","completion_sha256":sha(completion),"checked_artifact_records":len(checked),"frozen_rows_verified":len(rows),"same_attempt_edns":43,"xml_paths":listed,"edn_missing_from_xml":missing,"vhdl_port_count":32,"resources":resources,"dcp_container_members":dcp_entries,"native_scope":"Independent EDF plus 43 EDN core and wrapper link passed per preserved native logs. Static ZIP checks are not native DCP reopening or NI integration."}
(root/"reports/SF003_ASTRA_STATIC_AUDIT.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("SF003_ASTRA_STATIC_AUDIT",len(checked),len(rows))