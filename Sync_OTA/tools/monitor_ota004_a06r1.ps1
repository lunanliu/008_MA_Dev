param(
 [Parameter(Mandatory=$true)][string]$Stage,
 [Parameter(Mandatory=$true)][string]$Attempt,
 [Parameter(Mandatory=$true)][string]$Source,
 [Parameter(Mandatory=$true)][string]$AbsoluteDeadlineUtc,
 [int]$HardSeconds=1200
)
$ErrorActionPreference='Stop'
$root='D:/008_MA_Dev/Sync_OTA'
function Assert-OtaLaunchInput {
 param([string]$StageValue,[string]$AttemptValue,[string]$SourceValue,[int]$Seconds)
 if($StageValue -cnotin @('smoke','synth')){throw 'stage must be exactly smoke or synth'}
 $cap=if($StageValue -ceq 'smoke'){2400}else{3600}
 if($Seconds -le 0 -or $Seconds -gt $cap){throw 'duration outside frozen stage cap'}
 # Narrow ASCII grammar excludes whitespace, shell metacharacters, expansion,
 # UNC/device paths, alternate streams and dot traversal.
 foreach($value in @($AttemptValue,$SourceValue)){
  if($value -cnotmatch '^[A-Za-z]:[\\/][A-Za-z0-9_./\\-]+$' -or $value -match '(^|[\\/])\.{1,2}([\\/]|$)'){throw 'unsafe launch path'}
 }
 $candidate=[IO.Path]::GetFullPath($AttemptValue).TrimEnd([char]92,[char]47)
 $entry=[IO.Path]::GetFullPath($SourceValue)
 $expected=[IO.Path]::GetFullPath('D:/008_MA_Dev/Sync_OTA/tools/vivado/run_ota004_a06r1.tcl')
 $parent=[IO.Path]::GetFullPath('D:/008_MA_Dev/Sync_OTA/work/OTA004').TrimEnd([char]92,[char]47)
 if(-not [String]::Equals($entry,$expected,[StringComparison]::OrdinalIgnoreCase)){throw 'source is not the frozen A06R1 entry'}
 if(-not [String]::Equals([IO.Path]::GetDirectoryName($candidate),$parent,[StringComparison]::OrdinalIgnoreCase)){throw 'attempt must be a direct child of work/OTA004'}
 if([IO.Path]::GetFileName($candidate) -cnotmatch ('^'+$StageValue+'_a06r1(?:_[A-Za-z0-9-]+)?$')){throw 'attempt stage/name does not match frozen revision'}
 foreach($value in @($candidate,$entry)){
  $probe=$value
  while($probe){
   $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'reparse path is forbidden'}
   $next=[IO.Path]::GetDirectoryName($probe)
   if($next -eq $probe){break};$probe=$next
  }
 }
 if(-not (Test-Path -LiteralPath $candidate -PathType Container)){throw 'attempt directory missing'}
 if(-not (Test-Path -LiteralPath $entry -PathType Leaf)){throw 'entry file missing'}
 if(@(Get-ChildItem -LiteralPath $candidate -Force).Count -ne 0){throw 'attempt must be new and empty; keep admission/launcher logs outside it'}
 $manifest=Get-Content -LiteralPath 'D:/008_MA_Dev/Sync_OTA/docs/jobs/OTA004_A06R1_source_lock.json' -Raw | ConvertFrom-Json
 $entryRows=@($manifest.files | Where-Object {$_.path -ceq 'tools/vivado/run_ota004_a06r1.tcl'})
 if($entryRows.Count -ne 1 -or (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entryRows[0].sha256){throw 'entry does not match the frozen source lock'}
 [PSCustomObject]@{attempt=$candidate;source=$entry;stage=$StageValue;stage_cap_seconds=$cap}
}
$absoluteDeadline=([DateTimeOffset]::Parse($AbsoluteDeadlineUtc,[Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
if($absoluteDeadline -le [DateTime]::UtcNow){throw 'expired absolute deadline'}
$validated=Assert-OtaLaunchInput -StageValue $Stage -AttemptValue $Attempt -SourceValue $Source -Seconds $HardSeconds
$attempt=$validated.attempt
$sourcePath=$validated.source


$nativeNames=@('vivado.exe','rdiArgs.exe','xsim.exe','xsimk.exe','xelab.exe','xvlog.exe','xvhdl.exe','wbtcv.exe','srcscanner.exe','gcc.exe','cc1.exe','matlab.exe')
$preExisting=@(Get-CimInstance Win32_Process|Where-Object{$nativeNames -contains $_.Name.ToLowerInvariant()})
if($preExisting.Count -ne 0){
 $utf8Pre=New-Object System.Text.UTF8Encoding($false)
 [System.IO.File]::WriteAllText((Join-Path $attempt 'precheck_processes.json'),(($preExisting|Select-Object Name,ProcessId,ParentProcessId,CreationDate,CommandLine|ConvertTo-Json -Depth 8)),$utf8Pre)
 throw 'tracked native .exe process exists; refusing launch'
}
function Get-MemorySnapshot {
 $memoryErrors=@()
 $perf=$null
 $pagefiles=@()
 try {$perf=Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop} catch {$memoryErrors+=('performance counters: '+$_.Exception.Message)}
 try {$pagefiles=@(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage)} catch {$memoryErrors+=('pagefile counters: '+$_.Exception.Message)}
 $headroom=$null
 if($null -ne $perf -and $null -ne $perf.CommitLimit -and $null -ne $perf.CommittedBytes){$headroom=[int64]$perf.CommitLimit-[int64]$perf.CommittedBytes}
 [PSCustomObject]@{
  timestamp_utc=[DateTime]::UtcNow.ToString('o')
  available_bytes=if($null -ne $perf){[int64]$perf.AvailableBytes}else{$null}
  committed_bytes=if($null -ne $perf){[int64]$perf.CommittedBytes}else{$null}
  commit_limit_bytes=if($null -ne $perf){[int64]$perf.CommitLimit}else{$null}
  commit_headroom_bytes=$headroom
  pages_input_per_second=if($null -ne $perf){[int64]$perf.PagesInputPersec}else{$null}
  pages_output_per_second=if($null -ne $perf){[int64]$perf.PagesOutputPersec}else{$null}
  pagefiles=$pagefiles
  observation_errors=$memoryErrors
 }
}
$freeStart=[int64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
$memoryStart=Get-MemorySnapshot
# User policy 2026-09-17: 12 GiB is advisory only. Commit/pagefile capacity,
# real paging, full tree memory and actual tool progress govern pressure review.
if($freeStart -lt 12582912){Write-Warning ('available physical memory below advisory 12 GiB; launch is not refused: '+$freeStart+' KiB')}
$memoryStartPath=Join-Path $attempt 'initial_memory_snapshot.json'
if(Test-Path -LiteralPath $memoryStartPath){throw 'preserve prior memory record'}
[System.IO.File]::WriteAllText($memoryStartPath,($memoryStart|ConvertTo-Json -Depth 8),(New-Object System.Text.UTF8Encoding($false)))

$tree=Join-Path $attempt 'process_tree.jsonl'
if(Test-Path -LiteralPath $tree){throw 'preserve prior process record'}
$summary=Join-Path $attempt 'process_summary.json'
$stdout=Join-Path $attempt 'wrapper_stdout.log'
$stderr=Join-Path $attempt 'wrapper_stderr.log'
$vivado='C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat'
$attemptForward=$attempt.Replace([char]92,[char]47)
$log=$attemptForward+'/native.log'
$journal=$attemptForward+'/native.jou'
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($tree,'',$utf8)
$startUtc=[DateTime]::UtcNow
if([DateTime]::UtcNow -ge $absoluteDeadline){throw 'absolute deadline expired before native launch'}
$cmdLine="$vivado -mode batch -source $sourcePath -log $log -journal $journal -tclargs $Stage $attempt"
$launcher=Start-Process -FilePath 'C:/Windows/System32/cmd.exe' -ArgumentList @('/d','/c',$cmdLine) -WorkingDirectory $root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
$rootPid=[int]$launcher.Id
$rootRecord=Get-CimInstance Win32_Process -Filter ("ProcessId = "+$rootPid)
if(-not $rootRecord){throw 'launcher identity unavailable immediately after start; execution owner must reconcile actual child tree'}
$rootCreation=$rootRecord.CreationDate.ToUniversalTime().ToString('o')
$knownCreation=@{}
$knownCreation[$rootPid]=$rootCreation
$seen=@{}
function Get-TreeSnapshot {
 param([int]$RootPid)
 $all=@(Get-CimInstance Win32_Process)
 $currentByPid=@{}
 foreach($p in $all){
  $c=$null
  if($p.CreationDate){$c=$p.CreationDate.ToUniversalTime().ToString('o')}
  $currentByPid[[int]$p.ProcessId]=$c
 }
 $ids=New-Object 'System.Collections.Generic.HashSet[int]'
 if($currentByPid.ContainsKey($RootPid) -and (-not $knownCreation.ContainsKey($RootPid) -or $knownCreation[$RootPid] -eq $currentByPid[$RootPid])){[void]$ids.Add($RootPid)}
 $changed=$true
 while($changed){
  $changed=$false
  foreach($p in $all){
   $procId=[int]$p.ProcessId
   $pc=$currentByPid[$procId]
   $knownSame=$seen.ContainsKey(('{0}:{1}' -f $procId,$pc))
   $parentId=[int]$p.ParentProcessId
   $parentOwned=$ids.Contains($parentId)
   if($parentOwned){$parentOwned=([DateTime]::Parse($pc) -ge [DateTime]::Parse($currentByPid[$parentId]))}
   if(($knownSame -or $parentOwned) -and $ids.Add($procId)){$changed=$true}
  }
 }
 $records=@($all|Where-Object{$ids.Contains([int]$_.ProcessId)}|ForEach-Object{
  $c=$currentByPid[[int]$_.ProcessId]
  $knownCreation[[int]$_.ProcessId]=$c
  $record=[PSCustomObject]@{pid=[int]$_.ProcessId;parent_pid=[int]$_.ParentProcessId;name=$_.Name;creation_utc=$c;command_line=$_.CommandLine;working_set_bytes=if($_.WorkingSetSize){[int64]$_.WorkingSetSize}else{$null};private_page_count_bytes=if($null -ne $_.PrivatePageCount){[int64]$_.PrivatePageCount}else{$null};cpu_time_100ns=([int64]$_.KernelModeTime+[int64]$_.UserModeTime);read_transfer_bytes=[int64]$_.ReadTransferCount;write_transfer_bytes=[int64]$_.WriteTransferCount}
  $seen[('{0}:{1}' -f $record.pid,$record.creation_utc)]=$record
  $record
 })
 $aggregateWorkingSet=[int64](($records | Measure-Object -Property working_set_bytes -Sum).Sum)
 $freeNow=[int64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 $memoryNow=Get-MemorySnapshot
 $progressLog=Get-Item -LiteralPath $log -ErrorAction SilentlyContinue
 $pressureReview=($freeNow -lt 1048576 -or ($null -ne $memoryNow.commit_headroom_bytes -and $memoryNow.commit_headroom_bytes -lt 1073741824))
 [PSCustomObject]@{memory=$memoryNow;advisory_below_12gib=($freeNow -lt 12582912);memory_pressure_requires_review=$pressureReview;native_log_bytes=if($progressLog){$progressLog.Length}else{$null};native_log_write_utc=if($progressLog){$progressLog.LastWriteTimeUtc.ToString('o')}else{$null};timestamp_utc=[DateTime]::UtcNow.ToString('o');root_pid=$RootPid;root_alive=($records.pid -contains $RootPid);known_pid_count=$knownCreation.Count;aggregate_working_set_bytes=$aggregateWorkingSet;free_physical_kib=$freeNow;processes=$records}
}
function Write-Record{param($Record);[System.IO.File]::AppendAllText($tree,(($Record|ConvertTo-Json -Depth 12 -Compress)+[Environment]::NewLine),$utf8)}
$first=Get-TreeSnapshot -RootPid $rootPid
if($first.root_alive){$rootCreation=($first.processes|Where-Object{$_.pid -eq $rootPid}|Select-Object -First 1).creation_utc}
Write-Record $first
Write-Output ($Stage+'_launcher_pid='+$rootPid)
Write-Output ($Stage+'_start_utc='+$startUtc.ToString('o'))
$deadline=$startUtc.AddSeconds($HardSeconds)
if($absoluteDeadline -lt $deadline){$deadline=$absoluteDeadline}
$stableEmpty=0
$cancellationPasses=0
$lastReport=$startUtc
$timedOut=$false
$minFree=$freeStart
$minimumCommitHeadroom=$memoryStart.commit_headroom_bytes
while($true){
 $snap=Get-TreeSnapshot -RootPid $rootPid
 Write-Record $snap
 if($snap.free_physical_kib -lt $minFree){$minFree=$snap.free_physical_kib}
 if($null -ne $snap.memory.commit_headroom_bytes -and ($null -eq $minimumCommitHeadroom -or $snap.memory.commit_headroom_bytes -lt $minimumCommitHeadroom)){$minimumCommitHeadroom=$snap.memory.commit_headroom_bytes}
 $now=[DateTime]::UtcNow
 if(($now-$lastReport).TotalSeconds -ge 30){Write-Output ($Stage+'_elapsed_s='+[int]($now-$startUtc).TotalSeconds+' tree_count='+@($snap.processes).Count+' known_pid_count='+$snap.known_pid_count+' free_kib='+$snap.free_physical_kib+' commit_headroom_bytes='+$snap.memory.commit_headroom_bytes+' pages_in_per_s='+$snap.memory.pages_input_per_second+' pages_out_per_s='+$snap.memory.pages_output_per_second+' pressure_review='+$snap.memory_pressure_requires_review);$lastReport=$now}
 $launcher.Refresh()
 if($launcher.HasExited -and @($snap.processes).Count -eq 0){$stableEmpty++}else{$stableEmpty=0}
 if($stableEmpty -ge 3){break}
 if($now -ge $deadline -and @($snap.processes).Count -gt 0){
  $timedOut=$true
  $cancellationPasses++
  Write-Output ($Stage+'_stage_timeout=true cancellation_pass='+$cancellationPasses)
  # Each stop is restricted to a currently confirmed recorded identity.
  # Descendants precede their parent; surviving or orphaned recorded identities
  # remain seeds in the next snapshot, including when the launcher has exited.
  $byPid=@{}
  foreach($record in @($snap.processes)){$byPid[[int]$record.pid]=$record}
  $ordered=@($snap.processes|ForEach-Object{
   $record=$_;$depth=0;$parent=[int]$record.parent_pid;$visited=New-Object 'System.Collections.Generic.HashSet[int]'
   while($byPid.ContainsKey($parent) -and $visited.Add($parent)){$depth++;$parent=[int]$byPid[$parent].parent_pid}
   [PSCustomObject]@{record=$record;depth=$depth}
  }|Sort-Object depth -Descending)
  foreach($item in $ordered){
   $record=$item.record
   $current=Get-CimInstance Win32_Process -Filter ("ProcessId = "+$record.pid)
   if($current -and $current.CreationDate.ToUniversalTime().ToString('o') -eq $record.creation_utc){
    Stop-Process -Id $record.pid -Force -ErrorAction SilentlyContinue
   }
  }
 }
 $remainingMs=($deadline-[DateTime]::UtcNow).TotalMilliseconds
 $sleepMs=if($remainingMs -gt 0){[int][Math]::Min(1000,[Math]::Max(1,$remainingMs))}else{1000}
 Start-Sleep -Milliseconds $sleepMs
}
try{$launcher.WaitForExit()}catch{}
$launcher.Refresh()
$exitCode=[int]$launcher.ExitCode
$endUtc=[DateTime]::UtcNow
$treeClosed=$snap.timestamp_utc
$summaryObj=[PSCustomObject]@{
 stage=$Stage
 attempt=$attempt
 source=$sourcePath
 root_pid=$rootPid
 root_creation_utc=$rootCreation
 start_utc=$startUtc.ToString('o')
 end_utc=$endUtc.ToString('o')
 launcher_exit_code=$exitCode
 timed_out=$timedOut
 absolute_deadline_utc=$absoluteDeadline.ToString('o')
 effective_deadline_utc=$deadline.ToString('o')
 stage_hard_seconds=$HardSeconds
 stable_empty_scans=$stableEmpty
 cancellation_passes=$cancellationPasses
 initial_free_physical_kib=$freeStart
 minimum_sampled_free_physical_kib=$minFree
 initial_memory=$memoryStart
 minimum_sampled_commit_headroom_bytes=$minimumCommitHeadroom
 memory_policy='12GiB advisory only; no memory-estimate auto-kill; Luna reviews actual paging, commit headroom, tool progress and full owned tree'
 tree_closed_utc=$treeClosed
 tree_record='process_tree.jsonl'
 seen_identities=@($seen.Values|Sort-Object pid,creation_utc)
}
[System.IO.File]::WriteAllText($summary,(($summaryObj|ConvertTo-Json -Depth 12)),$utf8)
Write-Output ($Stage+'_exit_code='+$exitCode)
Write-Output ($Stage+'_end_utc='+$endUtc.ToString('o'))
Write-Output ($Stage+'_tree_closed_utc='+$treeClosed)
if($timedOut -or -not $treeClosed){exit 3}
exit $exitCode