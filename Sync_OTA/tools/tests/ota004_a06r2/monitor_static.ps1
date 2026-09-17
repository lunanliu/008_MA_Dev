$ErrorActionPreference='Stop'
$root='D:/008_MA_Dev/Sync_OTA'
$monitor=Join-Path $root 'tools/monitor_ota004_a06r2.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($monitor,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-OtaLaunchInput'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$entry=Join-Path $root 'tools/vivado/run_ota004_a06r2.tcl'
$script:hash=(Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant()
function Get-Content {
 param([string]$LiteralPath,[switch]$Raw)
 if($LiteralPath -ne 'D:/008_MA_Dev/Sync_OTA/docs/jobs/OTA004_A06R2_source_lock.json'){throw 'unexpected fixture read'}
 @{files=@(@{path='tools/vivado/run_ota004_a06r2.tcl';sha256=$script:hash})}|ConvertTo-Json -Depth 4
}
$attempt=Join-Path $root ('work/OTA004/report_a06r2_static-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $attempt|Out-Null
$tests=New-Object System.Collections.Generic.List[object]
Assert-OtaLaunchInput report $attempt $entry 1800|Out-Null
$tests.Add(@{name='report_exact_entry_empty_attempt';result='PASS'})
function Reject {
 param([string]$Name,[string]$Stage='report',[string]$Dir=$attempt,[string]$Source=$entry,[int]$Seconds=1800)
 $denied=$false
 try{Assert-OtaLaunchInput $Stage $Dir $Source $Seconds|Out-Null}catch{$denied=$true}
 if(-not $denied){throw ('unexpected acceptance '+$Name)}
 $tests.Add(@{name=$Name;result='EXPECTED_REJECTION'})
}
Reject smoke_forbidden -Stage smoke
Reject synth_forbidden -Stage synth
Reject stage_injection -Stage 'report&echo'
Reject old_entry -Source ($entry.Replace('a06r2','a06r1'))
Reject source_injection -Source ($entry+';echo')
Reject outside_attempt -Dir 'D:/008_MA_Dev/report_a06r2'
Reject nested_attempt -Dir ($attempt+'/report_a06r2')
Reject traversal -Dir ($attempt+'/../report_a06r2')
Reject too_long -Seconds 1801
Reject invalid_budget -Seconds 0
$script:hash='00'*32
Reject wrong_hash
$script:hash=(Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath (Join-Path $attempt 'static_only.txt') -Value 'Offline fixture only; no native started.'
Reject nonempty_attempt
@{status='A06R2_MONITOR_STATIC_PASS';checks=@($tests.ToArray());scope='AST and preflight function; manifest fixture only; no native launched';fixture_attempt=$attempt}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'reports/OTA004/A06R2_MONITOR_STATIC.json') -Encoding utf8
@{checks=$tests.Count;status='PASS'}|ConvertTo-Json

