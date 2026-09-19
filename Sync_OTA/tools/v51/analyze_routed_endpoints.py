"""Summarize saved Vivado timing-path objects; no EDA or simulation execution."""
import argparse, collections, csv, hashlib, json, re
from pathlib import Path

def group_stats(rows, key):
    groups=collections.defaultdict(list)
    for row in rows: groups[key(row)].append(row)
    return [dict(group=k, endpoints=len(v), tns_ns=round(sum(float(x['SLACK']) for x in v),3),
                 wns_ns=min(float(x['SLACK']) for x in v))
            for k,v in sorted(groups.items(), key=lambda kv:sum(float(x['SLACK']) for x in kv[1]))]

def scope(pin, depth):
    parts=pin.split('/')[:-2]
    return '/'.join(parts[:depth]) or '(top)'

def family(pin):
    parts=pin.split('/')
    if len(parts)<2: return pin
    parts[-2]=re.sub(r'\[\d+\]', '[]', parts[-2])
    parts[-1]=re.sub(r'\[\d+\]', '[]', parts[-1])
    return '/'.join(parts)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('directory',type=Path);args=ap.parse_args();out=args.directory
    with (out/'failing_endpoints.csv').open(newline='',encoding='utf-8-sig') as f:rows=list(csv.DictReader(f))
    if not rows: raise ValueError('No failing paths exported; inspect summary before accepting empty data')
    keys=[(r['GROUP'],r['ENDPOINT_PIN']) for r in rows]
    if len(set(keys))!=len(keys): raise ValueError('Duplicate endpoint per path group; TNS would be double counted')
    if any(float(r['SLACK'])>=0 for r in rows): raise ValueError('Nonnegative path in failing set')
    full=(out/'timing_summary_checkpoint.rpt').read_text(errors='replace')
    clocks={}
    for line in full.splitlines():
        m=re.match(r'^(clk(?:125|150|500))\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s+',line)
        if m: clocks[m[1]]={'wns_ns':float(m[2]),'tns_ns':float(m[3]),'endpoints':int(m[4])}
    if set(clocks)!={'clk125','clk150','clk500'}: raise ValueError('Clock summary parsing incomplete')
    clock_groups=group_stats(rows,lambda r:r['GROUP'])
    mismatches=[]
    for clock,expected in clocks.items():
        actual=next((x for x in clock_groups if x['group']==clock),{'endpoints':0,'tns_ns':0,'wns_ns':0})
        if expected['endpoints']!=actual['endpoints'] or abs(expected['tns_ns']-actual['tns_ns'])>max(.01,expected['endpoints']*.00051):
            mismatches.append({'clock':clock,'expected':expected,'actual':actual})
    data={'evidence':'SAVED_ROUTED_CHECKPOINT_ALL_NEGATIVE_ENDPOINTS_ONE_WORST_PATH_PER_ENDPOINT',
          'count':len(rows),'tns_ns':round(sum(float(r['SLACK']) for r in rows),3),
          'clock_groups':clock_groups,'clock_summary':clocks,
          'slack_precision_ns':0.001,
          'tns_precision_note':'Module TNS sums quantized SLACK properties, not the internal full-precision sum. Counts match exactly; original summary remains authoritative for total TNS. No proportional correction is applied.',
          'all_failures_same_clock':all(r['STARTPOINT_CLOCK']==r['ENDPOINT_CLOCK']==r['GROUP'] for r in rows),'completeness_mismatches':mismatches,
          'by_module_depth3':group_stats(rows,lambda r:r['GROUP']+':'+scope(r['ENDPOINT_PIN'],3)),
          'by_module_depth4':group_stats(rows,lambda r:r['GROUP']+':'+scope(r['ENDPOINT_PIN'],4)),
          'by_source_destination':group_stats(rows,lambda r:r['GROUP']+':'+scope(r['STARTPOINT_PIN'],3)+' -> '+scope(r['ENDPOINT_PIN'],3)),
          'by_register_family':group_stats(rows,lambda r:r['GROUP']+':'+family(r['STARTPOINT_PIN'])+' -> '+family(r['ENDPOINT_PIN'])),
          'limits':'Groups attribute TNS to destination hierarchy, not to a proven causal module. Completeness requires exact endpoint counts and TNS consistency within per-path precision; totals are not asserted bit-for-bit equal.'}
    (out/'endpoint_groups.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for kind in ('by_module_depth3','by_module_depth4','by_source_destination','by_register_family'):
        with (out/(kind+'.csv')).open('w',newline='',encoding='utf-8-sig') as f:
            w=csv.DictWriter(f,fieldnames=['group','endpoints','tns_ns','wns_ns']);w.writeheader();w.writerows(data[kind])
    print(json.dumps({k:data[k] for k in ['count','tns_ns','clock_groups','completeness_mismatches','by_module_depth3']},ensure_ascii=False,indent=2))
    if mismatches: raise SystemExit('Completeness mismatch: review saved report and timing path export')
if __name__=='__main__':main()
