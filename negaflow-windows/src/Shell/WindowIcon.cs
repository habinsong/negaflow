using Microsoft.UI.Windowing;

namespace Negaflow.Shell;

internal static class WindowIcon
{
    public static void Apply(AppWindow appWindow)
    {
        string iconPath = Path.Combine(AppContext.BaseDirectory, "Negaflow.ico");
        if (File.Exists(iconPath))
        {
            appWindow.SetIcon(iconPath);
        }
    }
}
