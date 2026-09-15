"""Verify the passive LINK010R1 reset log; no waveform or estimator computation."""
from pathlib import Path
import argparse,json,hashlib,re

def run(path):
 path=Path(path);raw=path.read_bytes();lines=raw.decode('utf-8').splitlines()
 counts={k:0 for k in ['A','T','C','Q','Z']};epochs={i:{'A':[],'T':[],'C':[],'Q':[]} for i in range(9)};pairs={};terminal=None
 def need(ok,msg):
  if not ok:raise AssertionError(msg)
 def bits(s):
  need(bool(re.fullmatch('[01xXzZ]{32}',s)),'Expected a 32-bit four-state value')
  return {i:s[31-i].lower() for i in range(32)}
 def isv(b,zeros=(),ones=()):return all(b[x]=='0' for x in zeros) and all(b[x]=='1' for x in ones)
 for number,line in enumerate(lines,1):
  if not line.strip() or line.startswith('#'):continue
  need(terminal is None,f'Unexpected data after terminal line {number}')
  t=line.split();tag=t[0];need(tag in counts,f'Failure/unknown tag at {number}: {line}');counts[tag]+=1
  if tag=='Z':
   need(len(t)==8,'Bad terminal record');terminal=list(map(int,t[1:]));continue
  if tag=='A':
   need(len(t)==5,'Bad A record');trigger,check,epoch=map(int,t[1:4]);b=bits(t[4])
   need(check==trigger+10 and trigger>=0,'Asynchronous observation not at request+10ps')
   need(isv(b,[15,14,12,11],[31]),'Common reset did not mask all IO')
   if epoch==0:need(trigger==0 and b[26]=='1','Initial reset observation incorrect')
   need(isv(b,[29],[30]) if epoch==0 or epoch%2==1 else isv(b,[30],[29]),'Wrong reset/abort coverage')
   record={'trigger':trigger,'check':check,'bits':b}
  elif tag=='T':
   need(len(t)==5,'Bad T record');time,epoch,value,fast=map(int,t[1:])
   need(value in [0,1] and time==fast and time>=1000 and (time-1000)%2000==0,'FIFO reset transition not on fast rising edge')
   record={'time':time,'value':value}
  elif tag=='C':
   need(len(t)==4,'Bad C record');time,epoch=map(int,t[1:3]);b=bits(t[3])
   need(isv(b,[31,28,27,26,25,24,23,22,15,14,11,8,7,6],[21,20,19,18,17,16]),'Recovery did not clear FIFO/credit or complete handshake')
   need((time-1010)%2000==0,'Recovery not sampled 10ps after fast edge');record={'time':time,'bits':b}
  else:
   need(len(t)==8,'Bad Q record');edge,sample,epoch=map(int,t[1:4]);domain,phase=t[4:6];changed=int(t[6]);b=bits(t[7])
   need(domain in ['F','S'] and phase in ['P','A'] and changed in [0,1],'Invalid Q labels')
   first,period=(1000,2000) if domain=='F' else (3750,6666)
   need(edge>=first and (edge-first)%period==0,'Sample off declared clock grid')
   need(sample==edge+(-1 if phase=='P' else 10),'Wrong before/after sampling skew')
   if phase=='P':
    mask=[31,28,26,25,24,23] if domain=='F' else [31,27,26,25,24,22]
    blocked=[15,12] if domain=='F' else [14,5,11]
    if any(b[x]!='0' for x in mask):need(isv(b,blocked),'Enable asserted under edge-sampled reset/busy')
   elif not changed:
    if domain=='F':
     if b[19]=='1':need(isv(b,[26,25],[20]),'Writer completion asserted early')
     if b[23]=='0':need(isv(b,[31,28,26,25,24,22],[19,16]),'Fast admission opened early')
    else:
     if b[17]=='1':need(isv(b,[24],[18]),'Slow ready asserted early')
     if b[22]=='0':need(isv(b,[31,27,26,25,24],[18,17]),'Reader opened in reset-busy gap')
     if b[22]=='1':need(b[8]=='0','Frame credit changed in slow reset')
   key=(domain,edge);pair=pairs.setdefault(key,{})
   need(phase not in pair,'Duplicate sampling phase')
   record={'edge':edge,'sample':sample,'domain':domain,'phase':phase,'changed':changed,'bits':b,'epoch':epoch};pair[phase]=record
  need(epoch in epochs,'Invalid reset epoch');epochs[epoch][tag].append(record)
 need(terminal is not None and counts['Z']==1,'Missing terminal record')
 need(terminal[:4]==[9,8,9,9],'Reset/transition/recovery counts differ')
 need(counts['A']==9 and counts['T']==17 and counts['C']==9,'Event coverage incomplete')
 totals={d:0 for d in ['F','S']}
 transitions=[0,200231]
 for e in range(1,9):
  need(len(epochs[e]['A'])==1,'Missing reset request')
  t=epochs[e]['A'][0]['trigger'];transitions += [t,t+50117]
 for (domain,edge),pair in pairs.items():
  need(set(pair)=={'P','A'},'Unpaired clock sample');pre,post=pair['P'],pair['A'];totals[domain]+=1
  need(pre['changed']==post['changed'],'Mismatched sample window labels')
  external_diff=any(pre['bits'][x]!=post['bits'][x] for x in [31,30,29])
  real_window_change=any(edge<=t<=edge+10 for t in transitions)
  if external_diff:need(any(edge-1<=t<=edge+10 for t in transitions),'Reset bits differ without a stimulus transition')
  need(bool(pre['changed'])==(external_diff or real_window_change),'Unsupported reset-change exemption')
  need(post['epoch']-pre['epoch'] in [0,1],'Invalid epoch transition')
  if not pre['changed']:need(pre['epoch']==post['epoch'],'Unmarked common-reset change')
 need(terminal[4:]==[totals['F'],totals['S'],counts['Q']] and counts['Q']==2*len(pairs),'Terminal sample totals mismatch')
 last_recovery=-1
 for epoch,rows in epochs.items():
  need(len(rows['A'])==len(rows['C'])==1,'Each epoch needs one request and recovery')
  transitions=sorted(rows['T'],key=lambda x:x['time']);wanted=[0] if epoch==0 else [1,0]
  need([x['value'] for x in transitions]==wanted,'Incorrect per-epoch reset transitions')
  request=rows['A'][0]['trigger'];recovery=rows['C'][0]['time']
  need(request>last_recovery and request<transitions[0]['time'] and transitions[-1]['time']<recovery,'Reset sequence ordering invalid')
  last_recovery=recovery
  witness=pairs.get(('F',recovery-10),{}).get('A')
  need(witness is not None and witness['epoch']==epoch and witness['bits']==rows['C'][0]['bits'],'Recovery lacks matching fast POST witness')
  for domain,first,period in [('F',1000,2000),('S',3750,6666)]:
   start=first+max(0,(request-first+period-1)//period)*period
   for edge in range(start,recovery-9,period):
    need((domain,edge) in pairs,'Gap in clock observations during reset/recovery')
  for domain,busy in [('F',23),('S',22)]:
   after=[q for q in rows['Q'] if q['domain']==domain and q['phase']=='A']
   need(any(q['bits'][busy]=='1' for q in after),'Missing busy observation')
   need(any(q['bits'][23]==q['bits'][22]=='0' and q['sample']>=recovery for q in after),'Missing post-recovery observation')
 return {'status':'LINK010R1_RESET_AUDIT_PASS','path':str(path),'sha256':hashlib.sha256(raw).hexdigest().upper(),'rows':counts,'fast_sample_pairs':totals['F'],'slow_sample_pairs':totals['S'],'reset_epochs':9,'asynchronous_stop_checks':9,'fifo_assertions':8,'fifo_deassertions':9,'recoveries':9,'scope':'Passive checks on the unchanged LINK010 stimulus; no physical CDC qualification.'}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('path',type=Path);a=ap.parse_args();print(json.dumps(run(a.path)))
if __name__=='__main__':main()
