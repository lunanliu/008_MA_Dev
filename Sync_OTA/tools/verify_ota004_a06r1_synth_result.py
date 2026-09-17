"""Fail-closed A06R1 report audit; callable parsers also support offline fixtures."""
from pathlib import Path
from collections import Counter
import csv,hashlib,json,re,sys

RULES={
 'CDC-1':('Critical','1-bit unknown CDC circuitry'),
 'CDC-3':('Info','1-bit synchronized with ASYNC_REG property'),
 'CDC-6':('Warning','Multi-bit synchronized with ASYNC_REG property'),
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
   require(clock in PERIODS,'unknown source clock')
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
   require(depth.isdigit() and src and dst and exception=='None',('unknown CDC detail metadata',parts))
   rowno+=1;lastrow=True
   details.append(dict(rule=rule,source=src,destination=dst,source_clock=clock,destination_clock=dest,depth=int(depth)))
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
 expected={(a,b) for a in PERIODS for b in PERIODS if a!=b}
 require(len(blocks)==6 and pairs==expected,('CDC clock block set incomplete',blocks))
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
 identity(text,'report_bus_skew')
 require(re.search(r'(?m)^\| Command\s*: report_bus_skew .*?-cells\s+\{?'+re.escape(gray)+r'\}?(?:\s|$)',text),'bus-skew native report has wrong instance scope')
 require('src_gray_ff_reg' in text and 'dest_graysync_ff_reg' in text and gray in text,'no instance Gray endpoints in bus-skew report')
 # UG906 summary has Id/From/To/Corner/Requirement/Actual/Slack columns.
 # Require a fully parsed numeric row for these exact scoped endpoint patterns.
 headings=None;found=[]
 for line in text.splitlines():
  parts=re.split(r'\s{2,}',line.strip().strip('|').strip())
  normalized=[p.strip().lower().replace(' (ns)','') for p in parts]
  if all(k in normalized for k in ('from','to','corner','requirement','actual','slack')):
   headings=normalized;continue
  if headings and len(parts)==len(headings):
   row=dict(zip(headings,parts))
   if gray+'/src_gray_ff_reg' not in row['from'] or gray+'/dest_graysync_ff_reg' not in row['to']:continue
   require(row['corner'] in ('Slow','Fast'),'unknown bus-skew corner')
   values=[]
   for key in ('requirement','actual','slack'):
    require(re.fullmatch(r'-?\d+(?:\.\d+)?(?:ns)?',row[key]),('unparsed bus-skew value',row))
    values.append(float(row[key].removesuffix('ns')))
   require(near(values[0],skew),'active bus-skew requirement differs from vendor period rule')
   found.append(row)
 require(found,'bus-skew active summary absent/unparsed for exact instance')
 return found
def audit_gray(out):
 directory=out/'gray_constraints'
 require((directory/'completed.txt').read_text().strip()=='OTA004_A06R1_GRAY_EXPORT_COMPLETE groups=24','Gray export incomplete')
 groups=table(directory/'groups.tsv',['id','fifo','gray','source_clock','destination_clock','source_period','destination_period','width'])
 endpoints=table(directory/'endpoints.tsv',['id','role','cell'])
 constraints=table(directory/'constraints.tsv',['id','origin','kind','value','datapath_only','from','to'])
 timing=table(directory/'effective_timing.tsv',['id','destination_cell','startpoint_pin','endpoint_pin','requirement'])
 require(len(groups)==24 and {r['id'] for r in groups}=={str(i) for i in range(1,25)},'missing/duplicate Gray macro')
 expect={f+'/gnuram_async_fifo.xpm_fifo_base_inst/gen_cdc_pntr.'+t for f in FIFOS for t in TYPES}
 require({r['gray'] for r in groups}==expect,'Gray macro identity mismatch')
 all_ids={r['id'] for r in groups}
 for rows in (endpoints,constraints,timing):require({r['id'] for r in rows}==all_ids,'unrecognized/missing Gray receipt group')
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
def main():
 root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]).resolve()
 require(out.parent==root/'work/OTA004','attempt outside frozen parent')
 run=root/'Sync_OTA.runs/synth_1/runme.log';log=run.read_text(errors='strict')
 errors=re.findall(r'(?mi)^\s*(?:error|fatal|critical warning)\s*:.*$',log)
 require(not errors,('native errors/critical warnings',errors))
 require('Synthesis finished with 0 errors' in log,'native successful synthesis marker missing')
 require((out/'cdc_report_completed.txt').read_text().strip()=='Vivado2021.1 sync_ota_top report_cdc -details completed','report-stage completion receipt absent')
 parsed=parse_cdc((out/'synth_cdc.txt').read_text());accepted=accept_cdc(parsed)
 xdc=(out/'synth_applied_constraints.xdc').read_text()
 require(not re.search(r'(?m)^set_clock_groups\s.*-asynchronous',xdc),'blanket asynchronous clock group forbidden')
 gray=audit_gray(out);ips=audit_ips(out)
 artifacts=[run,out/'synth_cdc.txt',out/'synth_applied_constraints.xdc',out/'cdc_report_completed.txt']
 artifacts+=sorted((out/'gray_constraints').iterdir())+sorted(out.glob('reused_ip_runs_*.tsv'))
 hashes=[dict(path=str(p),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in artifacts if p.is_file()]
 result=dict(status='OTA004_A06R1_CDC_SOURCE_REPAIR_LIMITED_PASS',native_errors=0,native_critical_warnings=0,cdc_counts=parsed['counts'],cdc_clock_blocks=parsed['clock_blocks'],reset_only_cdc10=accepted,gray_instance_evidence=gray,reused_ip_phases=list(ips),physical_timing='NOT_QUALIFIED',artifacts=hashes)
 (out/'strict_synth_review.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(dict(status=result['status'],cdc_counts=parsed['counts'],gray_macros=len(gray))))
if __name__=='__main__':main()

