from pathlib import Path
import xml.etree.ElementTree as ET,hashlib,json
root=Path(__file__).resolve().parents[1]
ns='{http://www.spiritconsortium.org/XMLSchema/SPIRIT/1685-2009}'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
selected={};originals=[];duplicates=[]
def cfg(p):
 return {e.get(ns+'referenceId'):e.text for e in ET.parse(p).getroot().iter(ns+'configurableElementValue')}
for name in ['Sync_Frontend','Sync_SFO']:
 src=root.parent/name
 for f in ET.parse(root/f'docs/provenance/{name}.xpr.xml').getroot().iter('File'):
  value=f.get('Path','')
  if not value.endswith('.xci'):continue
  p=Path(value.replace('$PPRDIR',str(src)).replace('$PSRCDIR',str(src/f'{name}.srcs'))).resolve()
  if any(x['source']==str(p) for x in originals):continue
  assert p.is_file(),str(p)
  original=root/f'docs/provenance/ip_originals/{name}/{p.name}'
  original.parent.mkdir(parents=True,exist_ok=True)
  if original.exists():assert original.read_bytes()==p.read_bytes()
  else:original.write_bytes(p.read_bytes())
  originals.append(dict(source=str(p),copied_original=original.relative_to(root).as_posix(),sha256=sha(p)))
  if p.stem in selected:
   prior=selected[p.stem];a,b=cfg(prior),cfg(p)
   diff={k:[a.get(k),b.get(k)] for k in a.keys()|b.keys() if a.get(k)!=b.get(k)}
   assert set(diff)<={'PROJECT_PARAM.PREFHDL','RUNTIME_PARAM.OUTPUTDIR'},(p.stem,diff)
   duplicates.append(dict(module=p.stem,first=str(prior),second=str(p),differences=diff,selection='Sync_SFO canonical XCI; functional configuration identical'))
  selected[p.stem]=p
build=[]
for module,src in selected.items():
 dst=root/f'ip/config/{module}/{module}.xci';dst.parent.mkdir(parents=True,exist_ok=True)
 t=ET.parse(src);changes={}
 for e in t.getroot().iter(ns+'configurableElementValue'):
  key=e.get(ns+'referenceId')
  if key=='RUNTIME_PARAM.OUTPUTDIR' and e.text!='.':changes[key]=[e.text,'.'];e.text='.'
  if key=='PROJECT_PARAM.PREFHDL' and e.text!='VERILOG':changes[key]=[e.text,'VERILOG'];e.text='VERILOG'
  assert not any(s in (e.text or '').lower() for s in ['.coe','.mem',':/']), (module,key,e.text)
 ET.register_namespace('spirit',ns[1:-1]);ET.register_namespace('xilinx','http://www.xilinx.com')
 assert not dst.exists(),str(dst)
 t.write(dst,encoding='UTF-8',xml_declaration=True)
 actual=cfg(dst);before=cfg(src)
 assert {k for k in actual.keys()|before.keys() if actual.get(k)!=before.get(k)}==set(changes)
 build.append(dict(module=module,source=str(src),source_sha256=sha(src),target=dst.relative_to(root).as_posix(),target_sha256=sha(dst),transport_changes=changes))
roms=[]
for src,rel in [(root.parent/'Sync_Frontend/ip/rom/fine_ps1_reference_16lane.mem','ip/rom/fine_ps1_reference_16lane.mem'),(root.parent/'Sync_SFO/sim/data/residual_pilot_phase.mem','ip/rom/residual_pilot_phase.mem')]:
 dst=root/rel;dst.parent.mkdir(parents=True,exist_ok=True);assert not dst.exists();dst.write_bytes(src.read_bytes())
 roms.append(dict(source=str(src),target=rel,sha256=sha(dst)))
(root/'docs/provenance/OTA_IP_SOURCE_LOCK.json').write_text(json.dumps(dict(originals=originals,duplicates=duplicates,build=build,roms=roms,note='Original XCI preserved byte-for-byte. New build XCIs differ only in generated-output directory and preferred HDL; no algorithm/IP functional parameters changed. Coefficients are embedded in XCI, no external coe/mem reference in these 45 configs.'),indent=2),encoding='utf-8')
(root/'ip/sources.f').write_text('\n'.join(x['target'] for x in build)+'\n',encoding='utf-8')
print('IP_CLOSURE_PREPARED',len(originals),'originals',len(build),'unique IPs',len(duplicates),'identical-functional duplicates',len(roms),'ROMs')
