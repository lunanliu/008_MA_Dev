$ErrorActionPreference='Stop'
$sfoRoot='D:\008_MA_Dev\Sync_SFO'
$sfoAudit=Join-Path $sfoRoot 'docs\functional_review_20260915'
$sfoPrivate=Join-Path $sfoRoot 'work\FN01\project'
$sfoOut=Join-Path $sfoRoot 'reports\functional_review\FN01'
if((Test-Path -LiteralPath $sfoPrivate) -or (Test-Path -LiteralPath $sfoOut)){throw 'Existing attempt preserved; do not overwrite or repeat successful stages'}
$sfoManifest=Import-Csv -LiteralPath (Join-Path $sfoAudit 'current_input_manifest.csv')
foreach($sfoItem in $sfoManifest){
 $sfoSource=[IO.Path]::GetFullPath((Join-Path $sfoRoot $sfoItem.destination_relative))
 if(-not $sfoSource.StartsWith($sfoRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Source path escaped module'}
 if((Get-FileHash -LiteralPath $sfoSource).Hash -ne $sfoItem.destination_sha256){throw "Frozen source mismatch: $sfoSource"}
}
[IO.Directory]::CreateDirectory($sfoPrivate) | Out-Null
[IO.Directory]::CreateDirectory($sfoOut) | Out-Null
foreach($sfoItem in $sfoManifest){
 $sfoSource=Join-Path $sfoRoot $sfoItem.destination_relative
 $sfoDestination=[IO.Path]::GetFullPath((Join-Path $sfoPrivate $sfoItem.destination_relative))
 if(-not $sfoDestination.StartsWith($sfoPrivate+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escaped private project'}
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($sfoDestination)) | Out-Null
 Copy-Item -LiteralPath $sfoSource -Destination $sfoDestination
 if((Get-FileHash -LiteralPath $sfoDestination).Hash -ne $sfoItem.destination_sha256){throw "Private copy mismatch: $sfoDestination"}
}
Copy-Item -LiteralPath (Join-Path $sfoAudit 'current_input_manifest.csv') -Destination (Join-Path $sfoOut 'frozen_input_manifest.csv')
[ordered]@{state='PREPARED_NOT_STARTED';prepared_at=(Get-Date).ToString('o');files=$sfoManifest.Count;private_project=$sfoPrivate;output=$sfoOut} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sfoOut 'preparation.json') -Encoding utf8
