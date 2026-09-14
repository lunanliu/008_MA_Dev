param([Parameter(Mandatory=$true)][string]$AttemptDir)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'));$attempt=[IO.Path]::GetFullPath($AttemptDir)
if(-not $attempt.StartsWith((Join-Path $repo 'work')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $attempt)){throw 'Fresh own work directory required'}
$admission=Get-Content -LiteralPath (Join-Path $repo 'docs/verification/NATIVE_ADMISSION.json') -Raw|ConvertFrom-Json
if($admission.job_id -ne 'T10_MIGRATE_GUI001' -or [DateTimeOffset]::UtcNow -ge [DateTimeOffset]::Parse($admission.admission_expires_utc)){throw 'Missing or expired exact admission'}
$job=Get-Content -LiteralPath (Join-Path $repo 'docs/verification/native_project/JOB.json') -Raw|ConvertFrom-Json
foreach($f in $job.inputs){if((Get-FileHash -LiteralPath (Join-Path $repo $f.path)).Hash -ne $f.sha256){throw ('Frozen input differs: '+$f.path)}}
$inventory=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '^(MATLAB|vivado|rdiArgs|xsim|xsimk|xelab|xvlog|xvhdl)\.exe$'}|Select-Object ProcessId,ParentProcessId,Name,CreationDate,CommandLine)
foreach($p in $inventory){if($p.Name -ne 'vivado.exe' -or $p.ProcessId -ne $admission.existing_foreign_vivado_pid){throw 'Unreviewed native process occupies resource; never modify it'}}
$free=([double](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024)/1GB
if($free -lt $admission.start_minimum_free_gib){throw 'Insufficient free memory'}
[void][IO.Directory]::CreateDirectory($attempt)
$source=@"
using System;using System.Runtime.InteropServices;using System.Text;
public sealed class NativeProjectJob:IDisposable {
 [StructLayout(LayoutKind.Sequential)]struct SI {public uint cb;public IntPtr a,b,c;public uint d,e,f,g,h,i,j,k;public ushort l,m;public IntPtr n,o,p,q;}
 [StructLayout(LayoutKind.Sequential)]struct PI {public IntPtr p,t;public uint pid,tid;}
 [StructLayout(LayoutKind.Sequential)]struct BASIC {public long a,b;public uint flags;public UIntPtr min,max;public uint limit;public UIntPtr affinity;public uint priority,schedule;}
 [StructLayout(LayoutKind.Sequential)]struct IO {public ulong a,b,c,d,e,f;}
 [StructLayout(LayoutKind.Sequential)]struct EXT {public BASIC basic;public IO io;public UIntPtr processMemory,jobMemory,peakProcess,peakJob;}
 [StructLayout(LayoutKind.Sequential)]struct ACCOUNT {public long a,b,c,d;public uint faults,total,active,terminated;}
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr CreateJobObject(IntPtr a,string b);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool SetInformationJobObject(IntPtr a,int b,ref EXT c,uint d);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool QueryInformationJobObject(IntPtr a,int b,IntPtr c,uint d,out uint e);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern bool CreateProcess(string a,StringBuilder b,IntPtr c,IntPtr d,bool e,uint f,IntPtr g,string h,ref SI i,out PI j);
 [DllImport("kernel32.dll",SetLastError=true)]static extern bool AssignProcessToJobObject(IntPtr a,IntPtr b);
 [DllImport("kernel32.dll")]static extern uint ResumeThread(IntPtr a);
 [DllImport("kernel32.dll")]static extern uint WaitForSingleObject(IntPtr a,uint b);
 [DllImport("kernel32.dll")]static extern bool GetExitCodeProcess(IntPtr a,out uint b);
 [DllImport("kernel32.dll")]static extern bool TerminateJobObject(IntPtr a,uint b);
 [DllImport("kernel32.dll")]static extern bool TerminateProcess(IntPtr a,uint b);
 [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr a);
 IntPtr job,process,thread;public uint RootPid;
 static Exception Error(string s){return new Exception(s+" WinError="+Marshal.GetLastWin32Error());}
 public NativeProjectJob(string cmd,string cwd){
  job=CreateJobObject(IntPtr.Zero,null);if(job==IntPtr.Zero)throw Error("CreateJob");
  EXT limit=new EXT();limit.basic.flags=0x2000;
  if(!SetInformationJobObject(job,9,ref limit,(uint)Marshal.SizeOf(typeof(EXT)))){CloseHandle(job);job=IntPtr.Zero;throw Error("SetJobLimits");}
  SI si=new SI();si.cb=(uint)Marshal.SizeOf(typeof(SI));PI pi;
  if(!CreateProcess(null,new StringBuilder(cmd),IntPtr.Zero,IntPtr.Zero,false,0x08000004,IntPtr.Zero,cwd,ref si,out pi)){CloseHandle(job);job=IntPtr.Zero;throw Error("CreateSuspended");}
  process=pi.p;thread=pi.t;RootPid=pi.pid;
  if(!AssignProcessToJobObject(job,process)){TerminateProcess(process,126);Dispose();throw Error("AssignJob");}
  if(ResumeThread(thread)==0xffffffff){TerminateJobObject(job,126);Dispose();throw Error("Resume");}
 }
 public int Active(){int size=Marshal.SizeOf(typeof(ACCOUNT));IntPtr p=Marshal.AllocHGlobal(size);try{uint n;if(!QueryInformationJobObject(job,1,p,(uint)size,out n))throw Error("QueryActive");return (int)((ACCOUNT)Marshal.PtrToStructure(p,typeof(ACCOUNT))).active;}finally{Marshal.FreeHGlobal(p);}}
 public long[] Pids(){int size=8+256*IntPtr.Size;IntPtr p=Marshal.AllocHGlobal(size);try{uint n;if(!QueryInformationJobObject(job,3,p,(uint)size,out n))throw Error("QueryPids");int count=Marshal.ReadInt32(p,4);if(count>256)throw new Exception("Too many owned processes");long[] ids=new long[count];for(int i=0;i<count;i++)ids[i]=Marshal.ReadIntPtr(p,8+i*IntPtr.Size).ToInt64();return ids;}finally{Marshal.FreeHGlobal(p);}}
 public bool RootExited(){return WaitForSingleObject(process,0)==0;}
 public int RootCode(){uint c;if(!GetExitCodeProcess(process,out c))throw Error("ExitCode");return unchecked((int)c);}
 public void Stop(uint code){if(!TerminateJobObject(job,code))throw Error("TerminateOwnedJob");}
 public void Dispose(){if(thread!=IntPtr.Zero){CloseHandle(thread);thread=IntPtr.Zero;}if(process!=IntPtr.Zero){CloseHandle(process);process=IntPtr.Zero;}if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}}
}
"@
Add-Type -TypeDefinition $source
$tool='C:/NIFPGA/programs/Vivado2021_1/bin/vivado.bat';$script=(Join-Path $repo 'docs/verification/native_project/native_project_check.tcl') -replace '\\','/';$ap=$attempt -replace '\\','/'
$command='cmd.exe /d /s /c ""'+$tool+'" -mode batch -source "'+$script+'" -log "'+$ap+'/vivado.log" -journal "'+$ap+'/vivado.jou" -tclargs "'+$ap+'""'
[ordered]@{job_id=$admission.job_id;started_utc=[DateTime]::UtcNow.ToString('o');command_line=$command;cwd=$attempt;inventory=$inventory;free_memory_gib=$free;hard_timeout_seconds=1200;owned_memory_budget_gib=4;foreign_pid_untouched=$admission.existing_foreign_vivado_pid;job_definition_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'docs/verification/native_project/JOB.json')).Hash;admission_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'docs/verification/NATIVE_ADMISSION.json')).Hash}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $attempt 'launch.json') -Encoding utf8
$owned=$null;$started=[Diagnostics.Stopwatch]::StartNew();$rootExitAt=$null;$timedout=$false;$cleanup=$false;$errorText=$null;$finalActive=-1;$rootCode=$null;$lastSnap=-10;$over=0;$reason=$null
try{
 $owned=[NativeProjectJob]::new($command,$attempt)
 while($true){
  $active=$owned.Active();$rootExited=$owned.RootExited()
  if($rootExited -and $null -eq $rootExitAt){$rootExitAt=$started.Elapsed.TotalSeconds}
  if($started.Elapsed.TotalSeconds-$lastSnap -ge 5){
   $members=@();$bytes=0L
   foreach($memberId in $owned.Pids()){try{$member=Get-Process -Id $memberId -ErrorAction Stop;$bytes+=$member.WorkingSet64;$members+=@{pid=$memberId;start=$member.StartTime.ToUniversalTime().ToString('o');name=$member.ProcessName;working_set=$member.WorkingSet64}}catch{}}
   [ordered]@{utc=[DateTime]::UtcNow.ToString('o');elapsed_s=$started.Elapsed.TotalSeconds;active=$active;root_pid=$owned.RootPid;root_exited=$rootExited;working_set=$bytes;members=$members}|ConvertTo-Json -Compress -Depth 6|Add-Content -LiteralPath (Join-Path $attempt 'job_snapshots.jsonl') -Encoding utf8
   $over=if($bytes -gt 4GB){$over+1}else{0};$lastSnap=$started.Elapsed.TotalSeconds
  }
  if($active -eq 0 -and $rootExited){$finalActive=0;$rootCode=$owned.RootCode();break}
  if($started.Elapsed.TotalSeconds -ge 1200){$timedout=$true;$reason='hard_timeout';$owned.Stop(124);break}
  if($over -ge 2){$reason='owned_memory_above4GiB';$owned.Stop(124);break}
  if($null -ne $rootExitAt -and $started.Elapsed.TotalSeconds-$rootExitAt -ge 5){$cleanup=$true;$reason='root_exit_child_cleanup';$owned.Stop(125);break}
  Start-Sleep -Milliseconds 500
 }
}catch{$errorText=$_.ToString();if($null -ne $owned){$owned.Stop(126)}}finally{
 if($null -ne $owned){
  $drain=[Diagnostics.Stopwatch]::StartNew()
  while($drain.Elapsed.TotalSeconds -lt 60){$finalActive=$owned.Active();if($finalActive -eq 0 -and $owned.RootExited()){$rootCode=$owned.RootCode();break};Start-Sleep -Milliseconds 250}
  $emptyUtc=if($finalActive -eq 0 -and $owned.RootExited()){[DateTime]::UtcNow.ToString('o')}else{$null}
  [ordered]@{ended_utc=[DateTime]::UtcNow.ToString('o');elapsed_seconds=$started.Elapsed.TotalSeconds;root_pid=$owned.RootPid;root_returncode=$rootCode;root_exited=$owned.RootExited();owned_active_after=$finalActive;job_empty_utc=$emptyUtc;timed_out=$timedout;post_root_cleanup=$cleanup;stop_reason=$reason;error=$errorText;foreign_pid_modified=$false}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $attempt 'owned_exit.json') -Encoding utf8
  $owned.Dispose()
 }
}
if($errorText -or $timedout -or $finalActive -ne 0 -or $rootCode -ne 0 -or ($reason -and -not $cleanup)){throw 'Native job failed; preserve evidence'}
$python='C:/Users/lunan/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $python -I -B -X utf8 (Join-Path $repo 'docs/verification/native_project/review_native_project.py') $attempt
if($LASTEXITCODE -ne 0){throw 'Native migration review failed; preserve computed project and inspect saved evidence'}
Write-Output ('NATIVE_REVIEW_COMPLETE '+$attempt)
