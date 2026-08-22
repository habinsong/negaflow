using System.Globalization;
using Microsoft.UI.Xaml;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Storage;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정창 "내보내기" 탭입니다. macOS <c>AppSettingsView.exportPane</c> +
/// <c>ColorManagementSettingsSection</c> 자리입니다.
/// </summary>
public sealed partial class SettingsRootView
{
    private void InitializeExportTab()
    {
        ExportPage.QuickExportFormatPicker.SelectionChanged += OnQuickExportFormatChanged;
        ExportPage.ExportVerificationPicker.SelectionChanged += OnExportVerificationChanged;
        ExportPage.SoftProofRow.Switched += OnSoftProofSwitched;
        ExportPage.GamutWarningRow.Switched += OnGamutWarningSwitched;
        BuildQuickExportChoices();
    }

    /// <summary>
    /// DPI·크기 목록입니다. macOS 와 <b>같은 값</b>이며 그 자리는
    /// <see cref="ExportSettings.DpiOptions"/> · <see cref="ExportSettings.LongEdgeOptions"/> 입니다.
    /// </summary>
    private void BuildQuickExportChoices()
    {
        ExportPage.QuickExportDpiComboBox.Items.Clear();
        foreach (int dpi in ExportSettings.DpiOptions)
        {
            ExportPage.QuickExportDpiComboBox.Items.Add(dpi == 0
                ? AppResources.Get("settingsSourceDPI", "Text")
                : string.Create(CultureInfo.CurrentCulture, $"{dpi} dpi"));
        }
        ExportPage.QuickExportSizeComboBox.Items.Clear();
        string suffix = AppResources.Get("exportLongEdgeSuffix", "Text");
        foreach (int edge in ExportSettings.LongEdgeOptions)
        {
            ExportPage.QuickExportSizeComboBox.Items.Add(edge == 0
                ? AppResources.Get("exportFullSize", "Text")
                : string.Create(CultureInfo.CurrentCulture, $"{edge} {suffix}"));
        }
    }

    private void LocalizeExportTab()
    {
        ExportPage.QuickExportSection.HeaderText = AppResources.Get("quickExportSection", "Text");
        ExportPage.QuickExportFormatRow.Label = AppResources.Get("settingsQuickExportFormat", "Text");
        ExportPage.QuickExportFormatPicker.SetOptions(
            [
                new SegmentOption(DevelopExportFormat.Jpeg8, "JPEG"),
                new SegmentOption(DevelopExportFormat.Png16, "PNG"),
            ],
            ExportPage.QuickExportFormatPicker.SelectedValue ?? DevelopExportFormat.Jpeg8);
        ExportPage.QuickExportDpiRow.Label = AppResources.Get("settingsQuickExportDPI", "Text");
        ExportPage.QuickExportSizeRow.Label = AppResources.Get("settingsQuickExportSize", "Text");
        ExportPage.QuickExportFolderRow.Label = AppResources.Get("settingsQuickExportFolder", "Text");
        BuildQuickExportChoices();

        string verification = AppResources.Get("settingsExportVerification", "Text");
        ExportPage.ExportVerificationSection.HeaderText = verification;
        ExportPage.ExportVerificationRow.Label = verification;
        ExportPage.ExportVerificationPicker.SetOptions(
            [
                new SegmentOption(
                    ImageContentHashMode.Off,
                    AppResources.Get("settingsExportVerificationStandard", "Content")),
                new SegmentOption(
                    ImageContentHashMode.Sha256,
                    AppResources.Get("settingsExportVerificationStrict", "Content")),
            ],
            ExportPage.ExportVerificationPicker.SelectedValue ?? ImageContentHashMode.Off);
        ExportPage.ExportVerificationHelp.Text =
            AppResources.Get("settingsExportVerificationHelp", "Text");

        ExportPage.ColorManagementSection.HeaderText =
            AppResources.Get("settingsColorManagementSection", "Text");
        ExportPage.ExportColorRow.Label = AppResources.Get("settingsExportColorLabel", "Text");
        ExportPage.SoftProofRow.Label = AppResources.Get("settingsExportSoftProofLabel", "Text");
        ExportPage.SoftProofProfileRow.Label = AppResources.Get("settingsColorProfile", "Text");
        ExportPage.SoftProofChooseProfileButton.Content =
            AppResources.Get("developExportChangeFolder", "Content");
        ExportPage.SoftProofProfileError.Text = AppResources.Get("softProofInvalidICC", "Text");
        ExportPage.SoftProofSimulationRow.Label = AppResources.Get("settingsExportProofLabel", "Text");
        ExportPage.SettingsSoftProofProfileOnlyLocalized.Content =
            AppResources.Get("settingsSoftProofProfileOnly", "Content");
        ExportPage.SettingsSoftProofPaperAndBlackLocalized.Content =
            AppResources.Get("settingsSoftProofPaperAndBlack", "Content");
        ExportPage.GamutWarningRow.Label = AppResources.Get("settingsColorGamutWarning", "Text");
        ExportPage.GamutUnavailableReason.Text =
            AppResources.Get("settingsColorGamutUnavailableReason", "Text");
        ExportPage.PrinterProfileRow.Label = AppResources.Get("settingsColorPrinterProfile", "Text");
        ExportPage.PrinterProfileButton.Content = AppResources.Get("developExportChangeFolder", "Content");
        ExportPage.PrinterProfileError.Text = AppResources.Get("softProofInvalidICC", "Text");
        ExportPage.ScannerEmulationRow.Label = AppResources.Get("settingsColorScannerInput", "Text");
        ExportPage.ColorWorkingRow.Label = AppResources.Get("settingsColorWorking", "Text");
        ExportPage.ColorMonitorRow.Label = AppResources.Get("settingsColorMonitor", "Text");
        ExportPage.ColorExportRow.Label = AppResources.Get("settingsColorExport", "Text");
        ExportPage.ColorSoftProofRow.Label = AppResources.Get("settingsColorSoftProof", "Text");
        string reset = AppResources.Get("developTabReset", "Value");
        ExportPage.SoftProofResetProfileButton.Content = reset;
        ExportPage.PrinterProfileResetButton.Content = reset;
    }

