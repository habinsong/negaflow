using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class StatusBarView : UserControl
{
    public StatusBarView()
    {
        InitializeComponent();
        Localize();
    }

    /// <summary>언어가 바뀌면 다시 겁니다. x:Uid 는 읽을 때 한 번만 풀리기 때문입니다.</summary>
    public void Localize()
    {
        SortInputOrderLocalized.Text = AppResources.Get("sortInputOrder", "Text");
        LibraryAllShortLocalized.Text = AppResources.Get("libraryAllShort", "Text");
    }

    public void Initialize(NativeEngineStatus status)
    {
        ArgumentNullException.ThrowIfNull(status);
        StateText.Text = AppResources.Get(
            status.IsAvailable ? "idleStatus" : "capabilityUnavailable",
            "Value");
        StateDetail.Text = status.Detail;
        StateIndicator.Fill = new SolidColorBrush(
            status.IsAvailable ? Microsoft.UI.Colors.LimeGreen : Microsoft.UI.Colors.OrangeRed);
    }
}
