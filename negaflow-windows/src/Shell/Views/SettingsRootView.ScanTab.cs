using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정의 스캔 탭과 워크플로 탭에서 macOS 에 있고 여기 없던 항목들입니다.
/// </summary>
public sealed partial class SettingsRootView
{
    private ScannerPluginCapabilities? scannerCapabilities;

    /// <summary>
    /// 스캐너가 보고한 성능을 보여 줍니다. **장치가 말한 것만** 적습니다 — 앱이 지어낸 값을
    /// 여기 두면 사용자는 그것을 장치의 사양으로 읽습니다.
    /// </summary>
    public void ShowScannerCapabilities(ScannerPluginCapabilities? capabilities)
    {
        scannerCapabilities = capabilities;
        BuildScannerTruth();
    }

    private void BuildScannerTruth()
    {
        if (ScannerTruthRows is null)
        {
            return;
        }
        ScannerTruthRows.Children.Clear();
        if (scannerCapabilities is not { } caps)
        {
            ScannerTruthEmpty.Visibility = Visibility.Visible;
            return;
        }
        ScannerTruthEmpty.Visibility = Visibility.Collapsed;

        AddTruthRow("resolution", Join(caps.ResolutionsDpi.Select(dpi => $"{dpi} dpi")));
        AddTruthRow("bitDepth", Join(caps.BitDepths.Select(bits => $"{bits}-bit")));
        AddTruthRow("scanMode", Join(caps.Modes));
        AddTruthRow("transparency", YesNo(caps.SupportsTransparency));
        AddTruthRow("filterInfrared", YesNo(caps.SupportsInfrared));
        AddTruthRow("scanPreview", YesNo(caps.SupportsPreview));
        if (caps.MaxScanWidthMm is { } width && caps.MaxScanHeightMm is { } height)
        {
            AddTruthRow(
                "scanArea",
                $"{width:0.#} × {height:0.#} mm",
                translateKey: false);
        }
    }

    /// <summary>
    /// 한 줄입니다. 이름은 리소스에서 오고, 값은 장치가 보고한 그대로입니다.
    /// </summary>
    private void AddTruthRow(string labelKey, string value, bool translateKey = true)
    {
        Grid row = new() { ColumnSpacing = 16 };
        row.ColumnDefinitions.Add(
            new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(230) });
        row.Children.Add(new TextBlock
        {
            Text = translateKey ? TryResource(labelKey) : labelKey,
            FontSize = 12,
            VerticalAlignment = VerticalAlignment.Center,
        });
        TextBlock right = new()
        {
            Text = value,
            FontSize = 12,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
                "TextFillColorSecondaryBrush"],
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        Grid.SetColumn(right, 1);
        row.Children.Add(right);
        ScannerTruthRows.Children.Add(row);
    }

    /// <summary>
    /// 이름이 리소스에 없으면 키를 그대로 씁니다. 성능 항목 하나 때문에 설정 창이 터지는 것이
    /// 더 나쁩니다.
    /// </summary>
    private static string TryResource(string key)
    {
        try
        {
            return AppResources.Get(key, "Text");
        }
        catch (InvalidOperationException)
        {
            return key;
        }
    }

    private static string Join<T>(IEnumerable<T> values)
    {
        string joined = string.Join(", ", values);
        return joined.Length == 0 ? "—" : joined;
    }

    private static string YesNo(bool value) =>
        AppResources.Get(value ? "selected" : "notSelected", "Value");

    private void LocalizeScanTab()
    {
        ScanRotationLabel.Text = AppResources.Get("settingsDefaultScanRotation", "Text");
        AutomationProperties.SetName(ScanRotationComboBox, ScanRotationLabel.Text);
        ScanRotationHelp.Text = AppResources.Get("settingsDefaultScanRotationHelp", "Text");
        ScanRotation0Item.Content = AppResources.Get("settingsRotation0", "Text");
        ScanRotation90Item.Content = AppResources.Get("settingsRotation90", "Text");
        ScanRotation180Item.Content = AppResources.Get("settingsRotation180", "Text");
        ScanRotation270Item.Content = AppResources.Get("settingsRotation270", "Text");
        ScannerTruthHeading.Text = AppResources.Get("settingsScannerTruth", "Text");
        ScannerTruthEmpty.Text = AppResources.Get("settingsScannerTruthNone", "Text");
        MicroSpecksHeading.Text = AppResources.Get("settingsMicroSpecksSection", "Text");
        MicroSpecksHelp.Text = AppResources.Get("settingsMicroSpecksHelp", "Text");
        SetSwitchHeader(AutoDefectMicroSpecksToggle, "developAutoDefect");
        SetSwitchHeader(GuidedDefectMicroSpecksToggle, "developGuidedDefect");
        BuildScannerTruth();
    }

    private static void SetSwitchHeader(ToggleSwitch toggle, string key)
    {
        string text = TryResource(key);
        toggle.Header = text;
        AutomationProperties.SetName(toggle, text);
    }

    private void OnScanRotationChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        workspaceState?.SetDefaultScanRotation(ScanRotationComboBox.SelectedIndex switch
        {
            1 => ImageRotation.Degrees90,
            2 => ImageRotation.Degrees180,
            3 => ImageRotation.Degrees270,
            _ => ImageRotation.Degrees0,
        });
    }

    private void OnAutoDefectMicroSpecksToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetAutoDefectMicroSpecks(AutoDefectMicroSpecksToggle.IsOn);
        }
    }

    private void OnGuidedDefectMicroSpecksToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetGuidedDefectMicroSpecks(GuidedDefectMicroSpecksToggle.IsOn);
        }
    }

    private void SynchronizeScanTab(ShellPreferences preferences)
    {
        ScanRotationComboBox.SelectedIndex = preferences.DefaultScanRotation switch
        {
            ImageRotation.Degrees90 => 1,
            ImageRotation.Degrees180 => 2,
            ImageRotation.Degrees270 => 3,
            _ => 0,
        };
        AutoDefectMicroSpecksToggle.IsOn = preferences.AutoDefectDetectsMicroSpecks;
        GuidedDefectMicroSpecksToggle.IsOn = preferences.GuidedDefectDetectsMicroSpecks;
    }
}
