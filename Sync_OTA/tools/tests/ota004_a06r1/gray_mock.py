from pathlib import Path
import importlib.util,json,tempfile,tkinter
root=Path('D:/008_MA_Dev/Sync_OTA')
spec=importlib.util.spec_from_file_location('m',root/'tools/verify_ota004_a06r1_synth_result.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
t=tkinter.Tcl();t.eval((root/'tools/vivado/audit_ota004_a06r1_gray.tcl').read_text())
cells=[];clockargs=[];periodargs=[];xdcmax=[];xdcbus=[];busargs=[]
header='| Tool Version : Vivado v.2021.1\n| Design : sync_ota_top\n| Device : xcvu11p-flgb2104\n'
for fifo,(sc0,dc0,w) in m.FIFOS.items():
 for typ in m.TYPES:
  gray=fifo+'/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.'+typ
  sc,dc=(dc0,sc0) if typ.startswith('rd_') else (sc0,dc0);width=w+('_dc_inst' in typ)
  src=[gray+f'/src_gray_ff_reg[{i}]' for i in range(width)];dst=[gray+f'/dest_graysync_ff_reg[0][{i}]' for i in range(width)]
  cells+=src+dst
  for cell in src:clockargs+=[cell,sc]
  for cell in dst:clockargs+=[cell,dc]
  periodargs+=[gray,m.PERIODS[sc]]
  xdcmax.append('set_max_delay -from [get_cells {'+' '.join(src)+'}] -to [get_cells {'+' '.join(dst)+'}] '+str(m.PERIODS[sc])+' -datapath_only\n')
  skew=min(m.PERIODS[sc],m.PERIODS[dc])
  xdcbus.append('set_bus_skew -from [get_cells {'+' '.join(src)+'}] -to [get_cells {'+' '.join(dst)+'}] '+str(skew)+'\n')
  busargs+=[gray,header+f'| Command : report_bus_skew -cells {gray} -no_detailed_paths\n\nId  From  To  Corner  Requirement  Actual  Slack\n1  {gray}/src_gray_ff_reg*  {gray}/dest_graysync_ff_reg[0]*  Slow  {skew}  0.100  1.000\n']
t.setvar('fixture_cells',tuple(cells))
t.setvar('fixture_clocks',t.call('dict','create',*clockargs))
t.setvar('fixture_periods',t.call('dict','create',*periodargs))
t.setvar('fixture_bus',t.call('dict','create',*busargs))
t.setvar('fixture_valid',''.join(xdcmax))
t.eval(r'''
proc get_cells {args} {
 if {[lindex $args 0] eq "-hierarchical"} {return $::fixture_cells}
 return [lindex $args end]
}
proc get_pins {args} {
 set objects [lindex $args 1];set pin [expr {[lindex $args end] eq "REF_PIN_NAME == C" ? "C" : "D"}]
 set result {};foreach o $objects {lappend result $o/$pin};return $result
}
proc get_clocks {args} {
 set result {};foreach pin [lindex $args 1] {lappend result [dict get $::fixture_clocks [file dirname $pin]]}
 return [lsort -unique $result]
}
proc get_timing_paths {args} {return [lindex $args [expr {[lsearch -exact $args -to]+1}]]}
proc get_property {key obj} {
 if {$key ne "NAME"} {set obj [lindex $obj 0]}
 switch -- $key {
  NAME {return $obj}
  PERIOD {return [dict get {clk125 8.0 clk150 6.667 clk500 2.0} $obj]}
  REQUIREMENT {set cell [file dirname $obj];return [dict get $::fixture_periods [file dirname $cell]]}
  ENDPOINT_PIN {return $obj}
  STARTPOINT_PIN {regsub {dest_graysync_ff_reg\[0\]} $obj src_gray_ff_reg p;return [string range $p 0 end-1]C}
  default {error "unknown synthetic property $key"}
 }
}
proc report_exceptions {args} {set f [open [lindex $args end] w];puts -nonewline $f $::fixture_valid;close $f}
proc report_bus_skew {args} {set f [open [lindex $args end] w];puts -nonewline $f [dict get $::fixture_bus [lindex $args 1]];close $f}
''')
with tempfile.TemporaryDirectory(prefix='ota_gray_mock_') as tmp:
 out=Path(tmp);(out/'synth_applied_constraints.xdc').write_text(''.join(xdcbus))
 t.call('ota_a06r1_gray_audit',out.as_posix())
 reviewed=m.audit_gray(out);assert len(reviewed)==24
 # With one unknown macro under a required FIFO, the actual discovery gate must
 # fail before it could accept the 24 familiar macros alone.
 t.setvar('fixture_cells',tuple(cells+[next(iter(m.FIFOS))+'/unreviewed/src_gray_ff_reg[0]']))
 try:t.call('ota_a06r1_gray_audit',out.as_posix())
 except tkinter.TclError as e:
  assert 'unexpected/missing Gray macros' in str(e),str(e)
 else:raise AssertionError('unexpected Gray macro accepted')
 for channel in t.splitlist(t.eval('chan names')):
  if channel not in ('stdin','stdout','stderr'):t.call('close',channel)
result={'status':'A06R1_GRAY_TCL_PYTHON_MOCK_PASS','scope':'full helper with synthetic Tcl APIs then strict Python auditor; not a Vivado run','positive_macros':24,'positive_bits':sum(int(g['width']) for g in reviewed),'unknown_actual_macro':'EXPECTED_REJECTION'}
p=root/'reports/OTA004/A06R1_GRAY_MOCK_TEST.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))

