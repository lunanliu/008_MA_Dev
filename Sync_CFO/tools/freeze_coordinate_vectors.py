"""Freeze finite-word controller vectors; no signal generation, MATLAB or native tools."""
from pathlib import Path
import hashlib,json,random
R=Path(__file__).resolve().parents[1]
MASK48=(1<<48)-1
FS=500000000

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def dump(p,obj):p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def round_even(n,d):
    q,r=divmod(n,d)
    return q+(2*r>d or (2*r==d and q%2==1))
def calc(mode,f,s1,s2,o):
    zero=dict(ok=0,error=0,step=0,phase0=0,step48=0,phase48=0,origin_output_q16=0)
    if f==-(1<<31) or o==-(1<<53):return dict(zero,error=1)
    if not s1 or not s2:return dict(zero,error=2)
    ratio=s1*s2
    if ratio>=1<<62:return dict(zero,error=3)
    origin_mag=round_even(abs(o)*(1<<44),ratio)&MASK48
    origin=(-1 if o<0 else 1)*origin_mag
    step_mag=round_even(abs(f)*((1<<32) if mode else ratio),FS if mode else FS*65536)&MASK48
    if step_mag>=1<<47:return dict(zero,error=4)
    step48=(-1 if f>=0 else 1)*step_mag
    phase_mag=round_even(abs(f)*(origin_mag if mode else abs(o))*((1<<16) if mode else 4096),FS)&MASK48
    phase48=((-1 if (f>=0)==(o>=0) else 1)*phase_mag)&MASK48
    step=(-1 if step48<0 else 1)*round_even(abs(step48),65536)
    return dict(ok=1,error=0,step=step&0xffffffff,phase0=round_even(phase48,65536)&0xffffffff,
                step48=step48,phase48=phase48,origin_output_q16=origin)

def pack(fields):
    v=0
    for value,bits in fields:v=(v<<bits)|(int(value)&((1<<bits)-1))
    return v

