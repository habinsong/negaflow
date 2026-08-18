using System.Runtime.InteropServices;

namespace Negaflow.Shell;

/// <summary>
/// 패키지 없이 exe 를 직접 실행한 두 번째 프로세스가 기존 창을 다시 보여 달라고
/// 보내는 숨은 창입니다. Windows App Runtime COM 이 없어도 FindWindow /
/// PostMessage 만으로 동작합니다.
/// </summary>
internal sealed class RestoreSignalWindow : IDisposable
{
    private const uint WmRestoreExisting = 0x0400;
    private readonly WndProc wndProc;
    private readonly Action onRestore;
    private nint classAtom;
    private nint handle;
    private bool disposed;

    private delegate nint WndProc(nint window, uint message, nint wParam, nint lParam);

    public RestoreSignalWindow(Action onRestore)
    {
        this.onRestore = onRestore;
        wndProc = HandleMessage;
        var windowClass = new WndClassExW
        {
            cbSize = (uint)Marshal.SizeOf<WndClassExW>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(wndProc),
            hInstance = GetModuleHandleW(null),
            lpszClassName = Program.RestoreWindowClass,
        };
        classAtom = RegisterClassExW(ref windowClass);
        if (classAtom == 0)
        {
            return;
        }

        handle = CreateWindowExW(
            0x08000080,
            Program.RestoreWindowClass,
            string.Empty,
            0x80000000,
            0,
            0,
            0,
            0,
            0,
            0,
            windowClass.hInstance,
            0);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        if (handle != 0)
        {
            _ = DestroyWindow(handle);
            handle = 0;
        }

        if (classAtom != 0)
        {
            _ = UnregisterClassW(Program.RestoreWindowClass, GetModuleHandleW(null));
            classAtom = 0;
        }
    }

    private nint HandleMessage(nint window, uint message, nint wParam, nint lParam)
    {
        if (message == WmRestoreExisting)
        {
            onRestore();
            return 0;
        }

        return DefWindowProcW(window, message, wParam, lParam);
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WndClassExW
    {
        public uint cbSize;
        public uint style;
        public nint lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public nint hInstance;
        public nint hIcon;
        public nint hCursor;
        public nint hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public nint hIconSm;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint RegisterClassExW(ref WndClassExW windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterClassW(string className, nint instance);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint CreateWindowExW(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint parameter);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(nint window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern nint DefWindowProcW(nint window, uint message, nint wParam, nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint GetModuleHandleW(string? moduleName);
}
