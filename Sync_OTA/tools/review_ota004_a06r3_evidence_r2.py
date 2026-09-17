"""Fail-closed A06R3 report audit; callable parsers also support offline fixtures."""
from pathlib import Path
from collections import Counter
import csv,hashlib,json,re,sys

RULES={
 'CDC-1':('Critical','1-bit unknown CDC circuitry'),
 'CDC-3':('Info','1-bit synchronized with ASYNC_REG property'),
 'CDC-6':('Warning','Multi-bit synchronized with ASYNC_REG property'),
 'CDC-9':('Info','Asynchronous reset synchronized with ASYNC_REG property'),
 'CDC-26':('Warning','LUTRAM read/write potential collision'),
 'CDC-10':('Critical','Combinational logic detected before a synchronizer'),
 'CDC-13':('Critical','1-bit CDC path on a non-FD primitive'),
 'CDC-15':('Warning','Clock enable controlled CDC structure detected'),
}
RESET125={
 'context_reset/arststages_ff_reg[0]/PRE',
 'metadata/rd_reset/arststages_ff_reg[0]/PRE',
 'sfo/two_pass_transport/initial_context_cdc/read_reset_sync/syncstages_ff_reg[0]/D',
 'sfo/two_pass_transport/raw_samples_cdc/read_reset_sync/syncstages_ff_reg[0]/D',
 'sfo/two_pass_transport/reset_150/sync_reset/arststages_ff_reg[0]/PRE',
 'sfo/two_pass_transport/residual_config_cdc/write_reset_sync/syncstages_ff_reg[0]/D',
 'sfo/two_pass_transport/residual_data_cdc/write_reset_sync/syncstages_ff_reg[0]/D',
 'sfo/two_pass_transport/residual_request_cdc/read_reset_sync/syncstages_ff_reg[0]/D',
 'sfo/two_pass_transport/residual_result_cdc/read_reset_sync/syncstages_ff_reg[0]/D',
}
RESET150={
 'cfo/observation_backend/reset_fast_sync/arststages_ff_reg[0]/PRE',
 'cfo/reset500/arststages_ff_reg[0]/PRE',
 'cfo/window_samples/rd_reset/arststages_ff_reg[0]/PRE',
}
FIFOS={
 'metadata/fifo':('clk125','clk150',5),
 'completion/fifo':('clk150','clk125',5),
 'ddr/requests/fifo':('clk150','clk125',5),
 'ddr/responses/fifo':('clk125','clk150',5),
 'cfo/window_samples/fifo':('clk150','clk500',5),
 'cfo/observation_backend/observation_fifo':('clk500','clk150',4),
}
TYPES=('wr_pntr_cdc_inst','wr_pntr_cdc_dc_inst','rd_pntr_cdc_inst','rd_pntr_cdc_dc_inst')
PERIODS={'clk125':8.0,'clk150':6.667,'clk500':2.0}
def require(ok,message):
 if not ok:raise ValueError(message)
def near(a,b):return abs(float(a)-float(b))<=0.0011
def identity(text,command):
 for pattern in (r'(?m)^\| Tool Version\s*: Vivado v\.2021\.1\b',
                 r'(?m)^\| Design\s*: sync_ota_top\s*$',
                 r'(?m)^\| Device\s*: xcvu11p-flgb2104\s*$',
                 r'(?m)^\| Command\s*: '+re.escape(command)+r'\b'):
  require(re.search(pattern,text),('report identity missing',pattern))
 require(text.endswith('\n') and '\ufffd' not in text,'truncated/non-UTF8 report')
