"""Read-only check of a full OTA project's actual source and managed IP identity."""
from pathlib import Path
import sys,json,hashlib,xml.etree.ElementTree as ET,re
root=Path(__file__).resolve().parents[1];attempt=Path(sys.argv[1]).resolve()
assert attempt.is_relative_to(root/'work/OTA004'),attempt
ns='{http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009}'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def lines(p):return [s.strip() for s in p.read_text(encoding='utf-8-sig').splitlines() if s.strip()]
def cfg(p):return {e.get(ns+'referenceId'):e.text for e in ET.parse(p).getroot().iter(ns+'configurableElementValue')}
rtl=lines(root/'rtl/sources.f');ips=lines(root/'ip/sources.f')
rows=[s.split('\t') for s in lines(attempt/'actual_sources.tsv')]
actual_rtl=[Path(a[1]).resolve() for a in rows if a[0]=='sources_1' and Path(a[1]).suffix=='.sv' and '/rtl/vendor/' not in a[1].replace('\\','/')]
assert sorted(actual_rtl)==sorted((root/s).resolve() for s in rtl)
for fs,path,lib,synth,sim in rows:
 p=Path(path).resolve()
 if p.suffix=='.sv' and ('/rtl/' in p.as_posix() or '/sim/' in p.as_posix()):assert lib=='ota_xpm',(path,lib)
 if '/rtl/vendor/' in p.as_posix():assert (synth,sim)==('1','0')
 if '/sim/vendor/' in p.as_posix():assert (synth,sim)==('0','1')
actual_ips=[s.split('\t') for s in lines(attempt/'actual_ips.tsv')]
assert len(actual_ips)==len(ips)==45
expected={Path(p).stem:root/p for p in ips};ip_records=[]
for name,path,locked in actual_ips:
 assert name in expected and locked.lower() in ('0','false'),(name,path,locked)
 p=Path(path).resolve();assert p.is_relative_to(root/'Sync_OTA.srcs'),p
 before,after=cfg(expected[name]),cfg(p)
 differences={k:[before.get(k),after.get(k)] for k in before.keys()|after.keys() if before.get(k)!=after.get(k)}
 assert all(k.startswith('RUNTIME_PARAM.') for k in differences),(name,differences)
 ip_records.append(dict(name=name,path=str(p),sha256=sha(p),runtime_only_differences=differences))
mods={}
for rel in rtl:
 t=re.sub(r'//[^\n]*|/\*.*?\*/','',(root/rel).read_text(),flags=re.S)
 t=re.sub(r'"(?:\\.|[^"\\])*"','""',t)
 for kind,name in re.findall(r'\b(module|package)\s+(\w+)',t):
  assert name not in mods,(name,rel,mods.get(name));mods[name]=rel
assert mods['sync_ota_top']=='rtl/control/sync_ota_top.sv'
assert mods['ota_cfo_chain']=='rtl/cfo/ota_cfo_chain_a02.sv'
assert '.REQUIRE_CONTEXT_ACK(1)' in (root/rtl[-1]).read_text()
compiled={}
for usage in ['simulation','synthesis']:
 entries=[]
 for value in lines(attempt/f'compile_order_{usage}.txt'):
  p=Path(value).resolve();assert p.is_file(),p
  entries.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)))
 compiled[usage]=entries
result=dict(status='OTA004_PROJECT_IDENTITY_PASS',rtl_files=len(rtl),module_and_package_definitions=len(mods),managed_ips=ip_records,source_set_sha256=sha(attempt/'actual_sources.tsv'),compile_order_inputs=compiled)
(attempt/'project_identity_verified.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('OTA004_PROJECT_IDENTITY_PASS rtl='+str(len(rtl))+' ips=45')
