"""LINK010 vectors reuse saved FRONT009 and BACKEND006R1 evidence; no FFT runs."""
from pathlib import Path
import json,hashlib,runpy,copy
R=Path(__file__).resolve().parents[1]
B=runpy.run_path(str(R/'tools/backend74_reference.py'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def pack(items):
 w=0
 for v,b in items:w=(w<<b)|(int(v)&((1<<b)-1))
 return w
def signed(n,b):return n-(1<<b) if n&(1<<(b-1)) else n
def decode(w):
 return {'frame':w>>145,'generation':(w>>113)&0xffffffff,'window':(w>>106)&127,'z_i':signed((w>>68)&((1<<38)-1),38),'z_q':signed((w>>30)&((1<<38)-1),38),'pilot_count':(w>>20)&1023,'fft_saturations':(w>>4)&65535,'front_error':w&15}
def encode(p):return pack([(p['frame'],32),(p['generation'],32),(p['window'],7),(p['z_i'],38),(p['z_q'],38),(p['pilot_count'],10),(p['fft_saturations'],16),(p['front_error'],4)])
def mutate(p,kind):
 p=dict(p)
 if kind==1:p['frame']^=1
 elif kind==2:p['generation']^=1
 elif kind in [3,4]:p['window']+=1
 elif kind==5:p['window']=74
 elif kind==6:p['pilot_count']=819
 elif kind in [7,8,9]:p['front_error']=kind-6
 elif kind==10:p['z_i']=-(1<<37)
 return p
def read_word(p,base,n):
 err=0
 if p['front_error']:err=4
 elif p['pilot_count']!=820:err=5
 elif p['window']>=74:err=3
 elif n and (p['frame']!=base['frame'] or p['generation']!=base['generation']):err=1
 elif p['window']!=n:err=2
 elif p['z_i']==-(1<<37) or p['z_q']==-(1<<37):err=6
 return pack([(base['frame'],32),(base['generation'],32),(p['window'],7),(p['z_i'],38),(p['z_q'],38),(p['fft_saturations'],16),(err,4),(p['front_error'],4)]),err
def backend_word(c):return pack([(B['result_word'](c),170),(B['quality_word'](c['expected']),197),(B['phase_word'](c['expected']),132)])
def build():
 O=R/'sim/vectors';sources={}
 def src(p):sources[p.relative_to(R).as_posix()]=sha(p);return p
 data=json.loads(src(R/'sim/vectors/backend74_cases.json').read_text());front=json.loads(src(R/'sim/vectors/front2048_cases.json').read_text())
 actual=src(R/'work/CFO_FRONT009/attempt_20260914T183142105831Z_luna/front2048_actual.txt')
 for p in [R/'reports/FRONT009_REVIEW_20260914/INDEPENDENT_REVIEW.json',R/'reports/BACKEND006R1_REVIEW_20260914/INDEPENDENT_REVIEW.json',R/'tools/backend74_reference.py']:src(p)
 actual_words={}
 for line in actual.read_text().splitlines():
  it=line.split()
  if it[0]=='Z' and 0<=int(it[1])<74:actual_words[int(it[2])]=int(it[3],16)
 assert sorted(actual_words)==list(range(74))
 cases=[]
 for k,bi in enumerate([9,27,3,19]):
  c=copy.deepcopy(data['cases'][bi]);c['backend_source_index']=bi;c['index']=k;c['frame']=6000 if k==0 else 8100+k;c['generation']=0x9abc0000 if k==0 else 0xbcde0000+k
  packets=[]
  for n,z in enumerate(c['z']):
   if k==0:
    p=decode(actual_words[n]);assert [p['z_i'],p['z_q']]==z==front['cases'][n]['expected']['z'] and p['window']==n and p['frame']==c['frame'] and p['generation']==c['generation'] and p['pilot_count']==820 and p['front_error']==0
   else:p={'frame':c['frame'],'generation':c['generation'],'window':n,'z_i':z[0],'z_q':z[1],'pilot_count':820,'fft_saturations':45056 if k==1 and n<2 else n%7,'front_error':0}
   packets.append(p)
  c['packets']=packets;c['input_words']=[encode(p) for p in packets];c['read_words']=[read_word(p,packets[0],n)[0] for n,p in enumerate(packets)]
  c['fft_saturation_sum']=sum(p['fft_saturations'] for p in packets)
  c['result_word']=pack([(backend_word(c),499),(0,4),(0,4),(c['fft_saturation_sum'],23)]);cases.append(c)
 errors=[]
 for kind in range(1,11):
  n=0 if kind in [4,5] else 6;ps=[dict(p) for p in cases[0]['packets'][:n+1]];ps[-1]=mutate(ps[-1],kind);rw,err=read_word(ps[-1],ps[0],n)
  base=pack([(cases[0]['frame'],32),(cases[0]['generation'],32),(0,435)])
  result=pack([(base,499),(err,4),(ps[-1]['front_error'],4),(sum(p['fft_saturations'] for p in ps),23)])
  errors.append({'kind':kind,'bad_index':n,'input_words':[encode(p) for p in ps],'read_words':[read_word(p,ps[0],j)[0] for j,p in enumerate(ps)],'error':err,'result_word':result})
 def mem(name,values,width):(O/name).write_text(''.join(f'{v:0{width}x}\n' for v in values),encoding='ascii')
 mem('link010_input.mem',[w for c in cases for w in c['input_words']],45);mem('link010_read.mem',[w for c in cases for w in c['read_words']],43);mem('link010_result.mem',[c['result_word'] for c in cases],133)
 mem('link010_error_input.mem',[e['input_words'][-1] for e in errors],45);mem('link010_error_read.mem',[e['read_words'][-1] for e in errors],43);mem('link010_error_result.mem',[e['result_word'] for e in errors],133)
 (O/'link010_cases.json').write_text(json.dumps({'schema':'link010_saved_evidence_vectors_v1','source_hashes':sources,'cases':cases,'errors':errors},separators=(',',':'))+'\n',encoding='utf-8')
 (O/'link010_config.svh').write_text('localparam integer LINK_CASES=4;\nlocalparam integer LINK_ERRORS=10;\n',encoding='ascii')
 out={'status':'LINK010_SAVED_EVIDENCE_VECTORS_READY','cases':4,'modes':[c['expected']['mode'] for c in cases],'real_front009_windows':74,'real_front009_z_matches_backend_reference':True,'error_cases':10,'source_hashes':sources,'no_matlab_fft_or_native_recomputed':True,'nominal_source_interval_fast_cycles':15448,'qualification':'Only packet vectors and frozen expected results prepared; no native link test yet'}
 (R/'reports/LINK010_VECTOR_CHECK.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in out.items() if k!='source_hashes'}))
if __name__=='__main__':build()