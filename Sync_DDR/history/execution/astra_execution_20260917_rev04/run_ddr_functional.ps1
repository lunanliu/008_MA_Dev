#Requires -Version 7.0
[CmdletBinding()] param([switch]$ValidateOnly,[string]$GrantId,[datetime]$FirstStartNotAfterUtc=[datetime]::MinValue)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root='D:\007 Dev\OTA_RTL_0829\output\DDR_Control_VHDL_20260916_rev02'
$exe='C:\NIFPGA\programs\Vivado2021_1\bin\vivado.bat'
$jobOut=Join-Path $root 'validation_native_01'
$out=Join-Path $root 'validation_native_04'
$project=Join-Path $root 'project\DDR_Control.xpr'
$manifestHash='FEC4D048CBAA1837FAA86EFE6D7885938AFD855B1DAFA44C55EB5B9DE5199ADA'
function Canon([string]$p){[IO.Path]::GetFullPath($p).Replace('/','\').TrimEnd('\').ToLowerInvariant()}
function Stamp([datetime]$d){$d.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.ffffffZ')}
function Need([bool]$test,[string]$why){if(-not $test){throw $why}}
function JsonFile($v,[string]$p){$v|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $p -Encoding utf8}
$job=Get-Content -LiteralPath (Join-Path $root 'VALIDATION_JOB.json') -Raw|ConvertFrom-Json
Need ($job.job_id -ceq 'DDR_VHDL_CTRL_NATIVE_20260916_REV02') 'Unexpected job ID.'
Need ((Canon $job.root)-eq(Canon $root)) 'Unexpected job root.'
Need ((Canon $job.native_executable)-eq(Canon $exe)) 'Unexpected executable.'
Need ((Canon $job.output_directory)-eq(Canon $jobOut)) 'Unexpected output.'
Need ((Canon $job.project_path)-eq(Canon $project)) 'Unexpected project.'
Need ((Canon $job.manifest_path)-eq(Canon (Join-Path $root 'manifest.json'))) 'Unexpected manifest path.'
Need (Test-Path -LiteralPath $exe -PathType Leaf) 'Pinned Vivado is missing.'
Need ($job.manifest_sha256 -ceq $manifestHash) 'Job manifest identity changed.'
Need ((Get-FileHash -LiteralPath $job.manifest_path -Algorithm SHA256).Hash -ceq $manifestHash) 'Manifest hash mismatch.'
$manifest=Get-Content -LiteralPath $job.manifest_path -Raw|ConvertFrom-Json
Need (@($manifest.files).Count-eq 16) 'Expected exactly 16 manifest entries.'
$identities=@();$seen=@{}
foreach($f in $manifest.files){
 $p=Canon (Join-Path $root $f.relative_path)
 Need ($p.StartsWith((Canon $root)+'\')) 'Manifest escaped root.'
 Need (-not $seen.ContainsKey($p)) 'Duplicate manifest entry.';$seen[$p]=$true
 $item=Get-Item -LiteralPath $p;$hash=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
 Need ($item.Length-eq[long]$f.bytes -and $hash-ceq$f.sha256) ('Frozen identity mismatch: '+$f.relative_path)
 $identities += [pscustomobject]@{path=$p;bytes=$item.Length;sha256=$hash}
}
$stages=@();$names=@('create','write','read');$limits=@(180,300,300)
Need (@($job.commands).Count-eq 3) 'Expected three native commands.'
for($i=0;$i-lt 3;$i++){
 $name=$names[$i];$source=if($i-eq 0){'create_project.tcl'}else{'simulate.tcl'}
 $argsExpected=@('-mode','batch','-source',(Join-Path $root ('scripts\'+$source)),'-log',(Join-Path $jobOut ($name+'.log')),'-journal',(Join-Path $jobOut ($name+'.jou')))
 if($i-gt 0){$argsExpected+=@('-tclargs',$name)}
 $c=$job.commands[$i]
 Need ($c.stage-ceq$name -and (Canon $c.executable)-eq(Canon $exe)) 'Command stage/executable changed.'
 Need ([int]$c.timeout_seconds-eq$limits[$i]) 'Stage timeout changed.'
 Need ((ConvertTo-Json -Compress -InputObject @($c.arguments))-ceq(ConvertTo-Json -Compress -InputObject $argsExpected)) 'Command arguments changed.'
 $marker=if($name-eq'write'){'DDR_UPLOAD_CTRL_TEST_PASS'}elseif($name-eq'read'){'DDR_READ_CTRL_TEST_PASS'}else{'DDR_CONTROL_PROJECT_CREATED'}
 $actualArgs=@($argsExpected);$actualArgs[3]=Join-Path $PSScriptRoot $(if($i-eq 0){'create_project_retry.tcl'}else{'simulate_retry.tcl'});$actualArgs[5]=Join-Path $out ($name+'.log');$actualArgs[7]=Join-Path $out ($name+'.jou')
 $stages += [pscustomobject]@{name=$name;arguments=$actualArgs;timeout=$limits[$i];marker=$marker}
}
Need ([int]$job.resources.whole_timeout_seconds-eq 900) 'Whole timeout changed.'
Need (-not(Test-Path -LiteralPath $out)) 'Output already exists; refusing overwrite or stage rerun.'
Need (-not(Test-Path -LiteralPath (Join-Path $root 'project_retry04'))) 'Project already exists; preserve prior evidence.'
Need (-not(Test-Path -LiteralPath (Join-Path $root 'actual_sources_retry04.txt'))) 'Source export already exists; preserve evidence.'
$tok=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$tok,[ref]$parseErrors)
Need (@($parseErrors).Count-eq 0) 'PowerShell parser error.'
$preflight=[ordered]@{job=$job.job_id;powershell=$PSVersionTable.PSVersion.ToString();script=$PSCommandPath;script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;manifest_sha256=$manifestHash;identities=$identities;working_directory=$root;stages=$stages;scope='create and behavioral simulations only'}

function CheckActualSources{
 $expected=@(
  "sources_1`t$(Canon (Join-Path $root 'rtl\ddr_upload_ctrl.vhd'))"
  "sources_1`t$(Canon (Join-Path $root 'rtl\ddr_read_ctrl.vhd'))"
  "sim_write`t$(Canon (Join-Path $root 'sim\tb_ddr_upload_ctrl.vhd'))"
  "sim_read`t$(Canon (Join-Path $root 'sim\tb_ddr_read_ctrl.vhd'))"
  "constrs_1`t$(Canon (Join-Path $root 'constraints\upload_150mhz.xdc'))"
 )
 $actual=@(Get-Content -LiteralPath (Join-Path $root 'actual_sources_retry04.txt')|ForEach-Object{
  $pair=$_-split "`t",2;Need ($pair.Count-eq 2) 'Malformed actual source export.';$pair[0]+"`t"+(Canon $pair[1])
 })
 Need ($actual.Count-eq 5 -and @(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count-eq 0) 'Actual Vivado filesets mismatch.'
 JsonFile $actual (Join-Path $out 'verified_actual_sources.json')
}
function CheckNativeLogs($stage){
 $files=@((Join-Path $out ($stage.name+'.log')),(Join-Path $out ($stage.name+'.launcher.log')),(Join-Path $out ($stage.name+'.stderr.log')))
 if($stage.name-ne'create'){
  $simDir=Join-Path $root ('project_retry04\DDR_Control.sim\sim_'+$stage.name+'\behav\xsim')
  $primary=Join-Path $simDir 'simulate.log'
  Need (Test-Path -LiteralPath $primary -PathType Leaf) 'Canonical native simulate.log is missing.'
  $files+=@(Get-ChildItem -LiteralPath $simDir -Filter '*.log' -File -Recurse|ForEach-Object{$_.FullName})
  $body=Get-Content -LiteralPath $primary -Raw
  Need ([regex]::Matches($body,[regex]::Escape($stage.marker)).Count-eq 1) ('Expected unique native PASS: '+$stage.marker)
 }else{Need ((Get-Content -LiteralPath $files[0] -Raw).Contains($stage.marker)) 'Native create marker missing.'}
 foreach($file in $files){if(Test-Path -LiteralPath $file){
  $bad=Select-String -LiteralPath $file -Pattern '^\s*(ERROR|FATAL|FAILURE)(?:\s*[:\[]|\s+\[)|\bAssertion\s+(failed|failure)\b'
  Need (@($bad).Count-eq 0) ('Native diagnostic in '+$file+': '+(@($bad)|Select-Object -First 1))
 }}
 return $files
}

$previous=Get-Content -LiteralPath (Join-Path $root 'validation_native_03\summary.json') -Raw|ConvertFrom-Json
Need ($previous.job-ceq$job.job_id -and $previous.grant_id-ceq'DDR_REV02_REV03_FUNCTIONAL_20260917T143558Z') 'Retry origin changed.'
Need ($previous.status-eq'FAIL' -and $previous.cleanup.closed -and @($previous.stages).Count-eq 1 -and $previous.stages[0].stage-eq'create' -and $previous.stages[0].status-eq'FAIL') 'Expected closed failed create attempt only.'
Need (([datetime]$previous.native_deadline_utc).ToUniversalTime().Ticks-eq([datetime]'2026-09-17T14:52:47.6387679Z').ToUniversalTime().Ticks) 'Absolute native budget changed.'
$preflight.original_native_deadline_utc=$previous.native_deadline_utc
$preflight.actual_project=Join-Path $root 'project_retry04\DDR_Control.xpr'
$preflight.execution_tcl=@('create_project_retry.tcl','simulate_retry.tcl')|ForEach-Object{Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $_) -Algorithm SHA256|Select-Object Path,Hash}
$helper=Join-Path $PSScriptRoot 'DdrJobGuard.cs'
Need (Test-Path -LiteralPath $helper -PathType Leaf) 'Job helper is missing.'
$helperHash=(Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
Add-Type -Path $helper
$emptyJob=[DdrNativeGuard.DdrJobGuard]::Create()
try{Need (@($emptyJob.GetLiveIds()).Count-eq 0) 'Fresh Job is not empty.'}finally{$emptyJob.Dispose()}
$preflight.helper_sha256=$helperHash
$preflight.actual_output=$out
$preflight.original_job_output=$jobOut
$preflight.empty_job_create_query_close='PASS_NO_PROCESS_STARTED'
if($ValidateOnly){$preflight|ConvertTo-Json -Depth 8;exit 0}
Need (-not[string]::IsNullOrWhiteSpace($GrantId)) 'Explicit resource grant required.'
Need ($GrantId-ceq$previous.grant_id -and [datetime]::UtcNow-lt([datetime]$previous.native_deadline_utc).ToUniversalTime()) 'Retry grant or remaining native budget invalid.'
New-Item -ItemType Directory -Path $out|Out-Null
JsonFile $preflight (Join-Path $out 'preflight.json')
$summary=[ordered]@{job=$job.job_id;grant_id=$GrantId;status='RUNNING';started_utc=[datetime]::UtcNow.ToString('o');native_deadline_utc=$previous.native_deadline_utc;stages=@();error=$null;cleanup=$null;finished_utc=$null}
$deadline=([datetime]$previous.native_deadline_utc).ToUniversalTime();$current=$null;$guard=$null;$lastMemory=[datetime]::MinValue
function SaveSummary{JsonFile $summary (Join-Path $out 'summary.json')}
function ObserveJob($g,[string]$stage){
 $live=@($g.GetLiveIds());$identities=@($g.GetLiveProcesses()|Select-Object Pid,CreationTimeUtc)
 $row=[ordered]@{utc=[datetime]::UtcNow.ToString('o');stage=$stage;live_ids=$live;live_identity=$identities}
 ($row|ConvertTo-Json -Depth 5 -Compress)|Add-Content -LiteralPath (Join-Path $out 'process_tree.jsonl') -Encoding utf8
 JsonFile @($g.GetObservedProcesses()|Select-Object Pid,CreationTimeUtc) (Join-Path $out ($stage+'.owned_processes.json'))
 return $live
}
function CloseJob($g,[bool]$stop,[string]$stage){
 $end=[datetime]::UtcNow.AddSeconds(30);$empty=0;$checks=@();$cancel=$null
 if($stop){
  $ids=@($g.GetLiveIds())
  $cancel=@($g.GetLiveProcesses()|Select-Object Pid,CreationTimeUtc)
  if($ids.Count-gt 0){$g.Kill(125)}
 }
 do{
  $ids=@(ObserveJob $g $stage)
  $checks+=,[pscustomobject]@{utc=[datetime]::UtcNow.ToString('o');live_ids=$ids}
  if($ids.Count-eq 0){$empty++}else{$empty=0}
  if($empty-ge 3){return [pscustomobject]@{closed=$true;empty_checks=$empty;cancel_identities=$cancel;observations=$checks}}
  Start-Sleep -Milliseconds 1000
 }while([datetime]::UtcNow-lt$end)
 return [pscustomobject]@{closed=$false;empty_checks=$empty;cancel_identities=$cancel;observations=$checks}
}
function MemoryWarning{
 if(([datetime]::UtcNow-$script:lastMemory).TotalSeconds-lt 15){return}
 $script:lastMemory=[datetime]::UtcNow
 try{
  $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 2;$m=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -OperationTimeoutSec 2
  $x=[ordered]@{utc=$script:lastMemory.ToString('o');free_physical_gib=[math]::Round($os.FreePhysicalMemory/1MB,3);committed_bytes=$m.CommittedBytes;commit_limit_bytes=$m.CommitLimit;pages_per_sec=$m.PagesPersec;warning=($os.FreePhysicalMemory/1MB-lt 8);policy='warning only'}
  ($x|ConvertTo-Json -Compress)|Add-Content -LiteralPath (Join-Path $out 'memory.jsonl')
 }catch{($_.Exception.Message)|Add-Content -LiteralPath (Join-Path $out 'warnings.log')}
}
try{
 foreach($stage in $stages){
  $current=[ordered]@{stage=$stage.name;status='STARTING';started_utc=[datetime]::UtcNow.ToString('o');exit_code=$null;ended_utc=$null;root_pid=$null;logs=@();cleanup=$null}
  $summary.stages+=,$current;SaveSummary
  $guard=[DdrNativeGuard.DdrJobGuard]::Create()
  if($null-eq$deadline){
   Need ([datetime]::UtcNow-lt$FirstStartNotAfterUtc.ToUniversalTime()) 'First-start grant expired.'
   $deadline=[datetime]::UtcNow.AddSeconds(900);$summary.native_deadline_utc=$deadline.ToString('o')
  }
  Need ([datetime]::UtcNow-lt$deadline) 'Absolute whole-job deadline reached.'
  $until=[datetime]::UtcNow.AddSeconds($stage.timeout)
  $cmdExe=Join-Path $env:SystemRoot 'System32\cmd.exe'
  $launcher=Join-Path $out ($stage.name+'.launcher.log')
  $allArgs=@($exe)+$stage.arguments
  foreach($a in $allArgs){Need ($a-notmatch '["&|<>^%!\r\n]') 'Unsafe fixed cmd argument.'}
  $inner=($allArgs|ForEach-Object{'"'+$_+'"'})-join ' '
  $commandLine='"'+$cmdExe+'" /d /s /c "'+$inner+' > "'+$launcher+'" 2>&1"'
  $current.command_line=$commandLine
  $guard.StartSuspendedThenAssignResume($cmdExe,$commandLine,$root)
  $current.root_pid=$guard.RootPid;$current.status='RUNNING';SaveSummary
  do{
   $live=@(ObserveJob $guard $stage.name);$current.exit_code=$guard.GetRootExitCode()
   if($null-ne$current.exit_code -and $current.exit_code-ne 0){throw ('Native stage exit '+$current.exit_code)}
   Need ([datetime]::UtcNow-lt$until -and [datetime]::UtcNow-lt$deadline) ('Native timeout: '+$stage.name)
   MemoryWarning;SaveSummary
   if($null-ne$current.exit_code -and $live.Count-eq 0){break}
   Start-Sleep -Milliseconds 1000
  }while($true)
  $current.cleanup=CloseJob $guard $false $stage.name
  Need $current.cleanup.closed 'Complete Job tree did not close.'
  Need ($current.exit_code-eq 0) 'Native stage exit code missing.'
  if($stage.name-eq'create'){CheckActualSources}
  $current.logs=@(CheckNativeLogs $stage);$current.status='PASS';$current.ended_utc=[datetime]::UtcNow.ToString('o')
  $guard.Dispose();$guard=$null;SaveSummary
 }
 $summary.cleanup=[ordered]@{closed=$true;method='All three kernel Jobs empty for three consecutive checks'}
 $summary.status='PASS'
}catch{
 $summary.error=$_.Exception.Message;$summary.status='FAIL'
 if($null-ne$current -and $current.status-ne'PASS'){$current.status='FAIL';$current.ended_utc=[datetime]::UtcNow.ToString('o')}
 if($null-ne$guard){try{$summary.cleanup=CloseJob $guard $true $current.stage}catch{$summary.cleanup=@{closed=$false;error=$_.Exception.Message}}}
}finally{
 if($null-ne$guard){$guard.Dispose()}
 $summary.finished_utc=[datetime]::UtcNow.ToString('o');SaveSummary
}
$summary|ConvertTo-Json -Depth 8
if($summary.status-ne'PASS' -or -not $summary.cleanup.closed){exit 1}
exit 0
