using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace Negaflow.Shell;

internal static class WindowDpiSizing
{
    private const double DefaultDpi = 96;

    /// <summary>
    /// 창의 <b>내용 영역</b>을 이 크기로 맞춥니다.
    /// </summary>
    /// <remarks>
    /// <c>AppWindow.Resize</c> 는 제목 표시줄과 테두리까지 포함한 <b>바깥</b> 크기를 잡습니다.
    /// 우리가 넘기는 값은 macOS 의 <c>contentSize</c> 라 내용 크기이고, 그대로 <c>Resize</c> 에
    /// 넘기면 제목 표시줄 높이만큼 내용이 모자라 잘립니다 - "negaflow 에 관하여" 의 아이콘
    /// 윗부분이 잘리던 것이 그것입니다.
    /// </remarks>
    public static void ResizeClientToContent(Window window, double width, double height)
    {
        ArgumentNullException.ThrowIfNull(window);
        window.AppWindow.ResizeClient(LogicalToPhysical(window, width, height));
    }

    public static SizeInt32 LogicalToPhysical(Window window, double width, double height)
    {
        ArgumentNullException.ThrowIfNull(window);
        nint handle = WinRT.Interop.WindowNative.GetWindowHandle(window);
        uint dpi = GetDpiForWindow(handle);
        double scale = dpi == 0 ? 1 : dpi / DefaultDpi;
        return new SizeInt32(
            checked((int)Math.Round(width * scale)),
            checked((int)Math.Round(height * scale)));
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint windowHandle);
}
