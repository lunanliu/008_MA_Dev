"""Compare saved LabVIEW captures against the frozen T10 case. Standard library only.
No Vivado/MATLAB, hardware access, or modification of reference data.
"""
from pathlib import Path
from array import array
import argparse, hashlib, json, math, struct, sys

ROOT = Path(__file__).resolve().parents[1]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest().upper()
def signed16(x): return x - 65536 if x & 32768 else x

def compare_iq(actual, reference):
    if len(actual) != len(reference):
        raise ValueError(f'IQ byte count: actual={len(actual)}, expected={len(reference)}')
    maximum = 0
    first = None
    for index, (a, b) in enumerate(zip(struct.iter_unpack('<h', actual), struct.iter_unpack('<h', reference))):
        d = abs(a[0] - b[0]); maximum = max(maximum, d)
        if d > 1 and first is None:
            first = dict(sample=index // 2, beat=index // 8, lane=(index // 2) % 4,
                         component='I' if index % 2 == 0 else 'Q', actual=a[0], expected=b[0], difference_lsb=d)
    return dict(compared_components=len(actual)//2, max_component_lsb=maximum,
                passes_lsb_gate=maximum <= 1, first_failure=first)

def windows(actual, reference, context):
    a=array('h'); a.frombytes(actual); b=array('h'); b.frombytes(reference)
    if sys.byteorder != 'little': a.byteswap(); b.byteswap()
    result=[]
    for slot in range(74):
        start=25984 + 17920*slot + context; lo=2*start; hi=lo+4096
        if hi > len(a) or hi > len(b): raise ValueError('Missing full FFT window')
        numerator=sum((int(x)-int(y))**2 for x,y in zip(a[lo:hi], b[lo:hi]))
        denominator=sum(int(y)**2 for y in b[lo:hi])
        if denominator == 0: raise ValueError('Zero reference energy')
        ratio=numerator/denominator
        result.append(dict(slot=slot, array_start=start, error_energy=numerator,
                           reference_energy=denominator, evm_percent=100*math.sqrt(ratio),
                           evm_db=10*math.log10(ratio) if ratio else None, zero_error=not numerator,
                           passes_minus45db=ratio < 10**(-45/10)))
    return result

