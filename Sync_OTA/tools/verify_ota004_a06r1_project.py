"""Read-only check of a full OTA project's actual source and managed IP identity."""
from pathlib import Path
import sys,json,hashlib,xml.etree.ElementTree as ET,re,html
root=Path(__file__).resolve().parents[1]
static_only=sys.argv[1:] == ['--dependencies-only']
attempt=None if static_only else Path(sys.argv[1]).resolve()
assert static_only or attempt.is_relative_to(root/'work/OTA004'),attempt
ns='{http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009}'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def lines(p):return [s.strip() for s in p.read_text(encoding='utf-8-sig').splitlines() if s.strip()]
def cfg(p):return {e.get(ns+'referenceId'):e.text for e in ET.parse(p).getroot().iter(ns+'configurableElementValue')}
def tsv(name,count):
 rows=[line.split('\t') for line in (attempt/name).read_text(encoding='utf-8-sig').splitlines() if line.strip()]
 assert all(len(row)==count for row in rows),(name,[(i,len(row)) for i,row in enumerate(rows) if len(row)!=count])
 return rows
def boundary(p):
 attributes=re.findall(rb'xilinx:boundaryDescriptionJSON="([^"]*)"',p.read_bytes(),re.S)
 assert len(attributes)==1,('expected one vendor boundary',p)
 literal=attributes[0]
 # Vivado's XCI wraps this embedded JSON attribute at physical line boundaries.
 # Preserve the literal in files; join only for JSON validation/comparison.
 text=html.unescape(literal.replace(b'\r',b'').replace(b'\n',b'').decode())
 return literal,json.loads(text)

rtl=lines(root/'rtl/sources_a06.f');ips=lines(root/'ip/sources_a04.f')

headers=lines(root/'rtl/headers_ota004_a02.f')
assert len(headers)==len(set(headers))==3,headers
expected_headers={(root/s).resolve() for s in headers}
include_dir=(root/'rtl/include').resolve()
lock=json.loads((root/'docs/jobs/OTA004_A06R1_source_lock.json').read_text(encoding='utf-8-sig'))
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
scan += [(root/'sim/tb/sync_ota_smoke_tb_a06.sv').resolve()]
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
ip_provenance=json.loads((root/'docs/provenance/OTA004_A04_IP_SOURCE_LOCK.json').read_text())
assert {r['target'] for r in ip_provenance['files']}==set(ips)
for r in ip_provenance['files']:
 p=root/r['target'];literal,_=boundary(p)
 assert sha(p)==r['target_sha256']
 assert hashlib.sha256(literal).hexdigest()==r['original_boundary_bytes_sha256'],('vendor boundary changed',p)
dependencies['byte_preserved_vendor_ip_boundaries']=len(ip_provenance['files'])

if static_only:
 print(json.dumps(dict(status='OTA004_A06R1_STATIC_DEPENDENCIES_PASS',**dependencies),indent=2))
 sys.exit(0)
dirs=tsv('actual_include_dirs.tsv',2)
assert len(dirs)==2 and {fs for fs,_ in dirs}=={'sources_1','sim_1'},dirs
assert all(Path(path).resolve()==include_dir for _,path in dirs),dirs
actual_headers=tsv('actual_headers.tsv',4)
assert len(actual_headers)==3 and {Path(r[0]).resolve() for r in actual_headers}==expected_headers,actual_headers
assert all((ft,sy,si)==('Verilog Header','1','1') for _,ft,sy,si in actual_headers),actual_headers
dependencies['actual_include_dirs']=dirs
dependencies['actual_headers_sha256']=sha(attempt/'actual_headers.tsv')
dependencies['actual_include_dirs_sha256']=sha(attempt/'actual_include_dirs.tsv')

rows=tsv('actual_sources.tsv',5)
actual_rtl=[Path(a[1]).resolve() for a in rows if a[0]=='sources_1' and Path(a[1]).suffix=='.sv' and '/rtl/vendor/' not in a[1].replace('\\','/')]
assert sorted(actual_rtl)==sorted((root/s).resolve() for s in rtl)
assert {Path(a[1]).resolve() for a in rows if a[0]=='sources_1' and Path(a[1]).suffix=='.svh'}==expected_headers
for fs,path,lib,synth,sim in rows:
 p=Path(path).resolve()
 if p.suffix=='.sv' and ('/rtl/' in p.as_posix() or '/sim/' in p.as_posix()):assert lib=='ota_xpm',(path,lib)
 if '/rtl/vendor/' in p.as_posix():assert (synth,sim)==('0','0')
 if '/sim/vendor/' in p.as_posix():assert (synth,sim)==('0','1')
