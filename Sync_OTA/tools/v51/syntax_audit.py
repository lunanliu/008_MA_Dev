"""SystemVerilog syntax inspection only. Does not execute RTL or start EDA."""
from pathlib import Path
import argparse,json,sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/v51_static_tools'))
import pyslang
p=argparse.ArgumentParser();p.add_argument('files',nargs='*');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
files=[ROOT/f for f in a.files] if a.files else [ROOT/x.strip() for x in (ROOT/'rtl/sources_v51.f').read_text().splitlines() if x.strip()]
sm=pyslang.SourceManager();sm.addUserDirectories(str(ROOT/'rtl/include'));rows=[]
for f in files:
    tree=pyslang.syntax.SyntaxTree.fromFile(str(f),sm)
    diagnostics=list(tree.diagnostics)
    rows.append({'file':str(f.relative_to(ROOT)), 'diagnostic_count':len(diagnostics),'error_count':sum(d.isError() for d in diagnostics),
                 'diagnostics':pyslang.DiagnosticEngine.reportAll(sm,diagnostics)})
result={'tool':'pyslang '+pyslang.__version__,'kind':'STATIC_SYNTAX_ONLY_NOT_ELABORATION_OR_SIMULATION',
        'files':rows,'diagnostic_count':sum(r['diagnostic_count'] for r in rows),'error_count':sum(r['error_count'] for r in rows)}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
for row in rows:
    if row['diagnostic_count']:print(row['file']+'\n'+row['diagnostics'])
print(f"Parsed {len(rows)} files; syntax diagnostics: {result['diagnostic_count']}")
raise SystemExit(int(result['error_count']!=0))