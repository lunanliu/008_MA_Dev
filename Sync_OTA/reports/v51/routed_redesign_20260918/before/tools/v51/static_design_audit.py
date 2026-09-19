"""Read-only source/parameter inspection and closed-form hardware budgeting.
No HDL simulator, EDA process, waveform generation or numerical experiment.
Outputs are static planning evidence, never functional/timing qualification.
"""
from pathlib import Path
import argparse, hashlib, json, math, re, subprocess, xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def inspect():
    manifest = ROOT / 'rtl/sources_v51.f'
    sources = [ROOT / l.strip() for l in manifest.read_text().splitlines()
               if l.strip() and not l.lstrip().startswith('#')]
    xml = ET.parse(ROOT / 'Sync_OTA.xpr').getroot()
    selected = []
    for fs in xml.findall('./FileSets/FileSet'):
        if fs.attrib.get('Name') == 'sources_1':
            for f in fs.findall('File'):
                raw = f.attrib['Path']
                p = Path(raw.replace('$PPRDIR', ROOT.as_posix()).replace('$PSRCDIR', (ROOT/'Sync_OTA.srcs').as_posix()))
                if p.suffix.lower() == '.sv':
                    selected.append(p.resolve())
    identities = []
    definitions = {}
    for p in sources:
        row = {'path': p.relative_to(ROOT).as_posix(), 'exists': p.is_file()}
        if p.is_file():
            row['sha256'] = digest(p)
            text = re.sub(r'/\*.*?\*/|//[^\n]*', '', p.read_text(encoding='utf-8-sig'), flags=re.S)
            for name in re.findall(r'^\s*module\s+(\w+)', text, flags=re.M):
                definitions.setdefault(name, []).append(row['path'])
        identities.append(row)
    ip_paths = []
    for elem in xml.findall('.//File'):
        raw = elem.attrib.get('Path', '')
        if raw.lower().endswith('.xci'):
            p = Path(raw.replace('$PPRDIR', ROOT.as_posix()).replace('$PSRCDIR', (ROOT/'Sync_OTA.srcs').as_posix()))
            ip_paths.append(p)
    ips = []
    for p in sorted(set(ip_paths)):
        row = {'path': p.as_posix(), 'exists': p.is_file()}
        if p.is_file():
            row['sha256'] = digest(p)
            doc = ET.parse(p).getroot()
            params = {}
            for e in doc.iter():
                ref = next((v for k,v in e.attrib.items() if k.endswith('referenceId')), '')
                if ref and e.text is not None and e.text.strip() and any(k in ref.lower() for k in ('coefficient', 'filter_type', 'rate', 'latency', 'rounding', 'scaling', 'architecture', 'width', 'transform_length', 'implementation_options', 'c_arch', 'c_nfft', 'target_clock', 'output_order', 'c_bram')):
                    params[ref] = e.text
            row['parameters'] = params
        ips.append(row)
    expected = {p.resolve() for p in sources}
    vendor = {p for p in selected if '/rtl/vendor/xpm/' in p.as_posix()}
    actual = set(selected) - vendor
    return {'evidence': 'STATIC_FILE_INSPECTION', 'base_commit': subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
            'branch': subprocess.check_output(['git','branch','--show-current'], cwd=ROOT, text=True).strip(),
            'part': next(e.attrib['Val'] for e in xml.findall('./Configuration/Option') if e.attrib['Name']=='Part'),
            'manifest': manifest.relative_to(ROOT).as_posix(), 'manifest_sha256': digest(manifest),
            'source_count': len(sources), 'xpr_sv_count': len(actual), 'sources': identities,
            'manifest_only': sorted(str(p) for p in expected-actual), 'xpr_only': sorted(str(p) for p in actual-expected),
            'duplicate_production_modules': {n: ps for n,ps in definitions.items() if len(ps)>1},
            'ip_count':len(ips), 'ips':ips, 'explicit_xpm_sources':[{'path':str(p),'sha256':digest(p)} for p in sorted(vendor)],
            'native_compile':'NOT_RUN', 'simulation':'NOT_RUN', 'synthesis':'NOT_RUN', 'implementation':'NOT_RUN'}

