from pathlib import Path
import json,re,hashlib,csv,subprocess,concurrent.futures,xml.etree.ElementTree as E,ast
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915';B=A/'baseline_files';plan=json.loads((A/'rename_plan.json').read_text());eq=json.loads((A/'preview_equivalence_v2.json').read_text());paths=plan['paths'];ids=plan['identifiers'];errors=[]
def need(ok,msg):
 if not ok:errors.append(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for r in eq['files']:need(sha(M/r['new'])==r['after_sha256'],'Active candidate mismatch '+r['new']);need(sha(B/r['old'])==r['before_sha256'],'Baseline mismatch '+r['old'])
# Invert every XML path/name value and compare the complete project tree, not just file counts.
x0=E.parse(B/'Sync_SFO.xpr').getroot();x1=E.parse(M/'Sync_SFO.xpr').getroot();reverse={v:k for k,v in ids.items()}
def restore(t):
 if t is None:return None
 for new,old in sorted(((v,k) for k,v in paths.items()),key=lambda x:-len(x[0])):t=t.replace(new,old)
 for old,new in paths.items():t=t.replace(Path(new).name,Path(old).name)
 return re.sub(r'\b[A-Za-z_][A-Za-z_0-9$]*\b',lambda m:reverse.get(m[0],m[0]),t)
def xc(n,invert=False):return (n.tag,sorted((k,restore(v) if invert else v) for k,v in n.attrib.items()),(n.text or '').strip(),tuple(xc(c,invert) for c in n))
need(xc(x0)==xc(x1,True),'XPR inverse structure mismatch')
need(x1.find("./Configuration/Option[@Name='Part']").get('Val')=='xcvu11p-flgb2104-2-e','Part')
refs=[]
for fs in x1.findall('./FileSets/FileSet'):
 for f in fs.findall('File'):
  raw=f.get('Path');need(raw.startswith('$PPRDIR/'),'Non-module direct reference '+raw);rel=raw.removeprefix('$PPRDIR/');need((M/rel).is_file(),'Missing XPR input '+rel);refs.append({'fileset':fs.get('Name'),'relative':rel,'sha256':sha(M/rel)})
need(len(refs)==120,'120 direct dependencies');need(sum(r['relative'].endswith('.xci') for r in refs)==34,'34 XCI')
core=(M/'rtl/sources.f').read_text().splitlines();need(len(core)==len(set(core))==74,'74 unique core sources');need(set(core)=={r['relative'] for r in refs if r['relative'].startswith('rtl/') and '/vendor/' not in r['relative']},'Core fileset membership')
# Vendor/data/config file identity against the frozen native baseline export.
prior=json.loads((A/'baseline_project_lock.json').read_text());unchanged=0
for fs in prior['direct_filesets']:
 for r in fs['members']:
  rel=Path(r['path']).relative_to(M).as_posix()
  if rel not in paths:need(sha(M/rel)==r['sha256'],'Frozen direct member changed '+rel);unchanged+=1
for rel in ('constraints/t10_root_clocks.xdc','sim/data/t09_pilot_phase.mem'):need((B/rel).read_bytes()==(M/paths[rel]).read_bytes(),'Clock/data bytes changed '+rel)
# Named connections to all self-owned modules, including inactive generate branches.
V=M/'work/functional_review_tools_20260915/package/verible-v0.0-4214-gce503962-win64/verible-verilog-syntax.exe'
def parse(rel):
 p=M/rel;raw=p.read_bytes();r=subprocess.run([str(V),'--export_json','--printtree','--printrawtokens',str(p)],capture_output=True);assert r.returncode==0,rel;return rel,raw,next(iter(json.loads(r.stdout).values()))
def nodes(n):
 if isinstance(n,dict):
  yield n
  for c in n.get('children',[]):yield from nodes(c)
def leaves(n):return [t for t in nodes(n) if 'start' in t]
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:parsed=list(pool.map(parse,[r['new'] for r in eq['files']]))
mods={};module_nodes=[];old_names=[]
for rel,raw,d in parsed:
 for t in d['rawtokens']:
  word=raw[t['start']:t['end']].decode()
  if t['tag'] in ('SymbolIdentifier','PP_Identifier','MacroIdentifier','MacroCallId') and word.lstrip('`') in ids:old_names.append((rel,word))
 for n in nodes(d['tree']):
  if n.get('tag')!='kModuleDeclaration':continue
  h=next(t for t in nodes(n) if t.get('tag')=='kModuleHeader');name=h['children'][2]['text'];ports={}
  for p in nodes(h):
   if p.get('tag')=='kPortDeclaration':
    ll=leaves(p['children'][3]);ident=next(t for t in ll if t['tag']=='SymbolIdentifier');ports[ident['text']]=p
  need(name not in mods,'Duplicate module '+name);mods[name]=ports;module_nodes.append((rel,raw,name,n))
need(not old_names,'Old identifiers remain '+repr(old_names[:10]));connections=0;instances=0
for rel,raw,mod,n in module_nodes:
 for inst in nodes(n):
  if inst.get('tag')!='kInstantiationBase':continue
  typ=next((t['text'] for t in leaves(inst['children'][0]) if t['tag']=='SymbolIdentifier'),None)
  for gate in nodes(inst):
   if gate.get('tag')!='kGateInstance':continue
   instances+=1
   if typ not in mods:continue
   names=[]
   for port in nodes(gate):
    if port.get('tag')=='kActualNamedPort':
     p=next(t['text'] for t in leaves(port) if t['tag']=='SymbolIdentifier');names.append(p);need(p in mods[typ],f'Unknown named port {rel}:{typ}.{p}');connections+=1
   need(len(names)==len(set(names)),f'Duplicate named connection {mod}:{typ}')
# Core and independent VHDL wrapper interface, full ordered names/directions/widths.
contract=json.loads((M/'wrapper/interface_contract.json').read_text());rawtop=(M/'rtl/control/sync_sfo_top.sv').read_bytes();coreports=[]
for name,p in mods['sync_sfo_top'].items():
 ll=leaves(p);decl=rawtop[min(t['start'] for t in ll):max(t['end'] for t in ll)].decode();rng=re.search(r'\[\s*(\d+)\s*:\s*(\d+)\s*\]',decl);width=abs(int(rng[1])-int(rng[2]))+1 if rng else (96 if 'bistatic_estimator_result_t' in decl else 1);coreports.append((name,ll[0]['tag'],width))
need(coreports==[(r['name'],r['direction'],r['width']) for r in contract['core_ports']],'Core port contract mismatch')
vhd=(M/'wrapper/sync_sfo_manual_wrapper.vhd').read_text()
def vhports(kind,name):
 s=re.search(r'\b'+kind+r'\s+'+name+r'\s+is\s+port\s*\((.*?)\)\s*;',vhd,re.S|re.I)[1];found=[]
 for n,d,typ in re.findall(r'(\w+)\s*:\s*(in|out)\s+(std_logic(?:_vector\(\d+\s+downto\s+\d+\))?)',s,re.I):
  r=re.search(r'\((\d+)\s+downto\s+(\d+)\)',typ);found.append((n,'input' if d=='in' else 'output',int(r[1])-int(r[2])+1 if r else 1))
 return found
need(vhports('component','sync_sfo_top')==coreports,'VHDL component ports mismatch');need(vhports('entity','sync_sfo_manual_wrapper')==[(r['name'],r['direction'],r['width']) for r in contract['wrapper_ports']],'VHDL entity ports mismatch')
# Reference documents stay outside the input manifest; freeze all data and executable inputs.
original=list(csv.DictReader((M/'docs/provenance/RTL_COPY_MANIFEST.csv').open(encoding='utf-8-sig')));manifest_paths={paths.get(r['destination_relative'],r['destination_relative']) for r in original};manifest_paths.update(r['relative'] for r in refs);manifest_paths.update(p.relative_to(M).as_posix() for p in (M/'ip/config').rglob('*') if p.is_file());manifest_paths.update(p.relative_to(M).as_posix() for p in (M/'tools/vivado').glob('*.tcl'));manifest_paths.update(p.relative_to(M).as_posix() for p in (M/'rtl/include').glob('*.svh'));manifest_paths.update(['Sync_SFO.xpr','rtl/sources.f','ip/ip_names.txt','wrapper/sync_sfo_manual_wrapper.vhd','wrapper/interface_contract.json','wrapper/ports.csv','tools/analysis/validate_gui.py','tools/analysis/check_prefix.py','tools/analysis/evidence/expected_fifo_bindings.json','docs/functional_review_20260915/preview_equivalence_v2.json','docs/functional_review_20260915/rename_plan.json'])
for rel in ('tools/analysis/validate_gui.py','tools/analysis/check_prefix.py'):ast.parse((M/rel).read_text(),filename=rel)
manifest=[]
for rel in sorted(manifest_paths):
 p=M/rel;need(p.is_file(),'Manifest file missing '+rel)
 if p.is_file():manifest.append({'destination_relative':rel,'destination_sha256':sha(p).upper(),'bytes':p.stat().st_size})
with (A/'current_input_manifest.csv').open('w',encoding='utf-8',newline='') as f:
 w=csv.DictWriter(f,fieldnames=['destination_relative','destination_sha256','bytes']);w.writeheader();w.writerows(manifest)
summary={'status':'PASS' if not errors else 'FAIL','errors':errors,'baseline':plan['baseline'],'active_verified_sv_headers':len(eq['files']),'core_rtl':len(core),'direct_xpr_references':len(refs),'unchanged_direct_members':unchanged,'vendor_xci':34,'module_count':len(mods),'instance_count':instances,'own_named_port_connections_checked':connections,'core_ports':len(coreports),'wrapper_ports':len(contract['wrapper_ports']),'xpr_inverse_structure_equal':xc(x0)==xc(x1,True),'native_compile_elaborate':'PENDING','inputs':len(manifest),'input_bytes':sum(r['bytes'] for r in manifest),'input_manifest_sha256':sha(A/'current_input_manifest.csv'),'direct_members':refs}
(A/'active_static_checks.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in summary.items() if k!='direct_members'}));assert not errors