def parse_cdc(text):
 identity(text,'report_cdc')
 require(re.search(r'(?m)^\| Command\s*: report_cdc -details(?:\s|$)',text),'CDC details not requested')
 require(text.count('\nCDC Report\n')==1,'CDC report body absent/duplicated')
 require(re.search(r'(?m)^ID\s+Severity\s+Count\s+Description\s*$',text),'CDC summary header absent')
 counts={};details=[];blocks=[];clock=None;dest=None;rowno=0;header=False;lastrow=False
 for line in text.splitlines():
  s=line.strip()
  if not s:continue
  lastrow=False
  if s.startswith('CDC-'):
   match=re.fullmatch(r'(CDC-\d+)\s+(Critical|Warning|Info)\s+(\d+)\s+(.+)',s)
   require(match is not None,('malformed CDC summary',s))
   rule,severity,n,description=match.groups()
   require(clock is None and rule in RULES and rule not in counts,('unknown/duplicate/misplaced CDC rule',rule))
   require((severity,description)==RULES[rule] and int(n)>0,('CDC summary metadata',s))
   counts[rule]=int(n)
  elif s.startswith('Source Clock:'):
   if clock is not None:
    require(dest and header and rowno>0,'incomplete clock block')
    blocks.append((clock,dest,rowno))
   clock=s.removeprefix('Source Clock:').strip();dest=None;rowno=0;header=False
   require(clock in set(PERIODS)|{'input port clock'},'unknown source clock')
  elif s.startswith('Destination Clock:'):
   require(clock and dest is None,'misplaced/duplicate destination clock')
   dest=s.removeprefix('Destination Clock:').strip()
   require(dest in PERIODS and dest!=clock,'unknown destination clock')
  elif s.startswith('CDC Type:'):
   require(s=='CDC Type: No Common Primary Clock' and dest,'unexpected clock relationship')
  elif s.startswith('Row '):
   require(dest and not header and all(v in s for v in ('Severity','Depth','Exception','Source (From)','Destination (To)')),'bad CDC detail header')
   header=True
  elif re.match(r'^\d+\s',s):
   parts=re.split(r'\s{2,}',s)
   require(header and len(parts)==8,('malformed CDC detail',s))
   n,rule,severity,description,depth,exception,src,dst=parts
   require(n.isdigit() and int(n)==rowno+1,'missing/duplicate CDC row')
   require(rule in counts and (severity,description)==RULES.get(rule),'CDC detail rule disagrees with summary')
   require(depth.isdigit() and src and dst and exception in {'None','False Path','Max Delay'},('unknown CDC detail metadata',parts))
   rowno+=1;lastrow=True
   details.append(dict(rule=rule,source=src,destination=dst,source_clock=clock,destination_clock=dest,depth=int(depth),exception=exception))
  elif 'CDC-' in s:
   raise ValueError(('unparsed CDC line',s))
  elif clock is not None and not re.fullmatch(r'[-\s]+',s):
   raise ValueError(('unknown content in CDC detail block',s))
 require(clock and dest and header and rowno>0 and lastrow,'missing/truncated final CDC block')
 blocks.append((clock,dest,rowno))
 require(counts and sum(counts.values())==len(details),'empty/truncated CDC summary')
 actual=dict(Counter(r['rule'] for r in details))
 require(actual==counts,('CDC per-rule summary/detail counts differ',counts,actual))
 pairs={(a,b) for a,b,_ in blocks}
 expected={(a,b) for a in PERIODS for b in PERIODS if a!=b}|{('input port clock',b) for b in PERIODS}
 require(len(blocks)==9 and pairs==expected,('CDC clock block set incomplete',blocks))
 return dict(counts=counts,details=details,clock_blocks=blocks)
def accept_cdc(parsed):
 counts=parsed['counts']
 # Missing zero-count rules are valid only after successful complete parsing.
 require(counts.get('CDC-1',0)==0 and counts.get('CDC-13',0)==0,('unsafe CDC circuitry remains',counts))
 accepted=[]
 for row in parsed['details']:
  if row['rule']!='CDC-10':continue
  pair=(row['source_clock'],row['destination_clock'])
  ok=(row['source']=='algorithm_reset_guard/reset_active_reg/C' and row['destination'] in RESET125 and pair==('clk125','clk150'))
  ok|=(row['source']=='cfo/compute_cancel150_reg/C' and row['destination'] in RESET150 and pair==('clk150','clk500'))
  require(ok and row['depth']==4,('unreviewed CDC-10 exact endpoint pair',row))
  accepted.append(row)
 return accepted
