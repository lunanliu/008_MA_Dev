import csv,json,sys,hashlib
from pathlib import Path
import numpy as np
if len(sys.argv)!=4:raise SystemExit('usage: python report_evm_gui.py REPO RUNTIME_DIR REVIEW_DIR')
p,s,o=map(Path,sys.argv[1:])
summary=json.loads((o/'summary.json').read_text());assert summary['checks_completed'] and summary['full_frame_behavioral_completed'] and not summary['T10_PASS']
def mem(name):return np.frombuffer(b''.join(int(l,16).to_bytes(16,'little') for l in (p/'sim/data'/name).read_text().splitlines()),dtype='<i2').reshape(-1,2)
refs={'E1':mem('r1.mem'),'OUT':mem('r2.mem')};got={k:np.empty_like(v) for k,v in refs.items()};counts={k:0 for k in refs}
with (s/'data.csv').open() as f:
 for r in csv.DictReader(f):
  k=r['Kind']
  if k not in got:continue
  i=int(r['Beat']);assert i==counts[k]
  got[k][4*i:4*i+4]=np.frombuffer(int(r['Data'],16).to_bytes(16,'little'),dtype='<i2').reshape(4,2);counts[k]+=1
for k in counts:assert counts[k]*4==len(refs[k])
def metrics(x,y):
 err=x.astype(np.float64)-y.astype(np.float64);ref=y.astype(np.float64);den=float(np.sum(ref*ref));num=float(np.sum(err*err))
 return dict(error_energy=num,reference_energy=den,evm_percent=100*np.sqrt(num/den) if den else None,max_component_lsb=int(np.max(np.abs(err))))
report=dict(definition='sqrt(sum(abs(actual-reference)^2)/sum(abs(reference)^2))*100; no gain/phase alignment; all2048 FFT bins; reference-difference EVM, not RF demodulation EVM',numeric_gate_unchanged='<=1LSB for each I/Q component',full_frame={},windows={},T10_PASS=False)
for k in refs:
 report['full_frame'][k]=metrics(got[k],refs[k]);report['windows'][k]=[]
 assert report['full_frame'][k]['max_component_lsb']<=1
 for slot in range(74):
  begin=25984+17920*slot+(36 if k=='E1' else 0);end=begin+2048
  x=got[k][begin:end].astype(np.float64);y=refs[k][begin:end].astype(np.float64);assert len(x)==len(y)==2048
  X=np.fft.fft(x[:,0]+1j*x[:,1]);Y=np.fft.fft(y[:,0]+1j*y[:,1]);den=float(np.vdot(Y,Y).real);num=float(np.vdot(X-Y,X-Y).real)
  report['windows'][k].append(dict(slot=slot,array_start=begin,length=2048,fft_all_bins_evm_percent=float(100*np.sqrt(num/den)) if den else None,**metrics(x,y)))
(o/'evm_reference_difference.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
summary['evm_reference_difference_report']='evm_reference_difference.json';summary['evm_full_frame']=report['full_frame'];summary['FFT_windows_reported']=74
(o/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8');print('FULL023_ADDITIVE_EVM_REPORT_COMPLETE')
