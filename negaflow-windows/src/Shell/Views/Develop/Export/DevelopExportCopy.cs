using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Export;

/// <summary>출력 패널의 이름과 목록을 채웁니다.</summary>
internal sealed class DevelopExportCopy
{
    private readonly DevelopExportPanel view;

    internal DevelopExportCopy(DevelopExportPanel view) => this.view = view;

    /// <summary>
    /// 출력 패널의 이름과 목록을 채웁니다. DPI·크기 목록은 항목 이름이 번역돼야 하므로 XAML 이
    /// 아니라 여기서 만듭니다.
    /// </summary>
    internal void LocalizeOutputPanel()
    {
        SetRadioText(view.ExportFileTabButton, AppResources.Get("developExportTabFile", "Content"));
        SetRadioText(view.ExportQualityTabButton, AppResources.Get("developExportTabQuality", "Content"));
        SetRadioText(view.ExportSourceTabButton, AppResources.Get("developExportTabSource", "Content"));

        view.ExportSequenceStartLabel.Text = AppResources.Get("developExportSequenceStart", "Text");
        AutomationProperties.SetName(view.ExportSequenceStartBox, view.ExportSequenceStartLabel.Text);
        SetLocalizedNameAndTooltip(
            view.ExportNamingOptionsButton,
            AppResources.Get("developExportNamingOptions", "Text"));
        BuildNamingOptionsMenu();

        view.ExportJpegQualityLabel.Text = AppResources.Get("developExportJpegQuality", "Text");
        AutomationProperties.SetName(view.ExportJpegQualitySlider, view.ExportJpegQualityLabel.Text);
        view.ExportTiffCompressionLabel.Text = AppResources.Get("developExportTiffCompression", "Text");
        AutomationProperties.SetName(
            view.ExportTiffCompressionSelector,
            view.ExportTiffCompressionLabel.Text);
        FillSelector(view.ExportTiffCompressionSelector, [
            (AppResources.Get("developExportCompressionNone", "Content"),
                DevelopTiffCompression.None.ToString()),
            (AppResources.Get("developExportCompressionLzw", "Content"),
                DevelopTiffCompression.Lzw.ToString()),
            (AppResources.Get("developExportCompressionDeflate", "Content"),
                DevelopTiffCompression.Deflate.ToString()),
        ]);

        view.ExportDpiLabel.Text = AppResources.Get("developExportDpi", "Text");
        AutomationProperties.SetName(view.ExportDpiSelector, view.ExportDpiLabel.Text);
        view.ExportSizeLabel.Text = AppResources.Get("developExportSize", "Text");
        AutomationProperties.SetName(view.ExportSizeSelector, view.ExportSizeLabel.Text);
        FillDpiSelector(view.ExportDpiSelector);
        FillSizeSelector(view.ExportSizeSelector);

        view.ExportSharpeningLabel.Text = AppResources.Get("developOutputSharpening", "Text");
        AutomationProperties.SetName(view.ExportSharpeningSlider, view.ExportSharpeningLabel.Text);
        view.ExportSharpeningMediumLabel.Text =
            AppResources.Get("developOutputSharpeningMedium", "Text");
        AutomationProperties.SetName(
            view.ExportSharpeningMediumSelector,
            view.ExportSharpeningMediumLabel.Text);
        FillSelector(view.ExportSharpeningMediumSelector, [
            (AppResources.Get("developSharpenScreen", "Content"),
                OutputSharpeningMedium.Screen.ToString()),
            (AppResources.Get("developSharpenMattePaper", "Content"),
                OutputSharpeningMedium.MattePaper.ToString()),
            (AppResources.Get("developSharpenGlossyPaper", "Content"),
                OutputSharpeningMedium.GlossyPaper.ToString()),
        ]);

        LocalizeToggleSwitch(view.ExportMainFlatMasterToggle, "developExportMainFlatMaster");
        LocalizeToggleSwitch(view.ExportOriginalRawToggle, "developExportOriginalRaw");
        LocalizeToggleSwitch(view.ExportSidecarToggle, "developExportSidecar");
        LocalizeToggleSwitch(view.ExportPreserveAlphaToggle, "developExportPreserveAlpha");
        view.ExportRecipeLabel.Text = AppResources.Get("developExportRecipeTitle", "Text");
        AutomationProperties.SetName(view.ExportRecipeSelector, view.ExportRecipeLabel.Text);
        SetLocalizedNameAndTooltip(view.ExportRecipeMenuButton, view.ExportRecipeLabel.Text);
        view.ExportMetadataLabel.Text = AppResources.Get("developExportMetadata", "Text");
        AutomationProperties.SetName(view.ExportMetadataSelector, view.ExportMetadataLabel.Text);
        view.ExportMetadataMinimalItem.Content =
            AppResources.Get("developExportMetadataMinimal", "Text");
        view.ExportMetadataCopyrightItem.Content =
            AppResources.Get("developExportMetadataCopyright", "Text");
        view.ExportMetadataRemoveLocationItem.Content =
            AppResources.Get("developExportMetadataRemoveLocation", "Text");
        view.ExportMetadataAllItem.Content = AppResources.Get("developExportMetadataAll", "Text");
        view.ExportSourceLabel.Text = AppResources.Get("developExportSourceLabel", "Text");

        view.QuickExportSectionText.Text = AppResources.Get("quickExportSection", "Text");
        view.QuickExportFormatLabel.Text = AppResources.Get("developExportFormat", "Text");
        AutomationProperties.SetName(view.QuickExportFormatSelector, view.QuickExportFormatLabel.Text);
        view.QuickExportDpiLabel.Text = view.ExportDpiLabel.Text;
        AutomationProperties.SetName(view.QuickExportDpiSelector, view.QuickExportDpiLabel.Text);
        view.QuickExportSizeLabel.Text = view.ExportSizeLabel.Text;
        AutomationProperties.SetName(view.QuickExportSizeSelector, view.QuickExportSizeLabel.Text);
        view.QuickExportJpegQualityLabel.Text = view.ExportJpegQualityLabel.Text;
        AutomationProperties.SetName(
            view.QuickExportJpegQualitySlider,
            view.QuickExportJpegQualityLabel.Text);
        view.QuickExportFolderLabel.Text = view.ExportFolderLabel.Text;
        SetButtonText(
            view.QuickExportFolderButton,
            AppResources.Get("developExportFolderChange", "Content"));
        view.QuickExportFilenameLabel.Text = AppResources.Get("developExportFilename", "Text");
        string reveal = AppResources.Get("libraryShowInExplorer", "Content");
        view.QuickExportButton.Title = AppResources.Get("commandQuickExport", "Text");
        view.QuickExportButton.RevealHelp = reveal;
        view.ExportButton.RevealHelp = reveal;
        view.ExportPreviewLabel.Text = AppResources.Get("developExportPreview", "Text");
        FillDpiSelector(view.QuickExportDpiSelector);
        FillSizeSelector(view.QuickExportSizeSelector);

        view.SynchronizeExportControls();
        view.OnExportDetailTabChecked(view, new RoutedEventArgs());
    }