    private void SynchronizeExportTab(ShellPreferences preferences)
    {
        QuickExportSettings quick = preferences.QuickExport;
        ExportPage.QuickExportFormatPicker.SetSelected(quick.Format);
        ExportPage.QuickExportDpiComboBox.SelectedIndex =
            Math.Max(0, ExportSettings.DpiOptions.ToList().IndexOf(quick.Dpi));
        ExportPage.QuickExportSizeComboBox.SelectedIndex =
            Math.Max(0, ExportSettings.LongEdgeOptions.ToList().IndexOf(quick.LongEdge));
        // macOS 는 폴더 이름만 냅니다("Quick Export"). 전체 경로는 디스크 탭에 있습니다.
        ExportPage.QuickExportFolderRow.ValueText =
            Path.GetFileName(preferences.ResolvedQuickExport.FolderPath);

        ExportPage.ExportVerificationPicker.SetSelected(preferences.ImageContentHash);

        ExportPage.ExportColorSpaceComboBox.SelectedIndex = preferences.Export.ColorSpace switch
        {
            ExportColorSpace.DisplayP3 => 1,
            ExportColorSpace.AdobeRgb => 2,
            _ => 0,
        };

        SoftProofPreferences proof = preferences.SoftProof;
        ExportPage.SoftProofRow.IsOn = proof.IsEnabled;
        // macOS 는 프루프가 꺼져 있으면 아래 줄들을 아예 그리지 않습니다.
        Visibility proofRows = proof.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
        ExportPage.SoftProofProfileRow.Visibility = proofRows;
        ExportPage.SoftProofSimulationRow.Visibility = proofRows;
        ExportPage.GamutWarningRow.Visibility = proofRows;
        ExportPage.SoftProofSimulationComboBox.SelectedIndex =
            proof.Simulation == SoftProofSimulation.PaperAndBlackInk ? 1 : 0;

        bool gamutAvailable = NativeGamutCheck.IsSupported(preferences.Export.EffectiveColorSpace);
        ExportPage.GamutWarningRow.IsEnabled = gamutAvailable;
        ExportPage.GamutUnavailableReason.Visibility = proof.IsEnabled && !gamutAvailable
            ? Visibility.Visible
            : Visibility.Collapsed;
        ExportPage.GamutWarningRow.IsOn = gamutAvailable && proof.GamutWarningEnabled;

        string profileName = proof.ProfileName.Length != 0
            ? proof.ProfileName
            : ColorSpaceLabel(preferences.Export.EffectiveColorSpace);
        ExportPage.SoftProofProfileName.Text = profileName;
        ExportPage.SoftProofResetProfileButton.Visibility =
            proof.ProfileName.Length != 0 ? Visibility.Visible : Visibility.Collapsed;
        ExportPage.PrinterProfileName.Text = proof.PrinterProfilePath.Length != 0
            ? Path.GetFileName(proof.PrinterProfilePath)
            : AppResources.Get("settingsColorUnassigned", "Text");
        ExportPage.PrinterProfileResetButton.Visibility =
            proof.PrinterProfilePath.Length != 0 ? Visibility.Visible : Visibility.Collapsed;

        ExportPage.ScannerEmulationRow.ValueText = AppResources.Get("settingsColorUnassigned", "Text");
        ExportPage.ScannerEmulationRow.Reason = AppResources.Get("settingsColorScannerInputReason", "Text");
        ExportPage.ColorWorkingRow.ValueText = "Linear sRGB (Chromabase)";
        ExportPage.ColorMonitorRow.ValueText = MonitorProfileName();
        ExportPage.ColorExportRow.ValueText = ColorSpaceLabel(preferences.Export.EffectiveColorSpace);
        ExportPage.ColorSoftProofRow.ValueText = proof.IsEnabled
            ? $"{profileName} · {SimulationLabel(proof.Simulation)}"
            : AppResources.Get("settingsColorOff", "Text");
        ExportPage.ColorSoftProofRow.Reason = proof.IsEnabled
            ? string.Empty
            : AppResources.Get("settingsColorSoftProofOffReason", "Text");
        ExportPage.ColorManagementSection.Apply();
    }

