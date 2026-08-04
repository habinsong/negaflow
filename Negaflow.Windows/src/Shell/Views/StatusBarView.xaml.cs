using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class StatusBarView : UserControl
{
    public StatusBarView()
    {
        InitializeComponent();
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
