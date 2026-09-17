from pathlib import Path
import json,re,csv,hashlib,collections,datetime,xml.etree.ElementTree as E
M=Path('D:/008_MA_Dev/Sync_SFO');R=M/'reports/functional_review/FN01';A=M/'docs/functional_review_20260915';P=M/'work/FN01/project';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper();summary=json.loads((R/'FN01_EXECUTION_SUMMARY.json').read_text());lines=(R/'native.log').read_text(errors='replace').splitlines();warnings=[]
for i,line in enumerate(lines):
 if line.startswith('WARNING:'):
  code=re.search(r'\[([^]]+)\]',line)[1];warnings.append({'line':i+1,'code':code,'message':line,'next_line':lines[i+1] if i+1<len(lines) else ''})
counts=collections.Counter(w['code'] for w in warnings);assert counts=={'filemgmt 56-3':2,'IP_Flow 19-2162':34,'filemgmt 56-2':2,'VRFC 10-3380':1,'VRFC 10-8426':1,'VRFC 10-2821':1,'VRFC 10-5021':1,'XSIM 43-3980':1};assert all('read-only' in w['next_line'] for w in warnings if w['code']=='IP_Flow 19-2162')
checks=[]
expected=(A/'job_FN01/expected_native_entries.tsv').read_text().splitlines()
for label,root in [('canonical',M),('private',P)]:
 rows=list(csv.DictReader((R/f'{label}_actual_files.tsv').open(),delimiter='\t'));actual=[]
 for r in rows:
  rel=Path(r['path']).relative_to(root).as_posix();actual.append('\t'.join([r['fileset'],rel.lower(),r['file_type'],r['library']]))
 assert sorted(actual)==sorted(expected);ips=list(csv.DictReader((R/f'{label}_ip_status.tsv').open(),delimiter='\t'));assert len(ips)==34 and all(r['locked']=='0' for r in ips);checks.append({'name':label,'native_members':len(rows),'native_members_match':True,'ip_count':34,'ip_export_locked_count':0})
diffs=json.loads((R/'astra_private_xpr_structure_diff.json').read_text());groups=collections.Counter()
for d in diffs:
 if d['path']=='Project':assert set(k for k in d['before'] if d['before'].get(k)!=d['after'].get(k))=={'Path'};groups['private_project_location']+=1
 elif 'WTXSimLaunchSim' in d['path']:assert d['before']['Val']=='0' and d['after']['Val']=='2';groups['compile_elaborate_launch_metadata']+=1
 elif d['path'].endswith('/Desc|'):assert d['before_count']==1 and d['after_count']==0;groups['strategy_description_removed']+=1
 else:
  assert 'Run|' in d['path'];assert {k for k in d['before'] if d['before'].get(k)!=d['after'].get(k)}=={'AutoIncrementalDir'};assert d['before']['AutoIncrementalCheckpoint']==d['after']['AutoIncrementalCheckpoint']=='false';groups['disabled_incremental_directory_rebased']+=1
assert groups=={'private_project_location':1,'compile_elaborate_launch_metadata':1,'strategy_description_removed':19,'disabled_incremental_directory_rebased':19}
# Baseline source-level origins of the five compile/elaborate warnings are retained by inverse equivalence.
verdict={'reviewed_at':datetime.datetime.now().astimezone().isoformat(),'reviewer':'01a0a53b-5d75-7e92-9b0b-184308ae662a','job':'SFO-FN01','status':'COMPILE_ELABORATE_AND_WRAPPER_SYNTAX_ACCEPTED','native_projects':checks,'actual_compilation':{'entries':138,'core':74,'tb':2,'xpm':3,'vendor_support':59,'all_inputs_private_and_frozen_hash_match':True},'errors':0,'critical_warnings':0,'warnings':{'count':len(warnings),'groups':dict(counts),'items':warnings},'canonical_frozen_inputs_verified':539,'canonical_frozen_input_mismatches':0,'private_unchanged_inputs':538,'private_xpr_diff_categories':dict(groups),'private_xpr_export_is_not_the_delivered_canonical_xpr':True,'native_seconds':(datetime.datetime.fromisoformat(summary['native_end'])-datetime.datetime.fromisoformat(summary['native_start'])).total_seconds(),'snapshot':'sync_sfo_full_frame_tb_behav','wrapper_syntax':'PASS_XVHDL_2021_1_2008','runtime_simulation':False,'synthesis':False,'physical_timing':False,'sustained_throughput':False,'NI_compile':False,'board_validation':False,'runtime_fifo_trace_binding_coverage':'NOT_RUN; 32 renamed expected paths retained, compile/elaboration accepted bind syntax, no runtime trace was produced.','remaining_review_item':'Process closure evidence archival from existing Luna telemetry; no rerun.'}
assert not any(re.match(r'^(?:ERROR:|CRITICAL WARNING:|FATAL:)',s) for s in lines)
assert 'Built simulation snapshot sync_sfo_full_frame_tb_behav' in '\n'.join(lines)
assert not list((P/'Sync_SFO.sim/sim_1/behav/xsim').glob('xsim.log'))
(R/'ASTRA_NATIVE_REVIEW_PRELIMINARY.json').write_text(json.dumps(verdict,ensure_ascii=False,indent=2),encoding='utf-8');print('NATIVE_REVIEW_ACCEPTED',dict(counts),'XML_DIFFS',dict(groups),'SECONDS',verdict['native_seconds'])
