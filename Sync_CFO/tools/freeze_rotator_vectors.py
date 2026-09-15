from pathlib import Path
import csv,json,struct,hashlib
D=Path(__file__).resolve().parents[1]
# This one-time vector freeze consumes only the independent local copies.
ref=D/'sim/reference';romfile=ref/'rcfo003/results/rom_NCO32_ROM10_C16F14.csv'
rom=[(int(r['cosine_code']),int(r['sine_code'])) for r in csv.DictReader(romfile.open())];assert len(rom)==1024
(D/'ip/cfo_rot_lut.mem').write_text(''.join(f'{((q&65535)<<16)|(i&65535):08x}\n' for i,q in rom))
def rne(n,d):
 q,r=divmod(n,d);return q+int(2*r>d or(2*r==d and q&1))
def sat(n):return max(-32768,min(32767,n))
def pack(data):return sum(((i&65535)|((q&65535)<<16))<<(32*l) for l,(i,q) in enumerate(data))
N=5120;cases=[]
for case in range(4):
 if case<2:
  src=ref/f'rcfo004/results/case_{1 if case==0 else 3:03d}';r=json.loads((src/'result.json').read_text());p=r['bittrue']['coarse_parameters'];raw=(src/'input_i16.bin').read_bytes()[:N*4];data=list(struct.iter_unpack('<hh',raw));source=str((src/'input_i16.bin').relative_to(D));phase=p['phase0'];step=p['step']
 elif case==2:
  data=[[(32767,32767),(-32768,32767),(32767,-32768),(-32768,-32768)][n%4] for n in range(N)];phase=128<<22;step=4<<22;source='deterministic full-scale quadrants, no MATLAB'
 else:
  data=[[(8192,0),(24576,0),(-8192,0),(-24576,0)][n%4] for n in range(N)];phase=1<<21;step=1<<22;source='deterministic signed RNE tie excitation, no MATLAB'
 outs=[];sats=[];ties={'positive_even':0,'positive_odd':0,'negative_even':0,'negative_odd':0};satcount=0
 for n,(i,q) in enumerate(data):
  ph=(int(phase)+n*int(step))%(1<<32);address=rne(ph,1<<22)%1024;c,s=rom[address];a=i*c-q*s;b=i*s+q*c
  for v in [a,b]:
   quotient,remainder=divmod(v,1<<14)
   if remainder==8192:ties[('negative_' if v<0 else 'positive_')+('odd' if quotient&1 else 'even')]+=1
  oi,oq=rne(a,1<<14),rne(b,1<<14);satbits=int(oi!=sat(oi))|(int(oq!=sat(oq))<<1);satcount+=(satbits&1)+((satbits>>1)&1);outs.append((sat(oi),sat(oq)));sats.append(satbits)
 vi=D/f'sim/vectors/rot_case{case}_input.mem';vo=D/f'sim/vectors/rot_case{case}_expected.mem';vs=D/f'sim/vectors/rot_case{case}_sat.mem'
 vi.write_text(''.join(f'{pack(data[j:j+4]):032x}\n' for j in range(0,N,4)));vo.write_text(''.join(f'{pack(outs[j:j+4]):032x}\n' for j in range(0,N,4)));vs.write_text(''.join(f'{sum(sats[j+l]<<(2*l) for l in range(4)):02x}\n' for j in range(0,N,4)))
 cases.append(dict(case_id=case,samples=N,beats=N//4,phase0=int(phase),step=int(step),source=source,saturation_components=satcount,ties=ties,files=[str(p.relative_to(D)) for p in [vi,vo,vs]]))
assert cases[2]['saturation_components']>0 and all(cases[3]['ties'].values())
inc='// Frozen configuration for four two-symbol tests.\n'
for c in cases:inc+=f"phase_table[{c['case_id']}]=32'h{c['phase0']&0xffffffff:08x};step_table[{c['case_id']}]=32'h{c['step']&0xffffffff:08x};\n"
(D/'sim/vectors/rotator_configs.svh').write_text(inc)
(D/'sim/vectors/ROTATOR_VECTOR_MANIFEST.json').write_text(json.dumps(dict(samples_per_case=N,cases=cases,algorithm='Exact integer phase32/address10/C16F14 ordinary complex multiply/RNE/sat; case3 includes phase-address half ties and modulo wrap',phase_correction_controller_tested=False),indent=2)+'\n')
print(json.dumps(cases,indent=2))