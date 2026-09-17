"""Check actual full-core PRJ and elaboration, preserving exact XPM boundaries."""
from pathlib import Path
import re,sys,json
root=Path(__file__).resolve().parents[1];sim=Path(sys.argv[1]).resolve()
assert sim.is_relative_to(root/'Sync_OTA.sim'),sim
prjs=list(sim.glob('*_vlog.prj'));assert len(prjs)==1
joined=re.sub(r'\\\s*\n',' ',prjs[0].read_text())
selected=[];selected_rtl=[]
for line in joined.splitlines():
 line=line.strip()
 if not line or line.startswith('#') or line=='nosort':continue
 for quoted in re.findall(r'"([^"]+)"',line):
  p=(sim/quoted).resolve()
  if p.name in ('xpm_cdc.sv','xpm_fifo.sv','xpm_memory.sv'):
   assert line.startswith(('sv ota_xpm ','verilog ota_xpm ')),line;selected.append(p)
  if p.is_relative_to(root/'rtl') and '/vendor/' not in p.as_posix():selected_rtl.append(p)
expected=[(root/f'sim/vendor/link010r1/{n}.sv').resolve() for n in ('xpm_cdc','xpm_fifo','xpm_memory')]
assert sorted(selected)==sorted(expected),selected
assert root/'rtl/control/sync_ota_top_a06.sv' in selected_rtl
assert root/'rtl/control/sync_ota_top.sv' not in selected_rtl
assert root/'rtl/control/sync_ota_top_a05.sv' not in selected_rtl
assert root/'rtl/common/ota_async_fifo_a06.sv' in selected_rtl
assert root/'rtl/cfo/cfo_estimator_link_a06.sv' in selected_rtl
assert root/'rtl/common/ota_async_fifo.sv' not in selected_rtl
assert root/'rtl/cfo/cfo_estimator_link_v2.sv' not in selected_rtl
assert root/'rtl/cfo/ota_cfo_chain_a06.sv' in selected_rtl
assert root/'rtl/cfo/ota_cfo_chain.sv' not in selected_rtl
elab=(sim/'elaborate.log').read_text(errors='replace')
assert not re.search(r'Compiling module xpm\.xpm_',elab)
for name in ['ota_algorithm_reset_guard','sync_ota_top','sync_frontend_top','sync_sfo_top','sfo_initial_estimator','sfo_first_resampler','sfo_residual_estimator4','sfo_second_resampler','ota_cfo_chain','cfo_rotate4','cfo_coordinate_control','cfo_front2048_window','cfo_estimate74_backend','xpm_fifo_async','xpm_cdc_single','xpm_cdc_sync_rst']:
 assert re.search(r'Compiling module ota_xpm\.'+name+r'\b',elab),name
commands=[l for l in elab.splitlines() if 'xelab' in l and '--' in l];assert commands
libs=re.findall(r'-L\s+([^\s"]+)',commands[0]);assert 'ota_xpm' in libs
if 'xpm' in libs:assert libs.index('ota_xpm')<libs.index('xpm')
print(json.dumps(dict(status='OTA004_REAL_CORE_BINDING_PASS',private_xpm=[str(p) for p in selected],own_rtl_compiled=len(selected_rtl),libraries=libs)))
