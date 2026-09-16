from pathlib import Path
import json,hashlib,shutil,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
parent=root.parent
rows=[]
def copy(src,dst,scope,evidence):
    dst.parent.mkdir(parents=True,exist_ok=True)
    data=src.read_bytes()
    if dst.exists() and dst.read_bytes()!=data:raise RuntimeError(f'preserve modified target {dst}')
    dst.write_bytes(data)
    rows.append(dict(scope=scope,source=str(src),target=str(dst.relative_to(root)),sha256=hashlib.sha256(data).hexdigest(),evidence=evidence))
for name,listing,evidence in [('Sync_Frontend','tools/sf003_rtl_sources.txt','SF003 core synthesis; SF002 autonomous four frames'),('Sync_SFO','rtl/sources.f','FN01 compile/elaborate; case6001 prior full-frame behavioral')]:
    srcroot=parent/name
    xpr=srcroot/(name+'.xpr')
    members=[]
    for fs in ET.parse(xpr).getroot().iter('FileSet'):
        if fs.get('Name')=='sources_1':
            for f in fs.findall('File'):
                members.append(Path(f.get('Path').strip().replace('$PPRDIR',str(srcroot))).resolve())
    selected=[srcroot/x.strip() for x in (srcroot/listing).read_text(encoding='utf-8-sig').splitlines() if x.strip()]
    for src in selected:
        if src.resolve() not in members:raise RuntimeError(f'not in canonical XPR: {src}')
        copy(src,root/'rtl'/name.removeprefix('Sync_').lower()/src.relative_to(srcroot/'rtl'),name,evidence)
    copy(xpr,root/'docs/provenance'/(name+'.xpr.xml'),name,'read-only provenance, not runnable project')
    copy(srcroot/listing,root/'docs/provenance'/(name+'_sources.txt'),name,evidence)
    (root/'docs/provenance'/(name+'_canonical_members.json')).write_text(json.dumps([str(p) for p in members],indent=2),encoding='utf-8')
cfo=parent/'Sync_CFO'
names=['cfo_rotate4.sv','cfo_coordinate_control.sv','cfo_front2048_window.sv','cfo_fft2048_core.sv','cfo_estimator_link_v2.sv','cfo_estimate74_backend.sv','cfo_fft74_quality_v2.sv','cfo_divide_rne64wide.sv','cfo_fft256_core.sv','cfo_phase74_core_v2.sv','cfo_divide_rne64.sv']
for name in names:copy(cfo/'rtl'/name,root/'rtl/cfo'/name,'Sync_CFO','rotate/coordinate/front stage source lists; LINK010R1 RTL v2 reset amendment, NOT native reset PASS')
for name in ['cfo_rot_lut.mem','fft2048_twiddle.mem','front2048_coefficient_index.mem','front2048_coefficient_table.mem','fft256_twiddle.mem','phase74_atan_q31.mem']:
    copy(cfo/'ip'/name,root/'ip/cfo'/name,'Sync_CFO','explicit stage project ROM dependencies')
for rel in ['docs/CFO_MAIN_CONTRACT.json','docs/ARCHITECTURE_AND_MEMORY_ZH.md','vivado/link010r1_project.tcl','vivado/front2048_project.tcl','vivado/coordinate_project.tcl','vivado/create_project.tcl']:
    copy(cfo/rel,root/'docs/provenance/CFO'/Path(rel).name,'Sync_CFO','read-only identity, not executable job')
(root/'docs/provenance/BASELINE_SOURCE_LOCK.json').write_text(json.dumps(dict(parent_git_head='84b9cd8f968e5f186fe68b31aba5a3a96b6d002d',files=rows,scope='RTL plus CFO ROM snapshot. Frontend/SFO vendor IP closure remains required before full-core native compile.'),indent=2),encoding='utf-8')
print('COPIED_VERIFIED',len(rows))
