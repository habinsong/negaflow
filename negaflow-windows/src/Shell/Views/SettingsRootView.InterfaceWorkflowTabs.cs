using Microsoft.UI.Xaml;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// 설정창 "인터페이스"·"워크플로우" 탭입니다. macOS <c>AppSettingsView.interfacePane</c> ·
/// <c>workflowPane</c> 자리입니다.
/// </summary>
public sealed partial class SettingsRootView
{
    private void InitializeInterfaceWorkflowTabs()
    {
        CanvasBackgroundPicker.SelectionChanged += OnCanvasBackgroundChanged;
        ClippingOverlayRow.Switched += OnClippingOverlaySwitched;
        PixelSamplerRow.Switched += OnPixelSamplerSwitched;
        ScannerSimulatorRow.Switched += OnScannerSimulatorSwitched;
        DevelopImportsRow.Switched += OnDevelopImportsSwitched;
        AutoDefectMicroSpecksRow.Switched += OnAutoDefectMicroSpecksSwitched;
        GuidedDefectMicroSpecksRow.Switched += OnGuidedDefectMicroSpecksSwitched;
    }

    private void LocalizeInterfaceWorkflowTabs()
    {
        InterfaceSection.HeaderText = AppResources.Get("settingsInterfaceTab", "Text");
        CanvasBackgroundRow.Label = AppResources.Get("settingsCanvasBackgroundPicker", "Text");
        CanvasBackgroundPicker.SetOptions(
            [
                new SegmentOption(
                    CanvasBackgroundKind.Black,
                    AppResources.Get("canvasBackgroundBlack", "Content")),
                new SegmentOption(
                    CanvasBackgroundKind.Gray,
                    AppResources.Get("canvasBackgroundGray", "Content")),
                new SegmentOption(
                    CanvasBackgroundKind.White,
                    AppResources.Get("canvasBackgroundWhite", "Content")),
            ],
            CanvasBackgroundPicker.SelectedValue ?? CanvasBackgroundKind.Black);
        ClippingOverlayRow.Label = AppResources.Get("colorClippingOverlay", "Header");
        PixelSamplerRow.Label = AppResources.Get("samplerEnabled", "Text");
        PixelSamplerHelp.Text = AppResources.Get("samplerMovePointer", "Text");

        WorkflowSection.HeaderText = AppResources.Get("settingsWorkflowTab", "Text");
        ScannerSimulatorRow.Label = AppResources.Get("commandToggleScannerSimulator", "Header");
        DevelopImportsRow.Label = AppResources.Get("developImportsAutomatically", "Header");
        MicroSpecksSection.HeaderText = AppResources.Get("defaultDefectMicroSpecks", "Text");
        AutoDefectMicroSpecksRow.Label = AppResources.Get("autoDefect", "Text");
        GuidedDefectMicroSpecksRow.Label = AppResources.Get("guidedDefect", "Text");
        MicroSpecksHelp.Text = AppResources.Get("defaultDefectMicroSpecksHelp", "Text");
    }

    private void SynchronizeInterfaceWorkflowTabs(ShellPreferences preferences)
    {
        CanvasBackgroundPicker.SetSelected(preferences.CanvasBackground);
        ClippingOverlayRow.IsOn = preferences.ClippingOverlayEnabled;
        PixelSamplerRow.IsOn = preferences.PixelSamplerEnabled;
        // macOS PixelSamplerSettingsRow — 도움말은 켜져 있을 때만 냅니다(`if store.isEnabled`).
        PixelSamplerHelp.Visibility = preferences.PixelSamplerEnabled
            ? Visibility.Visible
            : Visibility.Collapsed;
        InterfaceSection.Apply();

        ScannerSimulatorRow.IsOn = preferences.ScannerSimulatorEnabled;
        DevelopImportsRow.IsOn = preferences.DevelopsImportsAutomatically;
        AutoDefectMicroSpecksRow.IsOn = preferences.AutoDefectDetectsMicroSpecks;
        GuidedDefectMicroSpecksRow.IsOn = preferences.GuidedDefectDetectsMicroSpecks;
    }

    private void OnCanvasBackgroundChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Negaflow.Shell.Diagnostics.SettingsChangeLog.Write(
            $"canvas picker: updating={isUpdating} value={CanvasBackgroundPicker.SelectedValue}");
        if (!isUpdating && CanvasBackgroundPicker.SelectedValue is CanvasBackgroundKind kind)
        {
            workspaceState?.SetCanvasBackground(kind);
        }
    }

    private void OnClippingOverlaySwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetClippingOverlayEnabled(ClippingOverlayRow.IsOn);
        }
    }

    private void OnPixelSamplerSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetPixelSamplerEnabled(PixelSamplerRow.IsOn);
        }
    }

    private void OnScannerSimulatorSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetScannerSimulatorEnabled(ScannerSimulatorRow.IsOn);
        }
    }

    private void OnDevelopImportsSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetDevelopsImportsAutomatically(DevelopImportsRow.IsOn);
        }
    }

    private void OnAutoDefectMicroSpecksSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetAutoDefectMicroSpecks(AutoDefectMicroSpecksRow.IsOn);
        }
    }

    private void OnGuidedDefectMicroSpecksSwitched(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isUpdating)
        {
            workspaceState?.SetGuidedDefectMicroSpecks(GuidedDefectMicroSpecksRow.IsOn);
        }
    }
}
