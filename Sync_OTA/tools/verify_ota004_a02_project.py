"""Read-only check of a full OTA project's actual source and managed IP identity."""
from pathlib import Path
import sys,json,hashlib,xml.etree.ElementTree as ET,re
root=Path(__file__).resolve().parents[1]
static_only=sys.argv[1:] == ['--dependencies-only']
attempt=None if static_only else Path(sys.argv[1]).resolve()
assert static_only or attempt.is_relative_to(root/'work/OTA004'),attempt
ns='{http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009}'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def lines(p):return [s.strip() for s in p.read_text(encoding='utf-8-sig').splitlines() if s.strip()]
def cfg(p):return {e.get(ns+'referenceId'):e.text for e in ET.parse(p).getroot().iter(ns+'configurableElementValue')}
rtl=lines(root/'rtl/sources.f');ips=lines(root/'ip/sources.f')

headers=lines(root/'rtl/headers_ota004_a02.f')
assert len(headers)==len(set(headers))==3,headers
expected_headers={(root/s).resolve() for s in headers}
include_dir=(root/'rtl/include').resolve()
lock=json.loads((root/'docs/jobs/OTA004_A02_source_lock.json').read_text(encoding='utf-8-sig'))
locked={f['path']:f for f in lock['files']}
for rel,f in locked.items():
 p=root/rel
 assert p.is_file() and p.stat().st_size==f['bytes'] and sha(p)==f['sha256'],('frozen input mismatch',rel)
origin=json.loads((root/'docs/provenance/OTA004_A02_INCLUDE_SOURCE_LOCK.json').read_text())
assert {r['destination'] for r in origin['files']}==set(headers)
for r in origin['files']:
 assert sha(root/r['destination'])==r['sha256'],r
# Resolve every textual include in this exact production set, TB and private XPM;
# recursively visit included headers and reject missing or ambiguous local files.
# Headers are dependencies, not separate Verilog compilation units.
scan=[(root/s).resolve() for s in rtl+headers]
scan += [(root/'sim/tb/sync_ota_smoke_tb.sv').resolve()]
scan += [(root/f'sim/vendor/link010r1/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory')]
scan += [(root/f'rtl/vendor/xpm/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory')]
visited=set();edges=[];used_headers=set()
include_pattern=re.compile(chr(96)+r'include\s+([^\r\n]+)')
while scan:
 source=scan.pop()
 if source in visited:continue
 visited.add(source)
 body=re.sub(r'//[^\n]*|/\*.*?\*/','',source.read_text(),flags=re.S)
 for match in include_pattern.finditer(body):
  value=match.group(1).strip()
  parsed=re.fullmatch(r'"([^"]+)"',value)
  assert parsed,('unsupported dynamic include',source,value)
  name=parsed.group(1)
  candidates={p.resolve() for p in [source.parent/name,include_dir/name] if p.is_file()}
  assert len(candidates)==1,('missing or ambiguous include',source,name,sorted(map(str,candidates)))
  target=candidates.pop()
  assert target in expected_headers,('unregistered include dependency',source,target)
  used_headers.add(target);scan.append(target)
  edges.append(dict(source=source.relative_to(root).as_posix(),include=name,resolved=target.relative_to(root).as_posix(),bytes=target.stat().st_size,sha256=sha(target)))
assert used_headers==expected_headers,('unused/missing headers',expected_headers-used_headers)
dependencies=dict(header_files=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)) for p in sorted(expected_headers)],resolved_include_edges=edges,scanned_files=len(visited),locked_files=len(locked))
if static_only:
 print(json.dumps(dict(status='OTA004_A02_STATIC_DEPENDENCIES_PASS',**dependencies),indent=2))
 sys.exit(0)
dirs=[s.split('\t') for s in lines(attempt/'actual_include_dirs.tsv')]
assert len(dirs)==2 and {fs for fs,_ in dirs}=={'sources_1','sim_1'},dirs
assert all(Path(path).resolve()==include_dir for _,path in dirs),dirs
actual_headers=[s.split('\t') for s in lines(attempt/'actual_headers.tsv')]
assert len(actual_headers)==3 and {Path(r[0]).resolve() for r in actual_headers}==expected_headers,actual_headers
assert all((ft,sy,si)==('Verilog Header','1','1') for _,ft,sy,si in actual_headers),actual_headers
dependencies['actual_include_dirs']=dirs
dependencies['actual_headers_sha256']=sha(attempt/'actual_headers.tsv')
dependencies['actual_include_dirs_sha256']=sha(attempt/'actual_include_dirs.tsv')

rows=[s.split('\t') for s in lines(attempt/'actual_sources.tsv')]
actual_rtl=[Path(a[1]).resolve() for a in rows if a[0]=='sources_1' and Path(a[1]).suffix=='.sv' and '/rtl/vendor/' not in a[1].replace('\\','/')]
assert sorted(actual_rtl)==sorted((root/s).resolve() for s in rtl)
assert {Path(a[1]).resolve() for a in rows if a[0]=='sources_1' and Path(a[1]).suffix=='.svh'}==expected_headers
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
result=dict(status='OTA004_PROJECT_IDENTITY_PASS',rtl_files=len(rtl),module_and_package_definitions=len(mods),managed_ips=ip_records,source_set_sha256=sha(attempt/'actual_sources.tsv'),compile_order_inputs=compiled,include_dependencies=dependencies)
(attempt/'project_identity_verified.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('OTA004_PROJECT_IDENTITY_PASS rtl='+str(len(rtl))+' ips=45')
