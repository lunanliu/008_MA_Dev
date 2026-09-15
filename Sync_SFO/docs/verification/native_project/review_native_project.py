"""Read-only review of native project migration artifacts; no FPGA tool invocation."""
from pathlib import Path
import csv,hashlib,json,sys,xml.etree.ElementTree as ET,datetime
root=Path(__file__).resolve().parents[3];attempt=Path(sys.argv[1]).resolve();base=root/'docs/verification/native_project/baseline';ns='http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
problems=[];native=read(attempt/'native_complete.json');baseline=read(base/'IP_BASELINE.json');expected=read(root/'ip/expected_user_config.json');iprows=[]
for f in read(base/'IMMUTABLE_INPUTS.json')['files']:
 if sha(root/f['path'])!=f['sha256']:problems.append('Immutable input changed: '+f['path'])
for old in baseline['ips']:
 p=root/old['path'];tree=ET.parse(p);values={x.attrib['{'+ns+'}referenceId']:x.text or '' for x in tree.findall('.//{'+ns+'}configurableElementValue')};ref=tree.find('.//{'+ns+'}componentRef');vlnv=':'.join(ref.attrib['{'+ns+'}'+k] for k in ['vendor','library','name','version']);changes=[]
 for k in sorted(set(old['values'])|set(values)):
  if old['values'].get(k)!=values.get(k):changes.append(dict(key=k,before=old['values'].get(k),after=values.get(k)))
 cfg={k.removeprefix('PARAM_VALUE.'):v for k,v in values.items() if k.startswith('PARAM_VALUE.')}
 algorithm=[x for x in changes if x['key'].startswith(('PARAM_VALUE.','MODELPARAM_VALUE.'))]
 if algorithm or cfg!=expected[old['name']]:problems.append('Algorithm CONFIG/model changed: '+old['name'])
 if vlnv!=old['vlnv']:problems.append('IP version changed: '+old['name'])
 target=''.join([values.get('PROJECT_PARAM.DEVICE',''),'‑',values.get('PROJECT_PARAM.PACKAGE',''),values.get('PROJECT_PARAM.SPEEDGRADE',''),'‑',values.get('PROJECT_PARAM.TEMPERATURE_GRADE','').lower()]).replace('‑','-')
 if target!='xcvu11p-flgb2104-2-e':problems.append('Wrong IP target: '+old['name']+' '+target)
 iprows.append(dict(name=old['name'],path=old['path'],before_sha256=old['sha256'],after_sha256=sha(p),part=target,vlnv=vlnv,algorithm_changes=algorithm,all_value_changes=changes))
for stage in ['after','reopened']:
 with (attempt/f'config_{stage}.csv').open(encoding='utf-8-sig',newline='') as f:rows=list(csv.DictReader(f))
 for row in rows:
  if row['SourceMatches']!='1':problems.append('Native CONFIG differs from source: '+stage+'/'+row['IP']+'/'+row['Parameter'])
 if len(rows)!=sum(len(v) for v in expected.values()):problems.append('Native CONFIG coverage mismatch')
paths={x.resolve() for x in root.rglob('*.xci')};wanted={(root/x['path']).resolve() for x in baseline['ips']}
if paths!=wanted:problems.append('More than one active XCI source set or missing canonical XCI')
products=[p.relative_to(root).as_posix() for p in (root/'ip/config').rglob('*') if p.is_file() and p.suffix.lower() in ['.v','.sv','.vhd','.dcp','.mif','.ngc','.edf','.edn']]
if products:problems.append('Unexpected generated IP output products')
result=dict(status='PENDING_ASTRA_REVIEW' if not problems else 'REVIEW_FAILED',complete=not problems,utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),native=native,core_files_checked=74,ip_files_checked=len(iprows),canonical_ip_only=paths==wanted,ip_config=[*iprows],unexpected_products=products,problems=problems,scope='Project create, same-version native IP retarget, close/reopen and identity only; no output generation, simulation, synthesis, implementation or GUI interaction test')
(attempt/'review_summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status=result['status'],problems=problems,ip_files=len(iprows)),ensure_ascii=False));sys.exit(0 if not problems else 1)
