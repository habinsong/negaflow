using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>스캔 카드의 이름표입니다. 세션 실행과 다른 이유입니다.</summary>
internal sealed class LibraryScanCopy
{
    private readonly LibraryScanPanel view;

    internal LibraryScanCopy(LibraryScanPanel view) => this.view = view;

    internal void Localize()
    {
        view.ScanSectionText.Text = AppResources.Get("scanSection", "Text");
        view.ScanDeviceLabel.Text = AppResources.Get("libraryScannerLabel", "Content");
        AutomationProperties.SetName(view.ScanDeviceSelector, view.ScanDeviceLabel.Text);
        SetButtonText(view.ScanApprovePluginButton, AppResources.Get("scanPluginApprove", "Content"));
        string simulator = AppResources.Get("scanSimulator", "Content");
        view.ScanSimulatorToggle.Header = simulator;
        view.ScanSimulatorToggle.OnContent = simulator;
        view.ScanSimulatorToggle.OffContent = simulator;
        AutomationProperties.SetName(view.ScanSimulatorToggle, simulator);
        ToolTipService.SetToolTip(
            view.ScanSimulatorToggle,
            AppResources.Get("scanSimulatorHelp", "Text"));
        string rescan = AppResources.Get("scanDetectScanners", "Text");
        AutomationProperties.SetName(view.ScanRescanButton, rescan);
        ToolTipService.SetToolTip(view.ScanRescanButton, rescan);
        view.ScanFilmLabel.Text = AppResources.Get("scanFilm", "Text");
        AutomationProperties.SetName(view.ScanFilmSelector, view.ScanFilmLabel.Text);
        view.ScanFolderNameLabel.Text = AppResources.Get("scanFolderName", "Text");
        view.ScanFolderNameBox.PlaceholderText = AppResources.Get("scanUntitledFilm", "Text");
        AutomationProperties.SetName(view.ScanFolderNameBox, view.ScanFolderNameLabel.Text);
        AutomationProperties.SetName(
            view.ScanResolutionSelector,
            AppResources.Get("scanResolution", "Text"));
        AutomationProperties.SetName(
            view.ScanColorModeSelector,
            AppResources.Get("scanColorMode", "Text"));
        view.ScanBitDepthLabel.Text = AppResources.Get("scanBitDepth", "Text");
        AutomationProperties.SetName(view.ScanBitDepthSelector, view.ScanBitDepthLabel.Text);
        view.ScanBitDepthUnavailableText.Text = AppResources.Get("scanBitDepthUnavailable", "Text");
        view.ScanFrameFormatLabel.Text = AppResources.Get("scanFrameFormat", "Text");
        AutomationProperties.SetName(view.ScanFrameFormatSelector, view.ScanFrameFormatLabel.Text);
        view.ScanDetectionModeLabel.Text = AppResources.Get("scanDetectionMode", "Text");
        SetRadioText(
            view.ScanDetectionAutomaticButton,
            AppResources.Get("scanDetectionAutomatic", "Content"));
        SetRadioText(
            view.ScanDetectionManualButton,
            AppResources.Get("scanDetectionManual", "Content"));
        SetIconButtonName(view.ScanRefreshFramesButton, "scanRefreshFrames");
        SetIconButtonName(view.ScanCopyFrameButton, "scanCopyFrame");
        SetIconButtonName(view.ScanPasteFrameButton, "scanPasteFrame");
        SetIconButtonName(view.ScanAddFrameButton, "scanAddFrame");
        SetIconButtonName(view.ScanRemoveFrameButton, "scanRemoveFrame");
        view.ScanFrameCountLabel.Text = AppResources.FormatInteger("scanFramesFormat", "Text", 1);
        AutomationProperties.SetName(view.ScanFrameCountBox, view.ScanFrameCountLabel.Text);
        string infrared = AppResources.Get("scanInfrared", "Content");
        view.ScanInfraredToggle.Header = infrared;
        view.ScanInfraredToggle.OnContent = infrared;
        view.ScanInfraredToggle.OffContent = infrared;
        AutomationProperties.SetName(view.ScanInfraredToggle, infrared);
        SetButtonText(view.ScanPreviewButton, AppResources.Get("scanPreview", "Content"));
        SetButtonText(view.ScanStartButton, AppResources.Get("scanStart", "Content"));
    }

    /// <summary>글리프만 있는 단추의 이름입니다. 이름이 없으면 화면 낭독기가 읽지 못합니다.</summary>
    internal static void SetIconButtonName(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Text");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    internal static void SetRadioText(RadioButton radio, string text)
    {
        radio.Content = text;
        AutomationProperties.SetName(radio, text);
    }

    internal static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }
}