def check_status(path):
    s=json.loads(path.read_text(encoding='utf-8-sig')); problems=[]
    for name in ['fault','m_fault','m_reset','error_code125','error_code150','capture_overflow']:
        if s.get(name) is None or s[name] != 0: problems.append(f'{name} must be an ACTUAL captured zero')
    for name,n in [('input_accepted_beats',334215),('output_accepted_beats',334080)]:
        if s.get(name) != n: problems.append(f'{name} must equal {n}')
    for name in ['debug125','debug150']:
        x=s.get(name)
        if not isinstance(x,list) or len(x)!=16 or not all(type(v) is int and 0<=v<=0xffffffff for v in x):
            problems.append(name+' requires 16 ACTUAL unsigned32 words')
    if not problems:
        a=s['debug125']; b=s['debug150']
        exact125={0:334215,2:(-39303835)&0xffffffff,4:6001,5:(-12945)&0xffffffff,6:268435443,7:6001,8:1,13:74,14:74}
        exact150={0:334098,1:334080,2:334080,3:268395209,4:268435443,7:0,8:0,12:334215,15:0}
        for i,n in exact125.items():
            if a[i]!=n: problems.append(f'debug125_w{i:02d}: {a[i]} != {n}')
        for i,n in exact150.items():
            if b[i]!=n: problems.append(f'debug150_w{i:02d}: {b[i]} != {n}')
        for okay,message in [((a[1]&31)==3,'T06/T09 seen and idle/fault flags'),((a[3]&65535)==0x4800,'T06 status'),
                             ((a[10]&8191)==4096 and ((a[10]>>16)&8191)==4096,'T06 FFT counts'),
                             ((a[11]&8191)==6560 and ((a[11]>>16)&8191)==6560,'T06 observation/weight counts'),
                             ((a[15]&65535)==0,'T06/control errors'),((b[11]&0x13f)==0,'E1/E2/window idle and no halt')]:
            if not okay: problems.append(message)
    return dict(passes=not problems, failures=problems, file=str(path), sha256=sha(path))

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--capture',type=Path,required=True,help='OUT records: frame,gen,beat,last,iq0,iq1,iq2,iq3; 8 U32LE per accepted beat')
    ap.add_argument('--points',type=Path,help='74 point records; 5 U32LE per point')
    ap.add_argument('--e1',type=Path,help='E1 raw IQ; 4 U32LE per debug_e1_valid beat')
    ap.add_argument('--status',type=Path,help='Actual captured status following capture_status_template.json')
    ap.add_argument('--report',type=Path,help='Optional new JSON report; existing file is never overwritten')
    args=ap.parse_args()
    if args.report and args.report.exists(): raise FileExistsError('Preserve existing report: '+str(args.report))
    manifest=json.loads((ROOT/'data/data_manifest.json').read_text(encoding='utf-8'))
    for f in manifest['files']:
        path=ROOT/f['file']
        if path.stat().st_size!=f['bytes'] or sha(path)!=f['sha256']:raise ValueError('Reference identity mismatch: '+str(path))
    source=args.capture.read_bytes()
    if len(source)!=334080*32: raise ValueError(f'Expected 10690560 capture bytes, got {len(source)}; check array header/endian/count')
    iq=bytearray(334080*16); metadata_failures=[]
    for i,row in enumerate(struct.iter_unpack('<8I',source)):
        wanted=(6001,1,i,int(i==334079))
        if row[:4]!=wanted and len(metadata_failures)<8:metadata_failures.append(dict(record=i,actual=list(row[:4]),expected=list(wanted)))
        iq[i*16:(i+1)*16]=struct.pack('<4I',*row[4:])
    reference=(ROOT/'data/expected_output_iq_u32le.bin').read_bytes()
    result={'scope':'Comparison of supplied saved captures only; no proof of clock timing, NI compilation or continuous throughput',
            'capture':str(args.capture),'capture_sha256':sha(args.capture),'output_records':334080,
            'metadata_pass':not metadata_failures,'first_metadata_failures':metadata_failures,
            'output_iq':compare_iq(iq,reference),'output_windows':windows(iq,reference,0),
            'evm_definition':'Reference-difference over all2048 FFT bins; computed by Parseval-equivalent time-domain energy; no gain/phase alignment',
            'e1_checked':False,'points_checked':False,'status_checked':False,'platform_qualification':False}
    passes=result['metadata_pass'] and result['output_iq']['passes_lsb_gate'] and all(x['passes_minus45db'] for x in result['output_windows'])
    if args.e1:
        r=(ROOT/'data/expected_e1_iq_u32le.bin').read_bytes();a=args.e1.read_bytes();result['e1_checked']=True
        result['e1_iq']=compare_iq(a,r);result['e1_windows']=windows(a,r,36)
        passes=passes and result['e1_iq']['passes_lsb_gate'] and all(x['passes_minus45db'] for x in result['e1_windows'])
    if args.points:
        a=args.points.read_bytes();r=(ROOT/'data/expected_points_u32le.bin').read_bytes();result['points_checked']=True
        result['points']={'expected_bytes':1480,'actual_bytes':len(a),'exact_match':a==r,'first_mismatching_record':next((i//20 for i,(x,y) in enumerate(zip(a,r)) if x!=y),None)}
        passes=passes and a==r
    if args.status:
        result['status_checked']=True;result['status']=check_status(args.status);passes=passes and result['status']['passes']
    result['all_supplied_checks_pass']=bool(passes)
    result['result']='CAPTURE_CHECKS_PASS' if passes else 'CAPTURE_CHECKS_FAIL'
    result['not_supplied']=[name for name in ['e1','points','status'] if getattr(args,name) is None]
    if args.report:
        with args.report.open('x',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({k:result[k] for k in ['result','output_records','output_iq','metadata_pass','e1_checked','points_checked','status_checked','not_supplied','platform_qualification']},ensure_ascii=False,indent=2))
    return 0 if passes else 1
if __name__=='__main__':
    try:sys.exit(main())
    except (OSError,ValueError,KeyError,struct.error) as exc:
        print(json.dumps({'result':'CAPTURE_CHECKS_ERROR','error':str(exc)},ensure_ascii=False));sys.exit(2)