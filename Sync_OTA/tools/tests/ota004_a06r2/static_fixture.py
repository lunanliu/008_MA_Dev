from pathlib import Path
import hashlib,importlib.util,json,re,tempfile,tkinter
R=Path('D:/008_MA_Dev/Sync_OTA');OLD=R/'work/OTA004/synth_a06r1'
spec=importlib.util.spec_from_file_location('r2',R/'tools/verify_ota004_a06r2_report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
valid=(OLD/'gray_constraints/valid_exceptions.xdc').read_text()
applied=(OLD/'synth_applied_constraints.xdc').read_text()
pin_names=set(re.findall(r'get_pins \{([^}]+/(?:src_gray_ff_reg\[\d+\]/C|dest_graysync_ff_reg\[0\]\[\d+\]/D))\}',valid))
assert pin_names
cells={p.rsplit('/',1)[0] for p in pin_names}
scopes=set(re.findall(r'^current_instance ([A-Za-z0-9_./\[\]-]+)$',applied,re.M))
assert len(scopes)>24
macros={p.rsplit('/',1)[0] for p in cells}
# Synthetic object APIs use the actual frozen export's complete name inventory.
# They do not establish that those objects exist in the DCP; native does that.
t=tkinter.Tcl();t.eval((R/'tools/vivado/audit_ota004_a06r2_gray.tcl').read_text())
clockmap={};source_period={}
for fifo,(wr,rd,w) in m.FIFOS.items():
 for typ in m.TYPES:
  gray=fifo+'/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.'+typ
  sc,dc=(rd,wr) if typ.startswith('rd_') else (wr,rd)
  source_period[gray]=m.PERIODS[sc]
  for cell in cells:
   if cell.startswith(gray+'/'):clockmap[cell]=sc if '/src_gray_ff_reg' in cell else dc
def one(value):
 values=t.splitlist(value)
 assert len(values)==1,value
 return values[0]
def query(pool,pattern):
 exp='^'+re.escape(pattern).replace(r'\*','.*')+'$'
 return tuple(sorted(n for n in pool if re.fullmatch(exp,n)))
def get_cells(*args):
 if args[0]=='-of_objects':return tuple(p.rsplit('/',1)[0] for p in t.splitlist(args[1]))
 if args[0]=='-hierarchical':return tuple(sorted(cells))
 return query(cells|scopes|macros,one(args[-1]))
def get_pins(*args):
 if args[0]=='-of_objects':
  port='C' if args[-1]=='REF_PIN_NAME == C' else 'D'
  return tuple(c+'/'+port for c in t.splitlist(args[1]))
 return query(pin_names,one(args[-1]))
def get_property(key,obj):
 names=t.splitlist(obj)
 if key=='NAME':return names[0] if len(names)==1 else tuple(names)
 name=one(obj)
 if key=='REF_PIN_NAME':return name.rsplit('/',1)[-1]
 if key=='IS_PRIMITIVE':return int(name in cells)
 if key=='REF_NAME':return 'FDRE' if name in cells else 'xpm_cdc_gray'
 if key=='PERIOD':return m.PERIODS[name]
 endpoint=name.removeprefix('PATH:')
 if key=='ENDPOINT_PIN':return endpoint
 if key=='STARTPOINT_PIN':return endpoint.replace('dest_graysync_ff_reg[0]','src_gray_ff_reg').removesuffix('/D')+'/C'
 if key=='REQUIREMENT':return source_period[endpoint.rsplit('/',2)[0]]
 raise ValueError((key,obj))
def get_clocks(*args):return tuple(sorted({clockmap[p.rsplit('/',1)[0]] for p in t.splitlist(args[-1])}))
def get_paths(*args):return ('PATH:'+one(args[args.index('-to')+1]),)
def report_exceptions(*args):Path(args[-1]).write_text(valid)
def report_bus(*args):
 gray=one(args[1]);sp=source_period[gray]
 # Find the actual destination clock, preserving each group direction.
 dc=next(clockmap[c] for c in cells if c.startswith(gray+'/dest_graysync_ff_reg'))
 skew=min(sp,m.PERIODS[dc])
 text='| Tool Version : Vivado v.2021.1\n| Design : sync_ota_top\n| Device : xcvu11p-flgb2104\n'
 text+=f'| Command : report_bus_skew -cells {gray} -no_detailed_paths\n\nId  From  To  Corner  Requirement  Actual  Slack\n1  {gray}/src_gray_ff_reg*  {gray}/dest_graysync_ff_reg[0]*  Slow  {skew}  0.100  {skew-0.1:.3f}\n'
 Path(args[-1]).write_text(text)
for name,fn in [('get_cells',get_cells),('get_pins',get_pins),('get_property',get_property),('get_clocks',get_clocks),('get_timing_paths',get_paths),('report_exceptions',report_exceptions),('report_bus_skew',report_bus)]:
 t.createcommand(name,fn)
checks=[]
def reject(name,fn):
 try:fn()
 except (ValueError,tkinter.TclError,AssertionError):checks.append(dict(name=name,result='EXPECTED_REJECTION'));return
 raise AssertionError('unexpected acceptance '+name)
with tempfile.TemporaryDirectory(prefix='ota_a06r2_realexports_') as tmp:
 out=Path(tmp);(out/'synth_applied_constraints.xdc').write_text(applied)
 t.call('ota_a06r2_gray_audit',out.as_posix())
 rows=m.audit_gray(out)
 assert len(rows)==24 and sum(int(x['width']) for x in rows)==128
 checks.append(dict(name='actual_scoped_XDC_and_C_D_pin_export_to_24_macro_128_bit_mock_audit',result='PASS'))
 raw=m.table(out/'gray_constraints/query_objects.tsv',['id','kind','scope','role','query_kind','object_name','cell_name','ref_pin','primitive'])
 assert len(raw)==512
 checks.append(dict(name='preserves_256_original_C_D_pins_and_256_scoped_cells',result='PASS'))
 # Fault-inject only copies in temporary fixture directories.
 for name,text,origin,kinds in [
  ('lost_scope',applied.replace('current_instance ddr/requests/fifo/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.rd_pntr_cdc_inst','current_instance'),'APPLIED_XDC','set_bus_skew'),
  ('unresolved_scope',applied.replace('current_instance ddr/requests/fifo/','current_instance missing/requests/fifo/'),'APPLIED_XDC','set_bus_skew'),
  ('wrong_source_pin',valid.replace('src_gray_ff_reg[0]/C','src_gray_ff_reg[0]/Q'),'VALID_EXCEPTIONS','set_max_delay'),
  ('unknown_command_substitution','set_bus_skew -from [exec bad] -to [get_cells src_gray_ff_reg*] 2.0\n','APPLIED_XDC','set_bus_skew'),
  ('truncated_scope','current_instance {\n','APPLIED_XDC','set_bus_skew'),
  ('unknown_scope_switch','current_instance -unreviewed x\n','APPLIED_XDC','set_bus_skew')]:
  p=out/'bad.xdc';p.write_text(text)
  reject(name,lambda p=p,origin=origin,kinds=kinds:t.call('ota_gray::read_export',p.as_posix(),origin,kinds))
 # Raw pin evidence must independently match its owning cell and role.
 p=out/'gray_constraints/query_objects.tsv';text=p.read_text()
 p.write_text(text.replace('/C\t','/Q\t',1))
 reject('auditor_rejects_tampered_original_pin',lambda:m.audit_gray(out));p.write_text(text)
 cdc=(OLD/'synth_cdc.txt').read_text();parsed=m.parse_cdc(cdc)
 assert len(parsed['details'])==299 and len(m.accept_cdc(parsed))==12
 checks.append(dict(name='real_CDC_299_rows_9_blocks_12_exact_resets',result='PASS'))
 reject('empty_CDC',lambda:m.parse_cdc(''))
 reject('truncated_CDC',lambda:m.parse_cdc(cdc.rsplit('\n',3)[0]+'\n'))
 reject('unknown_CDC_rule',lambda:m.parse_cdc(cdc.replace('CDC-26','CDC-99')))
 reject('missing_input_clock_block',lambda:m.parse_cdc(cdc[:cdc.rfind('Source Clock: input port clock')]))
 reject('bad_summary_count',lambda:m.parse_cdc(cdc.replace('Info         94','Info         95')))
 for channel in t.splitlist(t.eval('chan names')):
  if channel not in ('stdin','stdout','stderr'):t.call('close',channel)
result=dict(status='A06R2_REAL_EXPORT_STATIC_FIXTURES_PASS',scope='actual frozen XDC/valid_exceptions parsed using synthetic object APIs; no native tool started',checks=checks,gray_macros=24,destination_bits=128,raw_objects=512,native_object_existence='NOT_YET_VERIFIED',native_bus_report_format='NOT_YET_OBSERVED',source_files=[dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in (OLD/'gray_constraints/valid_exceptions.xdc',OLD/'synth_applied_constraints.xdc',OLD/'synth_cdc.txt')])
p=R/'reports/OTA004/A06R2_STATIC_FIXTURES.json';assert not p.exists();p.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status=result['status'],checks=len(checks),gray_macros=24,raw_objects=512)))