actual_ips=tsv('actual_ips.tsv',3)
assert len(actual_ips)==len(ips)==45
expected={Path(p).stem:root/p for p in ips};ip_records=[]
for name,path,locked in actual_ips:
 assert name in expected and locked.lower() in ('0','false'),(name,path,locked)
 p=Path(path).resolve();assert p.is_relative_to(root/'Sync_OTA.srcs'),p
 expected_boundary=boundary(expected[name])[1];actual_boundary=boundary(p)[1]
 assert expected_boundary==actual_boundary,('vendor boundary content changed',name)
 before,after=cfg(expected[name]),cfg(p)
 differences={k:[before.get(k),after.get(k)] for k in before.keys()|after.keys() if before.get(k)!=after.get(k)}
 assert all(k.startswith('RUNTIME_PARAM.') for k in differences),(name,differences)
 ip_records.append(dict(name=name,path=str(p),sha256=sha(p),runtime_only_differences=differences))
mif_parameters=[]
for name,p in expected.items():
 for key,value in cfg(p).items():
  if value and value.lower().endswith('.mif'):
   assert Path(value).name==value and key=='MODELPARAM_VALUE.C_COEF_FILE',(name,key,value)
   mif_parameters.append(dict(ip=name,key=key,filename=value))
assert len(mif_parameters)==4
generated_state=(attempt/'audit_generation_state.txt').read_text().strip()
assert generated_state in ('0','1'),generated_state
mif_records=[]
if generated_state=='1':
 actual_mifs=[Path(s).resolve() for s in lines(attempt/'actual_mif_files.txt')]
 assert actual_mifs, 'generate_target did not publish registered MIF dependencies'
 for m in mif_parameters:
  matches=sorted(set(p for p in actual_mifs if p.name==m['filename']))
  assert matches,('missing registered generated MIF',m)
  for p in matches:
   assert p.is_relative_to(root) and p.is_file() and p.stat().st_size>0,p
  hashes={sha(p) for p in matches};assert len(hashes)==1,('conflicting MIF copies',m,matches)
  mif_records.append(dict(**m,sha256=hashes.pop(),actual_files=[str(p) for p in matches],bytes=matches[0].stat().st_size))
 if len(sys.argv)>2:
  sim=Path(sys.argv[2]).resolve();assert sim.is_relative_to(root/'Sync_OTA.sim'),sim
  for m in mif_records:
   p=sim/m['filename']
   assert p.is_file() and sha(p)==m['sha256'],('simulation MIF missing or changed',p)
   m['simulation_copy']=str(p)
elif len(sys.argv)>2:raise AssertionError('simulation must use generated targets')

mods={}
for rel in rtl:
 t=re.sub(r'//[^\n]*|/\*.*?\*/','',(root/rel).read_text(),flags=re.S)
 t=re.sub(r'"(?:\\.|[^"\\])*"','""',t)
 for kind,name in re.findall(r'\b(module|package)\s+(\w+)',t):
  assert name not in mods,(name,rel,mods.get(name));mods[name]=rel
assert mods['sync_ota_top']=='rtl/control/sync_ota_top_a06.sv'
assert mods['ota_cfo_chain']=='rtl/cfo/ota_cfo_chain_a06.sv'
assert '.REQUIRE_CONTEXT_ACK(1)' in (root/rtl[-1]).read_text()
compiled={}
for usage in ['simulation','synthesis']:
 entries=[]
 for value in lines(attempt/f'compile_order_{usage}.txt'):
  p=Path(value).resolve();assert p.is_file(),p
  entries.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)))
 compiled[usage]=entries
registration=(attempt/'actual_xpm_registration.txt').read_text().splitlines()
xpm_state=dict(stage=registration[0],libraries=registration[1].split(',') if len(registration)>1 and registration[1] else [])
if xpm_state['stage']=='synth':
 assert set(xpm_state['libraries'])=={'XPM_CDC','XPM_FIFO','XPM_MEMORY'},xpm_state
 assert all('/rtl/vendor/' not in f['path'].replace('\\','/') for f in compiled['synthesis'])
for row in json.loads((root/'docs/provenance/OTA004_A06_REUSED_IP_DCP_LOCK.json').read_text())['files']:
 target=root/row['path'];assert target.is_file() and sha(target)==row['sha256'],('reused IP DCP changed',row)
for row in json.loads((root/'docs/provenance/OTA004_A06_VENDOR_RUNTIME_LOCK.json').read_text())['files']:
 assert sha(Path(row['installed']))==row['sha256'] and sha(root/row['copy'])==row['sha256'],('vendor runtime changed',row)
result=dict(status='OTA004_PROJECT_IDENTITY_PASS',rtl_files=len(rtl),module_and_package_definitions=len(mods),managed_ips=ip_records,source_set_sha256=sha(attempt/'actual_sources.tsv'),compile_order_inputs=compiled,include_dependencies=dependencies,mif_dependencies=mif_records,generated_state=generated_state,xpm_registration=xpm_state)
(attempt/'project_identity_verified.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('OTA004_PROJECT_IDENTITY_PASS rtl='+str(len(rtl))+' ips=45')
