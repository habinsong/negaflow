using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Negaflow.Shell;

/// <summary>
/// 플러그인 자식들을 앱의 수명에 묶습니다.
/// </summary>
/// <remarks>
/// <para>
/// <b>왜 필요한가</b> — 앱이 <b>강제로</b> 죽으면(작업 관리자, 개발 중 재기동, 크래시)
/// Windows 는 자식 프로세스를 같이 죽이지 않습니다. 그러면 플러그인의 자식 프로세스가 고아로 남아
/// USB 스캐너를 계속 물고, 그 다음 실행의 장치 탐색이 커널 I/O 에서 막혀 90초 시간 초과로
/// <b>"스캐너를 찾을 수 없음"</b> 이 됩니다. 실측으로 그 상태의 자식 프로세스는 30초
/// 넘게 CPU 0.2초, 스레드는 <c>Wait/Executive</c> 였고, 그 프로세스를 지우자마자 탐색이
/// 곧바로 끝났습니다.
/// </para>
/// <para>
/// 정상 경로(시간 초과·취소)는 이미 <c>Kill(entireProcessTree: true)</c> 로 정리합니다.
/// 여기서 막는 것은 <b>앱이 그 정리를 할 기회조차 없이 죽는 경우</b>입니다 —
/// <c>JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE</c> 는 커널이 대신 해 줍니다.
/// </para>
/// <para>
/// 잡을 못 만들거나 못 붙이면 <b>조용히 넘어갑니다.</b> 정리 장치 하나 때문에 스캔을 막지
/// 않습니다 - 그 경우 예전과 같은 동작으로 돌아갈 뿐입니다.
/// </para>
/// </remarks>
internal static class ScannerPluginJobObject
{
    private const int ExtendedLimitInformation = 9;
    private const uint LimitKillOnJobClose = 0x00002000;

    private static readonly Lock Gate = new();
    private static IntPtr handle = IntPtr.Zero;
    private static bool attempted;

    /// <summary>이 자식과 그 자손을 앱 수명에 묶습니다. 실패는 조용히 넘어갑니다.</summary>
    internal static void Bind(Process process)
    {
        ArgumentNullException.ThrowIfNull(process);
        IntPtr job = Handle();
        if (job == IntPtr.Zero)
        {
            return;
        }
        try
        {
            if (!AssignProcessToJobObject(job, process.Handle))
            {
                ScannerDiagnosticsLog.Write(
                    $"plugin job assign failed win32={Marshal.GetLastWin32Error()}");
            }
        }
        catch (Exception error) when (error is InvalidOperationException or Win32Exception)
        {
            // 프로세스가 벌써 끝났습니다. 묶을 것이 없습니다.
        }
    }

    private static IntPtr Handle()
    {
        lock (Gate)
        {
            if (attempted)
            {
                return handle;
            }
            attempted = true;
            IntPtr created = CreateJobObjectW(IntPtr.Zero, null);
            if (created == IntPtr.Zero)
            {
                ScannerDiagnosticsLog.Write(
                    $"plugin job create failed win32={Marshal.GetLastWin32Error()}");
                return IntPtr.Zero;
            }
            JobObjectExtendedLimitInformation information = default;
            information.BasicLimitInformation.LimitFlags = LimitKillOnJobClose;
            int size = Marshal.SizeOf<JobObjectExtendedLimitInformation>();
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(information, buffer, fDeleteOld: false);
                if (!SetInformationJobObject(
                        created, ExtendedLimitInformation, buffer, (uint)size))
                {
                    ScannerDiagnosticsLog.Write(
                        $"plugin job limit failed win32={Marshal.GetLastWin32Error()}");
                    _ = CloseHandle(created);
                    return IntPtr.Zero;
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
            handle = created;
            return handle;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectBasicLimitInformation
    {
        internal long PerProcessUserTimeLimit;
        internal long PerJobUserTimeLimit;
        internal uint LimitFlags;
        internal nuint MinimumWorkingSetSize;
        internal nuint MaximumWorkingSetSize;
        internal uint ActiveProcessLimit;
        internal nuint Affinity;
        internal uint PriorityClass;
        internal uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters
    {
        internal ulong ReadOperationCount;
        internal ulong WriteOperationCount;
        internal ulong OtherOperationCount;
        internal ulong ReadTransferCount;
        internal ulong WriteTransferCount;
        internal ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JobObjectExtendedLimitInformation
    {
        internal JobObjectBasicLimitInformation BasicLimitInformation;
        internal IoCounters IoInfo;
        internal nuint ProcessMemoryLimit;
        internal nuint JobMemoryLimit;
        internal nuint PeakProcessMemoryUsed;
        internal nuint PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateJobObjectW(IntPtr attributes, string? name);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetInformationJobObject(
        IntPtr job, int informationClass, IntPtr information, uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}
