using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Export;

/// <summary>저장된 내보내기 값을 컨트롤에 되비춥니다.</summary>
internal sealed class DevelopExportControlSync
{
    private readonly DevelopExportPanel view;

    internal DevelopExportControlSync(DevelopExportPanel view) => this.view = view;

    /// <summary>
    /// 저장된 값을 컨트롤에 되비춥니다. 형식마다 화질을 정하는 손잡이가 다르므로 보이는 줄도
    /// 형식이 정합니다 — macOS 와 같은 규칙입니다.
    /// </summary>
    internal void SynchronizeExportControls()
    {
        if (view.ExportFormatSelector is null)
        {
            return;
        }
        view.isSynchronizingExport = true;
        try
        {
            view.ExportFormatSelector.SelectByTag(view.exportSettings.Format.ToString());
            view.ExportTiffCompressionSelector.SelectByTag(
                view.exportSettings.TiffCompression.ToString());
            view.ExportBitDepthSelector.SelectByTag(
                view.exportSettings.EffectiveBitDepth.ToString(CultureInfo.InvariantCulture));
            view.ExportDpiSelector.SelectByTag(view.exportSettings.Dpi);
            view.ExportSizeSelector.SelectByTag(view.exportSettings.LongEdge);
            view.ExportSharpeningMediumSelector.SelectByTag(
                view.exportSettings.OutputSharpeningMedium.ToString());
            view.ExportJpegQualitySlider.Value = Math.Round(view.exportSettings.JpegQuality * 100.0);
            view.ExportSharpeningSlider.Value = Math.Round(view.exportSettings.OutputSharpening * 100.0);
            if (view.ExportNamePatternBox.Text != view.exportSettings.NamingTemplate)
            {
                view.ExportNamePatternBox.Text = view.exportSettings.NamingTemplate;
            }
            view.ExportSequenceStartBox.Value = view.exportSettings.SequenceStart;

            view.QuickExportFormatSelector.SelectByTag(view.quickExportSettings.Format.ToString());
            view.QuickExportDpiSelector.SelectByTag(view.quickExportSettings.Dpi);
            view.QuickExportSizeSelector.SelectByTag(view.quickExportSettings.LongEdge);
            view.QuickExportJpegQualitySlider.Value =
                Math.Round(view.quickExportSettings.JpegQuality * 100.0);
            view.recipes.SynchronizeExportRecipeControls();
            view.ExportMainFlatMasterRow.IsOn = view.exportSettings.WriteMainFlatMaster;
            view.ExportOriginalRawRow.IsOn = view.exportSettings.WriteOriginalRaw;
            view.ExportSidecarRow.IsOn = view.exportSettings.WriteSidecar;
            view.ExportPreserveAlphaRow.IsOn = view.exportSettings.PreserveAlpha;
            view.ExportMetadataSelector.SelectSilently(view.exportSettings.MetadataPolicy switch
            {
                ExportMetadataPolicy.CopyrightOnly => 1,
                ExportMetadataPolicy.RemoveLocation => 2,
                ExportMetadataPolicy.All => 3,
                _ => 0,
            });
        }
        finally
        {
            view.isSynchronizingExport = false;
        }

        view.ExportBitDepthRow.Label = AppResources.Get(
            view.exportSettings.Format == DevelopExportFormat.Tiff16
                ? "developExportTiffBitDepth"
                : "developExportPngBitDepth",
            "Text");
        AutomationProperties.SetName(view.ExportBitDepthSelector, view.ExportBitDepthRow.Label);
        // macOS 는 강도가 0 이면 매체를 고를 수 없게 둡니다 — 아무 것도 바꾸지 않는 선택입니다.
        view.ExportSharpeningMediumSelector.IsEnabled = view.exportSettings.OutputSharpening > 0;
        view.SetQuickExportRowVisible(
            view.QuickExportJpegQualityRow,
            view.quickExportSettings.Format == DevelopExportFormat.Jpeg8);
        view.ExportJpegQualityValue.Text = Percent(view.exportSettings.JpegQuality);
        view.ExportSharpeningValue.Text = Percent(view.exportSettings.OutputSharpening);
        view.QuickExportJpegQualityValue.Text = Percent(view.quickExportSettings.JpegQuality);
        // 탭이 바뀌지 않아도 형식에 따라 줄이 늘고 줄어듭니다. 지금 고른 탭에 속하고
        // 형식이 허락하는 줄만 남깁니다 - 두 조건을 따로 쓰면 나중에 쓴 쪽이 앞의 것을
        // 덮어 JPEG 인데 비트 깊이가 남는 식이 됩니다.
        ApplyExportDetailTab();
        view.RefreshPreview();
    }

    /// <summary>
    /// 지금 고른 세부 탭(파일 · 품질 · 소스)에 속한 줄만 남깁니다. macOS 는
    /// <c>switch selectedDetailPage</c> 로 행 자체를 갈아 끼우므로 여기서도 <b>행을
    /// 숨겨</b> 카드 안 분리선이 따라가게 합니다.
    /// </summary>
    internal void ApplyExportDetailTab()
    {
        string page = view.ExportQualityTabButton.IsChecked == true
            ? "quality"
            : view.ExportSourceTabButton.IsChecked == true ? "source" : "file";
        DevelopExportFormat format = view.exportSettings.Format;
        bool changed = false;
        foreach (FrameworkElement row in view.ExportCard.Rows)
        {
            // 분리선은 카드가 스스로 끼워 넣은 것입니다. 표식이 문자열이라 그냥 훑으면
            // 페이지에 속하지 않는 줄로 보여 **분리선이 통째로 사라집니다.**
            if (SettingsSection.IsSeparator(row) || row.Tag is not string tag)
            {
                // 탭에 속하지 않는 줄(내보내기 설정 · 미리보기 · 단추)은 늘 보입니다.
                continue;
            }
            Visibility wanted = Visible(
                string.Equals(tag, page, StringComparison.Ordinal) && AllowedByFormat(row, format));
            if (row.Visibility == wanted)
            {
                continue;
            }
            row.Visibility = wanted;
            changed = true;
        }
        if (changed)
        {
            // 줄이 늘거나 줄면 분리선을 다시 놓습니다 — 그러지 않으면 접힌 줄 앞의 선이
            // 빈 자리에 남습니다. 값이 그대로면 건드리지 않습니다(슬라이더를 끄는 동안
            // 카드를 매번 다시 꾸미면 그만큼 밀립니다).
            view.ExportCard.Apply();
        }
    }

