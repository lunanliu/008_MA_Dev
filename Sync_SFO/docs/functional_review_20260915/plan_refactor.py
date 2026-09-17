from pathlib import Path
import json,re,hashlib,collections
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915';rows=json.loads((A/'baseline_source_inventory.json').read_text());own={n for r in rows for n in r['modules']};names={};paths={}
explicit={
'bistatic_stream_pkg':('common','sfo_stream_pkg'),
'farrow_microbench':('resampling','sfo_farrow_parallel'),
'g3_up15_top':('resampling','sfo_fir_up15'), 'g3_up47_top':('resampling','sfo_fir_up47'),
'g3_down15_top':('resampling','sfo_fir_down15'), 'g3_down47_top':('resampling','sfo_fir_down47'),
'g3_farrow_guard_stream':('resampling','sfo_guarded_farrow_stream'),
't03_main_fft_service':('fft_service','sfo_initial_fft_service'),
't03_uram_frame_bank':('buffering','sfo_uram_frame_bank'),
't05_local_capture_buffer':('buffering','sfo_training_capture_buffer'),
't05_phase_increment_controller':('initial_estimation','sfo_cfo_phase_increment'),
't05_vendor_multiplier_adapters':('common','sfo_vendor_multiplier_adapters'),
't06_initial_sfo_standalone':('initial_estimation','sfo_initial_estimator'),
't06_initial_sfo_service':('initial_estimation','sfo_initial_estimation_service'),
't06_main_fft_exclusive_owner':('fft_service','sfo_initial_fft_arbiter'),
't07_guard_frame_core':('resampling','sfo_guarded_resampling_core'),
't07_nominal_pack4_rev02':('resampling','sfo_nominal_pack4'),
't07_sync_fifo':('buffering','sfo_sync_fifo'),
't08_descriptor':('first_resampling','sfo_first_pass_descriptor'),
't08_first_sfo_resampler':('first_resampling','sfo_first_resampler'),
't08_frame_engine':('first_resampling','sfo_first_frame_scheduler'),
't09_aux_ifft_service4':('fft_service','sfo_residual_ifft_service4'),
't09_main_fft_service4':('fft_service','sfo_residual_fft_service4'),
't09_main_fft_window4':('fft_service','sfo_residual_fft_window4'),
't09_dtp_frame_backend4':('residual_estimation','sfo_residual_delay_backend4'),
't09_residual_sfo_pipeline4':('residual_estimation','sfo_residual_estimator4'),
't09_sfo_ls74':('residual_estimation','sfo_residual_ls74'),
't10_cdc_fifo':('buffering','sfo_record_cdc_fifo'),
't10_domain_reset':('control','sfo_domain_reset'),
't10_output_buffer':('buffering','sfo_output_buffer'),
't10_r1_bank':('buffering','sfo_intermediate_frame_bank'),
't10_raw_ring':('buffering','sfo_raw_frame_ring'),
't10_second_descriptor':('second_resampling','sfo_second_pass_descriptor'),
't10_second_sfo_resampler':('second_resampling','sfo_second_resampler'),
't10_two_pass_system':('control','sync_sfo_top'),
't10_two_pass_transport':('control','sfo_two_pass_transport')}
for r in rows:
 stem=Path(r['path']).stem
 if stem in explicit:group,new=explicit[stem]
 elif stem.startswith('t06_'):group,new='initial_estimation','sfo_initial_'+stem[4:]
 elif stem.startswith('t09_'):group,new='residual_estimation','sfo_residual_'+stem[4:]
 else:raise RuntimeError(stem)
 filename='sfo_farrow_arithmetic' if stem=='farrow_microbench' else new
 paths[r['path']]=f'rtl/{group}/{filename}.sv'
 for n in r['modules']:
  if n in explicit:names[n]=explicit[n][1]
  elif n.startswith('t06_'):names[n]='sfo_initial_'+n[4:]
  elif n.startswith('t09_'):names[n]='sfo_residual_'+n[4:]
  elif n.startswith('t05_'):names[n]='sfo_'+n[4:]
  elif n.startswith('farrow_'):names[n]='sfo_'+n
  else:raise RuntimeError(n)
