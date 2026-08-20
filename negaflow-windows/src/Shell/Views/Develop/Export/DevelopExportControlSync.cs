using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

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
            SelectByTag(view.ExportFormatSelector, view.exportSettings.Format.ToString());
            SelectByTag(view.ExportTiffCompressionSelector, view.exportSettings.TiffCompression.ToString());
            SelectByTag(
                view.ExportBitDepthSelector,
                view.exportSettings.EffectiveBitDepth.ToString(CultureInfo.InvariantCulture));
            SelectByTag(view.ExportDpiSelector, view.exportSettings.Dpi);
            SelectByTag(view.ExportSizeSelector, view.exportSettings.LongEdge);
            SelectByTag(
                view.ExportSharpeningMediumSelector,
                view.exportSettings.OutputSharpeningMedium.ToString());
            view.ExportJpegQualitySlider.Value = Math.Round(view.exportSettings.JpegQuality * 100.0);
            view.ExportSharpeningSlider.Value = Math.Round(view.exportSettings.OutputSharpening * 100.0);
            if (view.ExportNamePatternBox.Text != view.exportSettings.NamingTemplate)
            {
                view.ExportNamePatternBox.Text = view.exportSettings.NamingTemplate;
            }
            view.ExportSequenceStartBox.Value = view.exportSettings.SequenceStart;

            SelectByTag(view.QuickExportFormatSelector, view.quickExportSettings.Format.ToString());
            SelectByTag(view.QuickExportDpiSelector, view.quickExportSettings.Dpi);
            SelectByTag(view.QuickExportSizeSelector, view.quickExportSettings.LongEdge);
            view.QuickExportJpegQualitySlider.Value =
                Math.Round(view.quickExportSettings.JpegQuality * 100.0);
            view.recipes.SynchronizeExportRecipeControls();
            view.ExportMainFlatMasterToggle.IsOn = view.exportSettings.WriteMainFlatMaster;
            view.ExportOriginalRawToggle.IsOn = view.exportSettings.WriteOriginalRaw;
            view.ExportSidecarToggle.IsOn = view.exportSettings.WriteSidecar;
            view.ExportPreserveAlphaToggle.IsOn = view.exportSettings.PreserveAlpha;
            view.ExportMetadataSelector.SelectedIndex = view.exportSettings.MetadataPolicy switch
            {
                ExportMetadataPolicy.CopyrightOnly => 1,
                ExportMetadataPolicy.RemoveLocation => 2,
                ExportMetadataPolicy.All => 3,
                _ => 0,
            };
        }
        finally
        {
            view.isSynchronizingExport = false;
        }

        view.ExportJpegQualityRow.Visibility = Visible(
            view.exportSettings.Format == DevelopExportFormat.Jpeg8);
        view.ExportTiffCompressionRow.Visibility = Visible(
            view.exportSettings.Format == DevelopExportFormat.Tiff16);
        // JPEG 은 정의상 8-bit 이므로 고를 것이 없습니다.
        view.ExportBitDepthRow.Visibility = Visible(
            view.exportSettings.Format != DevelopExportFormat.Jpeg8);
        view.ExportPreserveAlphaToggle.Visibility = Visible(
            view.exportSettings.Format != DevelopExportFormat.Jpeg8);
        view.ExportBitDepthLabel.Text = AppResources.Get(
            view.exportSettings.Format == DevelopExportFormat.Tiff16
                ? "developExportTiffBitDepth"
                : "developExportPngBitDepth",
            "Text");
        AutomationProperties.SetName(view.ExportBitDepthSelector, view.ExportBitDepthLabel.Text);
        // macOS 는 강도가 0 이면 매체를 고를 수 없게 둡니다 — 아무 것도 바꾸지 않는 선택입니다.
        view.ExportSharpeningMediumSelector.IsEnabled = view.exportSettings.OutputSharpening > 0;
        view.ExportSequenceStartRow.Visibility = Visible(
            ExportNamingTemplate.UsesSequence(view.exportSettings.NamingTemplate));
        view.QuickExportJpegQualityRow.Visibility = Visible(
            view.quickExportSettings.Format == DevelopExportFormat.Jpeg8);
        view.ExportJpegQualityValue.Text = Percent(view.exportSettings.JpegQuality);
        view.ExportSharpeningValue.Text = Percent(view.exportSettings.OutputSharpening);
        view.QuickExportJpegQualityValue.Text = Percent(view.quickExportSettings.JpegQuality);
        view.RefreshPreview();
    }

    internal ExportNamingContext NamingContextFor(LibraryFrameSnapshot frame) =>
        ExportNamingContexts.For(
            frame,
            view.libraryHost?.RollFor(frame.Id),
            view.exportSettings.SequenceStart);

    internal static string Percent(double unit) =>
        Math.Round(unit * 100.0).ToString("0", CultureInfo.CurrentCulture) + "%";

    internal static Visibility Visible(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;

    internal static void SelectByTag(ComboBox selector, object tag)
    {
        foreach (object item in selector.Items)
        {
            if (item is ComboBoxItem candidate && Equals(candidate.Tag, tag))
            {
                selector.SelectedItem = candidate;
                return;
            }
        }
    }

    internal void UpdateExportPreview()
    {
        if (view.ExportPreviewText is null)
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
            AppResources.Get("exportSection", "Text"));
        view.ExportFolderPathText.Text = projected.ExportFolderPath;
        view.QuickExportFolderPathText.Text = projected.QuickExportFolderPath;
        view.ExportPreviewText.Text = projected.ExportFileNamePreview;
        view.QuickExportFilenameText.Text = projected.QuickExportFileName;
        view.ExportSourceSummaryText.Text = projected.SourceSummary;
        view.ExportButton.IsActionEnabled = projected.CanExport;
        view.QuickExportButton.IsActionEnabled = projected.CanExport;
        view.ExportButton.Title = projected.ExportButtonText;
    }
}
