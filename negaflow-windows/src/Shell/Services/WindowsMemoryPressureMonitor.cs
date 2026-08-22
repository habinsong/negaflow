using Microsoft.Win32.SafeHandles;
using Negaflow.Shell.Library;
using System.Runtime.InteropServices;

namespace Negaflow.Shell.Services;

/// <summary>
/// Windows의 시스템 전체 low/high memory 알림을 캐시 압력 단계로 바꿉니다.
/// low에서 오래된 재생성 캐시를 내리고, high가 될 때까지 줄인 상태를 유지합니다.
/// </summary>
internal sealed class WindowsMemoryPressureMonitor : IDisposable
{
    private enum MemoryResourceNotificationType
    {
        Low = 0,
        High = 1,
    }

    private sealed class NativeNotificationHandle : WaitHandle
    {
        internal NativeNotificationHandle(IntPtr handle) =>
            SafeWaitHandle = new SafeWaitHandle(handle, ownsHandle: true);
    }

    private readonly NativeNotificationHandle low;
    private readonly NativeNotificationHandle high;
    private readonly ManualResetEvent stop = new(initialState: false);
    private readonly Action<FrameCachePressureLevel> onChanged;
    private readonly Task worker;

    private WindowsMemoryPressureMonitor(
        NativeNotificationHandle low,
        NativeNotificationHandle high,
        Action<FrameCachePressureLevel> onChanged)
    {
        this.low = low;
        this.high = high;
        this.onChanged = onChanged;
        worker = Task.Run(Run);
    }

    internal static WindowsMemoryPressureMonitor? TryStart(
        Action<FrameCachePressureLevel> onChanged)
    {
        ArgumentNullException.ThrowIfNull(onChanged);
        IntPtr lowHandle = CreateMemoryResourceNotification(MemoryResourceNotificationType.Low);
        if (lowHandle == IntPtr.Zero)
        {
            return null;
        }
        IntPtr highHandle = CreateMemoryResourceNotification(MemoryResourceNotificationType.High);
        if (highHandle == IntPtr.Zero)
        {
            _ = CloseHandle(lowHandle);
            return null;
        }
        return new WindowsMemoryPressureMonitor(
            new NativeNotificationHandle(lowHandle),
            new NativeNotificationHandle(highHandle),
            onChanged);
    }

    public void Dispose()
    {
        stop.Set();
        worker.GetAwaiter().GetResult();
        stop.Dispose();
        low.Dispose();
        high.Dispose();
    }

    private void Run()
    {
        bool critical = IsSignaled(low);
        onChanged(
            critical ? FrameCachePressureLevel.Critical : FrameCachePressureLevel.Normal);

        WaitHandle[] waits = new WaitHandle[2];
        while (true)
        {
            waits[0] = critical ? high : low;
            waits[1] = stop;
            if (WaitHandle.WaitAny(waits) == 1)
            {
                return;
            }
            critical = !critical;
            onChanged(
                critical ? FrameCachePressureLevel.Critical : FrameCachePressureLevel.Normal);
        }
    }

    private static bool IsSignaled(NativeNotificationHandle notification) =>
        QueryMemoryResourceNotification(
            notification.SafeWaitHandle.DangerousGetHandle(),
            out bool signaled) && signaled;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateMemoryResourceNotification(
        MemoryResourceNotificationType notificationType);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryMemoryResourceNotification(
        IntPtr resourceNotificationHandle,
        [MarshalAs(UnmanagedType.Bool)] out bool resourceState);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
}