    internal void BuildNamingOptionsMenu()
    {
        view.ExportNamingOptionsFlyout.Items.Clear();
        foreach ((string key, string pattern) in new[]
        {
            ("developExportPhotoName", ExportNamingTemplate.DefaultPattern),
            ("developExportPhotoNameSequence", ExportNamingTemplate.PhotoNameSequencePattern),
            ("developExportSequenceOnly", ExportNamingTemplate.SequenceOnlyPattern),
        })
        {
            var item = new MenuFlyoutItem { Text = AppResources.Get(key, "Text") };
            string chosen = pattern;
            item.Click += (_, _) => view.MutateExportSettings(value => value with
            {
                NamingTemplate = chosen,
            });
            view.ExportNamingOptionsFlyout.Items.Add(item);
        }
        view.ExportNamingOptionsFlyout.Items.Add(new MenuFlyoutSeparator());
        var tokens = new MenuFlyoutSubItem { Text = AppResources.Get("developExportTokens", "Text") };
        foreach (string token in ExportNamingTemplate.Tokens)
        {
            string appended = "{" + token + "}";
            var item = new MenuFlyoutItem { Text = appended };
            item.Click += (_, _) => view.MutateExportSettings(value => value with
            {
                NamingTemplate = value.NamingTemplate + appended,
            });
            tokens.Items.Add(item);
        }
        view.ExportNamingOptionsFlyout.Items.Add(tokens);
    }

    internal static void LocalizeToggleSwitch(ToggleSwitch toggle, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Content");
        toggle.Header = text;
        toggle.OnContent = text;
        toggle.OffContent = text;
        AutomationProperties.SetName(toggle, text);
    }

    internal static void FillSelector(
        ComboBox selector,
        IReadOnlyList<(string Text, string Tag)> items)
    {
        selector.Items.Clear();
        foreach ((string text, string tag) in items)
        {
            selector.Items.Add(new ComboBoxItem { Content = text, Tag = tag });
        }
    }

    internal static void FillDpiSelector(ComboBox selector)
    {
        string sourceDpi = AppResources.Get("settingsSourceDPI", "Text");
        selector.Items.Clear();
        foreach (int dpi in ExportSettings.DpiOptions)
        {
            selector.Items.Add(new ComboBoxItem
            {
                Content = dpi == 0
                    ? sourceDpi
                    : string.Create(CultureInfo.CurrentCulture, $"{dpi} dpi"),
                Tag = dpi,
            });
        }
    }

    internal static void FillSizeSelector(ComboBox selector)
    {
        string fullSize = AppResources.Get("exportFullSize", "Text");
        string suffix = AppResources.Get("developExportLongEdgeSuffix", "Text");
        selector.Items.Clear();
        foreach (int edge in ExportSettings.LongEdgeOptions)
        {
            selector.Items.Add(new ComboBoxItem
            {
                Content = edge == 0
                    ? fullSize
                    : string.Create(CultureInfo.CurrentCulture, $"{edge} {suffix}"),
                Tag = edge,
            });
        }
    }

    internal static void SetLocalizedNameAndTooltip(ButtonBase button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    internal static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        SetLocalizedNameAndTooltip(button, text);
    }

    internal static void SetRadioText(RadioButton radio, string text)
    {
        radio.Content = text;
        AutomationProperties.SetName(radio, text);
    }
}