    /// <summary>형식이 그 줄을 쓰는지입니다. 쓰지 않는 손잡이는 macOS 도 내립니다.</summary>
    private bool AllowedByFormat(FrameworkElement row, DevelopExportFormat format)
    {
        if (ReferenceEquals(row, view.ExportJpegQualityRow))
        {
            return format == DevelopExportFormat.Jpeg8;
        }
        if (ReferenceEquals(row, view.ExportTiffCompressionRow))
        {
            return format == DevelopExportFormat.Tiff16;
        }
        // JPEG 은 정의상 8-bit 이라 고를 것이 없고 알파도 담지 못합니다.
        if (ReferenceEquals(row, view.ExportBitDepthRow) ||
            ReferenceEquals(row, view.ExportPreserveAlphaRow))
        {
            return format != DevelopExportFormat.Jpeg8;
        }
        if (ReferenceEquals(row, view.ExportSequenceStartRow))
        {
            return ExportNamingTemplate.UsesSequence(view.exportSettings.NamingTemplate);
        }
        return true;
    }

    internal ExportNamingContext NamingContextFor(LibraryFrameSnapshot frame) =>
        ExportNamingContexts.For(
            frame,
            view.libraryHost?.RollFor(frame.Id),
            view.exportSettings.SequenceStart);

    /// <summary>
    /// 빠른 내보내기의 이름 문맥입니다. macOS <c>quickExport(_:)</c> 와 같이 본 내보내기와
    /// <b>같은 이름</b>을 쓰되 순번만 1 로 고정합니다 — 빠른 내보내기에는 순번 시작 칸이
    /// 없습니다.
    /// </summary>
    internal ExportNamingContext QuickNamingContextFor(LibraryFrameSnapshot frame) =>
        ExportNamingContexts.For(frame, view.libraryHost?.RollFor(frame.Id), 1);

    internal static string Percent(double unit) =>
        Math.Round(unit * 100.0).ToString("0", CultureInfo.CurrentCulture) + "%";

    internal static Visibility Visible(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;

    internal void UpdateExportPreview()
    {
        if (view.ExportPreviewRow is null)
        {
            return;
        }
        LibraryFrameSnapshot? frame = view.panel?.SelectedFrame;
        ExportPanelView projected = ExportPanelProjection.Create(
            frame,
            view.exportSettings,
            view.quickExportSettings,
            frame is null ? null : NamingContextFor(frame),
            view.panel?.CanExport == true,
            view.libraryHost?.SelectedFrames.Count ?? 0,
            AppResources.Get("developExportFolderBesideSource", "Text"),
            AppResources.Get("exportSection", "Text"),
            AppResources.Get("commandQuickExport", "Text"),
            view.UsesPaperLayout,
            view.UsesCompositeLayout,
            view.PaperOutputCount?.Invoke() ?? 0);
        view.ExportFolderPathText.Text = projected.ExportFolderPath;
        view.QuickExportFolderPathText.Text = projected.QuickExportFolderPath;
        // 줄에는 폴더 이름만 적습니다(macOS `exportFolderDisplay`). 전체 경로는 여기서
        // 알려 줍니다 - 이름만 보고는 같은 이름의 다른 폴더를 가릴 수 없습니다.
        ToolTipService.SetToolTip(
            view.ExportFolderPathText,
            view.exportSettings.FolderPath is { Length: > 0 } exportFolder
                ? exportFolder
                : projected.ExportFolderPath);
        ToolTipService.SetToolTip(
            view.QuickExportFolderPathText,
            view.quickExportSettings.FolderPath is { Length: > 0 } quickFolder
                ? quickFolder
                : projected.QuickExportFolderPath);
        view.ExportPreviewRow.ValueText = projected.ExportFileNamePreview;
        // macOS `ExportNamingControls` — 패턴이 깨져 있으면 미리보기를 빨갛게 냅니다.
        // 그러지 않으면 무엇이 잘못됐는지 알려 주는 자리가 아예 없습니다.
        view.ExportPreviewRow.Kind = ExportNamingTemplate.IsValid(view.exportSettings.NamingTemplate)
            ? SettingsRowValueKind.Secondary
            : SettingsRowValueKind.Danger;
        view.ExportPreviewRow.ApplyBrushes();
        view.QuickExportFilenameRow.ValueText = projected.QuickExportFileName;
        view.ExportSourceSummaryRow.ValueText = projected.SourceSummary;
        view.ExportButton.IsActionEnabled = projected.CanExport;
        view.QuickExportButton.IsActionEnabled = projected.CanExport;
        view.ExportButton.Title = projected.ExportButtonText;
        view.QuickExportButton.Title = projected.QuickExportButtonText;
    }

    /// <summary>고를 수 있는 값들을 팝업 단추에 담습니다.</summary>
    internal static void FillSelector(
        NegaflowPopupPicker selector,
        IReadOnlyList<(string Text, object? Tag)> items) =>
        selector.SetOptions([.. items.Select(item => new PopupPickerOption(item.Text, item.Tag))]);
}
