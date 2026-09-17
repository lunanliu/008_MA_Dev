from pathlib import Path
import json
r=Path(__file__).resolve().parents[1]
ws=[int(s,16) for s in (r/'sim/data/autonomous_stream.mem').read_text().split()]
def ss(x):return x-65536 if x>=32768 else x
x=[(ss((w>>(j*32))&65535),ss((w>>(j*32+16))&65535)) for w in ws for j in range(4)]
c=[(a[0]*b[0]+a[1]*b[1],a[0]*b[1]-a[1]*b[0],b[0]**2+b[1]**2) for a,b in zip(x,x[1024:])]
p=q=e=0;start=None;runs=[]
for k,(a,b,t) in enumerate(c):
    p+=a;q+=b;e+=t
    if k>=1024:
        a,b,t=c[k-1024];p-=a;q-=b;e-=t
    if k>=1023 and (k-1023)%4==0:
        d=k-1023;qualified=e>0 and 100*(p*p+q*q)>=3*e*e
        if qualified and start is None:start=d
        if not qualified and start is not None:
            n=(d-start)//4
            if 4<=n<=1024 and (start+d-4)//2>=512:
                anchor=(((start+d-4)//2)-256)&~3
                runs.append(dict(start=start,last=d-4,beats=n,anchor=anchor,age_at_close_with_64_sample_pipeline_margin=d+2048+64-(anchor-256)))
            start=None
truth=json.loads((r/'sim/data/autonomous_manifest.json').read_text())['expected']
contain=[]
for t in truth:
    nearest=min(runs,key=lambda c:abs(c['anchor']-t['true_start']))
    err=nearest['anchor']-t['true_start']
    assert abs(err)<=128,(t,nearest)
    assert nearest['age_at_close_with_64_sample_pipeline_margin']+3200<8192
    contain.append(dict(true_start=t['true_start'],anchor=nearest['anchor'],anchor_error=err))
out=dict(status='OFFLINE_GEOMETRY_ONLY_NOT_RTL_PASS',candidates=runs,true_candidate_containment=contain)
(r/'reports/design/SF002_offline_geometry.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(contain));print('eligible_candidates',len(runs))
