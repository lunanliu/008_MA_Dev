$ErrorActionPreference='Stop'
$root='D:/008_MA_Dev/Sync_OTA'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools/monitor_ota004_a06r3.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Assert-OtaLaunchInput'},$true)
. ([scriptblock]::Create($fn.Extent.Text))
$entry=Join-Path $root 'tools/vivado/run_ota004_a06r3.tcl'
$attempt=Join-Path $root ('work/OTA004/report_a06r3_static-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $attempt|Out-Null
$tests=New-Object System.Collections.Generic.List[object]
Assert-OtaLaunchInput report $attempt $entry 2700|Out-Null
$tests.Add(@{name='initial_entry';result='PASS'})
function Reject {param([string]$Name,[string]$Stage='report',[string]$Dir=$attempt,[string]$Source=$entry,[int]$Seconds=2700)
 $denied=$false;try{Assert-OtaLaunchInput $Stage $Dir $Source $Seconds|Out-Null}catch{$denied=$true}
 if(-not $denied){throw ('unexpected acceptance '+$Name)}
 $tests.Add(@{name=$Name;result='EXPECTED_REJECTION'})
}
Reject synth_forbidden -Stage synth
Reject old_entry -Source ($entry.Replace('a06r3','a06r2'))
Reject outside_attempt -Dir 'D:/008_MA_Dev/report_a06r3'
Reject traversal -Dir ($attempt+'/../report_a06r3')
Reject injection -Source ($entry+';echo')
Reject excessive_budget -Seconds 2701
Reject zero_budget -Seconds 0
$repair=Join-Path $root ('work/OTA004/a06r3_repairs/static_'+[guid]::NewGuid().ToString('N'))
foreach($rel in @('tools/vivado/run_ota004_a06r3.tcl','tools/vivado/audit_ota004_a06r3_identity.tcl','tools/vivado/audit_ota004_a06r3_gray.tcl','tools/vivado/report_ota004_a06r3_timing.tcl','tools/verify_ota004_a06r3_report.py')){
 $dest=Join-Path $repair $rel;New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($dest))|Out-Null
 Copy-Item -LiteralPath (Join-Path $root $rel) -Destination $dest
}
$repairEntry=Join-Path $repair 'tools/vivado/run_ota004_a06r3.tcl'
Add-Content -LiteralPath $repairEntry -Value '# Offline fixture-only harmless execution revision, never executed.'
$r=Assert-OtaLaunchInput report $attempt $repairEntry 2700
if(-not $r.execution_revision -or $r.execution_files.Count -ne 5){throw 'repair identity not captured'}
$tests.Add(@{name='scoped_changed_execution_revision_accepted_and_hashed';result='PASS'})
Set-Content -LiteralPath (Join-Path $attempt 'static_only.txt') -Value 'Offline only, no native.'
Reject nonempty_attempt
@{status='A06R3_MONITOR_STATIC_PASS';checks=@($tests.ToArray());scope='AST-isolated preflight, initial and changed revision bundle, no native';fixture_attempt=$attempt;fixture_revision=$repair}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'reports/OTA004/A06R3_MONITOR_STATIC.json') -Encoding utf8
@{status='PASS';checks=$tests.Count}|ConvertTo-Json
