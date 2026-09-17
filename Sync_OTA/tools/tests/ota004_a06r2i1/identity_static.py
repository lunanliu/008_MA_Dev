import csv,io,json,tempfile,tkinter,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
helper=ROOT/'tools/vivado/audit_ota004_a06r2i1_identity.tcl'
entry=ROOT/'tools/vivado/run_ota004_a06r2i1.tcl'
results=[]
for label,name,part,nerr,perr,object_name in [
 ('both_exact','sync_ota_top','xcvu11p-flgb2104-2-e',0,0,'netlist'),
 ('NAME_differs_TOP_matches','netlist','xcvu11p-flgb2104-2-e',0,0,'netlist'),
 ('PART_wrong','sync_ota_top','wrong-part',0,0,'netlist'),
 ('both_wrong','wrong-name','wrong-part',0,0,'netlist'),
 ('NAME_query_error','unused','xcvu11p-flgb2104-2-e',1,0,'netlist'),
 ('PART_query_error','sync_ota_top','unused',0,1,'netlist'),
 ('empty_design','unused','unused',0,0,'')]:
 t=tkinter.Tcl();t.eval('rename puts original_puts; proc puts {args} {if {[llength $args]==1} {return}; uplevel 1 [linsert $args 0 original_puts]}')
 for key,value in {'mockName':name,'mockPart':part,'nerr':nerr,'perr':perr,'objectName':object_name}.items():t.setvar(key,value)
 t.eval('''
 set calls {}
 proc current_design {} {return $::objectName}
 proc get_property {p obj} {
  lappend ::calls $p
  if {$p eq "NAME"} {if {$::nerr} {error "mock NAME failed"}; return $::mockName}
  if {$p eq "PART"} {if {$::perr} {error "mock PART failed"}; return $::mockPart}
  if {$p eq "CLASS"} {return design}
  if {$p eq "TOP"} {return sync_ota_top}
  error "unexpected mock property"
 }
 proc list_property {obj} {return {CLASS NAME PART TOP}}
 ''')
 t.eval(helper.read_text(encoding='utf-8'))
 with tempfile.TemporaryDirectory(prefix='ota-i1-static-') as td:
  t.setvar('outdir',Path(td).as_posix());code=int(t.eval('catch {ota_a06r2i1_identity $outdir} msg'))
  rows=list(csv.DictReader((Path(td)/'identity_observation.tsv').open(encoding='utf-8'),delimiter='\t'))
  def decode(row,key):return bytes.fromhex(row[key+'_utf8_hex']).decode('utf-8')
  guard=[x for x in rows if x['kind']=='GUARD'];assert len(guard)==1
  if object_name:
   primary=[x for x in rows if x['kind']=='PRIMARY'];assert [x['property'] for x in primary]==['NAME','PART']
   assert t.splitlist(t.eval('set calls'))[:2]==('NAME','PART')
   assert all(rows.index(x)<rows.index(guard[0]) for x in primary)
   assert decode(primary[0],'expected')=='sync_ota_top'
   assert decode(primary[1],'expected')=='xcvu11p-flgb2104-2-e'
   if not nerr:assert decode(primary[0],'actual')==name
   if not perr:assert decode(primary[1],'actual')==part
  expected_pass=label=='both_exact';assert (code==0)==expected_pass
  if label=='NAME_differs_TOP_matches':
   assert guard[0]['comparison']=='0'
   assert any(x['kind']=='CONTEXT' and x['property']=='TOP' and decode(x,'actual')=='sync_ota_top' for x in rows)
  results.append({'name':label,'result':'PASS','guard_exit':code})
t=tkinter.Tcl()
for p in (helper,entry):assert int(t.call('info','complete',p.read_text(encoding='utf-8')))==1
for p in (ROOT/'tools/verify_ota004_a06r2i1_inputs.py',Path(__file__)):compile(p.read_text(encoding='utf-8'),str(p),'exec')
source=entry.read_text(encoding='utf-8')
import re
assert len(re.findall(r'^\s*open_checkpoint\s+\$dcp\s*$',source,re.M))==1
for forbidden in ('synth_design','write_checkpoint','write_edif','report_cdc','report_timing','open_project','set_property','set_part','launch_runs','reset_run','launch_simulation'):
 assert not re.search(r'^\s*'+forbidden+r'\b',source+'\n'+helper.read_text(encoding='utf-8'),re.M),forbidden
assert (ROOT/'tools/monitor_ota004_a06r2i1.ps1').read_text().split('$nativeNames=',1)[1]==(ROOT/'tools/monitor_ota004_a06r2.ps1').read_text().split('$nativeNames=',1)[1]
results.append({'name':'syntax_readonly_single_open_monitor_runtime','result':'PASS'})
record={'status':'A06R2I1_OFFLINE_FIXTURES_PASS','checks':results,'tcl_version':t.eval('info patchlevel'),'scope':'Synthetic Tcl API objects only; no Vivado and no actual NAME/PART acceptance'}
p=ROOT/'reports/OTA004/A06R2I1_IDENTITY_STATIC_TESTS.json'
with p.open('x',encoding='utf-8') as f:json.dump(record,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({'status':record['status'],'checks':len(results)}))
