using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

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
        // macOS `sectionHeader(내보내기 / 빠른 내보내기)` — 두 절의 머리글입니다.
        view.ExportSectionText.Text = AppResources.Get("exportSection", "Text");
        view.QuickExportSectionText.Text = AppResources.Get("quickExportSection", "Text");

        SetRadioText(view.ExportFileTabButton, AppResources.Get("developExportTabFile", "Content"));
        SetRadioText(view.ExportQualityTabButton, AppResources.Get("developExportTabQuality", "Content"));
        SetRadioText(view.ExportSourceTabButton, AppResources.Get("developExportTabSource", "Content"));

        view.ExportRecipeRow.Label = AppResources.Get("developExportRecipeTitle", "Text");
        AutomationProperties.SetName(view.ExportRecipeSelector, view.ExportRecipeRow.Label);
        SetLocalizedNameAndTooltip(view.ExportRecipeMenuButton, view.ExportRecipeRow.Label);

        // 파일
        view.ExportFormatRow.Label = AppResources.Get("developExportFormat", "Text");
        AutomationProperties.SetName(view.ExportFormatSelector, view.ExportFormatRow.Label);
        FillFormatSelector(view.ExportFormatSelector);
        view.ExportFolderRow.Label = AppResources.Get("developExportFolder", "Text");
        SetButtonText(
            view.ExportFolderButton,
            AppResources.Get("developExportFolderChange", "Content"));
        view.ExportNamePatternRow.Label = AppResources.Get("developExportNamePattern", "Text");
        AutomationProperties.SetName(view.ExportNamePatternBox, view.ExportNamePatternRow.Label);
        view.ExportSequenceStartRow.Label = AppResources.Get("developExportSequenceStart", "Text");
        AutomationProperties.SetName(view.ExportSequenceStartBox, view.ExportSequenceStartRow.Label);
        SetLocalizedNameAndTooltip(
            view.ExportNamingOptionsButton,
            AppResources.Get("developExportNamingOptions", "Text"));
        BuildNamingOptionsMenu();

        // 품질
        view.ExportJpegQualityRow.Label = AppResources.Get("developExportJpegQuality", "Text");
        AutomationProperties.SetName(view.ExportJpegQualitySlider, view.ExportJpegQualityRow.Label);
        view.ExportTiffCompressionRow.Label = AppResources.Get("developExportTiffCompression", "Text");
        AutomationProperties.SetName(
            view.ExportTiffCompressionSelector,
            view.ExportTiffCompressionRow.Label);
        // LZW 는 고르는 자리에서 뺐습니다 — 이유는 `ExportSettings.TiffCompressionOptions`
        // 에 적어 두었습니다. 그 목록과 여기가 어긋나면 고를 수 없는 값이 남으므로 목록을
        // 따라 돌면서 이름만 붙입니다.
        DevelopExportControlSync.FillSelector(
            view.ExportTiffCompressionSelector,
            [.. ExportSettings.TiffCompressionOptions.Select(
                compression => (TiffCompressionText(compression), (object?)compression.ToString()))]);
        // 비트 깊이 이름은 형식에 따라 바뀝니다(TIFF/PNG). 목록 자체는 같습니다.
        FillBitDepthSelector(view.ExportBitDepthSelector);
        view.ExportPreserveAlphaRow.Label = AppResources.Get("developExportPreserveAlpha", "Content");

        view.ExportDpiRow.Label = AppResources.Get("developExportDpi", "Text");
        AutomationProperties.SetName(view.ExportDpiSelector, view.ExportDpiRow.Label);
        view.ExportSizeRow.Label = AppResources.Get("developExportSize", "Text");
        AutomationProperties.SetName(view.ExportSizeSelector, view.ExportSizeRow.Label);
        FillDpiSelector(view.ExportDpiSelector);
        FillSizeSelector(view.ExportSizeSelector);

        view.ExportSharpeningRow.Label = AppResources.Get("developOutputSharpening", "Text");
        AutomationProperties.SetName(view.ExportSharpeningSlider, view.ExportSharpeningRow.Label);
        view.ExportSharpeningMediumRow.Label =
            AppResources.Get("developOutputSharpeningMedium", "Text");
        AutomationProperties.SetName(
            view.ExportSharpeningMediumSelector,
            view.ExportSharpeningMediumRow.Label);
        DevelopExportControlSync.FillSelector(view.ExportSharpeningMediumSelector, [
            (AppResources.Get("developSharpenScreen", "Content"),
                (object?)OutputSharpeningMedium.Screen.ToString()),
            (AppResources.Get("developSharpenMattePaper", "Content"),
                OutputSharpeningMedium.MattePaper.ToString()),
            (AppResources.Get("developSharpenGlossyPaper", "Content"),
                OutputSharpeningMedium.GlossyPaper.ToString()),
        ]);

        // 소스
        view.ExportMetadataRow.Label = AppResources.Get("developExportMetadata", "Text");
        AutomationProperties.SetName(view.ExportMetadataSelector, view.ExportMetadataRow.Label);
        DevelopExportControlSync.FillSelector(view.ExportMetadataSelector, [
            (AppResources.Get("developExportMetadataMinimal", "Text"), (object?)"Minimal"),
            (AppResources.Get("developExportMetadataCopyright", "Text"), "CopyrightOnly"),
            (AppResources.Get("developExportMetadataRemoveLocation", "Text"), "RemoveLocation"),
            (AppResources.Get("developExportMetadataAll", "Text"), "All"),
        ]);
        view.ExportMainFlatMasterRow.Label =
            AppResources.Get("developExportMainFlatMaster", "Content");
        view.ExportOriginalRawRow.Label = AppResources.Get("developExportOriginalRaw", "Content");
        view.ExportSidecarRow.Label = AppResources.Get("developExportSidecar", "Content");
        view.ExportSourceSummaryRow.Label = AppResources.Get("developExportSourceLabel", "Text");
        view.ExportPreviewRow.Label = AppResources.Get("developExportPreview", "Text");

        // 빠른 내보내기
        view.QuickExportFormatRow.Label = view.ExportFormatRow.Label;
        AutomationProperties.SetName(view.QuickExportFormatSelector, view.QuickExportFormatRow.Label);
        // macOS 빠른 내보내기는 JPEG 과 PNG 둘만 고릅니다 - 보관용 TIFF 는 "빠른" 자리가
        // 아니라 위쪽 내보내기가 맡습니다.
        DevelopExportControlSync.FillSelector(view.QuickExportFormatSelector, [
            ("JPEG", (object?)DevelopExportFormat.Jpeg8.ToString()),
            ("PNG", DevelopExportFormat.Png16.ToString()),
        ]);
        view.QuickExportDpiRow.Label = view.ExportDpiRow.Label;
        AutomationProperties.SetName(view.QuickExportDpiSelector, view.QuickExportDpiRow.Label);
        view.QuickExportSizeRow.Label = view.ExportSizeRow.Label;
        AutomationProperties.SetName(view.QuickExportSizeSelector, view.QuickExportSizeRow.Label);
        view.QuickExportJpegQualityRow.Label = view.ExportJpegQualityRow.Label;
        AutomationProperties.SetName(
            view.QuickExportJpegQualitySlider,
            view.QuickExportJpegQualityRow.Label);
        view.QuickExportFolderRow.Label = view.ExportFolderRow.Label;
        SetButtonText(
            view.QuickExportFolderButton,
            AppResources.Get("developExportFolderChange", "Content"));
        view.QuickExportFilenameRow.Label = AppResources.Get("developExportFilename", "Text");
        FillDpiSelector(view.QuickExportDpiSelector);
        FillSizeSelector(view.QuickExportSizeSelector);

        string reveal = AppResources.Get("libraryShowInExplorer", "Content");
        // 강조 알약의 이름은 고른 사진 수에 따라 바뀌므로 되비출 때 넣습니다. 빠른 내보내기는
        // 늘 같은 이름입니다.
        view.QuickExportButton.Title = AppResources.Get("commandQuickExport", "Text");
        view.QuickExportButton.RevealHelp = reveal;
        view.ExportButton.Title = AppResources.Get("commandExport", "Text");
        view.ExportButton.RevealHelp = reveal;

        view.SynchronizeExportControls();
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

    /// <summary>TIFF 압축 이름입니다. 고를 수 있는 것은 없음과 Deflate 둘뿐입니다.</summary>
    private static string TiffCompressionText(DevelopTiffCompression compression) =>
        compression == DevelopTiffCompression.Deflate
            ? AppResources.Get("developExportCompressionDeflate", "Content")
            : AppResources.Get("developExportCompressionNone", "Content");

    /// <summary>내보낼 형식입니다. macOS <c>DevelopExportFormat.allCases</c> 와 같은 셋입니다.</summary>
    internal static void FillFormatSelector(NegaflowPopupPicker selector) =>
        DevelopExportControlSync.FillSelector(selector, [
            ("TIFF", (object?)DevelopExportFormat.Tiff16.ToString()),
            ("PNG", DevelopExportFormat.Png16.ToString()),
            ("JPEG", DevelopExportFormat.Jpeg8.ToString()),
        ]);

    /// <summary>채널당 비트입니다. 이름은 형식이 정하고 값은 같습니다.</summary>
    internal static void FillBitDepthSelector(NegaflowPopupPicker selector) =>
        DevelopExportControlSync.FillSelector(selector, [
            ("8", (object?)"8"),
            ("16", "16"),
        ]);

    internal static void FillDpiSelector(NegaflowPopupPicker selector)
    {
        string sourceDpi = AppResources.Get("settingsSourceDPI", "Text");
        DevelopExportControlSync.FillSelector(selector, [.. ExportSettings.DpiOptions.Select(
            dpi => (
                dpi == 0 ? sourceDpi : string.Create(CultureInfo.CurrentCulture, $"{dpi} dpi"),
                (object?)dpi))]);
    }

    internal static void FillSizeSelector(NegaflowPopupPicker selector)
    {
        string fullSize = AppResources.Get("exportFullSize", "Text");
        string suffix = AppResources.Get("developExportLongEdgeSuffix", "Text");
        DevelopExportControlSync.FillSelector(selector, [.. ExportSettings.LongEdgeOptions.Select(
            edge => (
                edge == 0 ? fullSize : string.Create(CultureInfo.CurrentCulture, $"{edge} {suffix}"),
                (object?)edge))]);
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
