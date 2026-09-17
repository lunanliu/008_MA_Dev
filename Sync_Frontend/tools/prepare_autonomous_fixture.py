from pathlib import Path
import csv,json,random,hashlib
root=Path(__file__).resolve().parents[1]
a=[int(x,16) for x in (root/'sim/data/stimulus_beats.mem').read_text().split()]
b=[int(x,16) for x in (root/'sim/data/t05_full91_capture_128.mem').read_text().split()]
truth=list(csv.DictReader((root/'sim/data/bit_true_case_results.csv').open(encoding='utf-8-sig')))
rng=random.Random(9414002)
def lanes(ws):return [(w>>(j*32))&0xffffffff for w in ws for j in range(4)]
def noise(n):return [((rng.randrange(-10,11)&65535)<<16)|(rng.randrange(-10,11)&65535) for _ in range(n)]
x=noise(4096)
fake=[((rng.randrange(-8000,8001)&65535)<<16)|(rng.randrange(-8000,8001)&65535) for _ in range(1024)]
x+=fake[-512:]+fake+fake
x+=noise(8192)
expected=[]
for lane,c in enumerate((0,1,5,6)):
    to=int(truth[c]['to_true'])
    while (len(x)+256+to)%4 != lane:x+=noise(1)
    origin=len(x)
    aa=a[c*768:(c+1)*768];bb=b[c*692:(c+1)*692]
    assert aa[102:]==bb[:666],f'overlap {c}'
    block=lanes(aa+bb[666:]);assert len(block)==3176
    x+=block
    expected.append(dict(case=c,case_id=truth[c]['case_id'],fixture_start=origin,true_start=origin+256+to,expected_cfo_hz=(-150000,0,150000,-150000)[lane],lane=lane))
    x+=noise(8192)
while len(x)%4:x+=noise(1)
words=[sum(x[i+j]<<(32*j) for j in range(4)) for i in range(0,len(x),4)]
(root/'sim/data/autonomous_stream.mem').write_text(''.join(f'{w:032x}\n' for w in words),encoding='ascii')
(root/'sim/data/autonomous_truth.mem').write_text(''.join(f'{((e["true_start"]<<32)|(e["expected_cfo_hz"]&0xffffffff)):032x}\n' for e in expected),encoding='ascii')
manifest=dict(seed=9414002,accepted_samples=len(x),beats=len(words),expected_results=len(expected),expected=expected,fake_preamble='512+1024+1024 repeated random IQ, not PS1',block_beats=256,pause_cycles=8000,scope='short finite fragments; not sustained ADC qualification',truth_routing='autonomous_truth.mem only consumed by passive checker')
for fn in ('autonomous_stream.mem','autonomous_truth.mem'):
    manifest[fn+'_sha256']=hashlib.sha256((root/'sim/data'/fn).read_bytes()).hexdigest()
(root/'sim/data/autonomous_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest,indent=2))
