from pathlib import Path
import json,re,hashlib
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915';B=A/'baseline_files';P=M/'work/functional_refactor_preview_v2_20260915/ready';plan=json.loads((A/'rename_plan.json').read_text());paths=plan['paths'];ids=plan['identifiers'];eq=json.loads((A/'preview_equivalence_v2.json').read_text());assert eq['status']=='PASS' and eq['passed']==79
all_paths=set(paths)|{'Sync_SFO.xpr','rtl/sources.f','wrapper/ports.csv','wrapper/interface_contract.json','tools/analysis/evidence/expected_fifo_bindings.json','tools/vivado/create_project.tcl','tools/vivado/open_sync_sfo.tcl','tools/vivado/start_simulation_0ns.tcl','tools/vivado/setup_waves.tcl','tools/analysis/validate_gui.py','tools/analysis/check_prefix.py','constraints/README_ZH.md'}
for rel in sorted(all_paths):
 src=M/rel;dst=B/rel
 if not dst.exists():dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(src.read_bytes())
 assert src.read_bytes()==dst.read_bytes(),rel

def save(rel,text):
 p=P/paths.get(rel,rel);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text,encoding='utf-8',newline='\n')
def rename_text(t):
 for old,new in sorted(paths.items(),key=lambda x:-len(x[0])):t=t.replace(old,new)
 for old,new in paths.items():t=t.replace(Path(old).name,Path(new).name)
 return re.sub(r'\b[A-Za-z_][A-Za-z_0-9$]*\b',lambda m:ids.get(m[0],m[0]),t)
for rel in ('constraints/t10_root_clocks.xdc','sim/data/t09_pilot_phase.mem'):
 p=P/paths[rel];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((B/rel).read_bytes())
wrapper=(B/'wrapper/t10_sfo_manual_wrapper.vhd').read_text();newwrapper=rename_text(wrapper)
# VHDL comments are unchanged; exact token stream restores after entity/core renaming.
wt=lambda s:re.findall(r'--[^\n]*|"(?:[^"]|"")*"|[A-Za-z_][A-Za-z_0-9]*|\d+|\S',s)
reverse={v:k for k,v in ids.items()};assert wt(wrapper)==[reverse.get(t,t) for t in wt(newwrapper)]
save('wrapper/t10_sfo_manual_wrapper.vhd',newwrapper)
save('Sync_SFO.xpr',rename_text((B/'Sync_SFO.xpr').read_text()))
save('rtl/sources.f','\n'.join(paths[x] for x in (B/'rtl/sources.f').read_text().splitlines())+'\n')
save('wrapper/ports.csv',(B/'wrapper/ports.csv').read_text())
contract=json.loads((B/'wrapper/interface_contract.json').read_text());contract['core']='sync_sfo_top';contract['entity']='sync_sfo_manual_wrapper';contract['core_source_sha256']=hashlib.sha256((P/'rtl/control/sync_sfo_top.sv').read_bytes()).hexdigest().upper();contract['baseline_commit']=plan['baseline'];contract['functional_refactor_proof']='../docs/functional_review_20260915/preview_equivalence_v2.json';contract['wrapper_source_sha256']=hashlib.sha256(newwrapper.encode()).hexdigest().upper();save('wrapper/interface_contract.json',json.dumps(contract,ensure_ascii=False,indent=2)+'\n')
for rel in ('tools/vivado/open_sync_sfo.tcl','tools/vivado/setup_waves.tcl','tools/analysis/check_prefix.py','constraints/README_ZH.md'):save(rel,rename_text((B/rel).read_text()))
rel='tools/vivado/create_project.tcl';s=rename_text((B/rel).read_text());s=s.replace('set projdir [file join $root vivado T10_SFO]','set projdir $root').replace('set projectfile [file join $projdir T10_SFO.xpr]','set projectfile [file join $projdir Sync_SFO.xpr]').replace('create_project T10_SFO $projdir','create_project Sync_SFO $projdir').replace('Opened existing T10_SFO','Opened existing Sync_SFO');s=s.replace('set target xcvu11p-flgb2104-2-e','if {[llength [get_projects -quiet]]} {error "Use an empty session; preserve any open GUI project."}\nset target xcvu11p-flgb2104-2-e');save(rel,s)
rel='tools/vivado/start_simulation_0ns.tcl';s=rename_text((B/rel).read_text()).replace('set simdir [file join $root vivado T10_SFO T10_SFO.sim sim_1 behav xsim]','if {[get_property TOP [get_filesets sources_1]] ne "sync_sfo_top"} {error "Expected sync_sfo_top"}\nif {[file normalize [get_property DIRECTORY [current_project]]] ne $root} {error "Use the root Sync_SFO project"}\nset simdir [file join $root Sync_SFO.sim sim_1 behav xsim]');save(rel,s)
# Rename hierarchical bindings using instance/type context, never replace common names globally.
types={}
for r in plan['instances']:types.setdefault(r['module'],{})[r['instance']]=r['type']
def hierarchy(text):
 parts=text.split('.');context=parts[0];out=[ids.get(context,context)]
 for part in parts[1:]:
  match=re.fullmatch(r'(\w+)(\[\d+\])?',part);name=match[1] if match else part;suffix=(match[2] or '') if match else ''
  if name in types.get(context,{}):out.append(plan['instance_scopes'].get(context,{}).get(name,name)+suffix);context=types[context][name]
  else:out.append(part)
 return '.'.join(out)