def build():
    out=R/'sim/vectors';out.mkdir(exist_ok=True)
    rows=[];source_info={};published=0
    def add(label,mode,f,s1,s2,o,p=None,path=None):
        nonlocal published
        vals=[int(x) for x in (f,s1,s2,o)];f,s1,s2,o=vals
        assert all(int(x)==x for x in (f,s1,s2,o))
        result=calc(mode,f,s1,s2,o)
        if p is not None:
            assert result['ok'],label
            width=int(p['width']);step_key='step' if width==32 else 'step48';phase_key='phase0' if width==32 else 'phase48'
            assert (result[step_key]&((1<<width)-1))==(int(p['step'])&((1<<width)-1)),label
            assert result[phase_key]==int(p['phase0']),label
            assert result['origin_output_q16']==int(p['origin_output_q16']),label
            published+=1
        if path is not None:source_info[str(path.relative_to(R)).replace('\\','/')]=sha(path)
        i=len(rows);row=dict(index=i,label=label,frame=1000+i,generation=0x12340000+i,residual=int(mode),frequency_code=f,step1_q28=s1,step2_q28=s2,raw_origin_q28=o,expected=result)
        rows.append(row)
    for path in sorted((R/'sim/reference/rcfo004/results').glob('case_*/result.json')):
        data=json.loads(path.read_text(encoding='utf-8-sig'));d=data['descriptor']
        for mode,name in enumerate(('coarse_parameters','residual_parameters')):
            p=data['bittrue'][name];add(f'rcfo004/{path.parent.name}/{name}',mode,p['frequency_code'],d['step1_q28'],d['step2_q28'],d['raw_origin_q28'],p,path)
    for gp in sorted((R/'sim/reference/rcfo003/results').glob('case_*/golden.json')):
        d=json.loads(gp.read_text(encoding='utf-8-sig'))['descriptor'];source_info[str(gp.relative_to(R)).replace('\\','/')]=sha(gp)
        for bp in sorted(gp.parent.glob('bit_NCO*.json')):
            b=json.loads(bp.read_text(encoding='utf-8-sig'))['bittrue']
            for mode,name in enumerate(('coarse_parameters','residual_parameters')):
                p=b[name];add(f'rcfo003/{gp.parent.name}/{bp.stem}/{name}',mode,p['frequency_code'],d['step1_q28'],d['step2_q28'],d['raw_origin_q28'],p,bp)
    boundary_start=len(rows)
    base=1<<28
    for mode in (0,1):
        for f in (0,1,-1,38400000,-38400000,(1<<31)-1,-((1<<31)-1)):
            for o in (17*base+3,-17*base-3):
                add('nonzero_origin_sfo_pair',mode,f,base+40265,base-40265,o)
    for sign in (-1,1):
        for f in (1953125,3*1953125):add('step48_divide_half_even_odd',0,sign*f,1,1<<23,0)
        for o in (1,3):add('origin_divide_half_even_odd',0,1,1<<22,1<<23,sign*o)
        for f in (500000000,1500000000):add('step32_half_even_odd',0,sign*f,1,1<<31,0)
        add('phase32_half_even',0,sign*1953125,base,base,2048)
        add('phase32_half_odd',0,sign*1953125,base,base,6144)
        add('origin_modulo48_wrap',1,sign*65536,1,1,1<<52)
        add('phase_modulo48_wrap',0,sign*((1<<31)-1),base,base,(1<<53)-1)
    invalids=[('invalid_frequency_min',0,-(1<<31),base,base,0),('invalid_origin_min',0,1,base,base,-(1<<53)),('invalid_zero_s1',0,1,0,base,0),('invalid_zero_s2',1,1,base,0,0),('invalid_ratio_limit',0,1,1<<31,1<<31,0),('invalid_ratio_max',1,1,(1<<32)-1,(1<<32)-1,0),('invalid_step_range',0,(1<<31)-1,(1<<31)-1,1<<30,0)]
    for row in invalids:add(*row)
    rng=random.Random(20260914)
    for i in range(96):
        mode=i%2;f=rng.randrange(-(1<<31)+1,1<<31);s1=base+rng.randrange(-40265,40266);s2=base+rng.randrange(-40265,40266);o=rng.randrange(-(1<<53)+1,1<<53)
        add('deterministic_integer_boundary',mode,f,s1,s2,o)
    inputs=[];expected=[]
    for r in rows:
        e=r['expected'];inputs.append(f"{pack([(r['frame'],32),(r['generation'],32),(r['residual'],1),(r['frequency_code'],32),(r['step1_q28'],32),(r['step2_q28'],32),(r['raw_origin_q28'],54)]):054x}")
        expected.append(f"{pack([(r['frame'],32),(r['generation'],32),(r['residual'],1),(e['ok'],1),(e['error'],4),(e['step'],32),(e['phase0'],32),(e['step48'],48),(e['phase48'],48),(e['origin_output_q16'],49)]):070x}")
    (out/'coordinate_input.mem').write_text('\n'.join(inputs)+'\n',encoding='ascii');(out/'coordinate_expected.mem').write_text('\n'.join(expected)+'\n',encoding='ascii')
    (out/'coordinate_config.svh').write_text(f'localparam integer COORD_CASES={len(rows)};\n',encoding='ascii')
    dump(out/'coordinate_cases.json',dict(schema='cfo_coordinate_vectors_v1',published_parameter_matches=published,boundary_cases=len(rows)-boundary_start,source_hashes=source_info,rows=rows))
    counts={str(k):sum(r['expected']['error']==k for r in rows) for k in range(5)}
    return dict(cases=len(rows),published_parameter_matches=published,boundary_cases=len(rows)-boundary_start,error_counts=counts,source_files=len(source_info),sha256={p.name:sha(p) for p in out.glob('coordinate_*')})
if __name__=='__main__':
    result=build();dump(R/'reports/COORDINATE_VECTOR_CHECK.json',result);print(json.dumps(result))