from pathlib import Path
import xml.etree.ElementTree as ET,json,hashlib,zipfile,shutil,datetime
r=Path(r'D:\008_MA_Dev');o=r/'docs/verification/native_project';o.mkdir(exist_ok=True);b=o/'baseline';b.mkdir(exist_ok=False)
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def js(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
original=json.loads((r/'docs/provenance/NATIVE_PROJECT_INPUTS.json').read_text(encoding='utf-8-sig'))
for f in original['files']:assert h(r/f['path'])==f['sha256'].upper(),f['path']
shutil.copy2(r/'ip/expected_user_config.json',b/'original_expected_user_config.json');shutil.copy2(r/'tools/vivado/create_project.tcl',b/'original_create_project.tcl');shutil.copy2(r/'docs/provenance/NATIVE_PROJECT_INPUTS.json',b/'original_native_inputs.json')
ns='http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009';names=(r/'ip/ip_names.txt').read_text().split();assert len(names)==len(set(names))==34
expected={};ips=[];corrections=[];old=json.loads((r/'ip/expected_user_config.json').read_text(encoding='utf-8-sig'))
with zipfile.ZipFile(b/'original_ip_xci.zip','w',zipfile.ZIP_DEFLATED) as z:
 for n in names:
  p=r/'ip/config'/n/(n+'.xci');tree=ET.parse(p);values={x.attrib['{'+ns+'}referenceId']:x.text or '' for x in tree.findall('.//{'+ns+'}configurableElementValue')};cfg={k.removeprefix('PARAM_VALUE.'):v for k,v in values.items() if k.startswith('PARAM_VALUE.')};ref=tree.find('.//{'+ns+'}componentRef');vlnv=':'.join(ref.attrib['{'+ns+'}'+k] for k in ['vendor','library','name','version']);assert values['PROJECT_PARAM.PACKAGE']=='flgc2104'
  expected[n]=cfg;ips.append(dict(name=n,path=p.relative_to(r).as_posix(),sha256=h(p),vlnv=vlnv,values=values))
  z.write(p,p.relative_to(r).as_posix())
  for k in sorted(set(old[n])|set(cfg)):
   if old[n].get(k)!=cfg.get(k):corrections.append(dict(ip=n,parameter=k,old=old[n].get(k),corrected=cfg.get(k)))
js(r/'ip/expected_user_config.json',expected)
js(b/'IP_BASELINE.json',dict(source='Copied XCI bytes before any native migration',ips=ips,source_zip_sha256=h(b/'original_ip_xci.zip')))
js(o/'CONFIG_BASELINE_CORRECTION.json',dict(original_manifest_verified=True,original_json_sha256=h(b/'original_expected_user_config.json'),corrected_json_sha256=h(r/'ip/expected_user_config.json'),reason='Only spirit:configurableElementValue stores PARAM_VALUE values; later configElementInfo references have no text and must not overwrite values.',corrections=corrections,RTL_modified=False,XCI_modified=False))
def tq(s):return '"'+str(s).replace('\\','\\\\').replace('"','\\"').replace('$','\\$').replace('[','\\[').replace(']','\\]').replace('\n','\\n').replace('\r','\\r')+'"'
lines=['# Generated from the pre-migration XCI configurableElementValue nodes.','set expected_user_config [dict create]','set expected_ipdef [dict create]']
for i in ips:
 n=i['name'];lines.append('dict set expected_ipdef '+tq(n)+' '+tq(i['vlnv']))
 for k,v in expected[n].items():lines.append('dict set expected_user_config '+tq(n)+' '+tq(k)+' '+tq(v))
(r/'ip/expected_user_config.tcl').write_text('\n'.join(lines)+'\n',encoding='utf-8')
core=(r/'rtl/sources.f').read_text().split();assert len(core)==len(set(core))==74
files=core+['rtl/sources.f','ip/ip_names.txt','rtl/vendor/xpm/xpm_cdc.sv','rtl/vendor/xpm/xpm_memory.sv','rtl/vendor/xpm/xpm_fifo.sv','sim/tb/t10_full023_tb.sv','sim/tb/t10_full023_fifo_observer.sv','constraints/t10_root_clocks.xdc']+['sim/data/'+n for n in ['raw.mem','r1.mem','r2.mem','delay.mem','delta.mem','t09_pilot_phase.mem']]
js(b/'IMMUTABLE_INPUTS.json',dict(files=[dict(path=f,sha256=h(r/f),bytes=(r/f).stat().st_size) for f in files]))
js(o/'REPORT_CLOCK.json',dict(work_state='WORKING',started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),next_due_utc=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=15)).isoformat(),scope='Native GUI project preparation and review only'))
print(json.dumps(dict(ips=len(ips),config_corrections=len(corrections),immutable_inputs=len(files),baseline=str(b))))
