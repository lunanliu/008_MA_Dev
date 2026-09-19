#Requires -Version 7.0
[CmdletBinding()] param([switch]$ValidateOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root='D:\007 Dev\OTA_RTL_0829\output\DDR_Control_VHDL_20260916_rev02'
$exe='C:\NIFPGA\programs\Vivado2021_1\bin\vivado.bat'
$out=Join-Path $root 'validation_native_01'
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
Need ((Canon $job.output_directory)-eq(Canon $out)) 'Unexpected output.'
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
 $argsExpected=@('-mode','batch','-source',(Join-Path $root ('scripts\'+$source)),'-log',(Join-Path $out ($name+'.log')),'-journal',(Join-Path $out ($name+'.jou')))
 if($i-gt 0){$argsExpected+=@('-tclargs',$name)}
 $c=$job.commands[$i]
 Need ($c.stage-ceq$name -and (Canon $c.executable)-eq(Canon $exe)) 'Command stage/executable changed.'
 Need ([int]$c.timeout_seconds-eq$limits[$i]) 'Stage timeout changed.'
 Need ((ConvertTo-Json -Compress -InputObject @($c.arguments))-ceq(ConvertTo-Json -Compress -InputObject $argsExpected)) 'Command arguments changed.'
 $marker=if($name-eq'write'){'DDR_UPLOAD_CTRL_TEST_PASS'}elseif($name-eq'read'){'DDR_READ_CTRL_TEST_PASS'}else{'DDR_CONTROL_PROJECT_CREATED'}
 $stages += [pscustomobject]@{name=$name;arguments=$argsExpected;timeout=$limits[$i];marker=$marker}
}
Need ([int]$job.resources.whole_timeout_seconds-eq 900) 'Whole timeout changed.'
Need (-not(Test-Path -LiteralPath $out)) 'Output already exists; refusing overwrite or stage rerun.'
Need (-not(Test-Path -LiteralPath (Split-Path $project))) 'Project already exists; preserve prior evidence.'
Need (-not(Test-Path -LiteralPath (Join-Path $root 'actual_sources.txt'))) 'Source export already exists; preserve evidence.'
$tok=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($PSCommandPath,[ref]$tok,[ref]$parseErrors)
Need (@($parseErrors).Count-eq 0) 'PowerShell parser error.'
$preflight=[ordered]@{job=$job.job_id;powershell=$PSVersionTable.PSVersion.ToString();script=$PSCommandPath;script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;manifest_sha256=$manifestHash;identities=$identities;working_directory=$root;stages=$stages;scope='create and behavioral simulations only'}
if($ValidateOnly){$preflight|ConvertTo-Json -Depth 8;exit 0}
# Assigned Luna must obtain manager admission before invoking execution mode.
New-Item -ItemType Directory -Path $out|Out-Null
JsonFile $preflight (Join-Path $out 'preflight.json')
$script:owners=@{};$script:records=[Collections.Generic.List[object]]::new()
$script:eventId='DDR-process-start-'+[guid]::NewGuid().ToString('N')
$script:roots=@{};$script:deadline=$null;$script:lastMemory=[datetime]::MinValue
$summary=[ordered]@{job=$job.job_id;status='RUNNING';started_utc=[datetime]::UtcNow.ToString('o');native_deadline_utc=$null;stages=@();error=$null;cleanup=$null;finished_utc=$null}
function SaveSummary{JsonFile $summary (Join-Path $out 'summary.json');JsonFile ($script:records.ToArray()) (Join-Path $out 'owned_processes.json')}
function AddOwned($row,[string]$stage,[int]$depth,$trace){
 $rec=[pscustomobject]@{pid=[int]$row.ProcessId;parent_pid=[int]$row.ParentProcessId;creation_utc=(Stamp $row.CreationDate);stage=$stage;depth=$depth;trace_utc=$trace;last_seen_utc=[datetime]::UtcNow.ToString('o')}
 $script:owners[[string]$rec.pid]=$rec;$script:records.Add($rec);return $rec
}
function SnapshotOwned{
 $rows=@(Get-CimInstance Win32_Process -Property ProcessId,ParentProcessId,CreationDate)
 $map=@{};foreach($r in $rows){$map[[string]$r.ProcessId]=$r}
 $events=@(Get-Event -SourceIdentifier $script:eventId -ErrorAction SilentlyContinue|Sort-Object {$_.SourceEventArgs.NewEvent.TIME_CREATED})
 foreach($ev in $events){
  $e=$ev.SourceEventArgs.NewEvent;$key=[string]$e.ProcessID;$pk=[string]$e.ParentProcessID
  $trace=[datetime]::FromFileTimeUtc([long]$e.TIME_CREATED);$row=$map[$key]
  if($script:roots.ContainsKey($key)){
   $r=$script:roots[$key]
   if($null-eq$row -or (Stamp $row.CreationDate)-eq$r.creation_utc){$script:owners[$key]=$r}
   else{$script:owners.Remove($key)}
  }elseif($script:owners.ContainsKey($pk)){
   $parent=$script:owners[$pk];$parentNow=$map[$pk]
   $ok=$null-eq$parentNow -or (Stamp $parentNow.CreationDate)-eq$parent.creation_utc
   if($ok -and $null-ne$row -and [math]::Abs(($row.CreationDate.ToUniversalTime()-$trace).TotalSeconds)-lt 2){
    [void](AddOwned $row $parent.stage ($parent.depth+1) $trace.ToString('o'))
   }elseif($ok -and $null-eq$row){
    # Preserve dead intermediate parent starts for later child event attribution.
    $dead=[pscustomobject]@{pid=[int]$e.ProcessID;parent_pid=[int]$e.ParentProcessID;creation_utc=(Stamp $trace);stage=$parent.stage;depth=$parent.depth+1;trace_utc=$trace.ToString('o');last_seen_utc=$null}
    $script:owners[$key]=$dead;$script:records.Add($dead)
   }else{$script:owners.Remove($key)}
  }else{$script:owners.Remove($key)}
  Remove-Event -EventIdentifier $ev.EventIdentifier
 }
 do{
  $added=$false
  foreach($row in $rows){
   $key=[string]$row.ProcessId;$pk=[string]$row.ParentProcessId
   if($script:owners.ContainsKey($key)){
    if($script:owners[$key].creation_utc-eq(Stamp $row.CreationDate)){continue}
    $script:owners.Remove($key)
   }
   if($script:owners.ContainsKey($pk)){
    $parent=$script:owners[$pk];$parentNow=$map[$pk]
    if(($null-eq$parentNow -or (Stamp $parentNow.CreationDate)-eq$parent.creation_utc) -and $row.CreationDate.ToUniversalTime()-ge[datetime]::Parse($parent.creation_utc).ToUniversalTime()){
     [void](AddOwned $row $parent.stage ($parent.depth+1) $null);$added=$true
    }
   }
  }
 }while($added)
 $live=@();foreach($row in $rows){$key=[string]$row.ProcessId
  if($script:owners.ContainsKey($key) -and $script:owners[$key].creation_utc-eq(Stamp $row.CreationDate)){
   $script:owners[$key].last_seen_utc=[datetime]::UtcNow.ToString('o');$live+=$script:owners[$key]
  }
 };return $live
}
function MemoryWarning{
 if(([datetime]::UtcNow-$script:lastMemory).TotalSeconds-lt 15){return};$script:lastMemory=[datetime]::UtcNow
 try{
  $os=Get-CimInstance Win32_OperatingSystem;$m=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
  $s=[ordered]@{utc=$script:lastMemory.ToString('o');free_physical_gib=[math]::Round($os.FreePhysicalMemory/1MB,3);committed_bytes=$m.CommittedBytes;commit_limit_bytes=$m.CommitLimit;pages_per_sec=$m.PagesPersec;warning=($os.FreePhysicalMemory/1MB-lt 8);policy='warning only'}
  ($s|ConvertTo-Json -Compress)|Add-Content -LiteralPath (Join-Path $out 'memory.jsonl')
 }catch{('Memory warning: '+$_.Exception.Message)|Add-Content -LiteralPath (Join-Path $out 'warnings.log')}
}
function CloseOwned([bool]$Stop){
 $empty=0;$end=[datetime]::UtcNow.AddSeconds(30);$checks=@()
 do{
  $live=@(SnapshotOwned);$checks+=[pscustomobject]@{utc=[datetime]::UtcNow.ToString('o');live=@($live|ForEach-Object{$_.pid})}
  if($live.Count-eq 0){$empty++}else{$empty=0}
  if($Stop){foreach($r in ($live|Sort-Object depth -Descending)){
   $p=$null
   try{
    $p=[Diagnostics.Process]::GetProcessById($r.pid);[void]$p.Handle
    if((Stamp $p.StartTime)-eq$r.creation_utc){$p.Kill()}
   }catch{('Cleanup observation: '+$_.Exception.Message)|Add-Content -LiteralPath (Join-Path $out 'warnings.log')}
   finally{if($null-ne$p){$p.Dispose()}}
  }}
  if($empty-ge 3){return [pscustomobject]@{closed=$true;empty_checks=$empty;observations=$checks}}
  Start-Sleep -Milliseconds 1000
 }while([datetime]::UtcNow-lt$end)
 return [pscustomobject]@{closed=$false;empty_checks=$empty;observations=$checks}
}
function CheckActualSources{
 $expected=@(
  "sources_1`t$(Canon (Join-Path $root 'rtl\ddr_upload_ctrl.vhd'))"
  "sources_1`t$(Canon (Join-Path $root 'rtl\ddr_read_ctrl.vhd'))"
  "sim_write`t$(Canon (Join-Path $root 'sim\tb_ddr_upload_ctrl.vhd'))"
  "sim_read`t$(Canon (Join-Path $root 'sim\tb_ddr_read_ctrl.vhd'))"
  "constrs_1`t$(Canon (Join-Path $root 'constraints\upload_150mhz.xdc'))"
 )
 $actual=@(Get-Content -LiteralPath (Join-Path $root 'actual_sources.txt')|ForEach-Object{
  $pair=$_-split "`t",2;Need ($pair.Count-eq 2) 'Malformed actual source export.';$pair[0]+"`t"+(Canon $pair[1])
 })
 Need ($actual.Count-eq 5 -and @(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count-eq 0) 'Actual Vivado filesets mismatch.'
 JsonFile $actual (Join-Path $out 'verified_actual_sources.json')
}
function CheckNativeLogs($stage){
 $files=@((Join-Path $out ($stage.name+'.log')),(Join-Path $out ($stage.name+'.stdout.log')),(Join-Path $out ($stage.name+'.stderr.log')))
 if($stage.name-ne'create'){
  $simDir=Join-Path $root ('project\DDR_Control.sim\sim_'+$stage.name+'\behav\xsim')
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
$registered=$false;$current=$null
try{
 Register-CimIndicationEvent -Namespace root/cimv2 -Query 'SELECT * FROM Win32_ProcessStartTrace' -SourceIdentifier $script:eventId|Out-Null
 $registered=$true
 foreach($stage in $stages){
  $current=[ordered]@{stage=$stage.name;status='STARTING';started_utc=[datetime]::UtcNow.ToString('o');exit_code=$null;ended_utc=$null;root_pid=$null;logs=@();empty_tree_observations=@()}
  $summary.stages+=,$current;SaveSummary
  if($null-eq$script:deadline){$script:deadline=[datetime]::UtcNow.AddSeconds(900);$summary.native_deadline_utc=$script:deadline.ToString('o')}
  Need ([datetime]::UtcNow-lt$script:deadline) 'Absolute whole-job deadline reached.'
  $start=[datetime]::UtcNow;$until=$start.AddSeconds($stage.timeout)
  $allArgs=@($exe)+$stage.arguments
  foreach($a in $allArgs){Need ($a-notmatch '["&|<>^%!\r\n]') 'Unsafe fixed cmd argument.'}
  $cmd='/d /s /c "'+(($allArgs|ForEach-Object{'"'+$_+'"'})-join ' ')+'"'
  $proc=Start-Process -FilePath $env:ComSpec -ArgumentList $cmd -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $out ($stage.name+'.stdout.log')) -RedirectStandardError (Join-Path $out ($stage.name+'.stderr.log'))
  $seed=[pscustomobject]@{ProcessId=$proc.Id;ParentProcessId=$PID;CreationDate=$proc.StartTime}
  $rec=AddOwned $seed $stage.name 0 $null;$script:roots[[string]$proc.Id]=$rec
  $current.root_pid=$proc.Id;$current.status='RUNNING';SaveSummary;$empty=0
  do{
   $live=@(SnapshotOwned);$proc.Refresh()
   if($proc.HasExited){$current.exit_code=$proc.ExitCode}
   if($proc.HasExited -and $live.Count-eq 0){$empty++;$current.empty_tree_observations+=,[datetime]::UtcNow.ToString('o')}else{$empty=0;$current.empty_tree_observations=@()}
   if($null-ne$current.exit_code -and $current.exit_code-ne 0){throw ('Native stage exit '+$current.exit_code)}
   Need ([datetime]::UtcNow-lt$until -and [datetime]::UtcNow-lt$script:deadline) ('Native timeout: '+$stage.name)
   MemoryWarning;SaveSummary
   if($empty-ge 3){break};Start-Sleep -Milliseconds 1000
  }while($true)
  $proc.Dispose();Need ($current.exit_code-eq 0) 'Native stage did not exit normally.'
  if($stage.name-eq'create'){CheckActualSources}
  $current.logs=@(CheckNativeLogs $stage);$current.status='PASS';$current.ended_utc=[datetime]::UtcNow.ToString('o');SaveSummary
 }
 $summary.cleanup=CloseOwned $false;Need $summary.cleanup.closed 'Owned tree did not close.'
 $summary.status='PASS'
}catch{
 $summary.error=$_.Exception.Message;$summary.status='FAIL'
 if($null-ne$current -and $current.status-ne'PASS'){$current.status='FAIL';$current.ended_utc=[datetime]::UtcNow.ToString('o')}
 if($registered){try{$summary.cleanup=CloseOwned $true}catch{$summary.cleanup=@{closed=$false;error=$_.Exception.Message}}}
}finally{
 if($registered){Unregister-Event -SourceIdentifier $script:eventId -ErrorAction SilentlyContinue;Get-Event -SourceIdentifier $script:eventId -ErrorAction SilentlyContinue|Remove-Event}
 $summary.finished_utc=[datetime]::UtcNow.ToString('o');SaveSummary
}
$summary|ConvertTo-Json -Depth 8
if($summary.status-ne'PASS' -or -not $summary.cleanup.closed){exit 1}
exit 0
