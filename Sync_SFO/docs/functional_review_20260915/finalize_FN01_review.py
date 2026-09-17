from pathlib import Path
import datetime, hashlib, json
M=Path('D:/008_MA_Dev/Sync_SFO')
R=M/'reports/functional_review/FN01'
A=M/'docs/functional_review_20260915'
now=datetime.datetime.now().astimezone().isoformat()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def record(p): return {'path':p.relative_to(M).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}
def write(p,obj):
    assert p.resolve().is_relative_to(M.resolve())
    p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
closure=R/'FN01_PROCESS_CLOSURE_EVIDENCE.json'
assert sha(closure)=='195B3D81345267B38FD7560C1DB7AF66038D6DF418DFB24CC499E80BA47169BB'
entries=read(closure)['evidence_artifacts']
for e in entries:
    p=Path(e['path'])
    assert p.is_relative_to(M) and p.stat().st_size==e['bytes'] and sha(p)==e['sha256'], e['path']
assert len(entries)==16
check=R/'ASTRA_PROCESS_CLOSURE_CHECK.json'
c=read(check)
assert c['recursive_remaining']==[]
assert all(p['ProcessId']==14300 for p in c['all_native_compiler_processes'])
assert sha(M/'Sync_SFO.xpr')=='647E6B30D931C22D4BE8D9EB50456DD95ABABF5167D9208CCD0760B481357189'
assert sha(A/'current_input_manifest.csv')=='107B78D5BF50433BA297FA3CB743EC560FE4581D0EC46A364F7883986C73C72C'
final=read(R/'ASTRA_NATIVE_REVIEW_PRELIMINARY.json')
final.pop('remaining_review_item')
final.update(finalized_at=now, review_complete=True, process_closure_evidence=record(closure), independent_process_closure_check=record(check), closure_artifacts_verified=16, process_closure_scope='Recorded FN01 roots and descendants absent; current native tool census contains only preserved user GUI. Short-lived wrapper child PID was not recorded. No claim of complete historical PID capture or continuously measured resource peak.', ready_for_manual_clip_integration=True, ready_for_board_test=False, board_test_prerequisites=['Core synthesis and suitable netlist export','NI project binding and target compilation with clocks, resets, CDC, DDR/DMA and capture/replay','Independent case6001 input/references followed by board validation'], frontend_integration_prerequisites=['288-bit atomic record adaptation to SFO interfaces with coordinate/status conversion','Full-frame raw IQ storage and replay outside the frontend local capture buffer'], no_additional_native_job_required_for_this_naming_scope=True)
write(R/'ASTRA_NATIVE_REVIEW.json',final)
for p,old,new in [
(R/'ASTRA_REVIEW_ZH.md','原生工程打开、行为源编译/展开及独立 Wrapper 语法检查通过；进程结束记录待补充归档后封存最终回执。','原生工程打开、行为源编译/展开及独立 Wrapper 语法检查通过；16项补充证据哈希核对一致，进程结束复核和最终归档已完成。'),
(A/'REVIEW_STATUS_ZH.md','FN01 原生内容复核通过；进程结束记录正在补齐归档。','FN01 原生内容与进程结束复核均通过，最终证据已归档。')]:
    s=p.read_text(encoding='utf-8-sig'); assert old in s
    p.write_text(s.replace(old,new,1),encoding='utf-8')
p=R/'ASTRA_REVIEW_ZH.md'
s=p.read_text(encoding='utf-8')
s+='''\n## 进程结束与当前可测试范围\n\nLuna补充的16项既有文件均已重新核对长度和SHA256。18:37 CEST的独立进程检查中，记录的FN01启动器、Vivado、xelab与其当前可追踪后代均无残留，原用户Vivado GUI保留。Wrapper短时子进程PID未记录，结论同时依据成功结束日志和当前原生工具进程清单；不声称捕获所有历史瞬时PID。\n\n工程、独立Wrapper、case6001测试资料及Host操作指南已具备，可以开始手工CLIP集成准备。实际板测还须完成核心综合及网表导出、NI接口绑定与全目标编译，并落实125/150/500 MHz时钟、复位、DDR/DMA喂数和结果捕获。连接同步前端时还须实现288位记录适配和整帧raw IQ回放；本轮没有实现这两项。\n\n最终判定见 [机器可读复核](ASTRA_NATIVE_REVIEW.json)，文件身份见 [最终证据清单](FINAL_EVIDENCE_MANIFEST.json)，进程记录见 [Luna补充证据](FN01_PROCESS_CLOSURE_EVIDENCE.json) 和 [Astra独立核查](ASTRA_PROCESS_CLOSURE_CHECK.json)。共享执行槽由总管家登记归还，本任务不改中央锁。\n'''
p.write_text(s,encoding='utf-8')
write(R/'RESOURCE_RETURN_REQUEST_FN01.json',{'created_at':now,'job':'SFO-FN01','grant_id':'SFO_FN01_20260915_OPEN_COMPILE_ELABORATE','grant_sha256':'1EBDB7340CAD52B564696BD3B462766F76613339C37D1DD76CBCB1EA99333D5E','requester':'01a0a53b-5d75-7e92-9b0b-184308ae662a','manager':'01a06e5a-ad5f-7bb3-9fb2-a4eb4560bbb7','action':'RETURN_SHARED_VIVADO_SLOT_AFTER_COMPLETED_REVIEW','status':'REQUESTED_TO_MANAGER','native_jobs_remaining':0,'next_native_job':None,'review':record(R/'ASTRA_NATIVE_REVIEW.json'),'process_check':record(check),'central_resource_slot_modified_by_this_task':False,'source_commit':'c4d853a1987f66f212fd44fcd8e9a42dd00035d2','request_commit':'9c4f1683a71622e885b75df553d0b70a88ffe777','ready_for_manual_clip_integration':True,'board_validation':'NOT_RUN'})
selected=[M/'README_ZH.md',M/'docs/SFO_SYNC_MODULE_GUI_ZH.md',M/'Sync_SFO.xpr',M/'wrapper/sync_sfo_manual_wrapper.vhd',M/'wrapper/interface_contract_FN01.json',A/'REVIEW_STATUS_ZH.md',A/'current_input_manifest.csv',A/'RESOURCE_REQUEST_FN01.json']
files=sorted(p for p in R.rglob('*') if p.is_file() and p.name!='FINAL_EVIDENCE_MANIFEST.json')+selected
write(R/'FINAL_EVIDENCE_MANIFEST.json',{'created_at':now,'job':'SFO-FN01','scope':'Final native evidence and current delivery entry points; excludes itself, runtime workspaces and report clock. Original frozen input manifest remains unchanged.','files':[record(p) for p in files]})
clock=read(A/'report_clock.json');clock.update(last_report_at='2026-09-15T18:41:22+02:00',next_due_at='2026-09-15T18:56:22+02:00');write(A/'report_clock.json',clock)
print(json.dumps({'closure_artifacts_verified':len(entries),'evidence_manifest_files':len(files),'manifest_sha256':sha(R/'FINAL_EVIDENCE_MANIFEST.json'),'final_review_sha256':sha(R/'ASTRA_NATIVE_REVIEW.json'),'completed_at':now},ensure_ascii=False))
