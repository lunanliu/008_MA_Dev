from pathlib import Path
import hashlib,json,csv,subprocess,xml.etree.ElementTree as ET
D=Path(r'D:/008_MA_Dev/T11_CFO');A=D/'work/CFO_NATIVE001/attempt_20260914T112107511Z_luna';O=D/'reports/CFO_NATIVE001_REVIEW_20260914'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
C=read(A/'ATTEMPT_COMPLETION.json');assert sha(A/'ATTEMPT_COMPLETION.json')=='E4CD04723695F2C493F14834120C419CFDD842D64D1D2EBCA892637BA6CB1035'
checks=[]
def check(p,h):
 assert sha(p)==h.upper(),str(p);checks.append(dict(path=str(p),sha256=h.upper()))
for r in C['simulation']['archivedResultFiles']:check(Path(r['archive']),r['sha256'])
for path,h in [('NATIVE_SIMULATION_RESULT.json',C['simulation']['numericResultJsonSha256']),('CANCEL_RESULT.json',C['cancellation']['jsonSha256']),('ACTUAL_SOURCE_REVIEW.json',C['sourceReview']['jsonSha256']),('EXECUTION_FREEZE.json',C['execution']['freezeSha256']),('SIMULATION_ADMISSION.json',C['simulation']['admissionJsonSha256']),('actual_sources.csv',C['project']['actualSourcesSha256']),('project_identity.txt',C['project']['projectIdentitySha256']),('create.log',C['projectCreation']['logSha256']),('create.jou',C['projectCreation']['journalSha256']),('simulate.log',C['simulation']['simulateLogSha256']),('simulate.jou',C['simulation']['simulateJournalSha256']),('cancel.log',C['cancellation']['cancelLogSha256']),('cancel.jou',C['cancellation']['cancelJournalSha256'])]:check(A/path,h)
p=subprocess.run([r'C:/Python314/python.exe','-I','-B','-X','utf8',str(D/'tools/verify_rotator.py'),'--actual',str(A/'actual_sources.csv'),'--results',str(A/'native_results'),'--native-log',str(A/'simulate.log')],capture_output=True,text=True,encoding='utf-8');assert p.returncode==0,p.stdout+p.stderr;(O/'frozen_verifier_output.txt').write_text(p.stdout,encoding='utf-8')
# Independent re-evaluation from inputs/phase words and the approved ROM CSV.
rom=[(int(r['cosine_code']),int(r['sine_code'])) for r in csv.DictReader((D/'sim/reference/rcfo003/results/rom_NCO32_ROM10_C16F14.csv').open())]
def rne(v,b):
 sign=-1 if v<0 else 1;a=abs(v);q,r=divmod(a,1<<b);return sign*(q+int(2*r>(1<<b) or (2*r==(1<<b) and q%2)))
def signed16(x):return x if x<32768 else x-65536
def sat(x):return min(32767,max(-32768,x))
rows=list(csv.DictReader((A/'native_results/rotator_actual.csv').open()));vectors=read(D/'sim/vectors/ROTATOR_VECTOR_MANIFEST.json');samples=0;saturations=0
for case in vectors['cases']:
 c=case['case_id'];inputs=[int(x,16) for x in (D/f'sim/vectors/rot_case{c}_input.mem').read_text().splitlines()]
 for b,word in enumerate(inputs):
  output=int(rows[c*1280+b]['record_hex'],16);flags=int(rows[c*1280+b]['saturation_hex'],16)
  for lane in range(4):
   n=b*4+lane;i=signed16((word>>(lane*32))&65535);q=signed16((word>>(lane*32+16))&65535)
   phase=(case['phase0']+n*case['step'])&0xffffffff;addr=rne(phase,22)&1023;co,si=rom[addr]
   ri=rne(i*co-q*si,14);rq=rne(i*si+q*co,14);actuali=signed16((output>>(lane*32))&65535);actualq=signed16((output>>(lane*32+16))&65535)
   assert (actuali,actualq)==(sat(ri),sat(rq)),(c,n)
   sf=int(ri!=sat(ri))|int(rq!=sat(rq))<<1;assert (flags>>(lane*2))&3==sf;saturations+=sf.bit_count();samples+=1
# Source export and protocol assertions are frozen and passed; no new native run.
R=dict(event='T11_NATIVE001_REVIEW_E4CD0472',attempt=str(A),completion_sha256=sha(A/'ATTEMPT_COMPLETION.json'),checked_artifact_hashes=checks,source_lock_members=39,actual_project_members=17,functional_acceptance='PASS_ROTATOR_ARITHMETIC_AND_PROTOCOL_ONLY',independently_recomputed_complex_samples=samples,independently_recomputed_IQ_components=samples*2,saturation_components=saturations,continuous_case_input_and_output_II_cycles=1,continuous_case_latency_cycles=5,reset_discarded_beats=4,abort_discarded_beats=4,backpressure_stall_cycles=[0,659,1202,1205],native_create_wall_seconds=11,native_simulation_wall_seconds=23,native_parent_peak_reported_MB=1131.988,whole_owned_tree_peak_memory='NOT_RECORDED',cancel_final_release='CONFIRMED_FOR_RECORDED_FRESH_ENTRY_TREE',cancel_deadline_acceptance='FAIL_60_SECOND_BOUND_NOT_MET',cancel_finding='11:28:28.499937Z native creation; Ctrl+C requested11:29:02.611Z; first forced cleanup11:29:42.393Z failed read-only PowerShell PID variable; subsequent quoting/encoding fixes delayed final cleanup beyond60s and60s cleanup budget.',cancel_ready_plus_3s_claim='NOT_SUPPORTED_AS_ACTUAL_END_TO_END_DELAY',runtime_watchdog_acceptance='NOT_PROVEN_AUTONOMOUS',post_run_xpr_sha256=sha(D/'vivado/CFO_SYNC/CFO_SYNC.xpr'),pre_sim_xpr_sha256=C['project']['xprSha256'],xpr_hash_note='Vivado updated its mutable project during simulation; actual17source members unchanged. Current hash equals CANCEL_ADMISSION. Preserve pre/post distinction.',next_required_action='Keep successful arithmetic computation; repair autonomous owned-tree timeout/resource supervision and validate only affected native-entry probes before the next compute job.',formal_T11_T12_T13_PASS=False,estimator_tested=False,synthesis_tested=False,timing_tested=False,sustained_rate_proven=False)
assert R['post_run_xpr_sha256']==read(A/'CANCEL_ADMISSION.json')['xpr_sha256']
(O/'INDEPENDENT_REVIEW.json').write_text(json.dumps(R,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in R.items() if k!='checked_artifact_hashes'},indent=2))