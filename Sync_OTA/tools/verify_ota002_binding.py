"""Read-only check of the new job's actual XPM compile and elaboration binding."""
from pathlib import Path
import re,sys,json
root=Path(__file__).resolve().parents[1]
sim=Path(sys.argv[1]).resolve()
assert sim.is_relative_to(root/'work/OTA002'),str(sim)
prjs=list(sim.glob('*_vlog.prj'));assert len(prjs)==1,prjs
text=prjs[0].read_text()
selected=[]
for line in text.splitlines():
 if line.strip()=='nosort' or not line.strip():continue
 assert line.startswith('sv ota_xpm ') or line.startswith('verilog ota_xpm '),line
 for quoted in re.findall(r'"([^"]+)"',line):
  p=(sim/quoted).resolve()
  if p.name in ('xpm_cdc.sv','xpm_fifo.sv','xpm_memory.sv'):selected.append(p)
expected=[(root/f'sim/vendor/link010r1/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory')]
assert sorted(selected)==sorted(expected),(selected,expected)
elab=(sim/'elaborate.log').read_text(errors='replace')
assert not re.search(r'Compiling module xpm\.xpm_',elab), 'installed precompiled XPM bound'
for name in ['xpm_fifo_async','xpm_cdc_single','xpm_cdc_sync_rst']:
 assert re.search(r'Compiling module ota_xpm\.'+name+r'\b',elab),name
commands=[line for line in elab.splitlines() if 'xelab' in line and '--' in line]
assert commands, 'no actual xelab command'
libs=re.findall(r'-L\s+([^\s"]+)',commands[0]);assert 'ota_xpm' in libs,libs
if 'xpm' in libs:assert libs.index('ota_xpm')<libs.index('xpm'),libs
assert (sim/'xsim.dir/ota_xpm').is_dir()
result=dict(status='OTA002_PRIVATE_XPM_BINDING_PASS',simdir=str(sim),actual_vendor=[str(p) for p in selected],libraries=libs)
(sim/'binding_verified.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
