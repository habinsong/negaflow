using Microsoft.UI;
using Microsoft.UI.Windowing;
using Negaflow.Interop;
using Negaflow.Shell.Views;

namespace Negaflow.Shell.Services;

/// <summary>
/// 미리보기 캔버스의 화면 색관리입니다. 창이 놓인 모니터의 ICC 프로파일로 표를 만들어 두고,
/// 캔버스는 그리기 직전에 sRGB 화소를 그 표로 옮깁니다.
/// </summary>
/// <remarks>
/// <para>
/// Windows 는 Advanced Color(ACM·WCG·HDR)가 꺼져 있으면 앱 화소를 sRGB 로 보고 색관리 없이
/// 보냅니다. 광색역 모니터에서 미리보기가 과포화로 보이는 이유입니다(macOS 는 OS 가 화면
/// 프로파일로 옮깁니다). 켜져 있으면 OS 가 옮기고 <c>GetICMProfileW</c> 가 sRGB 를 돌려주므로
/// 표가 항등이 되어 아무것도 하지 않습니다 — 두 번 옮기는 일이 없습니다.
/// </para>
/// <para>
/// 옮기는 것은 <b>화면에 그리는 화소뿐</b>입니다. 캐시·히스토그램·썸네일·스포이드·내보내기는
/// sRGB 그대로입니다. XAML 로 그리는 바탕색·글자·필름 띠는 Windows 가 색관리하지 않는 UI
/// 요소라 그대로입니다.
/// </para>
/// <para>UI 스레드에서만 부릅니다.</para>
/// </remarks>
internal static class DisplayColorManagement
{
    // 프로파일을 바꾸는 일은 드뭅니다. 그리는 횟수마다 장치 문맥을 열지 않도록 이 간격으로만
    // 다시 묻습니다. 모니터가 바뀌면 바로 묻습니다.
    private const long RecheckMilliseconds = 2000;
    private const long MaximumProfileBytes = 16L * 1024 * 1024;

    private static nint window;
    private static nint monitor;
    private static string? profilePath;
    private static DateTime profileWritten;
    private static DisplayColorTransform? transform;
    private static long checkedAt = long.MinValue;

    /// <summary>표가 바뀌었습니다(다른 모니터, 바뀐 프로파일). 캔버스는 지금 그림을 다시 그립니다.</summary>
    internal static event EventHandler? Changed;

    internal static void AttachWindow(WindowId id)
    {
        window = Win32Interop.GetWindowFromWindowId(id);
        if (AppWindow.GetFromWindowId(id) is { } appWindow)
        {
            appWindow.Changed += OnWindowChanged;
        }
        Refresh(force: true);
    }

    /// <summary>
    /// 모니터 프로파일이나 Advanced Color(ACM·HDR) 전환 직후 창이 다시 활성화되었을 때 즉시
    /// 프로파일 변경 여부를 확인합니다. 바뀌지 않았으면 표를 다시 만들지 않습니다.
    /// </summary>
    internal static void RefreshNow() => Refresh(force: false);

    /// <summary>지금 그릴 화소에 걸 표입니다. null 이면 그대로 그립니다.</summary>
    internal static DisplayColorTransform? Current
    {
        get
        {
            if (Environment.TickCount64 - checkedAt >= RecheckMilliseconds)
            {
                Refresh(force: false);
            }
            return transform;
        }
    }

    /// <summary>
    /// 화면에 쓸 화소입니다. 표가 없으면 <paramref name="pixels"/> 그대로이고, 있으면
    /// <paramref name="scratch"/> 에 옮긴 값입니다. 원본 배열은 바꾸지 않습니다.
    /// </summary>
    internal static byte[] ForDisplay(byte[] pixels, int width, int height, ref byte[]? scratch)
    {
        if (Current is not { } active)
        {
            return pixels;
        }
        int bytes = width * height * 4;
        if (scratch is null || scratch.Length < bytes)
        {
            scratch = new byte[bytes];
        }
        return active.Apply(pixels, scratch, width, height) ? scratch : pixels;
    }

    /// <summary>부르는 쪽이 가진 배열을 제자리에서 옮깁니다.</summary>
    internal static void ApplyInPlace(byte[] pixels, int width, int height) =>
        _ = Current?.Apply(pixels, pixels, width, height);

    private static void OnWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        // 창을 끄는 동안 이벤트가 연달아 옵니다. 모니터 핸들만 보고, 바뀌었을 때만 프로파일을
        // 다시 읽습니다.
        if ((args.DidPositionChange || args.DidSizeChange) &&
            window != 0 &&
            MonitorColorProfile.Monitor(window) != monitor)
        {
            Refresh(force: false);
        }
    }

    private static void Refresh(bool force)
    {
        checkedAt = Environment.TickCount64;
        if (window == 0)
        {
            return;
        }
        nint currentMonitor = MonitorColorProfile.Monitor(window);
        string? path = MonitorColorProfile.Path(window);
        DateTime written = default;
        try
        {
            if (path is not null && File.Exists(path))
            {
                written = File.GetLastWriteTimeUtc(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            path = null;
        }
        if (!force &&
            currentMonitor == monitor &&
            string.Equals(path, profilePath, StringComparison.OrdinalIgnoreCase) &&
            written == profileWritten)
        {
            return;
        }
        monitor = currentMonitor;
        profilePath = path;
        profileWritten = written;

        DisplayColorTransform? next = null;
        if (path is not null)
        {
            try
            {
                FileInfo file = new(path);
                if (file.Exists && file.Length is >= 128 and <= MaximumProfileBytes)
                {
                    next = DisplayColorTransform.TryCreate(File.ReadAllBytes(path));
                }
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                next = null;
            }
        }
        DisplayColorTransform? previous = transform;
        transform = next;
        previous?.Dispose();
        if (previous is not null || next is not null)
        {
            Changed?.Invoke(null, EventArgs.Empty);
        }
    }
}
