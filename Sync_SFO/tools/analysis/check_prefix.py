from pathlib import Path
from decimal import Decimal
from datetime import datetime, timezone
import csv,json,re,hashlib

def require(ok,text):
 if not ok: raise AssertionError(text)
def canon(s):return re.sub(r'\\([^\s]+)\s*',r'\1',s).replace('/','.').strip('.')

def validate(root,package,emit=True,log_path=None):
 root,package=Path(root),Path(package)
 rows=list(csv.DictReader((root/'xpm_trace.csv').open(encoding='utf-8-sig')));groups={}
 for r in rows:
  domain=int(r['Domain']);identity=canon(r['Fifo']).removesuffix('.full023_observer');t=int(r['TimePs'])
  g=groups.setdefault((identity,domain),{});require(t not in g or g[t]==r,'Conflicting FIFO trace duplicates');g[t]=r
  require(r['Sleep'] in ['0','x'] and r['Overflow'] in ['0','x'] and r['Underflow'] in ['0','x'],'FIFO diagnostic event')
  en=r['WrEn' if domain==0 else 'RdEn'];busy=(r['Rst']!='0' or r['WrBusy']!='0') if domain==0 else r['RdBusy']!='0'
  if en=='1':require(not busy and r['Full' if domain==0 else 'Empty']=='0','Illegal FIFO access')
  if t>1000000:require(en in ['0','1'] and r['Sleep']==r['Overflow']==r['Underflow']=='0','Undefined FIFO control after startup')
 binding_path=package/'tools/analysis/evidence/expected_fifo_bindings.json'
 binding=json.loads(binding_path.read_text(encoding='utf-8'))
 expected={(identity,domain) for identity in binding['instances'] for domain in binding['domains']}
 require(len(binding['instances'])==32 and binding['domains']==[0,1] and len(expected)==64,'Invalid frozen FIFO binding inventory')
 for rel,wanted in binding['bound_input_sha256'].items():
  p=(package/rel).resolve();require(p.is_relative_to(package.resolve()),'Binding input leaves project')
  require(hashlib.sha256(p.read_bytes()).hexdigest().upper()==wanted,'FIFO binding source identity changed: '+rel)
 require(set(groups)==expected,'FIFO binding set mismatch: missing='+repr(sorted(expected-set(groups)))+' unexpected='+repr(sorted(set(groups)-expected)))
 log=(Path(log_path) if log_path is not None else root/'native_chunk_stream.log').read_text(errors='replace');context=None;classified=[]
 for line in log.splitlines():
  m=re.match(r'Time:\s*([0-9.]+) (ps|ns) Started:\s*([0-9.]+) (ps|ns) Scope:\s*(\S+)',line)
  if m:context=(int(Decimal(m[1])*(1000 if m[2]=='ns' else 1)),int(Decimal(m[3])*(1000 if m[4]=='ns' else 1)),canon(m[5]))
  if re.match(r'(?i)^\s*(?:error:|fatal:|error |fatal )',line):
   require(context is not None,'Native error without context: '+line)
   t,start,scope=context;m=re.match(r'Error: \[(SLEEP_CHECK S-[67]|EMPTY_CHECK S-4)\]',line)
   require(m is not None,'Unclassified native error: '+line);code=m[1];domain=0 if code.endswith('6') else 1
   matches=[k for k in groups if k[1]==domain and (scope==k[0] or scope.startswith(k[0]+'.'))]
   require(len(matches)==1,'Native diagnostic FIFO binding missing or ambiguous: '+scope)
   group=groups[matches[0]];require(t in group,'Missing exact diagnostic trace sample');cur=group[t]
   if code.startswith('SLEEP'):
    require(t==min(group) and start==t and cur['Sleep']==cur['WrEn']==cur['RdEn']=='0' and 'for 0 ' in line,'Sleep startup predicate not proven')
    proof=[cur]
   else:
    times=sorted(group);i=times.index(t);require(i>=2,'Missing EMPTY diagnostic history');old,prev=[group[x] for x in times[i-2:i]]
    require(int(prev['TimePs'])==start and prev['RdBusy']=='1' and old['RdBusy'] in ['0','x'] and prev['Empty']==cur['Empty']=='1' and prev['RdEn']==cur['RdEn']=='0','EMPTY reset predicate not proven')
    # Dense monitor history around each reset change retains consecutive read edges.
    require(t-start==start-int(old['TimePs']),'Nonconsecutive EMPTY signal history');proof=[old,prev,cur]
   classified.append(dict(code=code,time_ps=t,start_ps=start,scope=scope,predicate_proof=proof));context=None
 require(not re.search(r'(?i)warning:.*\[(?:OVERFLOW|UNDERFLOW)',log),'FIFO overflow warning')
 require('FULL023_FIXTURES_LOADED raw=334215 r1=334098 r2=334080 points=74' in log,'Input fixtures not loaded')
 # Source and numerical assertions execute every accepted beat in the native TB.
 events=list(csv.DictReader((root/'events.csv').open()))
 last_event=max((int(e['TimePs']) for e in events),default=None)
 last_trace=max((int(r['TimePs']) for r in rows),default=None)
 v=dict(status='TRACE_PREDICATES_CHECKED_BINDINGS_MATCH',checked_utc=datetime.now(timezone.utc).isoformat(),last_algorithm_event_time_ps=last_event,last_observed_trace_time_ps=last_trace,current_simulation_time_ps=None,complete_prefix_time_ps=None,prefix_closure_proven=False,continuous_trace_coverage_proven=False,binding_completeness_verified=True,binding_inventory_sha256=hashlib.sha256(binding_path.read_bytes()).hexdigest().upper(),fifo_instances=len(groups)//2,classified_native_events=classified,new_errors=0,complete_result_present=(root/'result.txt').exists(),T10_PASS=False)
 v['time_semantics']='Observed event and trace timestamps only; neither proves current simulation time or a closed prefix interval.'
 if emit:
  (root/'prefix_gate_latest.json').write_text(json.dumps(v,indent=2)+'\n',encoding='utf8')
  with (root/'prefix_gate_history.jsonl').open('a',encoding='utf8') as f:f.write(json.dumps({k:x for k,x in v.items() if k!='classified_native_events'})+'\n')
 return v
