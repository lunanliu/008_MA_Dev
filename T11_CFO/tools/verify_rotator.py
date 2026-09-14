"""Read-only identity and native numeric review. Python standard library only."""
from pathlib import Path
import argparse,csv,hashlib,json
D=Path(__file__).resolve().parents[1]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest().upper()
def check(ok,msg):
 if not ok:raise SystemExit('CFO_CHECK_FAIL: '+msg)
def normalized(p):return str(Path(p).resolve()).replace('\\','/').casefold()
p=argparse.ArgumentParser();p.add_argument('--actual',type=Path);p.add_argument('--results',type=Path);p.add_argument('--native-log',type=Path);args=p.parse_args()
lock=json.loads((D/'docs/ROTATOR_SOURCE_LOCK.json').read_text(encoding='utf-8'))
for row in lock['files']:
 f=D/row['path'];check(f.is_file(),f'missing {row["path"]}');check(f.stat().st_size==row['bytes'] and sha(f)==row['sha256'],f'identity {row["path"]}')
print(f'CFO_SOURCE_IDENTITIES_PASS files={len(lock["files"])}')
if args.actual:
 actual=list(csv.DictReader(args.actual.open(encoding='utf-8-sig')))
 got=[(r['fileset'],normalized(r['path'])) for r in actual]
 expected=[(r['fileset'],normalized(D/r['path'])) for r in lock['project_files']]
 check(len(got)==len(set(got)),'duplicate actual source entries')
 check(set(got)==set(expected),'actual source mismatch extra='+str(set(got)-set(expected))+' missing='+str(set(expected)-set(got)))
 identity=dict(line.strip().split('=',1) for line in (args.actual.parent/'project_identity.txt').read_text().splitlines() if '=' in line)
 for k,v in dict(part='xcvu11p-flgb2104-2-e',hardware_top='cfo_rotate4',simulation_top='cfo_rotate4_tb',vivado='2021.1',xelab_jobs='16').items():check(identity.get(k)==v,f'project {k}={identity.get(k)} != {v}')
 print(f'CFO_ACTUAL_PROJECT_PASS files={len(got)}')
if args.results:
 check(args.native_log is not None,'--native-log required for native review')
 log=args.native_log.read_text(encoding='utf-8',errors='replace')
 check('CFO_ROTATOR_PASS cases=4 accepted_output_beats=5120 complex_samples=20480 flush_discarded_beats=8' in log,'native completion marker missing')
 check('CFO_FIRST_ERROR' not in log and 'Fatal:' not in log,'native failure found')
 rows=list(csv.DictReader((args.results/'rotator_actual.csv').open()))
 check(len(rows)==5120,f'output row count {len(rows)}')
 idx=0;actual_stats=[]
 for c in range(4):
  expected=[int(s,16) for s in (D/f'sim/vectors/rot_case{c}_expected.mem').read_text().splitlines()]
  sats=[int(s,16) for s in (D/f'sim/vectors/rot_case{c}_sat.mem').read_text().splitlines()]
  cycles=[];sat_count=0
  for n,(data,sat) in enumerate(zip(expected,sats)):
   row=rows[idx];idx+=1;want=((100+c)<<193)|((20+c)<<161)|(n<<129)|(int(n==1279)<<128)|data
   check(int(row['case'])==c and int(row['beat'])==n,f'order case{c} beat{n}')
   check(int(row['record_hex'],16)==want and int(row['saturation_hex'],16)==sat,f'numeric case{c} beat{n}')
   cycles.append(int(row['cycle']));sat_count+=sat.bit_count()
  check(all(b>a for a,b in zip(cycles,cycles[1:])),'non-increasing output cycles')
  if c==0:check(all(b==a+1 for a,b in zip(cycles,cycles[1:])),'II=1 failed')
  actual_stats.append(dict(case=c,beats=1280,saturated_components=sat_count,first_cycle=cycles[0],last_cycle=cycles[-1]))
 summaries=list(csv.DictReader((args.results/'rotator_summary.csv').open()))
 check(len(summaries)==4,'summary case count')
 for c,r in enumerate(summaries):
  check(int(r['case'])==c and int(r['input_beats'])==int(r['output_beats'])==1280,'summary count')
  check(int(r['saturated_components'])==actual_stats[c]['saturated_components'],'summary saturation')
  check(int(r['first_output_cycle'])==actual_stats[c]['first_cycle'] and int(r['last_output_cycle'])==actual_stats[c]['last_cycle'],'summary cycles')
  if c>0:check(int(r['output_stall_cycles'])>0,'backpressure unexercised')
 print('CFO_NATIVE_NUMERIC_PASS '+json.dumps(actual_stats))
print('Scope: rotation arithmetic/handshake only; no estimator, coordinate controller, fullframe, synthesis or sustained-rate claim.')