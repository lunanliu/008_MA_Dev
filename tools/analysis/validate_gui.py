from pathlib import Path
import csv,hashlib,json,re,sys,importlib.util

def validate_source_membership(repo, compile_order):
    """Check exact local source paths; IP generated-file identity remains a separate audit."""
    import os, stat
    repo=Path(repo).resolve(strict=True)
    def fail(message): raise AssertionError(message)
    def checked(raw):
        if not raw or raw!=raw.strip() or raw.startswith(('#','//',';')) or any(c in raw for c in ('\x00','\n','\r','"',"'",'{','}')):
            fail('Not a plain source path: '+repr(raw))
        p=Path(raw)
        if not p.is_absolute() or '..' in p.parts: fail('Source path must be absolute without traversal: '+raw)
        # Reject symlinks, junctions/reparse points and hard-linked files, not merely their targets.
        for item in (p,*p.parents):
            st=item.lstat()
            if stat.S_ISLNK(st.st_mode) or getattr(st,'st_file_attributes',0)&0x400:
                fail('Linked/reparse source path forbidden: '+raw)
        if not p.is_file() or p.stat().st_nlink!=1: fail('Source must be one regular unlinked file: '+raw)
        resolved=p.resolve(strict=True)
        try: resolved.relative_to(repo)
        except ValueError: fail('Source outside this project: '+raw)
        return resolved
    source_entries=(repo/'rtl/sources.f').read_text(encoding='utf-8-sig').splitlines()
    if len(source_entries)!=74 or len(set(source_entries))!=74: fail('Expected exactly 74 distinct core entries')
    expected={}
    for rel in source_entries:
        q=Path(rel)
        if q.is_absolute() or '..' in q.parts or not rel.startswith('rtl/') or q.suffix.lower()!='.sv':fail('Invalid frozen core entry: '+rel)
        path=checked(str(repo/q));expected[os.path.normcase(str(path))]='core'
    for rel,kind in [('sim/tb/t10_full023_tb.sv','tb'),('sim/tb/t10_full023_fifo_observer.sv','tb')]+[('rtl/vendor/xpm/'+n,'xpm') for n in ('xpm_cdc.sv','xpm_memory.sv','xpm_fifo.sv')]:
        path=checked(str(repo/rel));expected[os.path.normcase(str(path))]=kind
    if len(expected)!=79:fail('Core/TB/XPM identity collision')
    optional={os.path.normcase(str(checked(str(repo/'sim/data'/n)))) for n in ('raw.mem','r1.mem','r2.mem','delay.mem','delta.mem','t09_pilot_phase.mem')}
    optional.update(os.path.normcase(str(checked(str(p)))) for p in (repo/'rtl/include').glob('*.svh'))
    ip_names=(repo/'ip/ip_names.txt').read_text(encoding='utf-8-sig').splitlines()
    if len(ip_names)!=34 or len(set(ip_names))!=34 or any(not re.fullmatch(r'[A-Za-z0-9_]+',n) for n in ip_names):fail('Expected 34 exact IP names')
    prefixes=[Path('ip/config')/n for n in ip_names]
    prefixes += [Path('vivado/T10_SFO')/tree/'sources_1/ip'/n for tree in ('T10_SFO.gen','T10_SFO.srcs') for n in ip_names]
    seen=set();generated=[];counts={'core':0,'tb':0,'xpm':0,'optional_data_or_header':0}
    for lineno,raw in enumerate(Path(compile_order).read_text(encoding='utf-8-sig').splitlines(),1):
        if not raw:fail('Blank compile-order line '+str(lineno))
        p=checked(raw);key=os.path.normcase(str(p))
        if key in seen:fail('Duplicate compiled source: '+raw)
        seen.add(key)
        if key in expected:counts[expected[key]]+=1;continue
        if key in optional:counts['optional_data_or_header']+=1;continue
        rel=p.relative_to(repo)
        if re.search(r'(?i)(sim_netlist|post_synth|post_route|_stub\.|\.dcp$|\.sdf$)',p.name):fail('Forbidden netlist/stub source: '+raw)
        if p.suffix.lower() not in ('.v','.sv','.vhd','.vhdl','.vh','.svh'):fail('Unknown compiled source type: '+raw)
        if not any(rel.is_relative_to(prefix) for prefix in prefixes):fail('Unapproved additional compiled source: '+raw)
        if p.name in {Path(x).name for x in source_entries}|{'t10_full023_tb.sv','t10_full023_fifo_observer.sv','xpm_cdc.sv','xpm_memory.sv','xpm_fifo.sv'}:
            fail('Core/TB/XPM basename cannot be supplied by IP directory: '+raw)
        generated.append(rel.as_posix())
    missing=set(expected)-seen
    if missing:fail('Missing exact core/TB/XPM source: '+','.join(sorted(missing)))
    if counts['core']!=74 or counts['tb']!=2 or counts['xpm']!=3:fail('Unexpected source membership counts')
    return dict(counts=counts,generated_ip_files=generated,generated_ip_file_identity_audited=False,
                boundary='Path membership only; vendor-generated content/version/parameters require independent native identity audit.')

