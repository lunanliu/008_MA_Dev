"""Read saved evidence, packed vectors and native trace; no estimator recomputation."""
from pathlib import Path
import json,hashlib,csv,argparse
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def load(p):return json.loads(p.read_text('utf-8-sig'))
def mem(name):return [int(x,16) for x in (R/'sim/vectors'/name).read_text().split()]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sources',type=Path);ap.add_argument('--identity',type=Path);ap.add_argument('--actual',type=Path);a=ap.parse_args()
 lock=load(R/'docs/LINK010_SOURCE_LOCK.json')
 for x in lock['files']+lock['vendor_dependencies']:
  p=R/x['path'];assert p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],str(p)
 d=load(R/'sim/vectors/link010_cases.json');cs=d['cases'];es=d['errors'];assert len(cs)==4 and len(es)==10
 for p,h in d['source_hashes'].items():assert sha(R/p)==h,p
 for suffix,key in [('input','input_words'),('read','read_words')]:
  assert mem('link010_'+suffix+'.mem')==[v for c in cs for v in c[key]]
  assert mem('link010_error_'+suffix+'.mem')==[e[key][-1] for e in es]
 assert mem('link010_result.mem')==[c['result_word'] for c in cs]
 assert mem('link010_error_result.mem')==[e['result_word'] for e in es]
 assert [c['expected']['mode'] for c in cs]==[1,2,0,3]
 for c in cs:
  assert len(c['input_words'])==len(c['read_words'])==74
  assert c['result_word']&((1<<23)-1)==sum(p['fft_saturations'] for p in c['packets'])
 out={'status':'LINK010_SOURCE_VECTOR_PASS','frozen_files':len(lock['files']),'vendor_dependencies':len(lock['vendor_dependencies']),'cases':4,'real_front009_windows':74,'protocol_error_vectors':10,'native_checked':False,'no_fft_or_estimator_recomputation':True}
 if a.sources:
  rows=list(csv.DictReader(a.sources.open(newline='',encoding='utf-8-sig')))
  act={(x['fileset'],str(Path(x['path']).resolve()).casefold()) for x in rows};want={(x['fileset'],str((R/x['path']).resolve()).casefold()) for x in lock['project_members']}
  assert act==want and len(rows)==len(act),dict(extra=sorted(act-want),missing=sorted(want-act));out['actual_project_members']=len(rows)
 if a.identity:
  p=dict(x.split('=',1) for x in a.identity.read_text('utf-8-sig').splitlines())
  for k,v in {'part':'xcvu11p-flgb2104-2-e','hardware_top':'cfo_estimator_link','simulation_top':'cfo_estimator_link_tb','vivado':'2021.1','xelab_jobs':'16','xpm_libraries':'XPM_CDC XPM_FIFO XPM_MEMORY'}.items():assert p[k]==v,(k,p[k])
  assert Path(p['project']).resolve()==(R/'vivado/CFO_LINK010/CFO_LINK010.xpr').resolve();out['project_identity']='PASS'
 if a.actual:
  schedule=[('F',k,0) for k in range(4)]
  for i in range(8):schedule += [('D',0,i),('F',(i+1)%4,0)]
  for i in range(1,11):schedule += [('E',0,i),('F',(i-1)%4,0)]
  runs={};counts={x:0 for x in ['W','R','F','E','D','H']};max_tail=max_total=stalls=full_runs=0
  for line in a.actual.read_text().splitlines():
   it=line.split();tag=it[0];assert tag in counts,line;rid,k=map(int,it[1:3]);assert 0<=rid<len(schedule),line
   end,ci,param=schedule[rid];assert k==ci,line;r=runs.setdefault(rid,{'W':0,'R':0,'ended':False,'terminal':False});assert not r['ended'],line
   source=es[param-1] if end=='E' else cs[k]
   if tag in ['W','R']:
    assert not r['terminal'],line
    n=r[tag];key='input_words' if tag=='W' else 'read_words';assert len(it)==5 and int(it[3])==n and n<len(source[key]) and int(it[4],16)==source[key][n],line
    r[tag]+=1
    if tag=='R':assert r['R']<=r['W'],line
   elif tag=='F':
    assert end==tag and len(it)==11 and r['W']==r['R']==74 and int(it[3],16)==source['result_word'],line
    tail,total,stall,full,high,hold,paced=map(int,it[4:]);assert paced==int(rid==0) and hold==5+rid%4 and 1<=tail<=7800 and 0<total<=(1170000 if paced else 45000) and 0<=high<=18,line
    assert (stall==0 and full==0) if paced else (stall>0 and full==1),line
    max_tail=max(max_tail,tail);max_total=max(max_total,total);stalls+=stall;full_runs+=full;r['terminal']=True
   elif tag=='E':
    assert end==tag and len(it)==8 and int(it[3])==param and int(it[4],16)==source['result_word'] and int(it[5])==r['W']==len(source['input_words']) and int(it[6])==r['R']==r['W'] and int(it[7])==5+rid%4,line;r['terminal']=True
   elif tag=='H':
    assert end in ['E','F'] and r['terminal'] and len(it)==4 and int(it[3],16)==source['result_word'],line;r['ended']=True
   else:
    assert end==tag and len(it)==7 and int(it[3])==param%2 and int(it[4])==param//2 and int(it[5])==r['W'] and int(it[6])==r['R'],line
    place=param//2
    if place==0:assert r['W']==24 and 0<=r['R']<r['W'],line
    elif place==1:assert r['W']==r['R']==13,line
    else:assert r['W']==r['R']==74,line
    r['ended']=True
   counts[tag]+=1
  assert sorted(runs)==list(range(40)) and all(r['ended'] for r in runs.values()),runs
  assert counts['H']==32 and counts['F']==22 and counts['E']==10 and counts['D']==8 and counts['W']==2056 and 2066>counts['R']>=2008 and full_runs==21
  # W = normal1628 + errors58 + discards370 = 2056. Discards may intentionally flush unread queued packets.
  out.update(status='LINK010_NUMERIC_PASS_LIMITED_SCOPE',native_checked=True,rows=counts,max_tail_slow_cycles=max_tail,max_total_fast_cycles=max_total,source_backpressure_cycles=stalls,burst_full_runs=full_runs,complete_frames=22,discarded_frames=8,protocol_errors=10,modes=[1,2,0,3],whole_frame_waveform_tested=False,physical_cdc_qualified=False,synthesis_or_timing_qualified=False,formal_T11_T12_T13_PASS=False)
 print(json.dumps(out))
if __name__=='__main__':main()