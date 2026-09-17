// DDR functional-job isolation. Prepared only; no process is launched by loading this type.
// Microsoft Job Objects: https://learn.microsoft.com/windows/win32/procthread/job-objects
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace DdrNativeGuard
{
    public sealed class ProcessIdentity
    {
        public uint Pid { get; private set; }
        public DateTime CreationTimeUtc { get; private set; }
        internal ProcessIdentity(uint pid, DateTime time) { Pid = pid; CreationTimeUtc = time; }
    }

    // One guard, one native root. All regular CreateProcess descendants stay in this job,
    // including descendants whose parent exits. No BREAKAWAY_OK flag is set.
    public sealed class DdrJobGuard : IDisposable
    {
        private SafeFileHandle job;
        private SafeFileHandle root;
        private bool started, disposed;
        private readonly Dictionary<string, ProcessIdentity> observed =
            new Dictionary<string, ProcessIdentity>();
        public uint RootPid { get; private set; }

        private DdrJobGuard() { }
        private static Win32Exception Error(string operation, int code)
        { return new Win32Exception(code, operation + " failed; Win32=" + code); }
        private void Check()
        { if (disposed) throw new ObjectDisposedException("DdrJobGuard"); }
        private void Record(uint pid, DateTime time)
        {
            string key = pid.ToString() + ":" + time.Ticks.ToString();
            if (!observed.ContainsKey(key)) observed.Add(key, new ProcessIdentity(pid, time));
        }

        public static DdrJobGuard Create()
        {
            DdrJobGuard guard = new DdrJobGuard();
            IntPtr raw = CreateJobObjectW(IntPtr.Zero, null);
            if (raw == IntPtr.Zero) throw Error("CreateJobObjectW", Marshal.GetLastWin32Error());
            guard.job = new SafeFileHandle(raw, true);
            try
            {
                EXTENDED_LIMIT info = new EXTENDED_LIMIT();
                info.BasicLimitInformation.LimitFlags = 0x00002000; // KILL_ON_JOB_CLOSE only
                if (!SetInformationJobObject(guard.job, 9, ref info, (uint)Marshal.SizeOf(typeof(EXTENDED_LIMIT))))
                    throw Error("SetInformationJobObject", Marshal.GetLastWin32Error());
                return guard;
            }
            catch { guard.Dispose(); throw; }
        }

        public void StartSuspendedThenAssignResume(string applicationPath, string commandLine, string workingDirectory)
        {
            Check();
            if (started) throw new InvalidOperationException("A guard accepts exactly one root.");
            if (String.IsNullOrWhiteSpace(applicationPath) || String.IsNullOrWhiteSpace(commandLine) ||
                String.IsNullOrWhiteSpace(workingDirectory))
                throw new ArgumentException("Explicit application, command line and working directory are required.");
            started = true;
            STARTUPINFO si = new STARTUPINFO();
            si.cb = (uint)Marshal.SizeOf(typeof(STARTUPINFO));
            si.dwFlags = 1; si.wShowWindow = 0; // STARTF_USESHOWWINDOW / SW_HIDE
            PROCESS_INFORMATION pi;
            bool created = CreateProcessW(applicationPath, new StringBuilder(commandLine),
                IntPtr.Zero, IntPtr.Zero, false, 0x08000004, IntPtr.Zero, workingDirectory, ref si, out pi);
            if (!created) throw Error("CreateProcessW(CREATE_SUSPENDED|CREATE_NO_WINDOW)", Marshal.GetLastWin32Error());
            root = new SafeFileHandle(pi.hProcess, true);
            RootPid = pi.dwProcessId;
            try
            {
                // No code in the new root has run: assign first, then release its initial thread.
                if (!AssignProcessToJobObject(job, root))
                    throw Error("AssignProcessToJobObject", Marshal.GetLastWin32Error());
                Record(RootPid, CreationTime(root));
                if (ResumeThread(pi.hThread) == UInt32.MaxValue)
                    throw Error("ResumeThread", Marshal.GetLastWin32Error());
            }
            catch (Exception original)
            {
                // Only the exact process HANDLE returned by our own CreateProcess is touched.
                bool terminated = TerminateProcess(root, 0xD001);
                int terminateError = terminated ? 0 : Marshal.GetLastWin32Error();
                uint waitResult = terminated ? WaitForSingleObject(root, 5000) : UInt32.MaxValue;
                Dispose(); // KILL_ON_JOB_CLOSE also covers the assigned case.
                if (!terminated || waitResult != 0)
                    throw new InvalidOperationException("Root setup failed; cleanup TerminateProcess error=" +
                        terminateError + ", wait=" + waitResult + ". Original: " + original.Message, original);
                throw;
            }
            finally { CloseHandle(pi.hThread); }
        }

        public uint[] GetLiveIds()
        {
            Check();
            int capacity = 64;
            while (true)
            {
                int bytes = checked(8 + capacity * IntPtr.Size);
                IntPtr buffer = Marshal.AllocHGlobal(bytes);
                try
                {
                    Marshal.WriteInt32(buffer, 0, 0); Marshal.WriteInt32(buffer, 4, 0);
                    uint length;
                    bool ok = QueryInformationJobObject(job, 3, buffer, (uint)bytes, out length);
                    int error = ok ? 0 : Marshal.GetLastWin32Error();
                    uint assigned = unchecked((uint)Marshal.ReadInt32(buffer, 0));
                    uint count = unchecked((uint)Marshal.ReadInt32(buffer, 4));
                    if (!ok && error != 234) throw Error("QueryInformationJobObject(ProcessIdList)", error);
                    if (!ok || assigned > count || count > (uint)capacity)
                    {
                        ulong next = Math.Max((ulong)capacity * 2, (ulong)assigned + 16);
                        if (next > 1048576) throw new InvalidOperationException("Unexpected process-list size.");
                        capacity = (int)next;
                        continue;
                    }
                    uint[] ids = new uint[count];
                    for (int i = 0; i < ids.Length; i++)
                        ids[i] = checked((uint)Marshal.ReadIntPtr(buffer, 8 + i * IntPtr.Size).ToInt64());
                    return ids;
                }
                finally { Marshal.FreeHGlobal(buffer); }
            }
        }

        public ProcessIdentity[] GetLiveProcesses()
        {
            Check();
            List<ProcessIdentity> live = new List<ProcessIdentity>();
            foreach (uint pid in GetLiveIds())
            {
                IntPtr raw = OpenProcess(0x1000, false, pid); // QUERY_LIMITED_INFORMATION
                if (raw == IntPtr.Zero)
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error == 87) continue; // exited between the job snapshot and OpenProcess
                    throw Error("OpenProcess(" + pid + ")", error);
                }
                using (SafeFileHandle handle = new SafeFileHandle(raw, true))
                {
                    bool member;
                    if (!IsProcessInJob(handle, job, out member))
                        throw Error("IsProcessInJob(" + pid + ")", Marshal.GetLastWin32Error());
                    if (!member) continue; // PID reused after snapshot: never label it ours.
                    DateTime time = CreationTime(handle);
                    ProcessIdentity identity = new ProcessIdentity(pid, time);
                    live.Add(identity); Record(pid, time);
                }
            }
            return live.ToArray();
        }

        public ProcessIdentity[] GetObservedProcesses()
        {
            ProcessIdentity[] items = new ProcessIdentity[observed.Count];
            observed.Values.CopyTo(items, 0);
            return items;
        }

        public int? GetRootExitCode()
        {
            Check();
            if (root == null) throw new InvalidOperationException("No native root was created.");
            uint wait = WaitForSingleObject(root, 0);
            if (wait == 258) return null;
            if (wait == UInt32.MaxValue) throw Error("WaitForSingleObject(root)", Marshal.GetLastWin32Error());
            if (wait != 0) throw new InvalidOperationException("Unexpected root wait status: " + wait);
            uint code;
            if (!GetExitCodeProcess(root, out code))
                throw Error("GetExitCodeProcess(root)", Marshal.GetLastWin32Error());
            return unchecked((int)code);
        }

        public void Kill(uint exitCode)
        {
            Check();
            if (!TerminateJobObject(job, exitCode))
                throw Error("TerminateJobObject(this job only)", Marshal.GetLastWin32Error());
            // Termination is asynchronous. Caller still polls GetLiveIds until empty three times.
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            // SafeFileHandle also releases the kernel handle on exceptional managed lifetime exits.
            if (job != null) job.Dispose();
            if (root != null) root.Dispose();
        }

        private static DateTime CreationTime(SafeFileHandle process)
        {
            FILETIME creation, exit, kernel, user;
            if (!GetProcessTimes(process, out creation, out exit, out kernel, out user))
                throw Error("GetProcessTimes", Marshal.GetLastWin32Error());
            long ticks = ((long)creation.High << 32) | creation.Low;
            return DateTime.FromFileTimeUtc(ticks);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME { public uint Low, High; }
        [StructLayout(LayoutKind.Sequential)]
        private struct BASIC_LIMIT
        {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct EXTENDED_LIMIT
        {
            public BASIC_LIMIT BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFO
        {
            public uint cb;
            public IntPtr lpReserved, lpDesktop, lpTitle;
            public uint dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public ushort wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION
        {
            public IntPtr hProcess, hThread;
            public uint dwProcessId, dwThreadId;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(SafeFileHandle job, int infoClass, ref EXTENDED_LIMIT info, uint length);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObject(SafeFileHandle job, int infoClass, IntPtr info, uint length, out uint returnLength);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(string application, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes, [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags, IntPtr environment, string currentDirectory, ref STARTUPINFO startup, out PROCESS_INFORMATION process);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(SafeFileHandle job, SafeFileHandle process);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(SafeFileHandle process, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(SafeFileHandle job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(SafeFileHandle handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(SafeFileHandle process, out uint code);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsProcessInJob(SafeFileHandle process, SafeFileHandle job, [MarshalAs(UnmanagedType.Bool)] out bool result);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessTimes(SafeFileHandle process, out FILETIME creation, out FILETIME exit, out FILETIME kernel, out FILETIME user);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