def table(path,fields):
 with path.open(encoding='utf-8-sig',newline='') as f:
  reader=csv.DictReader(f,delimiter='\t')
  require(reader.fieldnames==fields,('bad TSV header',str(path),reader.fieldnames))
  rows=list(reader)
 require(rows and all(None not in r and None not in r.values() and all(v!='' for v in r.values()) for r in rows),('empty/malformed TSV',str(path)))
 return rows
def bus_report(text,gray,skew):
 # Vivado 2021.1 prints Tcl object expressions and wraps one row over 3 lines.
 # Parse text only: never evaluate report Tcl. Exact cell sets stay mandatory.
 identity(text,'report_bus_skew')
 command=re.search(r'(?m)^\| Command\s*:\s*(.+)$',text)
 require(command is not None,'bus-skew command absent')
 require(re.match(r'report_bus_skew -cells \[get_cells '+re.escape(gray)+r'\] -no_detailed_paths -file \S+$',command[1]),'bus-skew wrong instance scope/command')
 header=re.search(r'(?m)^Id\s+Position\s+From\s+To\s+Corner\s+Requirement\(ns\)\s+Actual\(ns\)\s+Slack\(ns\)\s*\n[- ]+\n',text)
 require(header is not None,'bus-skew native columns missing')
 expr=r'\[get_cells \[list(?: \{[^{}\r\n]+\})+\]\]'
 number=r'-?\d+(?:\.\d+)?'
 match=re.fullmatch(r'\s*(\d+)\s+(\d+)\s+('+expr+r')\s+('+expr+r')\s+(Slow|Fast)\s+('+number+r')\s+('+number+r')\s+('+number+r')\s*',text[header.end():])
 require(match is not None,'unparsed/incomplete/extra bus-skew native row')
 ident,position,src_expr,dst_expr,corner,requirement,actual,slack=match.groups()
 fifo,kind=gray.split('/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.')
 require(fifo in FIFOS and kind in TYPES,'bus-skew unknown macro')
 width=FIFOS[fifo][2]+int('_dc_inst' in kind)
 src=re.findall(r'\{([^{}]+)\}',src_expr);dst=re.findall(r'\{([^{}]+)\}',dst_expr)
 require(len(src)==len(set(src))==width and set(src)=={gray+'/src_gray_ff_reg['+str(i)+']' for i in range(width)},'bus-skew exact source cell set differs')
 require(len(dst)==len(set(dst))==width and set(dst)=={gray+'/dest_graysync_ff_reg[0]['+str(i)+']' for i in range(width)},'bus-skew exact destination cell set differs')
 require(int(ident)==1 and int(position)>0,'unexpected bus-skew row identity')
 require(near(requirement,skew),'active bus-skew requirement differs from vendor period rule')
 require(float(actual)>=0 and near(float(requirement)-float(actual),slack),'inconsistent bus-skew numeric fields')
 return [dict(id=ident,position=position,source_cells=src,destination_cells=dst,corner=corner,requirement=requirement,actual=actual,slack=slack)]

