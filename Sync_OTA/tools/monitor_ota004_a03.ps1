param(
 [Parameter(Mandatory=$true)][string]$Stage,
 [Parameter(Mandatory=$true)][string]$Attempt,
 [Parameter(Mandatory=$true)][string]$Source,
 [int]$HardSeconds=1200
)
$root='D:/008_MA_Dev/Sync_OTA'
$attempt=[System.IO.Path]::GetFullPath($Attempt)
$sourcePath=[System.IO.Path]::GetFullPath($Source)
if(-not (Test-Path -Path $attempt -PathType Container)){throw ('attempt missing: '+$attempt)}
if(Test-Path -Path (Join-Path $attempt 'project')){throw ('project already exists: '+$attempt)}
if(-not (Test-Path -Path $sourcePath -PathType Leaf)){throw ('source missing: '+$sourcePath)}
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
$cmdLine="$vivado -mode batch -source $sourcePath -log $log -journal $journal -tclargs $Stage $attempt"
$launcher=Start-Process -FilePath 'C:/Windows/System32/cmd.exe' -ArgumentList @('/d','/c',$cmdLine) -WorkingDirectory $root -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
$rootPid=[int]$launcher.Id
$rootCreation=$null
$knownCreation=@{}
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
   $knownSame=($knownCreation.ContainsKey($procId) -and $knownCreation[$procId] -eq $pc)
   $parentOwned=$ids.Contains([int]$p.ParentProcessId)
   if(($knownSame -or $parentOwned) -and $ids.Add($procId)){$changed=$true}
  }
 }
 $records=@($all|Where-Object{$ids.Contains([int]$_.ProcessId)}|ForEach-Object{
  $c=$currentByPid[[int]$_.ProcessId]
  if(-not $knownCreation.ContainsKey([int]$_.ProcessId)){$knownCreation[[int]$_.ProcessId]=$c}
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
 if($launcher.HasExited){break}
 if($now -ge $deadline){
  $timedOut=$true
  Write-Output ($Stage+'_stage_timeout=true')
  $live=@(Get-CimInstance Win32_Process)
  foreach($record in @($snap.processes|Sort-Object pid -Descending)){
   $current=$live|Where-Object{[int]$_.ProcessId -eq $record.pid}|Select-Object -First 1
   if($current -and $current.CreationDate.ToUniversalTime().ToString('o') -eq $record.creation_utc -and [int]$current.ProcessId -ne $rootPid){Stop-Process -Id $record.pid -Force -ErrorAction SilentlyContinue}
  }
  break
 }
 Start-Sleep -Seconds 1
}
if($timedOut){
 if(-not $launcher.WaitForExit(10000)){
  $currentRoot=Get-CimInstance Win32_Process -Filter ("ProcessId = "+$rootPid)
  if($currentRoot -and $currentRoot.CreationDate.ToUniversalTime().ToString('o') -eq $rootCreation){Stop-Process -Id $rootPid -Force -ErrorAction SilentlyContinue}
 }
}else{try{$launcher.WaitForExit()}catch{}}
$launcher.Refresh()
$exitCode=[int]$launcher.ExitCode
$endUtc=[DateTime]::UtcNow
$treeClosed=$null
for($i=0;$i -lt 60;$i++){
 $snap=Get-TreeSnapshot -RootPid $rootPid
 Write-Record $snap
 if(@($snap.processes).Count -eq 0){$treeClosed=$snap.timestamp_utc;break}
 Start-Sleep -Seconds 1
}
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