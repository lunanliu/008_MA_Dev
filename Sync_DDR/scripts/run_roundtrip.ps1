#Requires -Version 7.0
[CmdletBinding()] param([switch]$ValidateOnly,[ValidateSet('create','roundtrip')][string]$Stage='create',[string]$GrantFile)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$request=Get-Content -LiteralPath (Join-Path $root 'reports/operations/RESOURCE_REQUEST_ROUNDTRIP_V1.json') -Raw | ConvertFrom-Json
$manifestPath=Join-Path $root $request.manifest
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
function Need([bool]$test,[string]$message){if(-not $test){throw $message}}
function Canon([string]$p){[IO.Path]::GetFullPath($p).Replace('/','\').TrimEnd('\').ToLowerInvariant()}
function SaveJson($o,[string]$path){$o | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding utf8}
Need ((Canon $root)-eq(Canon $request.root)) 'Request root mismatch'
$manifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
Need ($manifestHash -ceq $request.manifest_sha256) 'Request manifest mismatch'
foreach($f in $manifest.files){
 $path=Join-Path $root $f.path
 Need ((Canon $path).StartsWith((Canon $root)+'\')) 'Input outside project'
 Need ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ceq $f.sha256) ('Changed input '+$f.path)
}
foreach($t in $manifest.tools){Need ((Get-FileHash -LiteralPath $t.path -Algorithm SHA256).Hash -ceq $t.sha256) ('Changed tool '+$t.path)}
$errors=$null;$tokens=$null
[void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$tokens,[ref]$errors)
Need (@($errors).Count-eq 0) 'Runner parse failed'
Add-Type -Path (Join-Path $PSScriptRoot 'DdrJobGuard.cs')
$probe=[DdrNativeGuard.DdrJobGuard]::Create()
try{Need (@($probe.GetLiveIds()).Count-eq 0) 'Nonempty preflight job'}finally{$probe.Dispose()}
$outRoot=Join-Path $root $request.output
if($ValidateOnly){
 [ordered]@{status='PASS_NO_EDA_STARTED';root=$root;manifest_sha256=$manifestHash;files=@($manifest.files).Count;tools=@($manifest.tools).Count;output=$outRoot;scope=$request.scope}|ConvertTo-Json -Depth 6
 exit 0
}
Need (-not[string]::IsNullOrWhiteSpace($GrantFile)) 'Fresh manager grant required'
$grant=Get-Content -LiteralPath $GrantFile -Raw | ConvertFrom-Json
Need ($grant.owner_thread_id -ceq $request.owner_thread_id) 'Grant owner mismatch'
Need ((Canon $grant.root)-eq(Canon $root)) 'Grant root mismatch'
Need ($grant.frozen_manifest_sha256 -ceq $manifestHash) 'Grant manifest mismatch'
Need ($grant.grant_id -notmatch 'DDR_REV02_REV03|RUNTIME_CONFIG|FOUR_STAGE') 'Old grant forbidden'
Need ($grant.stages -contains $Stage) 'Stage not granted'
$absolute=([datetime]$grant.absolute_deadline_utc).ToUniversalTime()
Need ([datetime]::UtcNow -lt $absolute) 'Grant deadline expired'
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
$statePath=Join-Path $outRoot 'run_state.json'
if(Test-Path -LiteralPath $statePath){$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable}
else{$state=@{first_native_utc=$null;deadline_utc=$null;project=$null;passed=@();attempts=@()}}
Need (-not($state.passed -contains $Stage)) 'Successful stage will not be rerun'
if($Stage-ne'create'){Need ($state.passed -contains 'create') 'Create must pass first'}
if($null-eq$state.deadline_utc){
 Need ([datetime]::UtcNow -lt ([datetime]$grant.first_start_not_after_utc).ToUniversalTime()) 'First-start expired'
 $first=[datetime]::UtcNow;$deadline=$first.AddSeconds([int]$request.whole_budget_seconds)
 if($absolute-lt$deadline){$deadline=$absolute}
 $state.first_native_utc=$first.ToString('o');$state.deadline_utc=$deadline.ToString('o')
}else{$deadline=([datetime]$state.deadline_utc).ToUniversalTime();if($absolute-lt$deadline){$deadline=$absolute}}
Need ([datetime]::UtcNow-lt$deadline) 'Original whole deadline reached'
$number=@($state.attempts).Count+1
$out=Join-Path $outRoot ('attempt_{0:d2}_{1}' -f $number,$Stage)
Need (-not(Test-Path -LiteralPath $out)) 'Preserve existing attempt'
New-Item -ItemType Directory -Path $out|Out-Null
$record=[ordered]@{stage=$Stage;status='STARTING';directory=$out;grant_id=$grant.grant_id;manifest_sha256=$manifestHash;started_utc=[datetime]::UtcNow.ToString('o');exit_code=$null;root_pid=$null;cleanup=$null;error=$null;logs=@();finished_utc=$null}
$state.attempts+=,$out;SaveJson $state $statePath
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $out 'frozen_manifest.json')
Copy-Item -LiteralPath $GrantFile -Destination (Join-Path $out 'manager_grant.json')
$source=Join-Path $PSScriptRoot $(if($Stage-eq'create'){'create_roundtrip_project.tcl'}else{'simulate_roundtrip.tcl'})
$arguments=@('-mode','batch','-source',$source,'-log',(Join-Path $out 'vivado.log'),'-journal',(Join-Path $out 'vivado.jou'),'-tclargs')
if($Stage-eq'create'){$arguments+=@($out)}else{$arguments+=@($Stage,$state.project)}
$allArgs=@($request.executable)+$arguments
foreach($a in $allArgs){Need ($a-notmatch '["&|<>^%!\r\n]') 'Unsafe command argument'}
$cmdExe=Join-Path $env:SystemRoot 'System32/cmd.exe'
$inner=($allArgs|ForEach-Object{'"'+$_+'"'})-join ' '
$launcher=Join-Path $out 'launcher.log'
$commandLine='"'+$cmdExe+'" /d /s /c "'+$inner+' > "'+$launcher+'" 2>&1"'
$record['command_line']=$commandLine;$record['deadline_utc']=$deadline.ToString('o')
$guard=$null
function SaveRecord{SaveJson $record (Join-Path $out 'result.json')}
function Observe{
 $ids=@($guard.GetLiveIds());$identities=@($guard.GetLiveProcesses()|Select-Object Pid,CreationTimeUtc)
 [ordered]@{utc=[datetime]::UtcNow.ToString('o');ids=$ids;identities=$identities}|ConvertTo-Json -Depth 5 -Compress|Add-Content -LiteralPath (Join-Path $out 'process_tree.jsonl')
 SaveJson @($guard.GetObservedProcesses()|Select-Object Pid,CreationTimeUtc) (Join-Path $out 'observed_processes.json')
 return $ids
}
function CloseOwned([bool]$stop){
 if($stop -and @($guard.GetLiveIds()).Count-gt 0){$guard.Kill(125)}
 $empty=0;$checks=@();$end=[datetime]::UtcNow.AddSeconds(30)
 do{
  $ids=@(Observe);$checks+=,@{utc=[datetime]::UtcNow.ToString('o');ids=$ids}
  if($ids.Count-eq 0){$empty++}else{$empty=0}
  if($empty-ge 3){return @{closed=$true;checks=$checks}}
  Start-Sleep -Milliseconds 500
 }while([datetime]::UtcNow-lt$end)
 return @{closed=$false;checks=$checks}
}
function CheckSourceSet{
 $tab=[char]9
 $expected=@($manifest.source_memberships|ForEach-Object{$_.fileset+$tab+(Canon (Join-Path $root $_.path))})
 $actual=@(Get-Content -LiteralPath (Join-Path $out 'actual_sources.txt')|ForEach-Object{
  $pair=$_-split $tab,2;Need ($pair.Count-eq 2) 'Malformed source export';$pair[0]+$tab+(Canon $pair[1])
 })
 Need ($actual.Count-eq $expected.Count -and @(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count-eq 0) 'Source set mismatch'
 $tops=@(Get-Content -LiteralPath (Join-Path $out 'actual_tops.txt'))
 $want=@($manifest.tops.PSObject.Properties|ForEach-Object{$_.Name+$tab+$_.Value})
 Need (@(Compare-Object ($tops|Sort-Object) ($want|Sort-Object)).Count-eq 0) 'Top mismatch'
}

try{
 $guard=[DdrNativeGuard.DdrJobGuard]::Create()
 $limit=if($Stage-eq'create'){180}else{300};$until=[datetime]::UtcNow.AddSeconds($limit)
 $guard.StartSuspendedThenAssignResume($cmdExe,$commandLine,$out)
 $record.root_pid=$guard.RootPid;$record.status='RUNNING';SaveRecord
 $lastMemory=[datetime]::MinValue
 do{
  $ids=@(Observe);$record.exit_code=$guard.GetRootExitCode()
  if($null-ne$record.exit_code -and $record.exit_code-ne 0){throw ('Native exit '+$record.exit_code)}
  Need ([datetime]::UtcNow-lt$deadline -and [datetime]::UtcNow-lt$until) 'Stage/whole deadline reached'
  if(([datetime]::UtcNow-$lastMemory).TotalSeconds-ge 15){
   $lastMemory=[datetime]::UtcNow
   $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 2
   $mem=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -OperationTimeoutSec 2
   [ordered]@{utc=$lastMemory.ToString('o');free_gib=$os.FreePhysicalMemory/1MB;committed_bytes=$mem.CommittedBytes;commit_limit=$mem.CommitLimit;pages_per_sec=$mem.PagesPersec;warning_only=($os.FreePhysicalMemory/1MB-lt 8)}|ConvertTo-Json -Compress|Add-Content -LiteralPath (Join-Path $out 'memory.jsonl')
  }
  SaveRecord
  if($null-ne$record.exit_code -and $ids.Count-eq 0){break}
  Start-Sleep -Milliseconds 1000
 }while($true)
 $record.cleanup=CloseOwned $false
 Need $record.cleanup.closed 'Owned Job did not close'
 Need ($record.exit_code-eq 0) 'Missing zero exit'
 if($Stage-eq'create'){
  CheckSourceSet
  Need ((Get-Content -LiteralPath (Join-Path $out 'vivado.log') -Raw).Contains('DDR_ROUNDTRIP_PROJECT_CREATED')) 'Missing create marker'
  $state.project=Join-Path $out 'project/DDR_Control.xpr'
 }else{
  $simDir=Join-Path ([IO.Path]::GetDirectoryName($state.project)) ('DDR_Control.sim/sim_'+$Stage+'/behav/xsim')
  $canonical=Join-Path $simDir 'simulate.log'
  Need (Test-Path -LiteralPath $canonical) 'Missing simulate.log'
  $marker='DDR_ROUNDTRIP_TEST_PASS'
  Need ([regex]::Matches((Get-Content -LiteralPath $canonical -Raw),[regex]::Escape($marker)).Count-eq 1) 'Missing/nonunique native PASS'
  $received=Join-Path $simDir 'host_received_u32.csv'
  Need (Test-Path -LiteralPath $received) 'Missing actual Host receive data'
  $got=@(Get-Content -LiteralPath $received|ForEach-Object{$_.Trim()})
  $want=@(Get-Content -LiteralPath (Join-Path $root 'examples/roundtrip_604/expected_u32.csv')|ForEach-Object{$_.Trim()})
  Need ($got.Count-eq 604 -and $want.Count-eq 604) 'Host receive count mismatch'
  for($i=0;$i-lt 604;$i++){Need ($got[$i]-ceq $want[$i]) ('Host data mismatch at '+$i)}
  $record['host_count']=604;$record['host_mismatch_count']=0

 }
 $logFiles=@(Get-ChildItem -LiteralPath $out -Filter '*.log' -File)
 if($Stage-ne'create'){$logFiles+=@(Get-ChildItem -LiteralPath $simDir -Filter '*.log' -File -Recurse)}
 foreach($f in $logFiles){
  $bad=@(Select-String -LiteralPath $f.FullName -Pattern '^\s*(ERROR|FATAL|FAILURE)(?:\s*[:\[]|\s+\[)|\bAssertion\s+(failed|failure)\b')
  Need ($bad.Count-eq 0) ('Native diagnostic in '+$f.FullName)
 }
 $record.status='PASS';$state.passed+=,$Stage
}catch{
 $record.status='FAIL';$record.error=$_.Exception.Message
 if($null-ne$guard){try{$record.cleanup=CloseOwned $true}catch{$record.cleanup=@{closed=$false;error=$_.Exception.Message}}}
}finally{
 if($null-ne$guard){$guard.Dispose()}
 if($Stage-ne'create' -and $null-ne$state.project){
  $dir=Join-Path ([IO.Path]::GetDirectoryName($state.project)) ('DDR_Control.sim/sim_'+$Stage+'/behav/xsim')
  if(Test-Path -LiteralPath $dir){
   $saved=Join-Path $out 'native_logs';New-Item -ItemType Directory -Path $saved|Out-Null
   Get-ChildItem -LiteralPath $dir -File | Where-Object {$_.Extension -in '.log','.prj','.tcl','.bat','.csv'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $saved}
   $record.logs=@(Get-ChildItem -LiteralPath $saved -File|Select-Object -ExpandProperty FullName)
  }
 }
 $record.finished_utc=[datetime]::UtcNow.ToString('o');SaveRecord;SaveJson $state $statePath
}
$record|ConvertTo-Json -Depth 8
if($record.status-ne'PASS' -or -not $record.cleanup.closed){exit 1}
