using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views.Print.Export;

/// <summary>
/// 인화뷰의 내보내기 · 빠른 내보내기입니다. macOS <c>exportPrintSelectionToFolder</c> ·
/// <c>quickExportPrintSelection</c> 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// 현상뷰와 같은 <c>ExportSection</c> 을 쓰지만 나가는 그림이 다릅니다 — 현상뷰는 사진
/// 한 장이고 인화뷰는 <b>판에 얹은 합성본</b>입니다(macOS 는 같은 배치에
/// <c>printComposition:</c> 을 얹어 보냅니다). Windows 는 그 합성을
/// <see cref="PrintSheetWriter"/> 가 이미 하고 있으므로 그것을 씁니다.
/// </para>
/// <para>
/// 폴더는 <b>묻지 않습니다</b>. macOS 도 <c>exportFolderURL</c> · <c>quickExportFolderURL</c>
/// 로 바로 씁니다 — 어디로 나갈지는 출력 탭에서 이미 고른 값입니다.
/// </para>
/// </remarks>
internal sealed class PrintSheetExportRunner
{
    private readonly Func<IReadOnlyList<LibraryFrameSnapshot>> sources;
    private readonly Func<WorkspacePresentationState?> state;
    private readonly Panel textRasterHost;
    private readonly Action<string> report;

    private bool isRunning;

    internal PrintSheetExportRunner(
        Func<IReadOnlyList<LibraryFrameSnapshot>> sources,
        Func<WorkspacePresentationState?> state,
        Panel textRasterHost,
        Action<string> report)
    {
        this.sources = sources;
        this.state = state;
        this.textRasterHost = textRasterHost;
        this.report = report;
    }

    /// <summary>출력 탭의 "내보내기" 폴더로, 고른 형식으로 판을 씁니다.</summary>
    internal Task RunExportAsync(ExportSettings settings) =>
        RunAsync(settings.FolderPath, settings.Format, settings.JpegQuality);

    /// <summary>출력 탭의 "빠른 내보내기" 폴더로, 고른 형식으로 판을 씁니다.</summary>
    internal Task RunQuickExportAsync(QuickExportSettings settings) =>
        RunAsync(settings.FolderPath, settings.Format, settings.JpegQuality);

    private async Task RunAsync(
        string destinationFolder,
        Negaflow.Interop.DevelopExportFormat format,
        double jpegQuality)
    {
        if (isRunning)
        {
            return;
        }
        IReadOnlyList<LibraryFrameSnapshot> selection = sources();
        if (state() is not { } presentation || selection.Count == 0)
        {
            return;
        }
        if (string.IsNullOrWhiteSpace(destinationFolder))
        {
            // 폴더를 한 번도 고르지 않았습니다. 어디로 나갈지 모르는 채로 쓰지 않습니다.
            report(AppResources.Get("developExportFolderFailed", "Text"));
            return;
        }

        // 인화소 ICC 를 고릅니다. macOS `selectedPrintWorkspaceOutputProfile` 과 같은 규칙이며,
        // 있어야 하는데 없으면 **내보내지 않고** 알립니다 — 그대로 내면 랩이 받는 색이 달라집니다.
        PrintOutputProfileChoice profile = PrintOutputProfile.For(
            selection,
            presentation.Current.Print,
            presentation.Current.SoftProof);
        if (profile.Missing)
        {
            report(AppResources.Get("printOutputProfileRequired", "Text"));
            return;
        }

        isRunning = true;
        report(string.Empty);
        try
        {
            ExportTrace.Write(
                $"print sheet press frames={selection.Count} format={format} " +
                $"icc={(profile.Profile is { } bytes ? bytes.Length : 0)}");
            using IDisposable _pressed = ExportTrace.Measure("print sheet total");
            PrintSheetWriteResult result = await PrintSheetWriter.WriteAsync(
                selection,
                presentation.Current.Print,
                destinationFolder,
                LibraryFrameNaming.DisplayName(selection[0]),
                textRasterHost,
                format,
                jpegQuality,
                profile.Profile);
            // 실패는 어느 단계에서 멈췄는지를 남깁니다. "쓰지 못했습니다" 만으로는 다시
            // 눌러 보는 것 말고 사용자가 할 수 있는 일이 없습니다 - 스캔 실패 줄과 같은
            // 규칙입니다.
            PreviewTrace.Write(
                $"print sheet export status={result.Status} count={result.Paths.Count} " +
                $"sources={selection.Count} folder={destinationFolder}");
            report(result.IsSuccess
                ? AppResources
                    .Get("printExportDone", "Text")
                    .Replace("{0}", destinationFolder, StringComparison.Ordinal)
                : AppResources.Get("printExportFailed", "Text") + " - " + result.Status);
        }
        finally
        {
            isRunning = false;
        }
    }
}