binding=json.loads((B/'tools/analysis/evidence/expected_fifo_bindings.json').read_text());binding['instances']=[hierarchy(s) for s in binding['instances']];assert len(set(binding['instances']))==32
bound={}
for old,h in binding['bound_input_sha256'].items():
 assert hashlib.sha256((M/old).read_bytes()).hexdigest().upper()==h
 new=paths.get(old,old);p=P/new if (P/new).is_file() else M/new;bound[new]=hashlib.sha256(p.read_bytes()).hexdigest().upper()
binding['bound_input_sha256']=bound;binding['scope']='Same frozen core behavior after verified functional naming/formatting; 32 expected FIFO identities remapped through module instance graph. Native binding observation for this renamed version remains pending.';binding['functional_refactor_baseline']=plan['baseline'];save('tools/analysis/evidence/expected_fifo_bindings.json',json.dumps(binding,indent=2)+'\n')
rel='tools/analysis/validate_gui.py';s=rename_text((B/rel).read_text());s=s.replace("P/'docs/provenance/RTL_FINAL_MANIFEST.csv'","P/'docs/functional_review_20260915/current_input_manifest.csv'");s=s.replace("prefixes += [Path('vivado/T10_SFO')/tree/'sources_1/ip'/n for tree in ('T10_SFO.gen','T10_SFO.srcs') for n in ip_names]","prefixes += [Path(tree)/'sources_1/ip'/n for tree in ('Sync_SFO.gen','Sync_SFO.srcs') for n in ip_names]")
start=s.index('    core=[x for x in copied');end=s.index('    log=L.read_text',start)
s=s[:start]+'''    proof=json.loads((P/'docs/functional_review_20260915/preview_equivalence_v2.json').read_text())
    need(proof['status']=='PASS' and proof['passed']==79,'Complete inverse-name proof required')
    mapping={r['old']:r for r in proof['files']}
    source_set=set((P/'rtl/sources.f').read_text().splitlines())
    core=[x for x in copied if x['destination_relative'] in mapping and mapping[x['destination_relative']]['new'] in source_set]
    need(len(core)==74,'74 original core identities required')
    for x in core:
        r=mapping[x['destination_relative']]
        need(r['before_sha256'].upper()==x['source_sha256'],'Baseline identity changed')
        need(sha(P/r['new'])==r['after_sha256'].upper(),'Renamed source differs from equivalence proof')
        need(all(r[k] for k in ('inverse_tokens_equal','inverse_raw_tokens_equal','inverse_tree_equal','ports_equal')),'Incomplete equivalence check')
    rename_plan=json.loads((P/'docs/functional_review_20260915/rename_plan.json').read_text())
    need({rename_plan['paths'].get(x['destination_relative'],x['destination_relative']) for x in copied}<=set(x['destination_relative'] for x in active),'Final manifest must cover all original migration inputs through rename map')
'''+s[end:];save(rel,s)
(A/'ancillary_preview.json').write_text(json.dumps({'status':'PASS','wrapper_inverse_tokens_equal':True,'core_ports':len(contract['core_ports']),'wrapper_ports':len(contract['wrapper_ports']),'fifo_binding_count':32,'pending_native_validation':True,'files':sorted(all_paths)},indent=2),encoding='utf-8');print('ANCILLARY_READY',len(all_paths),'WRAPPER_PORTS',len(contract['wrapper_ports']))
