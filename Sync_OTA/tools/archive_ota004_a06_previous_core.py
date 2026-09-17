from pathlib import Path
import shutil,json,hashlib,sys
root=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]).resolve();assert out.is_relative_to(root/'work/OTA004')
source=(root/'Sync_OTA.runs/synth_1').resolve();assert source.is_relative_to(root/'Sync_OTA.runs')
dest=out/'previous_core_run'
assert source.is_dir() and not dest.exists()
shutil.copytree(source,dest)
files=[]
for p in sorted(source.rglob('*')):
 if p.is_file():
  rel=p.relative_to(source);b=p.read_bytes();h=hashlib.sha256(b).hexdigest()
  assert hashlib.sha256((dest/rel).read_bytes()).hexdigest()==h
  files.append(dict(path=rel.as_posix(),bytes=len(b),sha256=h))
(out/'previous_core_run_archive.json').write_text(json.dumps(dict(source=str(source),archive=str(dest),files=files),indent=2)+'\n',encoding='utf-8')
print('PREVIOUS_CORE_RUN_ARCHIVE_VERIFIED files='+str(len(files)))
