"""Extract only already published FFT256 audit data; no MATLAB, no recomputation."""
from pathlib import Path
import runpy,json,sys,hashlib
R=Path(__file__).resolve().parents[1]
b=runpy.run_path(str(R/'tools/extract_phase74_published.py'))
O=R/'sim/vectors/fft256_published'
def main():
 assert not O.exists(),'Do not overwrite published output'
 O.mkdir()
 api=b['Hdf5'](b['HDF5_CANDIDATES'][0]);files=[]
 fields={'z_codes':74,'block_exponent':1,'fft_input_codes':74,'fft_codes':256,'power':256,'peak_bin_zero_based':1,'delta_q16':1}
 for family,spec in b['CASES'].items():
  for cid in spec['case_ids']:
   mp,jp=b['source_case'](R,family,cid);src=json.loads(jp.read_text(encoding='utf-8-sig'));ds={}
   with api.open(mp) as hf:
    for k,n in fields.items():
     d=hf.read_dataset('/ba/estimator/'+k);assert d['count']==n,(family,cid,k,d['count'])
     def integer(x):
      if isinstance(x,dict):return {k:integer(v) for k,v in x.items()}
      assert int(x)==x,(k,x);return int(x)
     ds[k]={'path':d['path'],'shape':d['shape'],'values':[integer(x) for x in d['values']]}
   keys=('bittrue.valid','bittrue.mode')+b['JSON_PHASE_FIELDS']
   context={k:b['nested_field'](src,k) for k in keys};assert all(x['present'] for x in context.values())
   obj={'schema':'fft256_published_case_v1','utc':b['utc'](),'family':family,'case_id':cid,'source_inputs':{'mat':b['file_info'](mp),'json':b['file_info'](jp)},'datasets':ds,'context':context,'new_signal_generated':False,'recomputed_fields':False}
   p=O/f'{family}_case_{cid:03d}.json';b['atomic_json'](p,obj);files.append(b['file_info'](p))
 obj={'schema':'fft256_published_manifest_v1','utc':b['utc'](),'status':'PASS','case_count':len(files),'files':files,'decoder':{'tool':b['file_info'](Path(__file__)),'reader':b['file_info'](R/'tools/extract_phase74_published.py'),'hdf5_library':b['file_info'](api.path),'hdf5_version':api.version,'python':sys.version,'executable':sys.executable},'no_matlab':True,'no_vivado':True,'no_new_signals':True}
 p=O/'manifest.json';b['atomic_json'](p,obj);print(json.dumps({'status':'PASS','cases':len(files),'manifest':str(p)}))
if __name__=='__main__':main()