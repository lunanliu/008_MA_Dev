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
$executionRoot=[IO.Path]::GetFullPath((Join-Path $repo 'reports/t09/execution/T09_FIXED007'))
if([string]::IsNullOrEmpty($AttemptDir)){
    $AttemptDir=Join-Path $executionRoot ('attempt_'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'_luna')
}
$attempt=[IO.Path]::GetFullPath($AttemptDir)
if(-not $attempt.StartsWith($executionRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Attempt directory must be inside T09_FIXED007 execution root'
}
if(Test-Path -LiteralPath $attempt){throw 'Each attempt directory must be new'}
$null=New-Item -ItemType Directory -Path $attempt -Force
foreach($name in @('work','prefs','temp')){$null=New-Item -ItemType Directory -Path (Join-Path $attempt $name)}
$modelPython='C:\Users\lunan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if(-not(Test-Path -LiteralPath $modelPython)){throw 'Frozen model Python missing'}
$supervisor=Join-Path $package 'private_job_supervisor_t09_v3.py'
# Reuse the complete successful probe; supervisor bytes are unchanged and manifest-bound.
$priorProbe=Get-Content -LiteralPath (Join-Path $package 'evidence/accepted_wrapper_probe_exit.json') -Raw | ConvertFrom-Json
if($priorProbe.root.returncode -ne 0 -or $priorProbe.supervisor_returncode -ne 125 -or
   -not $priorProbe.post_root_cleanup_automatic -or $priorProbe.owned_active_processes_after -ne 0 -or
   $priorProbe.root_to_job_empty_seconds -gt 15 -or $priorProbe.timed_out){
    throw 'Frozen prior automatic-cleanup probe is not accepted'
}
$argsList=@($supervisor,'--stage','official_cmodel','--attempt-id',(Split-Path $attempt -Leaf),
    '--cwd',(Join-Path $attempt 'work'),'--stdout',(Join-Path $attempt 'model.stdout.log'),
    '--stderr',(Join-Path $attempt 'model.stderr.log'),'--snapshots',(Join-Path $attempt 'supervisor_snapshots.jsonl'),
    '--latest',(Join-Path $attempt 'supervisor_latest.json'),'--exit-record',(Join-Path $attempt 'supervisor_exit.json'),
    '--cancel-path',(Join-Path $attempt 'CANCEL_REQUESTED'),'--deadline-seconds','1200',
    '--root-exit-grace-seconds','5','--snapshot-interval-seconds','10','--progress-path',(Join-Path $attempt 'results/progress.json'),
    '--execution-job-id','T09-FIXED007','--source-job-id','T09-FIXED007','--',
    $modelPython,(Join-Path $package 't09_fixed007.py'),'--package',$package,'--output',(Join-Path $attempt 'results'))
[ordered]@{job_id='T09-FIXED007';started_utc=[DateTime]::UtcNow.ToString('o');package=$package;
    manifest_sha256=$ExpectedManifestSha256;python=$PythonExe;supervisor_argv=$argsList;
    launch_inventory=$inventory;model_python=$modelPython;model_python_sha256=(Get-FileHash -LiteralPath $modelPython).Hash;
    expected_minutes=@(3,10);hard_seconds=1200;cancel_cleanup_max_seconds=60;
    resource_limit=@{python_cmodel=1;matlab=0;vivado=0;planned_peak_memory_gib=2;output_budget_gib=0.5};
    supervisor_provenance='Derived from accepted T08 Job supervisor; T09 v3 adds automatic cleanup 5s after native root exit; unchanged supervisor bytes reuse accepted isolated probe; no redundant probe execution';
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
if($summary.case_count -ne 9 -or $summary.branch_count -ne 2 -or $summary.T09_PASS){throw 'Completion structure or control mismatch'}
$caseFiles=@(Get-ChildItem -LiteralPath (Join-Path $attempt 'results') -Directory -Filter 'case_*')
if($caseFiles.Count -ne 9){throw 'Missing case directories'}
foreach($folder in $caseFiles){
    foreach($file in @('integer_nodes.npz','result.json')){
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




