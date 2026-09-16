from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1];cfo=root.parent/'Sync_CFO';rows=[]
def cp(a,b):
 b.parent.mkdir(parents=True,exist_ok=True)
 if b.exists():assert b.read_bytes()==a.read_bytes(),str(b)
 b.write_bytes(a.read_bytes());rows.append(dict(source=str(a),target=str(b.relative_to(root)),sha256=hashlib.sha256(b.read_bytes()).hexdigest()))
for name in ['xpm_cdc','xpm_memory','xpm_fifo']:
 cp(Path(f'C:/NIFPGA/programs/Vivado2021_1/data/ip/xpm/{name}/hdl/{name}.sv'),root/f'rtl/vendor/xpm/{name}.sv')
 cp(cfo/f'sim/vendor/link010r1/{name}.sv',root/f'sim/vendor/link010r1/{name}.sv')
for suffix in ['input','read','result']:
 cp(cfo/f'sim/vectors/link010_{suffix}.mem',root/f'sim/data/link010_{suffix}.mem')
cp(cfo/'tools/verify_link010r1_models.py',root/'tools/verify_link010r1_models.py')
(root/'docs/provenance/OTA002_REUSED_INPUTS.json').write_text(json.dumps(rows,indent=2))
print('OTA002_DEPENDENCIES_COPIED',len(rows))
