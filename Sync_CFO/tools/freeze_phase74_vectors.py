"""Build phase-path RTL vectors from already-published audit data and eight arithmetic corners."""
from pathlib import Path
import hashlib,json,runpy
R=Path(__file__).resolve().parents[1]
ref=runpy.run_path(str(R/'tools/phase74_reference.py'));calc=ref['phase74'];pack=ref['pack']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def dump(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def ints(values):
 assert all(isinstance(v,(int,float)) and int(v)==v for v in values)
 return list(map(int,values))
def build():
 source=R/'sim/vectors/phase74_published';out=R/'sim/vectors';manifest=read(source/'phase74_published_manifest.json')
 assert manifest['output_case_count']==19 and manifest['source_file_count']==38
 for row in manifest['output_files']:
  p=Path(row['path']);assert p.parent==source and sha(p)==row['sha256']
 hashes={str((source/'phase74_published_manifest.json').relative_to(R)):sha(source/'phase74_published_manifest.json')};cases=[];missing={}
 for p in sorted(source.glob('rcfo*.json')):
  d=read(p);hashes[str(p.relative_to(R))]=sha(p);fields=d['mat_datasets'];phase_fields=d['phase_fields']
  for item in d['source_inputs'].values():
   original=Path(item['path']);assert original.is_relative_to(R) and sha(original)==item['sha256'];hashes[str(original.relative_to(R))]=item['sha256']
  assert all(x['matches'] for x in d['length_checks'].values())
  absent=d['missing_fields']+d.get('optional_missing_fields',[])
  if absent:
   assert set(absent)<={'json.label','json.scope'};missing[p.name]=absent
  z=[tuple(ints([v['real'],v['imag']])) for v in fields['z_codes']['values']];result=calc(z)
  for k in ('angle_turn_q31','unwrapped_turn_q31','predicted_turn_q31','centered_residual_times74'):
   assert result[k]==ints(fields[k]['values']),(p.name,k)
  assert result['weighted_sum']==int(fields['weighted_sum']['value']),p.name
  assert result['atan_turn_q31']==ints(fields['cordic.atan_turn_q31']['values']),p.name
  assert int(fields['cordic.iterations']['value'])==24
  assert result['cordic_saturation']==int(fields['cordic.saturation']['value']),p.name
  assert phase_fields['bittrue.estimate.phase_q16']['present'] and phase_fields['bittrue.estimate.phase_linear']['present']
  assert result['phase_q16']==int(phase_fields['bittrue.estimate.phase_q16']['value']),p.name
  assert result['phase_linear']==bool(phase_fields['bittrue.estimate.phase_linear']['value']),p.name
  cases.append(dict(label=p.stem,published=True,z=z,expected=result))
 for label,z in ref['unit_cases']():cases.append(dict(label=label,published=False,z=z,expected=calc(z)))
 assert len(cases)==27
 outputs={name:[] for name in ('z','angle','pred','center','result')}
 for k,c in enumerate(cases):
  c.update(index=k,frame=2000+k,generation=0x56780000+k);e=c['expected']
  outputs['z'] += [f'{pack([(i,38),(q,38)]):019x}' for i,q in c['z']]
  outputs['angle'] += [f'{pack([(a,32),(u,40)]):018x}' for a,u in zip(e['angle_turn_q31'],e['unwrapped_turn_q31'])]
  outputs['pred'] += [f'{pack([(p,40),(r,56)]):024x}' for p,r in zip(e['predicted_turn_q31'],e['residual_turn_q31'])]
  outputs['center'] += [f'{pack([(x,64)]):016x}' for x in e['centered_residual_times74']]
  outputs['result'].append(f"{pack([(c['frame'],32),(c['generation'],32),(e['nonzero'],1),(e['phase_linear'],1),(0,4),(e['phase_q16'],32),(e['weighted_sum'],56),(e['max_centered'],64),(e['cordic_saturation'],12)]):059x}")
 for name,lines in outputs.items():(out/f'phase74_{name}.mem').write_text('\n'.join(lines)+'\n',encoding='ascii')
 (out/'phase74_config.svh').write_text('localparam integer PHASE_CASES=27;\n',encoding='ascii')
 (R/'ip/phase74_atan_q31.mem').write_text(''.join(f'{x:08x}\n' for x in ref['ATAN']),encoding='ascii')
 dump(out/'phase74_cases.json',dict(schema='phase74_vectors_v1',published_cases=19,arithmetic_corner_cases=8,source_hashes=hashes,unrelated_context_missing=missing,cases=cases))
 result=dict(status='PUBLISHED_PHASE_NODES_MATCH',published_cases=19,scalar_nodes_checked=19*324,unique_vectors=27,complex_points_per_vector=74,full_transactions_in_tb=33,protocol_error_results=5,discarded_transactions=6,expected_stall_cycles=sum(i%9 for i in range(27))+6*7,phase_linear_true=sum(c['expected']['phase_linear'] for c in cases),phase_linear_false=sum(not c['expected']['phase_linear'] for c in cases),both_unwrap_directions_covered=any(c['expected']['unwrap_positive'] for c in cases) and any(c['expected']['unwrap_negative'] for c in cases),source_file_count=len(hashes),no_matlab_run=True,no_new_waveform_experiment=True)
 dump(R/'reports/PHASE74_VECTOR_CHECK.json',result);return result
if __name__=='__main__':print(json.dumps(build()))