def audit_gray(out):
 directory=out/'gray_constraints'
 require((directory/'completed.txt').read_text().strip()=='OTA004_A06R3_GRAY_EXPORT_COMPLETE groups=24','Gray export incomplete')
 groups=table(directory/'groups.tsv',['id','fifo','gray','source_clock','destination_clock','source_period','destination_period','width'])
 endpoints=table(directory/'endpoints.tsv',['id','role','cell'])
 constraints=table(directory/'constraints.tsv',['id','origin','kind','value','datapath_only','from','to'])
 timing=table(directory/'effective_timing.tsv',['id','destination_cell','startpoint_pin','endpoint_pin','requirement'])
 require(len(groups)==24 and {r['id'] for r in groups}=={str(i) for i in range(1,25)},'missing/duplicate Gray macro')
 expect={f+'/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.'+t for f in FIFOS for t in TYPES}
 require({r['gray'] for r in groups}==expect,'Gray macro identity mismatch')
 all_ids={r['id'] for r in groups}
 for rows in (endpoints,constraints,timing):require({r['id'] for r in rows}==all_ids,'unrecognized/missing Gray receipt group')
 objects=table(directory/'query_objects.tsv',['id','kind','scope','role','query_kind','object_name','cell_name','ref_pin','primitive'])
 require({r['id'] for r in objects}==all_ids,'raw endpoint evidence missing/unknown group')
 result=[]
 for g in groups:
  ident=g['id'];gray=g['gray'];fifo=g['fifo'];typ=gray.rsplit('.',1)[-1]
  sc,dc,width=FIFOS[fifo]
  if typ.startswith('rd_'):sc,dc=dc,sc
  if '_dc_inst' in typ:width+=1
  require((g['source_clock'],g['destination_clock'],int(g['width']))==(sc,dc,width),'actual Gray clock/width mismatch')
  require(near(g['source_period'],PERIODS[sc]) and near(g['destination_period'],PERIODS[dc]),'actual clock period mismatch')
  e=[r for r in endpoints if r['id']==ident]
  src={gray+f'/src_gray_ff_reg[{bit}]' for bit in range(width)}
  dst={gray+f'/dest_graysync_ff_reg[0][{bit}]' for bit in range(width)}
  require(len(e)==2*width and {r['cell'] for r in e if r['role']=='SRC'}==src and {r['cell'] for r in e if r['role']=='DST'}==dst,'Gray endpoint bit coverage mismatch')
  c=[r for r in constraints if r['id']==ident]
  require(len(c)==2 and {r['kind'] for r in c}=={'set_max_delay','set_bus_skew'},'Gray constraint missing/duplicate')
  for r in c:
   require(set(r['from'].split('|'))==src and set(r['to'].split('|'))==dst,'Gray constraints do not cover exact instance endpoint sets')
   ismax=r['kind']=='set_max_delay'
   require(r['origin']==('VALID_EXCEPTIONS' if ismax else 'APPLIED_XDC'),'wrong constraint provenance')
   require(r['datapath_only']==('1' if ismax else '0'),'wrong datapath_only')
   require(near(r['value'],PERIODS[sc] if ismax else min(PERIODS[sc],PERIODS[dc])),'wrong vendor constraint value')
  for kind in ('set_max_delay','set_bus_skew'):
   for role,expected_cells in [('FROM',src),('TO',dst)]:
    obj=[r for r in objects if (r['id'],r['kind'],r['role'])==(ident,kind,role)]
    require(len(obj)==width and {r['cell_name'] for r in obj}==expected_cells,'original object/owning cell coverage mismatch')
    for r in obj:
     require(r['primitive'].startswith('FD'),'endpoint primitive not a verified flip-flop')
     if kind=='set_max_delay':
      pin='C' if role=='FROM' else 'D'
      require(r['scope']=='<root>' and r['query_kind']=='get_pins' and r['ref_pin']==pin and r['object_name']==r['cell_name']+'/'+pin,'valid exception did not preserve exact verified C/D pin')
     else:
      require(r['scope']==gray and r['query_kind']=='get_cells' and r['ref_pin']=='-' and r['object_name']==r['cell_name'],'bus-skew scope or original cell mismatch')
  require(len([r for r in objects if r['id']==ident])==4*width,'extra unrecognized raw endpoint rows')
  paths=[r for r in timing if r['id']==ident]
  require(len(paths)==width and {r['destination_cell'] for r in paths}==dst,'effective timing path bit coverage missing')
  for r in paths:
   require(r['endpoint_pin']==r['destination_cell']+'/D' and r['startpoint_pin'].rsplit('/',1)[0] in src,'effective timing path endpoints mismatched')
   require(near(r['requirement'],PERIODS[sc]),'max-delay overridden or wrong active timing requirement')
  active=bus_report((directory/f'bus_skew_{ident}.txt').read_text(),gray,min(PERIODS[sc],PERIODS[dc]))
  result.append(dict(**g,verified_bits=width,active_bus_skew=active))
 return result
