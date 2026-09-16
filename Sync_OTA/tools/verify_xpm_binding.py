"""Verify actual XPM binding, including PRJ comments/continuations; no input edits."""
from pathlib import Path
import re,sys,json
root=Path(__file__).resolve().parents[1]
sim=Path(sys.argv[1]).resolve();required=sys.argv[2] if len(sys.argv)>2 else 'fifo'
assert sim.is_relative_to(root/'work'),sim
prjs=list(sim.glob('*_vlog.prj'));assert len(prjs)==1,prjs
logical=[];pending=''
for raw in prjs[0].read_text().splitlines():
 line=raw.strip()
 if not line or line=='nosort' or line.startswith('#'):continue
 pending+=' '+line.rstrip('\\').strip()
 if not line.endswith('\\'):logical.append(pending.strip());pending=''
assert not pending,'unterminated PRJ continuation'
selected=[]
for line in logical:
 assert line.startswith(('sv ota_xpm ','verilog ota_xpm ')),line
 for quoted in re.findall(r'"([^"]+)"',line):
  p=(sim/quoted).resolve()
  if p.name in ('xpm_cdc.sv','xpm_fifo.sv','xpm_memory.sv'):selected.append(p)
expected=[(root/f'sim/vendor/link010r1/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory')]
assert sorted(selected)==sorted(expected),(selected,expected)
elab=(sim/'elaborate.log').read_text(errors='replace')
assert not re.search(r'Compiling module xpm\.xpm_',elab),'installed XPM bound'
if required=='fifo':
 for name in ['xpm_fifo_async','xpm_cdc_single','xpm_cdc_sync_rst']:
  assert re.search(r'Compiling module ota_xpm\.'+name+r'\b',elab),name
else:assert required=='none',required
commands=[line for line in elab.splitlines() if 'xelab' in line and '--' in line];assert commands
libs=re.findall(r'-L\s+([^\s"]+)',commands[0]);assert 'ota_xpm' in libs
if 'xpm' in libs:assert libs.index('ota_xpm')<libs.index('xpm'),libs
assert (sim/'xsim.dir/ota_xpm').is_dir()
print(json.dumps(dict(status='PRIVATE_XPM_EXACT_BINDING_PASS',simdir=str(sim),required_instances=required,actual_vendor=[str(p) for p in selected],libraries=libs)))
