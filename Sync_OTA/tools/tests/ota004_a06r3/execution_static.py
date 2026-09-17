from pathlib import Path
import tkinter,tempfile,json
R=Path('D:/008_MA_Dev/Sync_OTA')
checks=[]
for label,design_name,project_part,design_part,missing,bbox,expected in [
 ('design_label_differs_top','netlist','xcvu11p-flgb2104-2-e','xcvu11p-flgb2104-2-e','',0,True),
 ('design_label_same_top','sync_ota_top','xcvu11p-flgb2104-2-e','xcvu11p-flgb2104-2-e','',0,True),
 ('wrong_project_part','netlist','wrong','xcvu11p-flgb2104-2-e','',0,False),
 ('conflicting_design_part','netlist','xcvu11p-flgb2104-2-e','wrong','',0,False),
 ('missing_core_hierarchy','netlist','xcvu11p-flgb2104-2-e','xcvu11p-flgb2104-2-e','cfo',0,False),
 ('blackbox','netlist','xcvu11p-flgb2104-2-e','xcvu11p-flgb2104-2-e','',1,False)]:
 t=tkinter.Tcl()
 for k,v in dict(designName=design_name,projectPart=project_part,designPart=design_part,missing=missing,bbox=bbox).items():t.setvar(k,v)
 t.eval('proc current_design {} {return design_object}; proc current_project {} {return project_object}; proc list_property {obj} {return {NAME CLASS PART TOP}}')
 t.eval('proc get_property {p obj} {if {$obj eq "project_object"} {return $::projectPart}; if {$obj eq "design_object"} {switch $p {NAME {return $::designName} CLASS {return design} PART {return $::designPart} TOP {return sync_ota_top}}}; if {$p eq "NAME"} {return $obj}; error "unexpected property"}')
 t.eval('proc get_cells {args} {if {[lindex $args 0] eq "-hierarchical"} {if {$::bbox} {return blackbox}; return {}}; set cell [lindex $args 0]; if {$cell eq $::missing} {return {}}; return [list $cell]}')
 t.eval((R/'tools/vivado/audit_ota004_a06r3_identity.tcl').read_text())
 with tempfile.TemporaryDirectory(prefix='ota-r3-identity-') as temp:
  t.setvar('output',Path(temp).as_posix());code=int(t.eval('catch {ota_a06r3_identity $output} message'))
  assert (code==0)==expected,(label,t.eval('set message'))
  assert (Path(temp)/'runtime_design_properties.txt').exists()
  assert (Path(temp)/'report_identity.txt').exists()==expected
 checks.append({'name':label,'result':'PASS'})
entry=(R/'tools/vivado/run_ota004_a06r3.tcl').read_text()
t=tkinter.Tcl();t.eval('rename puts real_puts; proc puts {args} {if {[llength $args]==1 || [lindex $args 0] eq "stderr"} {return}; uplevel 1 [linsert $args 0 real_puts]}')
t.eval(entry[entry.index('proc ota_collect '):entry.index('set stageFile [open')])
with tempfile.TemporaryDirectory(prefix='ota-r3-stages-') as temp:
 t.setvar('file',str(Path(temp)/'stages.txt'));t.eval('set stageFile [open $file w]; set failures {}')
 assert t.eval('ota_collect format_problem {error "fixture format problem"}')=='0'
 assert t.eval('ota_collect independent_following_step {set reached 1}')=='1'
 assert t.eval('set reached')=='1' and t.eval('set failures')=='format_problem'
 t.eval('close $stageFile')
 checks.append({'name':'partial_failure_preserves_independent_progress','result':'PASS'})
for rel in ('tools/vivado/run_ota004_a06r3.tcl','tools/vivado/audit_ota004_a06r3_identity.tcl','tools/vivado/audit_ota004_a06r3_gray.tcl','tools/vivado/report_ota004_a06r3_timing.tcl'):
 assert int(t.call('info','complete',(R/rel).read_text()))==1
compile((R/'tools/verify_ota004_a06r3_report.py').read_text(),'reviewer','exec')
assert (R/'tools/monitor_ota004_a06r3.ps1').read_text().split('$nativeNames=',1)[1]==(R/'tools/monitor_ota004_a06r2.ps1').read_text().split('$nativeNames=',1)[1]
checks.append({'name':'syntax_and_unchanged_monitor_runtime','result':'PASS'})
p=R/'reports/OTA004/A06R3_EXECUTION_STATIC.json'
with p.open('x',encoding='utf-8') as f:json.dump({'status':'PASS','checks':checks,'scope':'Offline synthetic API objects; not native DCP acceptance'},f,indent=2);f.write('\n')
print(json.dumps({'status':'PASS','checks':len(checks)}))