def audit_ips(out):
 records={}
 for phase in ('before_stage','before_core_decision','after_core'):
  rows=table(out/f'reused_ip_runs_{phase}.tsv',['ip','run','status','needs_refresh','ip_locked'])
  require(len(rows)==45 and len({r['ip'] for r in rows})==45,'45 unique reused IPs required')
  for r in rows:
   require(r['run']==r['ip']+'_synth_1' and 'synth_design Complete' in r['status'] and r['needs_refresh'].lower() in ('0','false') and r['ip_locked'].lower() in ('0','false'),'stale/incomplete/locked reused IP')
  records[phase]=rows
 return records
def canonical_cdc(parsed):
 return sorted(parsed['details'],key=lambda row:tuple(str(row[k]) for k in sorted(row)))
def precheck(root,out):
 lock_path=root/'docs/jobs/OTA004_A06R3_scientific_lock.json'
 lock=json.loads(lock_path.read_text(encoding='utf-8-sig'))
 for row in lock['files']:
  p=root/row['path']
  require(p.is_file() and p.stat().st_size==row['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],('frozen recovery input changed',row['path']))
 for row in lock['tools']:
  p=Path(row['path'])
  require(p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'],('installed tool identity changed',row['path']))
 # The checkpoint content identity is independent of a runtime design label.
 import zipfile,xml.etree.ElementTree as ET
 with zipfile.ZipFile(root/lock['dcp']) as archive:
  meta=ET.fromstring(archive.read('dcp.xml'))
  require(meta.find('Top').get('Name')=='sync_ota_top','DCP XML top mismatch')
  require(meta.find('Part').get('Name')=='xcvu11p-flgb2104-2-e','DCP XML part mismatch')
  require(meta.find('BUILD_NUMBER').get('Name')=='3247384','DCP tool build mismatch')
  require(meta.find('OutOfContext').get('Name')=='1','DCP not expected OOC state')
 record=dict(status='A06R3_RECOVERY_PRECHECK_PASS',files=len(lock['files']),manifest_sha256=hashlib.sha256(lock_path.read_bytes()).hexdigest(),dcp_sha256=lock['dcp_sha256'],scope='report-only; existing DCP opened without source rebuild')
 receipt=out/'precheck_verified.json'
 if receipt.exists():require(json.loads(receipt.read_text())==record,'precheck receipt identity changed')
 else:receipt.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
 return record
def audit_timing_native(out):
 clock_text=(out/'synth_clocks.txt').read_text();identity(clock_text,'report_clocks')
 for clock,period in PERIODS.items():
  values=re.findall(r'(?m)^'+re.escape(clock)+r'\s+([0-9.]+)\s',clock_text)
  require(len(values)==1 and near(values[0],period),('clock period',clock))
 identity((out/'synth_timing.txt').read_text(),'report_timing_summary')
 queries=table(out/'timing_coverage/queries.tsv',['query','clock','target_scope','cap','returned'])
 paths=table(out/'timing_coverage/paths.tsv',['query','clock','target_scope','rank','startpoint_pin','endpoint_pin','slack_ns','requirement_ns'])
 specs=[('clk125','all',4),('clk150','all',32),('clk500','all',32),('clk150','cfo/observation_backend',8),('clk150','sfo/two_pass_transport/output_buffer',8),('clk150','cfo',8),('clk150','sfo',8),('clk500','cfo/observation_front',8),('clk500','sfo/initial_estimator',8)]
 require(len(queries)==9,'nine timing queries required');verified=[]
 for i,(q,(clock,scope,cap)) in enumerate(zip(queries,specs),1):
  require((q['query'],q['clock'],q['target_scope'],int(q['cap']))==(str(i),clock,scope,cap),'timing query changed')
  subset=[p for p in paths if p['query']==str(i)]
  require(0<len(subset)==int(q['returned'])<=cap,'timing count mismatch')
  text=(out/f'timing_coverage/paths_{i}.txt').read_text();identity(text,'report_timing')
  blocks=re.split(r'(?m)(?=^Slack \()',text)[1:]
  require(len(blocks)==len(subset),'native path block count differs from TSV')
  for rank,(p,b) in enumerate(zip(subset,blocks),1):
   require((p['clock'],p['target_scope'],int(p['rank']))==(clock,scope,rank),'timing rank/scope mismatch')
   source=re.search(r'(?m)^  Source:\s+(\S+)',b);dest=re.search(r'(?m)^  Destination:\s+(\S+)',b)
   slack=re.search(r'^Slack \((?:MET|VIOLATED)\)\s*:\s+(-?\d+(?:\.\d+)?)ns',b)
   req=re.search(r'(?m)^  Requirement:\s+(-?\d+(?:\.\d+)?)ns',b)
   clocks=re.findall(r'cell \S+ clocked by (\S+)\s',b)
   require(all((source,dest,slack,req)) and len(clocks)==2,'incomplete native timing path')
   require(source[1]==p['startpoint_pin'] and dest[1]==p['endpoint_pin'],'native/TSV endpoint mismatch')
   require(all(re.fullmatch(r'-?\d+(?:\.\d+)?',p[k]) for k in ('slack_ns','requirement_ns')),'invalid TSV numeric evidence')
   require(near(slack[1],p['slack_ns']) and near(req[1],p['requirement_ns']),'native/TSV numeric mismatch')
   require(clocks[0]==clock,'timing source clock mismatch')
   require((scope!='all' or clocks[1]==clock) and (scope=='all' or dest[1].startswith(scope+'/')),'timing destination scope mismatch')
   require('Logic Levels:' in b and 'Data Path Delay:' in b,'native timing detail incomplete')
   footer={k:re.findall(r'(?m)^\s+'+k+r'\s+(-?\d+(?:\.\d+)?)\s*$',b) for k in ('required time','arrival time','slack')}
   require(all(len(v)==1 for v in footer.values()),'native timing footer missing/duplicate')
   require(near(float(footer['required time'][0])+float(footer['arrival time'][0]),footer['slack'][0]) and near(footer['slack'][0],p['slack_ns']),'timing footer arithmetic/TSV mismatch')
   verified.append(dict(**p,actual_source_clock=clocks[0],actual_destination_clock=clocks[1]))
 require(len(paths)==len(verified)<=116,'timing total mismatch')
 require((out/'timing_coverage/completed.txt').read_text().strip()=='OTA004_A06R3_BOUNDED_TIMING_EXPORT_COMPLETE queries=9 max_paths_total=116','timing completion marker missing')
 return verified

def review(out):
 root=Path('D:/008_MA_Dev/Sync_OTA');checks={}
 def check(name,func):
  try:checks[name]=dict(status='PASS',evidence=func())
  except Exception as e:checks[name]=dict(status='FAIL',error=str(e))
 check('scientific_input_and_tools',lambda:precheck(root,out))
 def stages():
  rows=re.findall(r'(?m)^STAGE (\S+) CODE (\d+) MESSAGE ',(out/'collection_stages.tcldata').read_text())
  expected=['open_checkpoint','scientific_identity','clocks','cdc','timing_summary','applied_xdc','timing_paths','gray','close_design']
  require(rows==[(s,'0') for s in expected],'native stage failed/missing/duplicate')
  require((out/'collection_result.txt').read_text().strip()=='FAILED_STAGES {} NATIVE_COLLECTION_FINISHED 1 QUALIFICATION NOT_DECIDED','native completion mismatch')
  require((out/'report_identity.txt').read_text().strip()=='TOP=sync_ota_top PART=xcvu11p-flgb2104-2-e BLACKBOX=0 MODE=OPEN_EXISTING_A06R1_DCP REPORT_ONLY=1','scientific identity record')
  return rows
 check('native_stages_and_identity',stages)
 def cdc():
  parsed=parse_cdc((out/'synth_cdc.txt').read_text());baseline=parse_cdc((root/'work/OTA004/synth_a06r1/synth_cdc.txt').read_text())
  require(parsed['counts']==baseline['counts'] and canonical_cdc(parsed)==canonical_cdc(baseline),'CDC differs from frozen baseline')
  accepted=accept_cdc(parsed)
  require((out/'cdc_report_completed.txt').read_text().strip()=='Vivado2021.1 sync_ota_top report_cdc -details completed','CDC marker')
  warnings=[r for r in parsed['details'] if RULES[r['rule']][0]=='Warning']
  return dict(counts=parsed['counts'],details=len(parsed['details']),blocks=len(parsed['clock_blocks']),accepted_reset_pairs=accepted,open_warnings=warnings)
 check('cdc_unchanged_and_control_gates',cdc)
 def gray():
  xdc=(out/'synth_applied_constraints.xdc').read_text()
  require(not re.search(r'(?m)^set_clock_groups\s.*-asynchronous',xdc),'blanket async groups forbidden')
  return audit_gray(out)
 check('gray_effective_constraints',gray)
 check('bounded_timing_native_crosscheck',lambda:audit_timing_native(out))
 check('unchanged_45_ip_history',lambda:audit_ips(root/'work/OTA004/synth_a06r1'))
 def tree():
  rows=[json.loads(line) for line in (out/'process_tree.jsonl').read_text(encoding='utf-8-sig').splitlines() if line.strip()]
  summary=json.loads((out/'process_summary.json').read_text(encoding='utf-8-sig'))
  actual={(p['pid'],p['creation_utc']) for row in rows for p in row['processes']}
  require(actual=={(p['pid'],p['creation_utc']) for p in summary['seen_identities']},'tree identity union mismatch')
  require(len(rows)>=3 and all(not row['processes'] for row in rows[-3:]),'last3 not empty')
  require(summary['stable_empty_scans']>=3 and not summary['timed_out'],'tree closure/timeout')
  return dict(records=len(rows),identities=len(actual),last_three_empty=True,start=summary['start_utc'],end=summary['end_utc'])
 check('process_tree_closed',tree)
 native=(out/'native.log').read_text();old=(root/'docs/provenance/OTA004_A06R2_core_runme.log').read_text()
 check('prior_core_clean',lambda:require('Synthesis finished with 0 errors, 0 critical warnings' in old and not re.search(r'(?mi)^\s*(?:error|fatal|critical warning)\s*:',old),'prior synthesis not clean'))
 errors=re.findall(r'(?mi)^\s*(?:error|fatal)\s*:.*$',native)
 critical=re.findall(r'(?mi)^\s*critical warning\s*:.*$',native)
 check('native_error_free',lambda:require(not errors,errors))
 # Original all-critical gate is preserved as FAIL; it is never rewritten PASS.
 check('original_zero_critical_gate',lambda:require(not critical,critical))
 messages=[dict(line=i,level=m[1],id=m[2],text=line) for i,line in enumerate(native.splitlines(),1) if (m:=re.match(r'^(CRITICAL WARNING|WARNING|ERROR|FATAL): \[([^]]+)\]',line))]
 scientific=[name for name in checks if name!='original_zero_critical_gate']
 valid=all(checks[name]['status']=='PASS' for name in scientific)
 artifacts=[dict(path=str(p.relative_to(out)),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(out.rglob('*')) if p.is_file()]
 return dict(status='EVIDENCE_VERIFIED_WITH_OPEN_NATIVE_WARNINGS' if valid else 'EVIDENCE_INCOMPLETE_OR_FAILED',original_strict_run='FAILED_PRESERVED',overall_job_pass=False,report_evidence_complete=valid,checks=checks,native_messages=messages,artifacts=artifacts,warning_waivers_added=0,physical_timing='NOT_QUALIFIED',continuous_throughput='NOT_VERIFIED',NI_board='NOT_RUN')

if __name__=='__main__':
 require(len(sys.argv)==3,'usage: evidence_attempt NEW_RESULT_JSON')
 source=Path(sys.argv[1]).resolve();destination=Path(sys.argv[2]).resolve()
 require(source==Path('D:/008_MA_Dev/Sync_OTA/work/OTA004/report_a06r3'),'wrong current evidence attempt')
 result=review(source)
 with destination.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2);f.write('\n')
 print(json.dumps({'status':result['status'],'checks':{k:v['status'] for k,v in result['checks'].items()},'overall_job_pass':False}))
