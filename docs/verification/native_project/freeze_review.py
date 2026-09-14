from pathlib import Path
import json,hashlib,ast,datetime,tkinter
r=Path(r'D:\008_MA_Dev');o=r/'docs/verification/native_project';b=o/'baseline'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def js(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
tcl=tkinter.Tcl();syntax=[]
for p in [r/'tools/vivado/create_project.tcl',o/'native_project_check.tcl',r/'ip/expected_user_config.tcl']:
 assert tcl.call('info','complete',p.read_text(encoding='utf-8-sig'))==1;syntax.append(p.relative_to(r).as_posix())
for p in [o/'prepare_native_review.py',o/'review_native_project.py']:ast.parse(p.read_text(encoding='utf-8-sig'))
# Evaluate only the generated constant configuration dictionaries in plain Tcl.
tcl.eval((r/'ip/expected_user_config.tcl').read_text());assert int(tcl.eval('dict size $expected_user_config'))==34
cfg=read(r/'ip/expected_user_config.json')
for n,d in cfg.items():
 for k,v in d.items():assert tcl.call('dict','get',tcl.getvar('expected_user_config'),n,k)==v
immutable=read(b/'IMMUTABLE_INPUTS.json')['files'];ips=read(b/'IP_BASELINE.json')['ips']
files=[x['path'] for x in immutable]+[x['path'] for x in ips]+['tools/vivado/create_project.tcl','tools/vivado/start_simulation_0ns.tcl','tools/vivado/setup_waves.tcl','ip/expected_user_config.json','ip/expected_user_config.tcl','docs/verification/native_project/native_project_check.tcl','docs/verification/native_project/run_native_project.ps1','docs/verification/native_project/review_native_project.py','docs/verification/native_project/baseline/IP_BASELINE.json','docs/verification/native_project/baseline/IMMUTABLE_INPUTS.json']
assert len(files)==len(set(files))
inputs=[dict(path=f,sha256=sha(r/f),bytes=(r/f).stat().st_size) for f in files]
for f in immutable:assert sha(r/f['path'])==f['sha256']
for f in ips:assert sha(r/f['path'])==f['sha256']
job=dict(job_id='T10_MIGRATE_GUI001',frozen_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),workspace=str(r),part='xcvu11p-flgb2104-2-e',designer='01a08299-4a14-7ef0-9000-50ec54cfdce2',executor='01a08298-b5b6-79b3-b5b4-18b8ac68993a',admission='docs/verification/NATIVE_ADMISSION.json',command_argv=['C:/Users/lunan/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe','-NoProfile','-File',str(o/'run_native_project.ps1'),'-AttemptDir','D:/008_MA_Dev/work/native_project_<unique_utc>_luna'],estimated_minutes=[2,8],native_hard_timeout_seconds=1200,cleanup_seconds=60,resources=dict(new_vivado=1,maximum_total_vivado=2,allowed_foreign_gui_pid=38288,new_process_memory_gib=4,minimum_free_memory_gib=8,matlab=0,general_threads=2),permitted=['create_project','read_canonical_ip','same_IPDEF_native_upgrade_to_project_part','report','close_and_reopen_project'],forbidden=['generate_target','synth_design','launch_runs','launch_simulation','implementation','MATLAB','CLIP','old_runner','old_workspace_source_reference'],inputs=inputs,checks=['74 exact core sources','34 canonical XCI only','all PARAM_VALUE and MODELPARAM unchanged','same IPDEF','FLGB device metadata in all34 XCI','project native close/reopen','no generated IP HDL/MIF/DCP','original inputs unchanged'],scope_pass_requires_independent_review=True)
js(o/'JOB.json',job)
js(o/'STATIC_REVIEW.json',dict(passed=True,scope='Source manifest, Python/Tcl syntax and constant dictionary identity; PowerShell AST and embedded C# compiled separately; no native design process',tcl_files=syntax,IPs=34,core_files=74,config_values=sum(map(len,cfg.values())),config_corrections=len(read(o/'CONFIG_BASELINE_CORRECTION.json')['corrections']),job_sha256=sha(o/'JOB.json'),input_files=len(inputs)))
(o/'README_ZH.md').write_text('''# 一次性原生工程迁移检查

此目录保存T10_MIGRATE_GUI001的一次性入口、冻结记录与证据，不是日常仿真启动框架。日常GUI入口是vivado/T10_SFO/T10_SFO.xpr，重建工程使用tools/vivado/create_project.tcl。

原始34份XCI保存在baseline/original_ip_xci.zip，只作历史证据，不是可编辑工程源。baseline/原始参数JSON的436处值被configElementInfo无文本节点覆盖；CONFIG_BASELINE_CORRECTION.json逐项记录修正。没有修改XCI算法数据。

本次原生操作只在新目录创建/打开工程，read_ip引用ip/config，限定同一IPDEF原生迁移到FLGB，再核对PARAM_VALUE、MODELPARAM、74源、34IP和关闭重开。禁止IP输出生成、综合、实现或仿真。预算新增1个Vivado/4GiB/1200秒，已批准保留用户GUI PID38288，总Vivado最多2个，绝不关闭该GUI。

run_native_project.ps1是一轮检查的有限进程监管；正常GUI使用不依赖它或Python。review_native_project.py只读本次结果。任何原生失败保留work/下独立目录，不修改参考答案掩盖问题。最终状态以独立复核为准。
''',encoding='utf-8')
print(json.dumps(dict(job_sha256=sha(o/'JOB.json'),inputs=len(inputs),config_values=sum(map(len,cfg.values())),admission_expires=read(r/'docs/verification/NATIVE_ADMISSION.json')['admission_expires_utc'])))
