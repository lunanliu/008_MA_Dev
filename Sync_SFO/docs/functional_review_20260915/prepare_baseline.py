from pathlib import Path
import json,subprocess,hashlib,concurrent.futures,collections,xml.etree.ElementTree as E
R=Path('D:/008_MA_Dev');M=R/'Sync_SFO';A=M/'docs/functional_review_20260915';V=M/'work/functional_review_tools_20260915/package/verible-v0.0-4214-gce503962-win64';rows=json.loads((A/'baseline_source_inventory.json').read_text());files=[M/r['path'] for r in rows]+list((M/'sim/tb').glob('*.sv'));dst=A/'baseline_syntax';dst.mkdir(exist_ok=False)
def run(p):
 r=subprocess.run([str(V/'verible-verilog-syntax.exe'),'--export_json','--printtree','--printtokens',str(p)],capture_output=True)
 key=p.relative_to(M).as_posix().replace('/','__');(dst/(key+'.json')).write_bytes(r.stdout)
 return {'path':p.relative_to(M).as_posix(),'exit':r.returncode,'stderr':r.stderr.decode(errors='replace'),'json':str(dst/(key+'.json'))}
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:result=list(pool.map(run,files))
(A/'baseline_parser_results.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('PARSER',len(result),'FAILURES',[r for r in result if r['exit']])
# Revalidate the prior native export against the exact unchanged XPR and all direct members.
prior=json.loads((M/'docs/reorganization_20260915/static_entry_checks.json').read_text())['projects'][0]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(M/'Sync_SFO.xpr')==prior['sha256']
for fs in prior['filesets']:
 for f in fs['members']:assert sha(Path(f['path']))==f['sha256'],f['path']
lock={'baseline_commit':'dd5e8f7a642625f06c4996d17e3642bbadc7d557','source_xpr':'Sync_SFO.xpr','source_xpr_sha256':sha(M/'Sync_SFO.xpr'),'prior_actual_source_export':'docs/reorganization_20260915/native_files_1.tsv','prior_actual_export_sha256':sha(M/'docs/reorganization_20260915/native_files_1.tsv'),'native_export_reuse_condition':'Exact XPR and every direct dependency revalidated unchanged; fresh renamed actual source export required in Luna job.','direct_filesets':prior['filesets'],'vendor_generated_sources_unchanged':True}
(A/'baseline_project_lock.json').write_text(json.dumps(lock,indent=2),encoding='utf-8')
# Instance inventories from concrete syntax, with containing module and exact token positions.
instances=[];ports=[]
def nodes(n):
 if isinstance(n,dict):
  yield n
  for ch in n.get('children',[]):yield from nodes(ch)
def leaves(n):return [x for x in nodes(n) if 'start'in x]
for item in result:
 if item['exit']:continue
 d=next(iter(json.loads(Path(item['json']).read_text()).values()))
 for module in [n for n in nodes(d['tree']) if n.get('tag')=='kModuleDeclaration']:
  header=next(n for n in nodes(module) if n.get('tag')=='kModuleHeader');mod=header['children'][2]['text']
  for n in nodes(module):
   if n.get('tag')=='kInstantiationBase':
    group=n.get('children',[]);typ=leaves(group[0]);t=[x for x in typ if x.get('tag')=='SymbolIdentifier'];typename=t[0]['text'] if t else None
    for inst in [z for z in nodes(n) if z.get('tag')=='kGateInstance']:
     ident=inst['children'][0];instances.append({'file':item['path'],'module':mod,'type':typename,'instance':ident.get('text'),'start':ident.get('start'),'end':ident.get('end')})
  ports.append({'file':item['path'],'module':mod,'declarations':sum(n.get('tag')=='kPortDeclaration' for n in nodes(header)),'inherited_ports':sum(n.get('tag')=='kPort' for n in nodes(header))})
(A/'baseline_instances.json').write_text(json.dumps(instances,indent=2),encoding='utf-8');(A/'baseline_port_groups.json').write_text(json.dumps(ports,indent=2),encoding='utf-8');print('INSTANCES',len(instances),'PORT_GROUPS',len(ports),'INHERITED',sum(p['inherited_ports'] for p in ports))
for i in instances:
 if i['module'] in ('t10_two_pass_system','t10_two_pass_transport'):print(i['module'],i['type'],i['instance'])
assert all(r['exit']==0 for r in result)
