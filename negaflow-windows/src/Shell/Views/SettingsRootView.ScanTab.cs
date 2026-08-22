using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정창 "스캔" 탭입니다. macOS <c>AppSettingsView.scanPane</c> +
/// <c>ScannerTruthSettingsSection</c> + <c>ScannerPluginTrustRows</c> 자리입니다.
/// </summary>
public sealed partial class SettingsRootView
{
    private ScannerPluginCapabilities? scannerCapabilities;

    /// <summary>
    /// 스캐너가 보고한 성능을 보여 줍니다. <b>장치가 말한 것만</b> 적습니다 — 앱이 지어낸 값을
    /// 여기 두면 사용자는 그것을 장치의 사양으로 읽습니다.
    /// </summary>
    public void ShowScannerCapabilities(ScannerPluginCapabilities? capabilities)
    {
        scannerCapabilities = capabilities;
        BuildScannerTruth();
    }

    private void OnScannerCapabilitiesChanged(object? sender, EventArgs args)
    {
        _ = args;
        if (sender is WorkspacePresentationState state)
        {
            ShowScannerCapabilities(state.ScannerCapabilities);
        }
    }

    private void BuildScannerTruth()
    {
        if (ScannerTruthSection is null)
        {
            return;
        }
        ScannerTruthSection.Rows.Clear();
        ScannerTruthSection.HeaderText = AppResources.Get("settingsScannerTruth", "Text");
        if (scannerCapabilities is not { } caps)
        {
            ScannerTruthSection.Rows.Add(new SettingsFootnote
            {
                Text = AppResources.Get("settingsScannerTruthNone", "Text"),
            });
            ScannerTruthSection.Apply();
            return;
        }

        // macOS ScannerTruthSettingsSection 과 같은 차례입니다.
        AddTruthRow("resolution", ResolutionSummary(caps));
        AddTruthRow("bitDepth", BitDepthSummary(caps));
        AddTruthRow(
            "transparency",
            TransparencySummary(caps),
            caps.SupportsTransparency);
        AddTruthRow(
            "brightness",
            AppResources.Get("capabilityUnavailable", "Value"),
            supported: false);
        AddTruthRow(
            "contrast",
            AppResources.Get("capabilityUnavailable", "Value"),
            supported: false);
        AddTruthRow(
            "infrared",
            AppResources.Get(
                caps.SupportsInfrared ? "capabilityAvailable" : "capabilityUnavailable",
                "Value"),
            caps.SupportsInfrared);
        ScannerTruthSection.Apply();
    }

    /// <summary>한 줄입니다. 이름은 리소스에서 오고, 값은 장치가 보고한 그대로입니다.</summary>
    private void AddTruthRow(string labelKey, string value, bool supported = true)
    {
        ScannerTruthSection.Rows.Add(new SettingsValueRow
        {
            Label = TryResource(labelKey),
            ValueText = value,
            Kind = supported ? SettingsRowValueKind.Primary : SettingsRowValueKind.Secondary,
        });
    }

    private static string ResolutionSummary(ScannerPluginCapabilities caps)
    {
        string joined = string.Join(", ", caps.ResolutionsDpi.Where(dpi => dpi > 0));
        return joined.Length == 0
            ? AppResources.Get("capabilityUnavailable", "Value")
            : joined + " dpi";
    }

    private static string BitDepthSummary(ScannerPluginCapabilities caps)
    {
        string joined = string.Join(", ", caps.BitDepths.Select(bits => $"{bits}-bit/ch"));
        return joined.Length == 0
            ? AppResources.Get("capabilityUnavailable", "Value")
            : joined;
    }

    private static string TransparencySummary(ScannerPluginCapabilities caps)
    {
        string joined = string.Join(", ", caps.Modes);
        if (joined.Length != 0)
        {
            return joined;
        }
        return AppResources.Get(
            caps.SupportsTransparency ? "capabilityAvailable" : "capabilityUnavailable", "Value");
    }

    /// <summary>
    /// 이름이 리소스에 없으면 키를 그대로 씁니다. 성능 항목 하나 때문에 설정 창이 터지는 것이
    /// 더 나쁩니다.
    /// </summary>
    private static string TryResource(string key) => TryResource(key, "Text");

    private static string TryResource(string key, string property)
    {
        try
        {
            return AppResources.Get(key, property);
        }
        catch (Exception exception) when (
            exception is InvalidOperationException or COMException)
        {
            return key;
        }
    }

