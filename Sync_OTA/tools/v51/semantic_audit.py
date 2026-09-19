"""Static SV binding/type inspection, no RTL execution or EDA invocation.
Vendor XPM/IP interfaces are bound; implementation bodies stay outside this check.
"""
from pathlib import Path
import sys,json,collections,argparse
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--candidate-manifest',type=Path)
args=parser.parse_args()
overrides={}
if args.candidate_manifest:
    for item in json.loads(args.candidate_manifest.read_text())['changes']:
        overrides[Path(item['production_path']).resolve()]=Path(item['candidate_path']).resolve()
sys.path.insert(0,str(ROOT/'work/v51_static_tools'))
import pyslang
sm=pyslang.SourceManager();sm.addUserDirectories(str(ROOT/'rtl/include'))
options=pyslang.ast.CompilationOptions();options.topModules={'sync_ota_top'};options.errorLimit=0;options.defaultTimeScale=pyslang.TimeScale.fromString('1ns/1ps')
bag=pyslang.Bag([options]);comp=pyslang.ast.Compilation(bag)
for name in (ROOT/'rtl/sources_v51.f').read_text().splitlines():
    if name.strip():
        production=(ROOT/name.strip()).resolve()
        comp.addSyntaxTree(pyslang.syntax.SyntaxTree.fromFile(str(overrides.get(production,production)),sm))
# These are declarations from the selected managed IPs, never replacement
# behavioral models. XPM headers are copied verbatim from the selected vendor
# source after comments are stripped; all implementation bodies stay excluded.
for stub in sorted((ROOT/'Sync_OTA.srcs/sources_1/ip').glob('*/*_stub.v')):
    comp.addSyntaxTree(pyslang.syntax.SyntaxTree.fromFile(str(stub),sm))
import re,hashlib
headers=[];header_sources=[]
for vendor in sorted((ROOT/'rtl/vendor/xpm').glob('*.sv')):
    txt=re.sub(r'/\*.*?\*/|//[^\n]*','',vendor.read_text(encoding='utf-8-sig'),flags=re.S)
    header_sources.append({'path':str(vendor.relative_to(ROOT)),'sha256':hashlib.sha256(vendor.read_bytes()).hexdigest()})
    for match in re.finditer(r'(?m)^\s*module\s+xpm_\w+\b',txt):
        headers.append(txt[match.start():].split(';',1)[0]+';\nendmodule\n')
header_file=ROOT/'work/v51_static_tools/vendor_interface_declarations.sv'
header_file.write_text('\n'.join(headers),encoding='utf-8')
comp.addSyntaxTree(pyslang.syntax.SyntaxTree.fromFile(str(header_file),sm))
diagnostics=list(comp.getAllDiagnostics())
errors=[d for d in diagnostics if d.isError()]
counts=collections.Counter(str(d.code) for d in errors)

output=args.output;output.mkdir(parents=True,exist_ok=True)
(output/'diagnostics.txt').write_text(pyslang.DiagnosticEngine.reportAll(sm,diagnostics),encoding='utf-8')
summary={'tool':'pyslang '+pyslang.__version__,'kind':'STATIC_BINDING_AND_TYPE_INSPECTION_NO_SIMULATION',
         'candidate_overrides':{str(k):str(v) for k,v in overrides.items()},
         'top':'sync_ota_top','diagnostics':len(diagnostics),'errors':len(errors),'error_codes':dict(counts),
         'all_diagnostic_codes':dict(collections.Counter(str(d.code) for d in diagnostics)),
         'vendor_boundary':'Vendor IP black-box stubs and XPM interface declarations only; bodies and primitive mapping are NOT checked.', 'xpm_header_sources':header_sources}
(output/'summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
print(json.dumps(summary,indent=2))
print(pyslang.DiagnosticEngine.reportAll(sm,[d for d in errors if 'UnknownModule' not in str(d.code)])[:16000])

raise SystemExit(int(bool(errors)))
