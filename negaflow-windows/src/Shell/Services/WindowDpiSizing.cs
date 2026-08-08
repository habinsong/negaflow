using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Windows.Graphics;

namespace Negaflow.Shell;

internal static class WindowDpiSizing
{
    private const double DefaultDpi = 96;

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
