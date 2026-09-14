param(
    [Parameter(Mandatory=$true)][string]$PackageRoot,
    [Parameter(Mandatory=$true)][string]$ExpectedManifestSha256,
    [string]$AttemptDir,
    [string]$PythonExe='C:\Python314\python.exe'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo='D:\007 Dev\OTA_RTL_0829'
$package=[IO.Path]::GetFullPath($PackageRoot)
$manifestPath=Join-Path $package 'manifest.json'
if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ne $ExpectedManifestSha256){throw 'Manifest identity mismatch'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
foreach($f in $manifest.files){
    $p=Join-Path $package $f.path
    if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $f.sha256){throw "Frozen input mismatch: $($f.path)"}
    if((Get-Item -LiteralPath $p).Length -ne $f.bytes){throw "Frozen input size mismatch: $($f.path)"}
}
$central=Get-Content -LiteralPath (Join-Path $repo 'reports/operations/single_task_control.json') -Raw | ConvertFrom-Json
if($central.active_task -ne 'T09' -or -not $central.new_launch_allowed){throw 'T09 admission is not active'}
if($central.pairs.T09.astra -ne '01a08299-4a14-7ef0-9000-50ec54cfdce2' -or
   $central.pairs.T09.luna -ne '01a08298-b5b6-79b3-b5b4-18b8ac68993a'){throw 'T09 fixed pairing mismatch'}
$inventory=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^(MATLAB|vivado|xsim|xelab|xvlog)\.exe$'} |
    Select-Object ProcessId,ParentProcessId,Name,CreationDate)
