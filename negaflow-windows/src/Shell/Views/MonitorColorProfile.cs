using System.Runtime.InteropServices;
using System.Text;

namespace Negaflow.Shell.Views;

/// <summary>
/// 지금 창이 놓인 화면의 색 프로파일 이름입니다.
/// </summary>
/// <remarks>
/// macOS 는 <c>NSScreen.main?.colorSpace?.localizedName</c> 을 냅니다
/// (<c>ColorManagementSettingsSection.swift:114-117</c>). Windows 에는 그와 같은
/// "색 공간의 이름" API 가 없고, 대신 화면에 걸린 ICC 프로파일 파일을 알려 주는
/// <c>GetICMProfileW</c> 가 있습니다. 그래서 그 파일 이름(확장자 제외)을 씁니다 —
/// 지어낸 값이 아니라 시스템이 실제로 쓰는 프로파일입니다.
/// 못 읽으면 macOS 와 같은 자리에 대체 문구를 냅니다.
/// </remarks>
internal static class MonitorColorProfile
{
    private const uint MonitorDefaultToPrimary = 1;

    /// <summary>프로파일 이름입니다. 못 읽으면 null 입니다.</summary>
    internal static string? Name(nint windowHandle)
    {
        nint monitor = MonitorFromWindow(windowHandle, MonitorDefaultToPrimary);
        MonitorInfoEx info = new() { Size = Marshal.SizeOf<MonitorInfoEx>() };
        if (monitor == 0 || !GetMonitorInfo(monitor, ref info))
        {
            return null;
        }

        nint deviceContext = CreateDC(null, info.DeviceName, null, 0);
        if (deviceContext == 0)
        {
            return null;
        }

        try
        {
            uint length = 0;
            // 첫 호출은 길이만 받습니다. 성공을 돌려주지 않는 것이 정상입니다.
            _ = GetICMProfile(deviceContext, ref length, null);
            if (length == 0 || length > 4096)
            {
                return null;
            }
            StringBuilder path = new((int)length);
            if (!GetICMProfile(deviceContext, ref length, path))
            {
                return null;
            }
            string file = path.ToString();
            return string.IsNullOrWhiteSpace(file)
                ? null
                : Path.GetFileNameWithoutExtension(file);
        }
        finally
        {
            _ = DeleteDC(deviceContext);
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MonitorInfoEx
    {
        public int Size;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string DeviceName;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    private static extern nint MonitorFromWindow(nint window, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetMonitorInfoW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfoEx info);

    [DllImport("gdi32.dll", EntryPoint = "CreateDCW", CharSet = CharSet.Unicode)]
    private static extern nint CreateDC(
        string? driver,
        string device,
        string? output,
        nint initializationData);

    [DllImport("gdi32.dll", EntryPoint = "GetICMProfileW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetICMProfile(
        nint deviceContext,
        ref uint bufferLength,
        StringBuilder? buffer);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DeleteDC(nint deviceContext);
}
