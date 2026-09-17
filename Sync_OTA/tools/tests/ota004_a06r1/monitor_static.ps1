$ErrorActionPreference='Stop'
$root='D:/008_MA_Dev/Sync_OTA'
$path=Join-Path $root 'tools/monitor_ota004_a06r1.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-OtaLaunchInput'},$true)
if(-not $fn){throw 'preflight function absent'}
. ([scriptblock]::Create($fn.Extent.Text))
$entry=Join-Path $root 'tools/vivado/run_ota004_a06r1.tcl'
$script:frozenHash=(Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant()
$script:badHash=$false
# Only the not-yet-frozen manifest is mocked. Paths, attributes, contents and
# actual entry hash use the real read-only PowerShell filesystem APIs.
function Get-Content {
 param([string]$LiteralPath,[switch]$Raw)
 if($LiteralPath -ne 'D:/008_MA_Dev/Sync_OTA/docs/jobs/OTA004_A06R1_source_lock.json'){throw 'unexpected read in static preflight fixture'}
 $hash=if($script:badHash){'00'*32}else{$script:frozenHash}
 @{files=@(@{path='tools/vivado/run_ota004_a06r1.tcl';sha256=$hash})}|ConvertTo-Json -Depth 5
}
$attempt=Join-Path $root ('work/OTA004/smoke_a06r1-static-'+[Guid]::NewGuid().ToString('N'))
# The actual permitted naming uses an underscore before a retry suffix.
$attempt=$attempt.Replace('smoke_a06r1-static-','smoke_a06r1_static-')
New-Item -ItemType Directory -Path $attempt | Out-Null
$checks=New-Object System.Collections.Generic.List[object]
$valid=Assert-OtaLaunchInput smoke $attempt $entry 2400
$checks.Add(@{name='valid_exact_entry_empty_direct_child';result='PASS'})
function Reject-Input {
 param([string]$Name,[string]$Stage='smoke',[string]$Dir=$attempt,[string]$Source=$entry,[int]$Seconds=2400)
 $rejected=$false;$reason=''
 try {Assert-OtaLaunchInput $Stage $Dir $Source $Seconds | Out-Null}catch{$rejected=$true;$reason=$_.Exception.Message}
 if(-not $rejected){throw ('unexpected acceptance: '+$Name)}
 $checks.Add(@{name=$Name;result='EXPECTED_REJECTION';reason=$reason})
}
Reject-Input 'stage_metachar' -Stage 'smoke&echo'
Reject-Input 'stage_unknown' -Stage 'prepare'
Reject-Input 'stage_wrong_case' -Stage 'SMOKE'
Reject-Input 'stage_path_mismatch' -Stage 'synth'
Reject-Input 'wrong_entry' -Source ($entry.Replace('_a06r1','_a06'))
Reject-Input 'source_command_separator' -Source ($entry+';echo')
Reject-Input 'attempt_command_separator' -Dir ($attempt+'&echo')
Reject-Input 'environment_expansion' -Dir ($attempt+'%PATH%')
Reject-Input 'attempt_outside_root' -Dir 'D:/008_MA_Dev/smoke_a06r1'
Reject-Input 'attempt_nested' -Dir ($attempt+'/smoke_a06r1')
Reject-Input 'path_traversal' -Dir ($attempt+'/../smoke_a06r1')
Reject-Input 'stage_budget_over_cap' -Seconds 2401
Reject-Input 'stage_budget_nonpositive' -Seconds 0
$script:badHash=$true
Reject-Input 'entry_hash_mismatch'
$script:badHash=$false
function Get-Item {
 param([string]$LiteralPath,[switch]$Force,[string]$ErrorAction)
 if($LiteralPath -eq $attempt.Replace('/','\')){return [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint}}
 Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
}
Reject-Input 'attempt_reparse_point'
Remove-Item Function:\Get-Item
Set-Content -LiteralPath (Join-Path $attempt 'static_fixture.txt') -Value 'Offline preflight fixture only; no native process launched.' -Encoding utf8
Reject-Input 'nonempty_attempt'
$result=@{status='A06R1_MONITOR_STATIC_TESTS_PASS';checks=@($checks.ToArray());fixture_directory=$attempt;native_processes_started=0;scope='AST and isolated preflight function only; frozen manifest and one reparse attribute are synthetic; process-tree runtime unchanged from A06'}
$out=Join-Path $root 'reports/OTA004/A06R1_MONITOR_STATIC_TESTS.json'
if(Test-Path -LiteralPath $out){throw 'preserve previous test receipt'}
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding utf8
@{status=$result.status;checks=$checks.Count}|ConvertTo-Json

