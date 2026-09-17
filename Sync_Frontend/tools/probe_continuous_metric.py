from pathlib import Path
import random
root=Path(__file__).resolve().parents[1]
a=[int(x,16) for x in (root/'sim/data/stimulus_beats.mem').read_text().split()]
b=[int(x,16) for x in (root/'sim/data/t05_full91_capture_128.mem').read_text().split()]
def signed(x):return x-65536 if x>=32768 else x
def unpack(ws):return [(signed((w>>(32*j))&65535),signed((w>>(32*j+16))&65535)) for w in ws for j in range(4)]
for c in (0,1,3,4,5,6,27):
    aa=a[c*768:(c+1)*768];bb=b[c*692:(c+1)*692]
    assert aa[102:] == bb[:666]
    v=unpack(aa+bb[666:])
    rng=random.Random(123)
    v=[(rng.randrange(-10,11),rng.randrange(-10,11)) for _ in range(4096)]+v+[(rng.randrange(-10,11),rng.randrange(-10,11)) for _ in range(8192)]
    corr=[(x[0]*y[0]+x[1]*y[1],x[0]*y[1]-x[1]*y[0],y[0]*y[0]+y[1]*y[1]) for x,y in zip(v,v[1024:])]
    pr=pi=en=0;runs=[];start=None
    for k,(re,im,e) in enumerate(corr):
        pr+=re;pi+=im;en+=e
        if k>=1024:
            re,im,e=corr[k-1024];pr-=re;pi-=im;en-=e
        if k>=1023 and (k-1023)%4==0:
            d=k-1023
            q=en>0 and 100*(pr*pr+pi*pi)>=3*en*en
            if q and start is None:start=d
            if not q and start is not None:runs.append((start,d-4,(start+d-4)//2-256));start=None
    print(c, 'runs',runs,'nominal_anchor',4096+256)
