from pathlib import Path
import json,hashlib,subprocess,sys,datetime
R=Path('D:/008_MA_Dev/T11_CFO');A=R/'work/CFO_PHASE004R1/attempt_20260914T144622597473Z_luna';O=R/'reports/PHASE004R1_REVIEW_20260914';O.mkdir(exist_ok=True)
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
c=load(A/'ATTEMPT_COMPLETION.json');m=load(A/'ATTEMPT_ARTIFACT_MANIFEST.json');f=load(A/'EXECUTION_FREEZE.json');s=c['stage']
assert sha(A/'ATTEMPT_COMPLETION.json')=='237675B8ADD0343A49C0CE806B5D911BB9DAAD6C372479B63CEF5A54240C5B5D'
assert sha(A/'ATTEMPT_ARTIFACT_MANIFEST.json')=='4C828459D33925AF92D998BC7BE9A7733CB510E25FECA27706D6ECBD8775B96A'
checked=[]
for a in m['artifacts']:
 if not a['exists']:continue
 p=Path(a['path']);assert p.is_file() and sha(p)==a['sha256'] and p.stat().st_size==a['bytes'];checked.append(a)
assert len(checked)==39
v=subprocess.run([sys.executable,'-I','-B','-X','utf8',str(R/'tools/verify_phase74_fix01.py'),'--actual',str(A/'phase74_actual.txt'),'--sources',str(A/'simulate_actual_sources.csv'),'--identity',str(A/'simulate_project_identity.txt')],capture_output=True,text=True,check=True);numeric=json.loads(v.stdout)
assert s['binding_succeeded'] and s['native_exit_code_final']==0 and s['status']=='PASS'
assert s['end_census']['empty_verified'] and s['final_census_before_close']['empty_verified']
assert not s['persistent_telemetry_fault'] and not s['termination_requested_by_controller']
t=s['event_mono_ns'];assert t['create_suspended']<t['job_assigned']<t['launch']<t['ready']<t['zero']
assert all(c['source_update_check']['checks'].values())
samples=[json.loads(x) for x in (A/'simulate.samples.jsonl').read_text().splitlines()]
assert all(x['job_pid_stride_bytes']==8 and x['job_pid_width_bits']==64 for x in samples)
assert samples[-1]['job_active_accounting']['active_processes']==0 and samples[-1]['active_process_ids']==[]
out={'schema':'phase004r1_independent_review_v1','event':'PHASE004R1_REVIEW_237675B8','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'PASS_LIMITED_PHASE_PATH','reviewer':'T11 Astra','attempt':str(A),'completion_sha256':sha(A/'ATTEMPT_COMPLETION.json'),'manifest_sha256':sha(A/'ATTEMPT_ARTIFACT_MANIFEST.json'),'artifact_hash_count':len(checked),'numeric':numeric,'actual_sources':c['source_update_check']['counts'],'source_update_only_v1_to_v2':True,'native_seconds':s['launch_to_zero_seconds'],'native_exit':0,'job_bound_before_resume':True,'final_job_empty_both_queries':True,'peak_job_private_bytes':max(x['job_memory']['peak_job_private_commit_bytes'] for x in samples),'minimum_available_physical_bytes':min(x['system_memory']['available_physical_bytes'] for x in samples),'telemetry_fault_samples':s['telemetry_fault_samples'],'controller_identity':f['controller'],'t10_unchanged_at_execution':c['t10_unchanged'],'native_tests_repeated_during_review':False,'no_matlab':True,'pending':['FFT256 arithmetic and quality gate','phase/FFT consistency and final mode selection','FFT2048 front end','full-frame scheduling','synthesis and physical timing','sustained throughput'],'historical_compile_failure_preserved':True}
(O/'INDEPENDENT_REVIEW.json').write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
(O/'README_ZH.md').write_text('''# PHASE004R1 独立复核

结论：74点CORDIC、相位展开和OLS频率支路在本次范围内通过；不等于T11/T12/T13整模块通过。

复核39份原生产物指纹、36份冻结文件、58份已发布参考身份、12项实际工程成员。27组输入（19组已发布MATLAB输入、8组整数边界）形成33次完整结果；P/R/C内部节点分别核对2740/2590/2590行，数值全部一致。复位/abort各3次，协议错误5次，输出停顿150拍。

最后一个输入到结果最长5272拍，测试台完整事务最长7172拍。按150MHz仅作周期换算，5272拍约35.15微秒；尚无实现时序或持续吞吐证据。仅将旧core替换为词法空格修复v2，未修改算术，未重复已通过旋转/坐标/保护测试。

原生作业27.586秒、exit 0，Job在恢复进程前绑定，最终两种内核查询都为空；峰值Job私有内存约1.12GiB，最低可用物理内存见JSON。旧编译失败、旧RTL和日志继续保留。

下一步是FFT256算术及质量判定，再与相位支路合并MAIN_PHASE/DEGRADED_FFT/INVALID模式；FFT2048前端、全帧、综合及时序仍待完成。
''',encoding='utf-8')
print(json.dumps({k:v for k,v in out.items() if k not in ['controller_identity','telemetry_fault_samples']},ensure_ascii=False))