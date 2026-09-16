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
$freeStart=[int64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
if($freeStart -lt 8388608){throw ('free memory below 8 GiB: '+$freeStart)}
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
  $record=[PSCustomObject]@{pid=[int]$_.ProcessId;parent_pid=[int]$_.ParentProcessId;name=$_.Name;creation_utc=$c;command_line=$_.CommandLine;working_set_bytes=if($_.WorkingSetSize){[int64]$_.WorkingSetSize}else{$null}}
  $seen[('{0}:{1}' -f $record.pid,$record.creation_utc)]=$record
  $record
 })
 $aggregateWorkingSet=[int64](($records | Measure-Object -Property working_set_bytes -Sum).Sum)
 $freeNow=[int64](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
 [PSCustomObject]@{timestamp_utc=[DateTime]::UtcNow.ToString('o');root_pid=$RootPid;root_alive=($records.pid -contains $RootPid);known_pid_count=$knownCreation.Count;aggregate_working_set_bytes=$aggregateWorkingSet;free_physical_kib=$freeNow;processes=$records}
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
while($true){
 $snap=Get-TreeSnapshot -RootPid $rootPid
 Write-Record $snap
 if($snap.free_physical_kib -lt $minFree){$minFree=$snap.free_physical_kib}
 $now=[DateTime]::UtcNow
 if(($now-$lastReport).TotalSeconds -ge 30){Write-Output ($Stage+'_elapsed_s='+[int]($now-$startUtc).TotalSeconds+' tree_count='+@($snap.processes).Count+' known_pid_count='+$snap.known_pid_count+' free_kib='+$snap.free_physical_kib);$lastReport=$now}
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