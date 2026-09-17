from pathlib import Path
import json,hashlib,csv
M=Path('D:/008_MA_Dev/Sync_SFO');A=M/'docs/functional_review_20260915';J=A/'job_FN01';J.mkdir(exist_ok=False)
plan=json.loads((A/'rename_plan.json').read_text());prior=json.loads((M/'docs/reorganization_20260915/final_verification.json').read_text())['native_projects'][0];supports=prior['existing_ip_support_members'];assert len(supports)==163
for r in supports:assert hashlib.sha256(Path(r['path']).read_bytes()).hexdigest()==r['sha256'],r['path']
(A/'vendor_support_recheck.json').write_text(json.dumps({'status':'PASS','members':len(supports),'reference':'docs/reorganization_20260915/final_verification.json','algorithm_or_vendor_files_changed':False},indent=2),encoding='utf-8')
rows=list(csv.DictReader((M/'docs/reorganization_20260915/native_files_1.tsv').open(),delimiter='\t'));out=[]
for r in rows:
 rel=Path(r['path']).relative_to(M).as_posix();rel=plan['paths'].get(rel,rel);out.append('\t'.join([r['fileset'],rel.lower(),r['file_type'],r['library']]))
(J/'expected_native_entries.tsv').write_text('\n'.join(sorted(out))+'\n',encoding='utf-8');assert len(out)==283
(J/'native_open_compile_elaborate.tcl').write_text('''# FN01: native project-manager open + behavioral compile/elaborate only.
# No simulate/run/synthesis/implementation command is present.
set jobdir [file normalize [file dirname [info script]]]
set canonical D:/008_MA_Dev/Sync_SFO
set private [file join $canonical work FN01 project]
set out [file join $canonical reports functional_review FN01]
if {[version -short] ne "2021.1"} {error "Vivado 2021.1 required"}
set_param general.maxThreads 8
set_param synth.maxThreads 8
set status [open [file join $out stage_status.tsv] a]
proc stage {text} {
    global status
    puts $status "[clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]\\t$text"
    flush $status
    puts "SFO_FN01_STAGE $text"
}
proc validate_export {root label} {
    global out jobdir
    if {[get_property PART [current_project]] ne "xcvu11p-flgb2104-2-e"} {error "Part mismatch"}
    if {[get_property TOP [get_filesets sources_1]] ne "sync_sfo_top"} {error "Core top mismatch"}
    if {[get_property TOP [get_filesets sim_1]] ne "sync_sfo_full_frame_tb"} {error "TB top mismatch"}
    if {[llength [get_ips -quiet]] != 34} {error "IP count mismatch"}
    set rows {}; set details [open [file join $out ${label}_actual_files.tsv] w]
    puts $details "fileset\\tpath\\tfile_type\\tlibrary"
    foreach fs [get_filesets] {
        foreach f [get_files -quiet -of_objects $fs] {
            set path [file normalize [get_property NAME $f]]
            if {![file isfile $path]} {error "Missing actual source $path"}
            set prefix "[file normalize $root]/"
            if {![string equal -nocase $prefix [string range $path 0 [expr {[string length $prefix]-1}]]]} {error "External source $path"}
            set rel [string range $path [string length $prefix] end]
            lappend rows "[get_property NAME $fs]\\t[string tolower $rel]\\t[get_property FILE_TYPE $f]\\t[get_property LIBRARY $f]"
            puts $details "[get_property NAME $fs]\\t$path\\t[get_property FILE_TYPE $f]\\t[get_property LIBRARY $f]"
        }
    }
    close $details
    set h [open [file join $jobdir expected_native_entries.tsv] r]; set wanted [split [string trim [read $h]] "\\n"]; close $h
    if {[lsort $rows] ne [lsort $wanted]} {
        set h [open [file join $out ${label}_membership_mismatch.txt] w]
        puts $h "ACTUAL\\n[join [lsort $rows] \\n]\\nEXPECTED\\n[join [lsort $wanted] \\n]"; close $h
        error "Exact source membership mismatch; do not relax the list"
    }
    set ips [open [file join $out ${label}_ip_status.tsv] w]
    puts $ips "name\\tipdef\\tlocked\\tip_file"
    foreach ip [get_ips -quiet] {puts $ips "[get_property NAME $ip]\\t[get_property IPDEF $ip]\\t[get_property IS_LOCKED $ip]\\t[get_property IP_FILE $ip]"}
    close $ips
    stage "$label OPEN_AND_MEMBERSHIP_PASS members=[llength $rows] ips=34"
}
if {[catch {
    stage "CANONICAL_OPEN_BEGIN"
    open_project -read_only [file join $canonical Sync_SFO.xpr]
    validate_export $canonical canonical
    close_project
    stage "PRIVATE_OPEN_BEGIN"
    open_project [file join $private Sync_SFO.xpr]
    validate_export $private private
    source [file join $private tools vivado configure_parallel_jobs.tcl]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    set_property xsim.elaborate.mt_level 16 [get_filesets sim_1]
    foreach ip [get_ips -quiet] {if {[get_property IS_LOCKED $ip]} {error "Locked IP: $ip"}}
    update_compile_order -fileset sim_1
    set h [open [file join $out compile_order_before.txt] w]
    foreach f [get_files -compile_order sources -used_in simulation] {puts $h [file normalize $f]}; close $h
    stage "COMPILE_BEGIN general=[get_param general.maxThreads] synth=[get_param synth.maxThreads] xelab=[get_property xsim.elaborate.mt_level [get_filesets sim_1]]"
    launch_simulation -simset sim_1 -mode behavioral -step compile
    stage "COMPILE_COMMAND_COMPLETED"
    launch_simulation -simset sim_1 -mode behavioral -step elaborate
    stage "ELABORATE_COMMAND_COMPLETED"
    set h [open [file join $out compile_order_after.txt] w]
    foreach f [get_files -compile_order sources -used_in simulation] {puts $h [file normalize $f]}; close $h
    close_project
    stage "SFO_FN01_NATIVE_STAGES_COMPLETED_NO_SIMULATION"
} message options]} {
    stage "FAILED $message"
    set h [open [file join $out native_error.txt] w]; puts $h $message; puts $h [dict get $options -errorinfo]; close $h
    close $status
    exit 1
}
close $status
exit 0
''',encoding='utf-8')
(J/'prepare_private.ps1').write_text('''$ErrorActionPreference='Stop'
$sfoRoot='D:\\008_MA_Dev\\Sync_SFO'
$sfoAudit=Join-Path $sfoRoot 'docs\\functional_review_20260915'
$sfoPrivate=Join-Path $sfoRoot 'work\\FN01\\project'
$sfoOut=Join-Path $sfoRoot 'reports\\functional_review\\FN01'
if((Test-Path -LiteralPath $sfoPrivate) -or (Test-Path -LiteralPath $sfoOut)){throw 'Existing attempt preserved; do not overwrite or repeat successful stages'}
$sfoManifest=Import-Csv -LiteralPath (Join-Path $sfoAudit 'current_input_manifest.csv')
foreach($sfoItem in $sfoManifest){
 $sfoSource=[IO.Path]::GetFullPath((Join-Path $sfoRoot $sfoItem.destination_relative))
 if(-not $sfoSource.StartsWith($sfoRoot+'\\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source path escaped module'}
 if((Get-FileHash -LiteralPath $sfoSource).Hash -ne $sfoItem.destination_sha256){throw "Frozen source mismatch: $sfoSource"}
}
[IO.Directory]::CreateDirectory($sfoPrivate) | Out-Null
[IO.Directory]::CreateDirectory($sfoOut) | Out-Null
foreach($sfoItem in $sfoManifest){
 $sfoSource=Join-Path $sfoRoot $sfoItem.destination_relative
 $sfoDestination=[IO.Path]::GetFullPath((Join-Path $sfoPrivate $sfoItem.destination_relative))
 if(-not $sfoDestination.StartsWith($sfoPrivate+'\\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped private project'}
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($sfoDestination)) | Out-Null
 Copy-Item -LiteralPath $sfoSource -Destination $sfoDestination
 if((Get-FileHash -LiteralPath $sfoDestination).Hash -ne $sfoItem.destination_sha256){throw "Private copy mismatch: $sfoDestination"}
}
Copy-Item -LiteralPath (Join-Path $sfoAudit 'current_input_manifest.csv') -Destination (Join-Path $sfoOut 'frozen_input_manifest.csv')
[ordered]@{state='PREPARED_NOT_STARTED';prepared_at=(Get-Date).ToString('o');files=$sfoManifest.Count;private_project=$sfoPrivate;output=$sfoOut} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sfoOut 'preparation.json') -Encoding utf8
''',encoding='utf-8')
(J/'JOB_ZH.md').write_text('''# FN01：功能命名版本原生工程打开、编译及展开

## 目的与范围

只核查根 XPR 的新命名选源、行为源编译/展开、独立 Wrapper 的 VHDL 语法。本作业不运行 XSim 时间、不做功能 PASS 判定、不综合、不实现、不重跑 case6001。核心 sync_sfo_top，仿真 sync_sfo_full_frame_tb，Vivado 2021.1 / xcvu11p-flgb2104-2-e。

唯一执行者为同步SFO Luna 01a0a592-d143-7770-a6e6-fa45251be664，回交 Astra 01a0a53b-5d75-7e92-9b0b-184308ae662a。须先核对管家对本 job 与冻结清单的资源授权；本文件不替代中央槽登记。

## 冻结输入与空间

539 文件、约 154.5 MiB，详见 ../current_input_manifest.csv；XPR 120 个直接依赖、原生预期 283 个成员（其中 163 个既有 IP 支持条目）。先运行 prepare_private.ps1，仅复制清单文件并逐个核对 SHA。工作区 D:/008_MA_Dev/Sync_SFO/work/FN01/project，正式证据 D:/008_MA_Dev/Sync_SFO/reports/functional_review/FN01。目录已存在时拒绝覆写。

所有 IP 及工具输出在私有副本内。原根 XPR 仅 read_only 打开；保持用户 Vivado GUI PID 14300 及其所有子进程。不要打开、保存或重新运行 Sync_Frontend/CFO/历史 T10 工程。

## 具体命令

准备：在独立 PowerShell 中执行本目录 prepare_private.ps1。

原生：工作目录为 reports/functional_review/FN01，调用 C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat，参数依次为 -mode batch -source D:/008_MA_Dev/Sync_SFO/docs/functional_review_20260915/job_FN01/native_open_compile_elaborate.tcl -log native.log -journal native.jou。使用原生参数传递及隐藏窗口，保留 stdout/stderr、实际命令、环境及进程身份。

VHDL：原生阶段完成后，在新的独立 work/FN01/wrapper_syntax 目录执行 C:/NIFPGA/programs/Vivado2021_1/bin/xvhdl.bat --2008 D:/008_MA_Dev/Sync_SFO/work/FN01/project/wrapper/sync_sfo_manual_wrapper.vhd。只进行语法/库编译，不把 Wrapper 当综合顶层，不执行 xelab Wrapper 或 read_checkpoint 回填。

## 资源与保护

本对 1 个 Vivado 主作业，全机最多 2；无 MATLAB。general/synth 请求 8，保留每个 run 的 PRE 钩子，xelab 默认 16。主作业及全部子编译合计内存初估 8～12 GiB；本次采样全机可用约 15.7 GiB，开始前须刷新并计入用户 GUI/Java及其他作业。估算超线仅告警；需要降低并发时记录实际余量与理由，不能无理由固定 2。

原生打开及 Wrapper 语法预计各 1～3 分钟；编译/展开初估 10～30 分钟。60 分钟为慢作业人工复核点，非到点终止；无日志变化不能独立证明卡死。120 分钟为本作业硬保护。严重持续资源压力、明确工具错误或确证停滞时按本作业进程树收尾；不按名称批量 kill。根 PID 退出后仍须核实记录过的全部后代及输出完成边界。

Luna 用自己的执行监控方式记录阶段、实际/预计耗时、进程树和全机资源；运行期间按15分钟模板报告。不能无人监控地启动后退出。常规命令、路径、私有环境/包装修复可另存版本；只重试必要失败阶段，保留成功阶段。需要新增/更改源、IP 参数、选择另一版源、修改测试含义或放宽选源清单则回交 Astra。

## 返回证据与判定

- 原根与私有工程的实际选源 TSV、IP 名称/版本/锁定状态、唯一 top/part；与冻结 283 行逐项比较，不能拿清单替代实际导出。
- 编译与展开日志、返回码及完成标志；查明 ERROR/CRITICAL WARNING/未解析模块，不能仅 exit 0 判定。
- 导出编译顺序与实际源哈希；74 核心、2 TB、3 XPM必须来自私有副本且对应冻结清单，生成IP文件另列来源/版本及哈希，不接受外部旧源或 netlist/stub 替代行为源。
- 全部自有实例的命名端口检查及 32 个预期 FIFO 层级绑定在日志/展开结果中的可验证情况；若只有编译证据则明确尚未运行时观察，不能冒充 trace 覆盖。
- Wrapper xvhdl 日志/返回码；只声明语法通过，不声明已与导出网表完成 NI 绑定。
- 原模块 539 个冻结输入前后哈希一致；记录可能新增的原根工具痕迹但不清理。原根源码、IP和XPR不能被改写。
- 实际峰值内存、耗时、当前所有作业后代已结束的证据及最终完整文件哈希清单。

本作业完成后封存报告，去重唤醒唯一 Astra 复核。不得继续综合、完整帧仿真或其他算法实验。
''',encoding='utf-8')
print('FN01_PACKAGE_CREATED SUPPORT_RECHECK',len(supports),'EXPECTED_NATIVE',len(out))