if($inventory.Count -gt 0){throw 'MATLAB/Vivado admission occupied; retain and diagnose without killing foreign processes'}
$executionRoot=[IO.Path]::GetFullPath((Join-Path $repo 'reports/t09/execution/T09_CLOSED002_rev02'))
if([string]::IsNullOrEmpty($AttemptDir)){
    $AttemptDir=Join-Path $executionRoot ('attempt_'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'_luna')
}
$attempt=[IO.Path]::GetFullPath($AttemptDir)
if(-not $attempt.StartsWith($executionRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Attempt directory must be inside T09_CLOSED002_rev02 execution root'
}
if(Test-Path -LiteralPath $attempt){throw 'Each attempt directory must be new'}
$null=New-Item -ItemType Directory -Path $attempt -Force
foreach($name in @('work','prefs','temp','results')){$null=New-Item -ItemType Directory -Path (Join-Path $attempt $name)}
$matlab='C:\Program Files\MATLAB\R2024a\bin\matlab.exe'
if(-not(Test-Path -LiteralPath $matlab)){throw 'Frozen MATLAB executable missing'}
$expr="addpath('"+$package.Replace('\','/').Replace("'","''")+"'); t09_closed002_rev02('"+
    $package.Replace('\','/').Replace("'","''")+"','"+
    (Join-Path $attempt 'results').Replace('\','/').Replace("'","''")+"');"
$supervisor=Join-Path $package 'private_job_supervisor_v2.py'
$argsList=@($supervisor,'--stage','matlab','--attempt-id',(Split-Path $attempt -Leaf),
    '--cwd',(Join-Path $attempt 'work'),'--stdout',(Join-Path $attempt 'matlab.stdout.log'),
    '--stderr',(Join-Path $attempt 'matlab.stderr.log'),'--snapshots',(Join-Path $attempt 'supervisor_snapshots.jsonl'),
    '--latest',(Join-Path $attempt 'supervisor_latest.json'),'--exit-record',(Join-Path $attempt 'supervisor_exit.json'),
    '--cancel-path',(Join-Path $attempt 'CANCEL_REQUESTED'),'--deadline-seconds','1500',
    '--snapshot-interval-seconds','10','--progress-path',(Join-Path $attempt 'results/progress.json'),
    '--execution-job-id','T09-CLOSED002-R02','--source-job-id','T09-CLOSED002-R02','--',
    $matlab,'-singleCompThread','-batch',$expr)
[ordered]@{job_id='T09-CLOSED002-R02';started_utc=[DateTime]::UtcNow.ToString('o');package=$package;
    manifest_sha256=$ExpectedManifestSha256;python=$PythonExe;supervisor_argv=$argsList;
    launch_inventory=$inventory;matlab_file_version=(Get-Item -LiteralPath $matlab).VersionInfo.FileVersion;
    expected_minutes=@(5,12);hard_seconds=1500;cancel_cleanup_max_seconds=60;
    resource_limit=@{matlab=1;vivado=0;planned_peak_memory_gib=8;output_budget_gib=1};
    supervisor_provenance='Exact-byte T08_009 accepted Job Object supervisor; legacy T08 schema labels retained';
    cancel_path=(Join-Path $attempt 'CANCEL_REQUESTED')} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $attempt 'launch_record.json') -Encoding utf8
$previous=@{prefs=$env:MATLAB_PREFDIR;temp=$env:TEMP;tmp=$env:TMP}
try{
    $env:MATLAB_PREFDIR=Join-Path $attempt 'prefs';$env:TEMP=Join-Path $attempt 'temp';$env:TMP=$env:TEMP
    & $PythonExe @argsList
    $code=$LASTEXITCODE
}finally{
    $env:MATLAB_PREFDIR=$previous.prefs;$env:TEMP=$previous.temp;$env:TMP=$previous.tmp
}
if(-not(Test-Path -LiteralPath (Join-Path $attempt 'supervisor_exit.json'))){throw 'Missing native exit/Job evidence'}
$exitRecord=Get-Content -LiteralPath (Join-Path $attempt 'supervisor_exit.json') -Raw | ConvertFrom-Json
$normal=($code -eq 0 -and $exitRecord.supervisor_returncode -eq 0)
$postCleanup=($code -eq 125 -and $exitRecord.supervisor_returncode -eq 125 -and $exitRecord.cancelled)
if((-not($normal -or $postCleanup)) -or $exitRecord.root.returncode -ne 0 -or $exitRecord.timed_out -or
    $null -ne $exitRecord.launch_error -or $null -ne $exitRecord.terminate_error -or
    $exitRecord.owned_active_processes_after -ne 0){throw "Native stage or owned Job did not complete: $attempt"}
$summaryPath=Join-Path $attempt 'results/summary.json'
if(-not(Test-Path -LiteralPath $summaryPath)){throw 'No mathematical summary'}
$summary=Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
if($summary.case_count -ne 3 -or $summary.admission_case_count -ne 4 -or $summary.T09_PASS){throw 'Completion structure or control mismatch'}
$caseFiles=@(Get-ChildItem -LiteralPath (Join-Path $attempt 'results') -Directory -Filter 'case_*')
if($caseFiles.Count -ne 3){throw 'Missing case directories'}
foreach($folder in $caseFiles){
    foreach($file in @('first_nodes.mat','first_resampled.mat','raw_input.mat','source_descriptor.mat','source_descriptor.json','input_identity.json','result.json')){
        if(-not(Test-Path -LiteralPath (Join-Path $folder.FullName $file))){throw 'Missing case evidence'}
    }
}
$records=@(Get-ChildItem -LiteralPath (Join-Path $attempt 'results') -File -Recurse | ForEach-Object {
    [ordered]@{path=[IO.Path]::GetRelativePath($attempt,$_.FullName);bytes=$_.Length;
        sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
$records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $attempt 'result_manifest.json') -Encoding utf8
[ordered]@{complete=$true;post_root_cleanup=$postCleanup;native_root_returncode=$exitRecord.root.returncode;status='PENDING_ASTRA_REVIEW';T09_PASS=$false;
    result_manifest_sha256=(Get-FileHash -LiteralPath (Join-Path $attempt 'result_manifest.json')).Hash;
    supervisor_exit_sha256=(Get-FileHash -LiteralPath (Join-Path $attempt 'supervisor_exit.json')).Hash;
    finished_utc=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $attempt 'COMPLETE.json') -Encoding utf8
Write-Output $attempt




