param([string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
foreach($row in (Import-Csv -LiteralPath (Join-Path $ProjectRoot 'reports/design/SF001_files.csv'))){
 $p=Join-Path $ProjectRoot $row.path
 if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing $p"}
 if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.sha256){throw "Hash mismatch $p"}
}
if(@(& git -C $ProjectRoot remote).Count -ne 0){throw 'Unexpected remote'}
Write-Output 'SF001_FROZEN_FILES_PASS'
