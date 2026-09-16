"""Reproduce the frozen two-symbol oracle using exact rational arithmetic.
--check verifies existing files; --write is only for preparing a new, unfrozen set.
"""
from pathlib import Path
from fractions import Fraction
import json,sys
root=Path(__file__).resolve().parents[1]
meta=json.loads((root/'docs/provenance/OTA_DUAL_FRAGMENT.json').read_text())
step1,step2,origin=meta['step1'],meta['step2'],meta['origin_q28']
ratio=step1*step2;origin16=round(Fraction(origin*(1<<44),ratio))
configs=[]
for declared in meta['configs']:
 residual,f=declared['residual'],declared['frequency_code']
 magnitude=round(Fraction(abs(f)*((1<<32) if residual else ratio),500000000 if residual else 32768000000000))
 step=(round(Fraction(magnitude,1<<16))*(1 if f<0 else -1))%(1<<32)
 phase_mag=round(Fraction(abs(f)*(abs(origin16) if residual else abs(origin))*(1<<(16 if residual else 12)),500000000))
 phase48=(phase_mag*(1 if (f<0)!=(origin<0) else -1))%(1<<48)
 phase0=round(Fraction(phase48,1<<16))%(1<<32)
 assert (step,phase0)==(declared['step'],declared['phase0'])
 configs.append((phase0,step))
rom=[int(x,16) for x in (root/'ip/cfo/cfo_rot_lut.mem').read_text().split()]
inputs=[int(x,16) for x in (root/'sim/data/ota_dual_input.mem').read_text().split()];assert len(inputs)==1280
def s16(x):return x-65536 if x&32768 else x
def rotate(words,configuration):
 phase,step=configuration;output=[]
 for b,w in enumerate(words):
  packed=0
  for lane in range(4):
   address=round(Fraction((phase+(4*b+lane)*step)%(1<<32),1<<22))%1024
   coefficient=rom[address];cs=s16(coefficient&65535);sn=s16(coefficient>>16)
   iv=s16((w>>(lane*32))&65535);qv=s16((w>>(lane*32+16))&65535)
   for part,value in enumerate([iv*cs-qv*sn,iv*sn+qv*cs]):
    q=max(-32768,min(32767,round(Fraction(value,1<<14))))
    packed|=(q&65535)<<(lane*32+part*16)
  output.append(packed)
 return output
coarse=rotate(inputs,configs[0]);final=rotate(coarse,configs[1])
for name,words in [('coarse',coarse),('final',final)]:
 path=root/f'sim/data/ota_dual_{name}.mem';text=''.join(f'{x:032x}\n' for x in words)
 if '--write' in sys.argv:path.write_text(text,encoding='ascii')
 else:assert path.read_text()==text,name
combined=rotate(inputs,tuple((configs[0][n]+configs[1][n])%(1<<32) for n in range(2)))
different=sum(a!=b for a,b in zip(final,combined));assert different>0
print('DUAL_FRAGMENT_REFERENCE_PASS beats=1280 stages=2 distinct_from_collapsed_beats='+str(different))