def main():
    if len(sys.argv) not in (5,6):raise SystemExit('usage: python validate_gui.py REPO RUNTIME_DIR SAVED_NATIVE_LOG NEW_REVIEW_DIR [FINAL_MANIFEST_CSV]')
    P,S,L,O=map(Path,sys.argv[1:5])
    final_candidate=Path(sys.argv[5]) if len(sys.argv)==6 else P/'docs/provenance/RTL_FINAL_MANIFEST.csv'
    if not final_candidate.is_file():raise FileNotFoundError('Final manifest is not frozen: '+str(final_candidate))
    if final_candidate.resolve()==(P/'docs/provenance/RTL_COPY_MANIFEST.csv').resolve():raise AssertionError('Final manifest cannot be the original copy snapshot')
    if O.exists():raise FileExistsError('Review directory must be new; preserve prior evidence')
    O.mkdir(parents=True)
    B=S
    def need(ok,m):
     if not ok:raise AssertionError(m)
    def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
    def un(x):
     v=int(x,16);return [((v>>(16*j))&65535)-(65536 if (v>>(16*j))&32768 else 0) for j in range(8)]
    metrics=dict(line.split('=',1) for line in (S/'result.txt').read_text().splitlines() if '=' in line)
    expected={'PASS':1,'NOMINAL_SAMPLES':1336320,'RAW_BEATS':334215,'E1_BEATS':334098,'E2_BEATS':334080,'OUTPUT_BEATS':334080,'T06_RESULTS':1,'T09_RESULTS':1,'T09_WINDOWS':74,'T09_POINTS':74,'T06_T09_RESULTS_INJECTED':0,'PRODUCTION_CAPACITY_SIMULATED':1,'OUTPUT_CLOCK_MHZ':150}
    for k,v in expected.items():need(int(metrics[k])==v,'TB completion metric '+k)
    refs={k:(P/'sim/data'/f'{k}.mem').read_text().splitlines() for k in ['r1','r2']}
    counts={k:0 for k in ['E1','E2','OUT','T09']};maxdiff=0;cycs={k:[] for k in counts};lasts={k:0 for k in counts}
    with (S/'data.csv').open() as f:
     for r in csv.DictReader(f):
      k=r['Kind'];need(k in counts,'Unknown data stage');i=counts[k];need(int(r['Frame'])==6001 and int(r['Generation'])==1 and int(r['Beat'])==i,'Frame/generation/order')
      expected_last=(i%512==511) if k=='T09' else i==({'E1':334098,'E2':334080,'OUT':334080}[k]-1)
      need(int(r['Last'])==int(expected_last),'Last flag');lasts[k]+=int(r['Last'])
      ref=refs['r1'][9+6496+4480*(i//512)+i%512] if k=='T09' else refs['r1' if k=='E1' else 'r2'][i]
      delta=max(abs(a-b) for a,b in zip(un(r['Data']),un(ref)));need(delta<=1,'Full-frame IQ mismatch');maxdiff=max(maxdiff,delta)
      cyc=int(r['Cycle']);need(not cycs[k] or cyc>cycs[k][-1],'Accepted beat cycles');cycs[k].append(cyc);counts[k]+=1
    need(counts==dict(E1=334098,E2=334080,OUT=334080,T09=37888),'Full output/window counts');need(maxdiff==int(metrics['MAX_LSB']),'TB vs independent IQ comparison')
    points=list(csv.DictReader((S/'points.csv').open()));need(len(points)==74,'All74 actual DTP points')
    golden=json.loads((P/'tools/analysis/evidence/t09_fixed007_case006.json').read_text())['branches'][1];point_diffs=[]
    for i,r in enumerate(points):
     v=int(r['Record'],16);delay=(v>>5)&0xffffff;delay-=1<<24 if delay&(1<<23) else 0;delta=(v>>29)&0x3ffff;delta-=1<<18 if delta&(1<<17) else 0
     need(int(r['Slot'])==i and (v>>97)==6001 and ((v>>65)&0xffffffff)==1 and ((v>>58)&127)==i and v&1,'Point identity/valid')
     point_diffs.append(dict(slot=i,delay_q16=delay,delta_q16=delta,delay_difference_q16=delay-golden['delay_q16'][i],delta_difference_q16=delta-golden['delta_bin_q16'][i]))
    events=list(csv.DictReader((S/'events.csv').open()));by={}
    for e in events:by.setdefault(e['Kind'],[]).append(e)
    for k in ['T06_RESULT','RAW_COMPLETE','E1_CONFIG','E1_PUBLISH','T09_CONFIG','T09_RESULT','E2_CONFIG','E2_COMPLETE']:need(len(by.get(k,[]))==1,'Required stage event '+k)
    need(len(by.get('T09_REQUEST',[]))==74,'All74 native requests')
    ordered=['T06_RESULT','RAW_COMPLETE','E1_CONFIG','E1_PUBLISH','T09_CONFIG','T09_RESULT','E2_CONFIG','E2_COMPLETE'];times=[int(by[k][0]['TimePs']) for k in ordered];need(all(a<b for a,b in zip(times,times[1:])),'True estimator/resampler causal chain')
    first=int(by['T06_RESULT'][0]['Record'],16);second=int(by['T09_RESULT'][0]['Record'],16)
    need((first>>64)&0xffffffff==(-39303835&0xffffffff),'Actual first estimate');need((second>>38)&0xffffffff==(-12945&0xffffffff) and (second>>6)&0xffffffff==268435443,'Actual residual estimate/reference applicability')
    source_membership=validate_source_membership(P,B/'compile_order.txt')
    copy_manifest=P/'docs/provenance/RTL_COPY_MANIFEST.csv'
    with copy_manifest.open(encoding='utf-8-sig',newline='') as stream:copied=list(csv.DictReader(stream))
    active_manifest=Path(sys.argv[5]) if len(sys.argv)==6 else P/'docs/provenance/RTL_FINAL_MANIFEST.csv'
    need(active_manifest.is_file(),'Final manifest is not frozen; RTL_FINAL_MANIFEST.csv required')
    need(active_manifest.resolve()!=copy_manifest.resolve(),'Original copy manifest cannot serve as final acceptance manifest')
    with active_manifest.open(encoding='utf-8-sig',newline='') as stream:active=list(csv.DictReader(stream))
    need(bool(active),'Empty active manifest')
    for x in active:need(sha(P/x['destination_relative'])==x['destination_sha256'],'Approved migration input changed: '+x['destination_relative'])
    core=[x for x in copied if x['destination_relative'] in (P/'rtl/sources.f').read_text().splitlines()]
    need(len(core)==74 and all(sha(P/x['destination_relative'])==x['source_sha256'] for x in core),'74 original production core sources must remain byte-identical')
    need(set(x['destination_relative'] for x in copied)<=set(x['destination_relative'] for x in active),'Final manifest must cover all original migration inputs')
    log=L.read_text(errors='replace');need('T10_FULL023_PASS full_frame=1336320 real_T06=1 real_T09=1' in log,'Native full-frame completion marker')
    spec=importlib.util.spec_from_file_location('prefix',P/'tools/analysis/check_prefix.py');prefix=importlib.util.module_from_spec(spec);spec.loader.exec_module(prefix);g=prefix.validate(S,P,emit=False,log_path=L)
    # GUI migration: require a saved native completion marker, then bind exact saved evidence hashes.
    # This is not a claim of batch capture sealing, process cleanup, or independent hardware acceptance.
    need('T10_FULL023_PASS' in log,'Saved native log lacks final completion')
    v=dict(status='PENDING_ASTRA_REVIEW',checks_completed=True,full_frame_behavioral_completed=True,metrics=metrics,accepted_counts=counts,compared_iq_components=sum(counts.values())*8,maximum_integer_component_error_lsb=maxdiff,point_comparisons=point_diffs,stage_order=ordered,stage_times_ps=times,fifo_instances=g['fifo_instances'],classified_native_events=g['classified_native_events'],actual_T06_arithmetic=True,actual_T09_74_windows_arithmetic=True,estimated_records_injected=False,production_capacity_simulated=True,matlab_executed=False,synthesis_executed=False,post_synthesis_simulation_executed=False,case_scope='One noiseless -150ppm/100kHz CFO frame6001; upstream T04/T05 saved records',continuous_frames_qualified=False,sustained_500MSps_qualified=False,T10_PASS=False)
    v['source_membership']=source_membership
    v['gui_saved_evidence']={'native_log_sha256':sha(L),'copy_manifest_sha256':sha(copy_manifest),'active_manifest_sha256':sha(active_manifest),'runtime_files':{n:sha(S/n) for n in ['result.txt','data.csv','events.csv','points.csv','xpm_trace.csv','compile_order.txt']},'batch_stream_sealing_proven':False,'process_cleanup_proven':False,'target_part_native_audit_required':True}
    v['accepted_cycle_statistics']={k:dict(first=cs[0],last=cs[-1],accepted_beats=len(cs),largest_service_gap_cycles=max(b-a for a,b in zip(cs,cs[1:])),clock_MHz=125 if k=='T09' else 150) for k,cs in cycs.items()}
    (O/'summary.json').write_text(json.dumps(v,indent=2)+'\n',encoding='utf8');print(json.dumps({k:v[k] for k in ['status','checks_completed','full_frame_behavioral_completed','accepted_counts','maximum_integer_component_error_lsb','T10_PASS']}))

if __name__=='__main__':
    main()