    /// <summary>
    /// 설치된 스캐너 플러그인과 그 승인 상태입니다. macOS <c>ScannerPluginTrustRows</c> 자리 —
    /// 플러그인이 없으면 구역 자체가 나오지 않습니다.
    /// </summary>
    private void BuildScannerPluginRows()
    {
        if (ScannerPluginSection is null)
        {
            return;
        }
        ScannerPluginSection.Rows.Clear();
        IReadOnlyList<InstalledScannerPlugin> plugins = ScannerPluginDiscovery.Discover(
            library?.StorageRoots?.PluginRoot);
        if (plugins.Count == 0)
        {
            ScannerPluginSection.Visibility = Visibility.Collapsed;
            return;
        }
        ScannerPluginSection.Visibility = Visibility.Visible;
        ScannerPluginSection.HeaderText =
            AppResources.Get("settingsScannerPluginApproval", "Text");
        ScannerPluginTrustStore trust = new();
        foreach (InstalledScannerPlugin plugin in plugins)
        {
            ScannerPluginApprovalState state = trust.StateFor(plugin);
            ScannerPluginSection.Rows.Add(new SettingsValueRow
            {
                Label = plugin.Manifest.Name,
                ValueText = AppResources.Get(state switch
                {
                    ScannerPluginApprovalState.Approved => "scannerPluginApproved",
                    ScannerPluginApprovalState.Changed => "scannerPluginChanged",
                    _ => "scannerPluginApprovalRequired",
                }, "Text"),
                Kind = state == ScannerPluginApprovalState.Approved
                    ? SettingsRowValueKind.Primary
                    : SettingsRowValueKind.Secondary,
            });
            ScannerPluginSection.Rows.Add(new SettingsValueRow
            {
                Label = AppResources.Get("scannerPluginVersion", "Text"),
                ValueText = plugin.Manifest.PluginVersion ??
                    AppResources.Get("scannerPluginNotReported", "Text"),
            });
            ScannerPluginSection.Rows.Add(new SettingsValueRow
            {
                Label = AppResources.Get("scannerPluginLicense", "Text"),
                ValueText = plugin.Manifest.License ??
                    AppResources.Get("scannerPluginNotReported", "Text"),
            });
            // 매니페스트 경로와 해시는 승인이 **어느 바이트**에 붙어 있는지를 말합니다.
            ScannerPluginSection.Rows.Add(new SettingsValueRow
            {
                Label = AppResources.Get("scannerPluginManifestPath", "Text"),
                ValueText = Negaflow.Shell.Storage.DiskStorageLocations.Abbreviate(
                    plugin.ManifestPath),
                Kind = SettingsRowValueKind.Secondary,
            });
            ScannerPluginSection.Rows.Add(new SettingsValueRow
            {
                Label = AppResources.Get("scannerPluginManifestHash", "Text"),
                ValueText = plugin.TrustIdentity.ManifestSha256,
                Kind = SettingsRowValueKind.Secondary,
            });
            ScannerPluginSection.Rows.Add(new SettingsValueRow
            {
                Label = AppResources.Get("scannerPluginExecutableHash", "Text"),
                ValueText = plugin.TrustIdentity.ExecutableSha256,
                Kind = SettingsRowValueKind.Secondary,
            });
        }
        ScannerPluginSection.Apply();
    }

    private void LocalizeScanTab()
    {
        ScanSection.HeaderText = AppResources.Get("settingsScanTab", "Text");
        ScanRotationRow.Label = AppResources.Get("settingsDefaultScanRotation", "Text");
        ScanRotationHelp.Text = AppResources.Get("settingsDefaultScanRotationHelp", "Text");
        ScanRotation0Item.Content = AppResources.Get("settingsRotation0", "Text");
        ScanRotation90Item.Content = AppResources.Get("settingsRotation90", "Text");
        ScanRotation180Item.Content = AppResources.Get("settingsRotation180", "Text");
        ScanRotation270Item.Content = AppResources.Get("settingsRotation270", "Text");
        BuildScannerTruth();
        BuildScannerPluginRows();
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

    private void SynchronizeScanTab(ShellPreferences preferences)
    {
        ScanRotationComboBox.SelectedIndex = preferences.DefaultScanRotation switch
        {
            ImageRotation.Degrees90 => 1,
            ImageRotation.Degrees180 => 2,
            ImageRotation.Degrees270 => 3,
            _ => 0,
        };
    }

    private void LocalizeLegalTab()
    {
        LegalLicenseSection.HeaderText = AppResources.Get("legalLicenseTitle", "Text");
        LegalLicenseBody.Text = AppResources.Get("legalLicenseBody", "Text");
        LegalTrademarkSection.HeaderText = AppResources.Get("legalTrademarkTitle", "Text");
        LegalTrademarkBody.Text = AppResources.Get("legalTrademarkBody", "Text");
        LegalNamesSection.HeaderText = AppResources.Get("legalNamesTitle", "Text");
        LegalNamesBody.Text = AppResources.Get("legalNamesBody", "Text");
        LegalProfilesSection.HeaderText = AppResources.Get("legalProfilesTitle", "Text");
        LegalProfilesBody.Text = AppResources.Get("legalProfilesBody", "Text");
        LegalAffiliationSection.HeaderText = AppResources.Get("legalAffiliationTitle", "Text");
        LegalAffiliationBody.Text = AppResources.Get("legalAffiliationBody", "Text");
    }
}