paths.update({'rtl/include/t06_observation_engine_ip_config.svh':'rtl/include/initial_observation_ip_config.svh','rtl/include/t06_pair_max_tracker_2lane_ip_config.svh':'rtl/include/initial_pair_max_tracker_ip_config.svh','rtl/include/t06_shared_gain_ip_config.svh':'rtl/include/initial_shared_gain_ip_config.svh','sim/tb/t10_full023_tb.sv':'sim/tb/sync_sfo_full_frame_tb.sv','sim/tb/t10_full023_fifo_observer.sv':'sim/tb/sfo_fifo_history_observer.sv','constraints/t10_root_clocks.xdc':'constraints/sync_sfo_clocks.xdc','sim/data/t09_pilot_phase.mem':'sim/data/residual_pilot_phase.mem','wrapper/t10_sfo_manual_wrapper.vhd':'wrapper/sync_sfo_manual_wrapper.vhd'})
names.update({'t10_full023_tb':'sync_sfo_full_frame_tb','t10_full023_fifo_observer':'sfo_fifo_history_observer','t10_sfo_manual_wrapper':'sync_sfo_manual_wrapper','full023_observer':'sfo_history_observer'})
instances=json.loads((A/'baseline_instances.json').read_text());protected={r['type'] for r in instances if r['type'] not in own};global_ids={}
for entry in json.loads((A/'baseline_parser_results.json').read_text()):
 d=next(iter(json.loads(Path(entry['json']).read_text()).values()))
 for t in d['tokens']:
  word=t.get('text','').lstrip('`')
  if not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9$]*',word):continue
  if word in names or word in protected:continue
  if word.startswith('t09_'):global_ids[word]='residual_'+word[4:]
  elif word.startswith('t06_'):global_ids[word]='initial_'+word[4:]
# Expand known initial-estimator abbreviated wires in the top without changing external ports.
global_ids.update({'t06fv':'initial_fine_valid','t06fr':'initial_fine_ready','t06cv':'initial_cfo_valid','t06cr':'initial_cfo_ready','t06mv':'initial_result_valid','t06mr':'initial_result_ready','t06halt':'initial_halted','t06err':'initial_error_stage','t06result':'initial_result'})
for p in (M/'rtl/include').glob('*.svh'):
 for word in re.findall(r'\bT06_[A-Z0-9_]+\b',p.read_text()):global_ids[word]='SFO_INITIAL_'+word[4:]
names.update(global_ids)
assert len(set(names.values()))==len(names),'Rename collision'
for old,new in paths.items():assert not (M/new).exists(),new
scoped={
 't10_two_pass_system':{'contexts':'frame_context_fifo','fine_binding':'fine_record_fifo','transport':'two_pass_transport'},
 't10_two_pass_transport':{'r125':'reset_125','r150':'reset_150','f125':'fault_125_to_150','f150':'fault_150_to_125','cdc0':'raw_samples_cdc','cdc1':'initial_context_cdc','cdc2':'residual_config_cdc','cdc3':'residual_request_cdc','cdc4':'residual_data_cdc','cdc5':'residual_result_cdc','cdc6':'output_data_cdc','raw_bank':'raw_frame_buffer','first_pass':'first_resampling','second_pass':'second_resampling','bank':'intermediate_bank'},
 't10_cdc_fifo':{'wreset':'write_reset_sync','rreset':'read_reset_sync','b0':'read_busy_to_write','b1':'write_busy_to_read','fifo':'record_fifo'},
 't07_guard_frame_core':{'up47':'fir47_interpolator','up15':'fir15_interpolator','down15':'fir15_decimator','down47':'fir47_decimator'}}
for mod,items in scoped.items():
 known={r['instance'] for r in instances if r['module']==mod}
 missing=set(items)-known
 if missing:
  for k in missing:del items[k]
 for old,new in items.items():assert new not in known,(mod,new)
 for r in instances:
  if r['module']==mod:r['new_instance']=items.get(r['instance'],r['instance'])
for r in instances:r.setdefault('new_instance',r['instance']);r['new_type']=names.get(r['type'],r['type']);r['action']='FUNCTIONAL_RENAME' if r['new_instance']!=r['instance'] else 'RETAIN_FUNCTIONAL_NAME'
plan={'baseline':'dd5e8f7a642625f06c4996d17e3642bbadc7d557','paths':paths,'identifiers':names,'instance_scopes':scoped,'instances':instances,'protected_vendor_types':sorted(v for v in protected if v),'port_policy':'Distribute each inherited ANSI port direction/type explicitly; canonical port descriptors and inverse-name token stream must match.','format_policy':{'indent':2,'column_limit':100,'named_port_alignment':'align','port_declarations_alignment':'align','semantic_change_allowed':False}}
(A/'rename_plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8');print('PLAN',len(paths),'paths',len(names),'identifiers',sum(r['action']=='FUNCTIONAL_RENAME' for r in instances),'instances')
# Snapshot manifest only; PowerShell performs the authorized copies.
snapshot=sorted(set(paths)|{'Sync_SFO.xpr','rtl/sources.f','wrapper/ports.csv','wrapper/interface_contract.json','tools/analysis/evidence/expected_fifo_bindings.json','tools/vivado/create_project.tcl','tools/vivado/open_sync_sfo.tcl','tools/analysis/validate_gui.py','tools/analysis/check_prefix.py','README_ZH.md','docs/SFO_SYNC_MODULE_GUI_ZH.md'})
(A/'snapshot_paths.json').write_text(json.dumps(snapshot,indent=2),encoding='utf-8')
