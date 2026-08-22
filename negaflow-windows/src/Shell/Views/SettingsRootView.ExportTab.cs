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
        QuickExportFormatPicker.SelectionChanged += OnQuickExportFormatChanged;
        ExportVerificationPicker.SelectionChanged += OnExportVerificationChanged;
        SoftProofRow.Switched += OnSoftProofSwitched;
        GamutWarningRow.Switched += OnGamutWarningSwitched;
        BuildQuickExportChoices();
    }

    /// <summary>
    /// DPI·크기 목록입니다. macOS 와 <b>같은 값</b>이며 그 자리는
    /// <see cref="ExportSettings.DpiOptions"/> · <see cref="ExportSettings.LongEdgeOptions"/> 입니다.
    /// </summary>
    private void BuildQuickExportChoices()
    {
        QuickExportDpiComboBox.Items.Clear();
        foreach (int dpi in ExportSettings.DpiOptions)
        {
            QuickExportDpiComboBox.Items.Add(dpi == 0
                ? AppResources.Get("settingsSourceDPI", "Text")
                : string.Create(CultureInfo.CurrentCulture, $"{dpi} dpi"));
        }
        QuickExportSizeComboBox.Items.Clear();
        string suffix = AppResources.Get("exportLongEdgeSuffix", "Text");
        foreach (int edge in ExportSettings.LongEdgeOptions)
        {
            QuickExportSizeComboBox.Items.Add(edge == 0
                ? AppResources.Get("exportFullSize", "Text")
                : string.Create(CultureInfo.CurrentCulture, $"{edge} {suffix}"));
        }
    }

    private void LocalizeExportTab()
    {
        QuickExportSection.HeaderText = AppResources.Get("quickExportSection", "Text");
        QuickExportFormatRow.Label = AppResources.Get("settingsQuickExportFormat", "Text");
        QuickExportFormatPicker.SetOptions(
            [
                new SegmentOption(DevelopExportFormat.Jpeg8, "JPEG"),
                new SegmentOption(DevelopExportFormat.Png16, "PNG"),
            ],
            QuickExportFormatPicker.SelectedValue ?? DevelopExportFormat.Jpeg8);
        QuickExportDpiRow.Label = AppResources.Get("settingsQuickExportDPI", "Text");
        QuickExportSizeRow.Label = AppResources.Get("settingsQuickExportSize", "Text");
        QuickExportFolderRow.Label = AppResources.Get("settingsQuickExportFolder", "Text");
        BuildQuickExportChoices();

        string verification = AppResources.Get("settingsExportVerification", "Text");
        ExportVerificationSection.HeaderText = verification;
        ExportVerificationRow.Label = verification;
        ExportVerificationPicker.SetOptions(
            [
                new SegmentOption(
                    ImageContentHashMode.Off,
                    AppResources.Get("settingsExportVerificationStandard", "Content")),
                new SegmentOption(
                    ImageContentHashMode.Sha256,
                    AppResources.Get("settingsExportVerificationStrict", "Content")),
            ],
            ExportVerificationPicker.SelectedValue ?? ImageContentHashMode.Off);
        ExportVerificationHelp.Text =
            AppResources.Get("settingsExportVerificationHelp", "Text");

        ColorManagementSection.HeaderText =
            AppResources.Get("settingsColorManagementSection", "Text");
        ExportColorRow.Label = AppResources.Get("settingsExportColorLabel", "Text");
        SoftProofRow.Label = AppResources.Get("settingsExportSoftProofLabel", "Text");
        SoftProofProfileRow.Label = AppResources.Get("settingsColorProfile", "Text");
        SoftProofChooseProfileButton.Content =
            AppResources.Get("developExportChangeFolder", "Content");
        SoftProofProfileError.Text = AppResources.Get("softProofInvalidICC", "Text");
        SoftProofSimulationRow.Label = AppResources.Get("settingsExportProofLabel", "Text");
        SettingsSoftProofProfileOnlyLocalized.Content =
            AppResources.Get("settingsSoftProofProfileOnly", "Content");
        SettingsSoftProofPaperAndBlackLocalized.Content =
            AppResources.Get("settingsSoftProofPaperAndBlack", "Content");
        GamutWarningRow.Label = AppResources.Get("settingsColorGamutWarning", "Text");
        GamutUnavailableReason.Text =
            AppResources.Get("settingsColorGamutUnavailableReason", "Text");
        PrinterProfileRow.Label = AppResources.Get("settingsColorPrinterProfile", "Text");
        PrinterProfileButton.Content = AppResources.Get("developExportChangeFolder", "Content");
        PrinterProfileError.Text = AppResources.Get("softProofInvalidICC", "Text");
        ScannerEmulationRow.Label = AppResources.Get("settingsColorScannerInput", "Text");
        ColorWorkingRow.Label = AppResources.Get("settingsColorWorking", "Text");
        ColorMonitorRow.Label = AppResources.Get("settingsColorMonitor", "Text");
        ColorExportRow.Label = AppResources.Get("settingsColorExport", "Text");
        ColorSoftProofRow.Label = AppResources.Get("settingsColorSoftProof", "Text");
        string reset = AppResources.Get("developTabReset", "Value");
        SoftProofResetProfileButton.Content = reset;
        PrinterProfileResetButton.Content = reset;
    }

    private void SynchronizeExportTab(ShellPreferences preferences)
    {
        QuickExportSettings quick = preferences.QuickExport;
        QuickExportFormatPicker.SetSelected(quick.Format);
        QuickExportDpiComboBox.SelectedIndex =
            Math.Max(0, ExportSettings.DpiOptions.ToList().IndexOf(quick.Dpi));
        QuickExportSizeComboBox.SelectedIndex =
            Math.Max(0, ExportSettings.LongEdgeOptions.ToList().IndexOf(quick.LongEdge));
        // macOS 는 폴더 이름만 냅니다("Quick Export"). 전체 경로는 디스크 탭에 있습니다.
        QuickExportFolderRow.ValueText =
            Path.GetFileName(preferences.ResolvedQuickExport.FolderPath);

        ExportVerificationPicker.SetSelected(preferences.ImageContentHash);

        ExportColorSpaceComboBox.SelectedIndex = preferences.Export.ColorSpace switch
        {
            ExportColorSpace.DisplayP3 => 1,
            ExportColorSpace.AdobeRgb => 2,
            _ => 0,
        };

        SoftProofPreferences proof = preferences.SoftProof;
        SoftProofRow.IsOn = proof.IsEnabled;
        // macOS 는 프루프가 꺼져 있으면 아래 줄들을 아예 그리지 않습니다.
        Visibility proofRows = proof.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
        SoftProofProfileRow.Visibility = proofRows;
        SoftProofSimulationRow.Visibility = proofRows;
        GamutWarningRow.Visibility = proofRows;
        SoftProofSimulationComboBox.SelectedIndex =
            proof.Simulation == SoftProofSimulation.PaperAndBlackInk ? 1 : 0;

        bool gamutAvailable = NativeGamutCheck.IsSupported(preferences.Export.EffectiveColorSpace);
        GamutWarningRow.IsEnabled = gamutAvailable;
        GamutUnavailableReason.Visibility = proof.IsEnabled && !gamutAvailable
            ? Visibility.Visible
            : Visibility.Collapsed;
        GamutWarningRow.IsOn = gamutAvailable && proof.GamutWarningEnabled;

        string profileName = proof.ProfileName.Length != 0
            ? proof.ProfileName
            : ColorSpaceLabel(preferences.Export.EffectiveColorSpace);
        SoftProofProfileName.Text = profileName;
        SoftProofResetProfileButton.Visibility =
            proof.ProfileName.Length != 0 ? Visibility.Visible : Visibility.Collapsed;
        PrinterProfileName.Text = proof.PrinterProfilePath.Length != 0
            ? Path.GetFileName(proof.PrinterProfilePath)
            : AppResources.Get("settingsColorUnassigned", "Text");
        PrinterProfileResetButton.Visibility =
            proof.PrinterProfilePath.Length != 0 ? Visibility.Visible : Visibility.Collapsed;

        ScannerEmulationRow.ValueText = AppResources.Get("settingsColorUnassigned", "Text");
        ScannerEmulationRow.Reason = AppResources.Get("settingsColorScannerInputReason", "Text");
        ColorWorkingRow.ValueText = "Linear sRGB (Chromabase)";
        ColorMonitorRow.ValueText = MonitorProfileName();
        ColorExportRow.ValueText = ColorSpaceLabel(preferences.Export.EffectiveColorSpace);
        ColorSoftProofRow.ValueText = proof.IsEnabled
            ? $"{profileName} · {SimulationLabel(proof.Simulation)}"
            : AppResources.Get("settingsColorOff", "Text");
        ColorSoftProofRow.Reason = proof.IsEnabled
            ? string.Empty
            : AppResources.Get("settingsColorSoftProofOffReason", "Text");
        ColorManagementSection.Apply();
    }

    private void OnQuickExportFormatChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating && QuickExportFormatPicker.SelectedValue is DevelopExportFormat format)
        {
            workspaceState?.UpdateQuickExport(quick => quick with { Format = format });
        }
    }

    private void OnQuickExportDpiChanged(object sender, Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        int index = QuickExportDpiComboBox.SelectedIndex;
        if (!isUpdating && index >= 0 && index < ExportSettings.DpiOptions.Count)
        {
            int dpi = ExportSettings.DpiOptions[index];
            workspaceState?.UpdateQuickExport(quick => quick with { Dpi = dpi });
        }
    }

    private void OnQuickExportSizeChanged(object sender, Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        int index = QuickExportSizeComboBox.SelectedIndex;
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
        if (!isUpdating && ExportVerificationPicker.SelectedValue is ImageContentHashMode mode)
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
            workspaceState?.UpdateSoftProof(value => value with { IsEnabled = SoftProofRow.IsOn });
        }
    }

    private void OnGamutWarningSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.UpdateSoftProof(
                value => value with { GamutWarningEnabled = GamutWarningRow.IsOn });
        }
    }

    private void OnExportColorSpaceChanged(
        object sender,
        Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        ExportColorSpace space = ExportColorSpaceComboBox.SelectedIndex switch
        {
            1 => ExportColorSpace.DisplayP3,
            2 => ExportColorSpace.AdobeRgb,
            _ => ExportColorSpace.Srgb,
        };
        workspaceState?.UpdateExport(settings => settings with { ColorSpace = space });
    }

    private void OnSoftProofSimulationChanged(
        object sender,
        Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        SoftProofSimulation simulation = SoftProofSimulationComboBox.SelectedIndex == 1
            ? SoftProofSimulation.PaperAndBlackInk
            : SoftProofSimulation.ProfileOnly;
        workspaceState?.UpdateSoftProof(value => value with { Simulation = simulation });
    }
}