    private void OnQuickExportFormatChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating && ExportPage.QuickExportFormatPicker.SelectedValue is DevelopExportFormat format)
        {
            workspaceState?.UpdateQuickExport(quick => quick with { Format = format });
        }
    }

    internal void OnQuickExportDpiChanged(object sender, Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        int index = ExportPage.QuickExportDpiComboBox.SelectedIndex;
        if (!isUpdating && index >= 0 && index < ExportSettings.DpiOptions.Count)
        {
            int dpi = ExportSettings.DpiOptions[index];
            workspaceState?.UpdateQuickExport(quick => quick with { Dpi = dpi });
        }
    }

    internal void OnQuickExportSizeChanged(object sender, Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        int index = ExportPage.QuickExportSizeComboBox.SelectedIndex;
        if (!isUpdating && index >= 0 && index < ExportSettings.LongEdgeOptions.Count)
        {
            int edge = ExportSettings.LongEdgeOptions[index];
            workspaceState?.UpdateQuickExport(quick => quick with { LongEdge = edge });
        }
    }

    /// <summary>
    /// macOS <c>exportVerificationLevel</c> 자리입니다. Windows 에서 같은 일을 하는 값은
    /// <see cref="ImageContentHashMode"/> 로, 확인 지점마다 바이트를 다시 해시할지를 정합니다.
    /// </summary>
    private void OnExportVerificationChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating && ExportPage.ExportVerificationPicker.SelectedValue is ImageContentHashMode mode)
        {
            workspaceState?.SetImageContentHashMode(mode);
        }
    }

    private void OnSoftProofSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.UpdateSoftProof(value => value with { IsEnabled = ExportPage.SoftProofRow.IsOn });
        }
    }

    private void OnGamutWarningSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.UpdateSoftProof(
                value => value with { GamutWarningEnabled = ExportPage.GamutWarningRow.IsOn });
        }
    }

    internal void OnExportColorSpaceChanged(
        object sender,
        Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        ExportColorSpace space = ExportPage.ExportColorSpaceComboBox.SelectedIndex switch
        {
            1 => ExportColorSpace.DisplayP3,
            2 => ExportColorSpace.AdobeRgb,
            _ => ExportColorSpace.Srgb,
        };
        workspaceState?.UpdateExport(settings => settings with { ColorSpace = space });
    }

    internal void OnSoftProofSimulationChanged(
        object sender,
        Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        SoftProofSimulation simulation = ExportPage.SoftProofSimulationComboBox.SelectedIndex == 1
            ? SoftProofSimulation.PaperAndBlackInk
            : SoftProofSimulation.ProfileOnly;
        workspaceState?.UpdateSoftProof(value => value with { Simulation = simulation });
    }
}
