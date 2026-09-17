from pathlib import Path
from collections import Counter
import copy, csv, hashlib, importlib.util, json, tempfile, tkinter
ROOT=Path('D:/008_MA_Dev/Sync_OTA')
spec=importlib.util.spec_from_file_location('review',ROOT/'tools/verify_ota004_a06r1_synth_result.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
checks=[]
def passed(name,fn):
 fn();checks.append({'name':name,'result':'PASS'})
def rejected(name,fn):
 try:fn()
 except (ValueError,AssertionError,FileNotFoundError,tkinter.TclError):checks.append({'name':name,'result':'EXPECTED_REJECTION'});return
 raise AssertionError('unexpected acceptance: '+name)
actual=(ROOT/'work/OTA004/synth_a05/synth_cdc.txt').read_text()
parsed=m.parse_cdc(actual)
assert len(parsed['details'])==2444 and sum(parsed['counts'].values())==2444
checks.append({'name':'A05_actual_report_2444_rows_six_blocks_closed','result':'PASS'})
rejected('A05_unsafe_CDC_NOT_accepted',lambda:m.accept_cdc(parsed))
# Build an explicitly synthetic complete report using the exact captured layout.
prefix=actual[:actual.index('\nCDC Report\n')]
summary={'CDC-3':6,'CDC-10':1}
def report(unknown=False):
 text=prefix+'\nCDC Report\n\nID  Severity  Count  Description\n'
 for key,n in summary.items():
  severity,description=m.RULES[key]
  text+=f'{key}  {severity}  {n}  {description}\n'
 for sc in m.PERIODS:
  for dc in m.PERIODS:
   if sc==dc:continue
   text+=f'\nSource Clock: {sc}\nDestination Clock: {dc}\nCDC Type: No Common Primary Clock\n\nRow  ID  Severity  Description  Depth  Exception  Source (From)  Destination (To)\n---  ---\n'
   text+='1  CDC-3  Info  1-bit synchronized with ASYNC_REG property  2  None  source/C  dest/D\n'
   if (sc,dc)==('clk125','clk150'):
    endpoint='context_reset/arststages_ff_reg[0]/PRE' if not unknown else 'unreviewed_reset/arststages_ff_reg[0]/PRE'
    text+=f'2  CDC-10  Critical  Combinational logic detected before a synchronizer  4  None  algorithm_reset_guard/reset_active_reg/C  {endpoint}\n'
 return text
valid=report()
passed('synthetic_complete_CDC_and_exact_reset_pair',lambda:m.accept_cdc(m.parse_cdc(valid)))
for name,text in [('empty',''),('truncated',valid.rsplit('\n',2)[0]+'\n'),('wrong_identity',valid.replace('Design            : sync_ota_top','Design            : other')),('summary_mismatch',valid.replace('CDC-3  Info  6','CDC-3  Info  7')),('unknown_rule',valid.replace('CDC-3','CDC-99')),('missing_block',valid[:valid.rfind('\nSource Clock:')]),('missing_row',valid.replace('2  CDC-10','3  CDC-10')),('bad_UTF8',valid+'\ufffd\n')]:
 rejected('CDC_'+name,lambda text=text:m.parse_cdc(text))
rejected('CDC10_unreviewed_reset_substring',lambda:m.accept_cdc(m.parse_cdc(report(True))))
rejected('CDC10_prefix_only_source',lambda:m.accept_cdc(m.parse_cdc(valid.replace('reset_active_reg/C','reset_active_reg_extra/C'))))
# Synthetic whole Gray receipt tests validate the downstream auditor, not native
# Vivado behavior; native report formatting remains subject to actual execution.
def tsv(path,fields,rows):
 with path.open('w',encoding='utf-8',newline='') as f:
  w=csv.DictWriter(f,fieldnames=fields,delimiter='\t');w.writeheader();w.writerows(rows)
with tempfile.TemporaryDirectory(prefix='ota_a06r1_static_') as tmp:
 out=Path(tmp);d=out/'gray_constraints';d.mkdir()
 gs=[];es=[];cs=[];ps=[];ident=0
 for fifo,(write,read,width0) in m.FIFOS.items():
  for typ in m.TYPES:
   ident+=1;k=str(ident);sc,dc=(read,write) if typ.startswith('rd_') else (write,read)
   width=width0+('_dc_inst' in typ)
   gray=fifo+'/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.'+typ
   gs.append(dict(id=k,fifo=fifo,gray=gray,source_clock=sc,destination_clock=dc,source_period=m.PERIODS[sc],destination_period=m.PERIODS[dc],width=width))
   src=[gray+f'/src_gray_ff_reg[{i}]' for i in range(width)];dst=[gray+f'/dest_graysync_ff_reg[0][{i}]' for i in range(width)]
   for role,cells in [('SRC',src),('DST',dst)]:
    es.extend(dict(id=k,role=role,cell=c) for c in cells)
   for kind,origin,value,datapath in [('set_max_delay','VALID_EXCEPTIONS',m.PERIODS[sc],1),('set_bus_skew','APPLIED_XDC',min(m.PERIODS[sc],m.PERIODS[dc]),0)]:
    cs.append(dict(id=k,origin=origin,kind=kind,value=value,datapath_only=datapath,**{'from':'|'.join(src),'to':'|'.join(dst)}))
   ps.extend(dict(id=k,destination_cell=b,startpoint_pin=a+'/C',endpoint_pin=b+'/D',requirement=m.PERIODS[sc]) for a,b in zip(src,dst))
   bus=prefix.replace('report_cdc -details -file D:/008_MA_Dev/Sync_OTA/work/OTA004/synth_a05/synth_cdc.txt',f'report_bus_skew -cells {gray} -no_detailed_paths -file bus_skew_{k}.txt')
   bus+='\nBus Skew Report\nId  From  To  Corner  Requirement  Actual  Slack\n'
   bus+=f'1  {gray}/src_gray_ff_reg*  {gray}/dest_graysync_ff_reg[0]*  Slow  {min(m.PERIODS[sc],m.PERIODS[dc]):.3f}  0.100  1.000\n'
   (d/f'bus_skew_{k}.txt').write_text(bus)
 def save():
  for file,rows in [('groups',gs),('endpoints',es),('constraints',cs),('effective_timing',ps)]:
   tsv(d/(file+'.tsv'),list(rows[0]),rows)
 save();(d/'completed.txt').write_text('OTA004_A06R1_GRAY_EXPORT_COMPLETE groups=24\n')
 passed('synthetic_24_Gray_macros_all_bits_both_directions',lambda:m.audit_gray(out))
 old=cs.pop();save();rejected('Gray_missing_bus_skew',lambda:m.audit_gray(out));cs.append(old)
 old=cs[0]['from'];cs[0]['from']='unrelated_sfo/src_gray_ff_reg[0]';save();rejected('Gray_unrelated_FIFO_constraint',lambda:m.audit_gray(out));cs[0]['from']=old
 old=ps[0]['requirement'];ps[0]['requirement']=1000;save();rejected('Gray_overridden_max_delay',lambda:m.audit_gray(out));ps[0]['requirement']=old
 old=ps.pop();save();rejected('Gray_missing_effective_bit_path',lambda:m.audit_gray(out));ps.append(old);save()
 original=(d/'bus_skew_1.txt').read_text();(d/'bus_skew_1.txt').write_text('')
 rejected('Gray_empty_native_bus_report',lambda:m.audit_gray(out))
 (d/'bus_skew_1.txt').write_text(original.replace('  6.667  ','  9.000  '))
 rejected('Gray_wrong_active_skew_value',lambda:m.audit_gray(out))
 (d/'bus_skew_1.txt').write_text(original)
# Tcl parsing/capture and IP gate negative checks use a Tcl interpreter with
# synthetic APIs; no Vivado process or native experiment is launched.
t=tkinter.Tcl()
for rel in ('tools/vivado/run_ota004_a06r1.tcl','tools/vivado/audit_ota004_a06r1_gray.tcl'):
 assert t.call('info','complete',(ROOT/rel).read_text())==1
t.eval((ROOT/'tools/vivado/audit_ota004_a06r1_gray.tcl').read_text())
t.eval('proc get_cells {args} {return [lindex $args end]}; proc get_property {key objects} {if {$key ne "NAME"} {error unsupported};return $objects}')
with tempfile.TemporaryDirectory(prefix='ota_gray_capture_') as tmp:
 p=Path(tmp)/'capture.xdc'
 p.write_text('set_max_delay -from [get_cells {g/src_gray_ff_reg[0] g/src_gray_ff_reg[1]}] -to [get_cells {g/dest_graysync_ff_reg[0][0] g/dest_graysync_ff_reg[0][1]}] 8.000 -datapath_only\n')
 t.call('ota_gray::read_export',p.as_posix(),'VALID_EXCEPTIONS','set_max_delay')
 assert int(t.eval('llength $ota_gray::captured'))==1
 checks.append({'name':'safe_Tcl_capture_expanded_exact_endpoints','result':'PASS'})
 p.write_text('set_max_delay -from [exec bad] -to [get_cells g/src_gray_ff_reg*] 8.0\n')
 rejected('safe_Tcl_capture_rejects_exec',lambda:t.call('ota_gray::read_export',p.as_posix(),'VALID_EXCEPTIONS','set_max_delay'))
 t.eval(Path(__file__).with_name('ip_gate.txt').read_text())
 t.eval('proc get_ips {} {set x {};for {set n 0} {$n<45} {incr n} {lappend x ip$n};return $x}; proc get_runs {args} {return [lindex $args end]}; proc list_property {obj} {return NEEDS_REFRESH}')
 t.eval('proc get_property {key obj} {switch -- $key {NAME {return $obj} IS_LOCKED {return 0} STATUS {return "synth_design Complete!"} NEEDS_REFRESH {return $::refresh} default {error unsupported}}}')
 t.setvar('out',tmp);t.setvar('refresh','false');t.call('audit_reused_ips','static_valid')
 checks.append({'name':'45_IP_complete_refresh_false','result':'PASS'})
 for value in ('true','1','','UNKNOWN'):
  t.setvar('refresh',value)
  rejected('IP_refresh_'+repr(value),lambda:t.call('audit_reused_ips','static_rejected'))
result=dict(status='A06R1_OFFLINE_AUDIT_TESTS_PASS',scope='Python/Tcl synthetic fixtures and existing A05 report only; no native experiment',checks=checks)
p=ROOT/'reports/OTA004/A06R1_AUDITOR_STATIC_TESTS.json'
assert not p.exists()
p.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':result['status'],'checks':len(checks)}))