def budget():
    n=1336320; beats=n//4; raw=334215; train=5172; lfir=72; g=66+lfir
    cfo_manifest=json.loads((ROOT/'reports/v51/pending_arithmetic/cfo_manifest.json').read_text())
    cfo_hashes=[digest(ROOT/x['production_path'].replace('\\','/').split('Sync_OTA/',1)[1]) for x in cfo_manifest['changes']]
    cfo_applied=all(actual==item['candidate_sha256'] for actual,item in zip(cfo_hashes,cfo_manifest['changes']))
    cfo_original=all(actual==item['production_sha256'] for actual,item in zip(cfo_hashes,cfo_manifest['changes']))
    if not (cfo_applied or cfo_original):
        raise ValueError('INVALID CFO source mixture or unknown hash: refusing to publish a cycle budget')
    delta=259 if cfo_applied else 0
    e0=356850+delta; server=345216+delta; fmin=334520; fmax=334992
    vacation=24610+delta+g; c1=345016+lfir
    c2_next=359130+delta+2*lfir; c2_free=359025+delta+2*lfir
    tmin=400834; cfg=32; rtail=9600
    jitter=20401+lfir
    e2_wait=max(0,c2_next+jitter+cfg-tmin)
    raw_peak=raw+math.ceil((cfg+c1-raw+2)*5/6)+256
    bank_life=e0+fmax+max(server-beats,0)+g
    sfo_life=c1+rtail+c2_free+2*cfg+e2_wait
    windows=[{'window':j,'start_sample':25984+17920*j,'sfo_bank_first_word':6505+4480*j,
              'sfo_bank_ready_exclusive':7017+4480*j} for j in range(74)]
    return {'evidence':'CLOSED_FORM_STATIC_DESIGN_CONTRACT_NOT_MEASUREMENT',
      'production_cfo_pipeline_candidates_applied':cfo_applied,
      'nominal_frame_samples':n,'nominal_frame_beats':beats,
      'nominal_frame_clock_budget':{'125':334080,'150':400896,'500':1336320},
      'arrival_contract':{'minimum_confirmed_frame_distance_words':334029,'minimum_period_cycles150':tmin,
         'assumptions':['one successful confirmation per physical frame','physical SFO within +/-150 ppm',
         'no additional unbounded interframe TO drift','healthy clocks and bounded internal IP service',
         'continuous 125 MHz four-sample ingress; external final backpressure is zero']},
      'vendor_contract':{'fir_input_and_output_ii':1,'fir_latency_sum':lfir,'extra_four_input_fifos_budget':64,
         'main_fft_gui_latency500':6287,'aux_fft_gui_latency500':6306,
         'main_fft_service_budget500':10447,'aux_fft_service_budget500':10466,
         'main_fft_required_upper500':10512,'aux_fft_required_upper500':12392,
         'first_epoch_configuration':'must complete before the first real FFT data acceptance',
         'qualification':'installed metadata + published vendor interface contract; not native model execution'},
      'raw':{'capacity_words':393216,'resampler_reads':raw,'one_training_reads':train,
         'maximum_competing_training_jobs':2,'cfg_fixed_cycles150':cfg,
         'joint_condition_cfg_plus_fir_max':59691,'joint_condition_actual':cfg+lfir,
         'conservative_live_words_bound':raw_peak,'measured_peak':None},
      'sfo':{'e1_commit_cycles150':c1,'e2_next_cfg_cycles150':c2_next,
         'e2_bank_free_cycles150':c2_free,'e2_previous_job_wait_bound':e2_wait,
         'residual_tail_budget_cycles150':rtail,'latest_bank_lifetime_cycles150':sfo_life,
         'two_frame_budget_cycles150':2*tmin,'two_bank_margin_cycles150':2*tmin-sfo_life,
         'output_ring_words':65536,'output_reserved_response_words':64,
         'output_ring_measured_peak':None,'source_internal_holes_bound':g},
      'cfo':{'fft_window_cycles500':15449,'all_windows_cycles500':74*15449,
         'phase_tail_cycles150':5687 if cfo_applied else 5272,
         'quality_tail_cycles150':7051 if cfo_applied else 6792,
         'backend_with_control_B':6832+delta,'first_frame_E0':e0,'steady_server_S':server,
         'coordinate_call_cycles150':440,'final_min_cycles150':fmin,'final_max_cycles150':fmax,
         'bank_feedback_induction_margin':e0+fmin-2*server,
         'final_nonqueue_margin':336384-fmax,'bank_lifetime_cycles150':bank_life,
         'output_no_consumption_gap_cycles150':vacation,'window_capacity':8,
         'window_reserved_upper_bound':2+math.floor((g+23098+delta)/4480),
         'window_measured_peak':None},
      'major_memory_estimates':{'raw_uram':192,'sfo_uram':328,'cfo_uram':328,
         'uram_total':848,'device_uram':960,'sfo_ring_bram36_expected':256,'cfo_window_bram36_expected':16,
         'qualification':'architectural geometry only, not synthesis or NI platform availability'},
      'output':{'clock_mhz':150,'samples_per_beat':4,'peak_samples_per_second':600000000,
         'nominal_average_samples_per_second':500000000,'downstream_backpressure_supported':False,
         'fixed_pipeline_stages':2,'stall_absorption_fifo_words':0},
      'windows':windows,'numerical_comparison':'NOT_RUN','new_synthesis_and_timing':'NOT_RUN'}

def main():
    p=argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a=p.parse_args()
    a.output.mkdir(parents=True, exist_ok=True)
    audit=inspect(); model=budget()
    for name,obj in [('source_audit.json',audit),('cycle_memory_budget.json',model)]:
        (a.output/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'sources':audit['source_count'],'xpr_sources':audit['xpr_sv_count'],'ips':audit['ip_count'],
                      'manifest_only':audit['manifest_only'],'xpr_only':audit['xpr_only'],
                      'duplicate_modules':audit['duplicate_production_modules'],
                      'missing_sources':[r['path'] for r in audit['sources'] if not r['exists']],
                      'missing_ips':[r['path'] for r in audit['ips'] if not r['exists']],
                      'output':str(a.output)},ensure_ascii=False,indent=2))
    return int(bool(audit['manifest_only'] or audit['xpr_only'] or audit['duplicate_production_modules'] or
                    any(not r['exists'] for r in audit['sources']+audit['ips'])))
if __name__=='__main__':
    raise SystemExit(main())