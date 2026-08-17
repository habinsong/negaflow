using System.IO;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>스캔해서 카탈로그에 게시합니다. 컨트롤 되비춤과 다른 이유입니다.</summary>
internal sealed class LibraryScanRunner
{
    private readonly LibraryScanPanel view;

    internal LibraryScanRunner(LibraryScanPanel view) => this.view = view;

    /// <summary>
    /// 스캔해서 카탈로그에 게시하고 격자를 다시 그립니다. 목적지는 매 장마다 새로 고르므로
    /// 이어서 뜨는 배치가 서로를 덮지 않습니다.
    /// </summary>
    internal async Task RunAsync(bool preview)
    {
        if (view.scanSession is null || view.libraryHost is null)
        {
            return;
        }
        if (view.libraryHost.StorageRoots is not { } roots)
        {
            view.ScanStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
            return;
        }

        string rollName = string.IsNullOrWhiteSpace(view.scanSession.Options.FolderName)
            ? AppResources.Get("scanUntitledFilm", "Text")
            : view.scanSession.Options.FolderName;
        string stem = ScanStorageLayout.ScannerAbbreviation(
            view.scanSession.SelectedDevice?.DisplayName);
        string directory;
        try
        {
            directory = ScanStorageLayout.EnsureRollDirectory(
                Path.Combine(roots.LibraryRoot, "Scans"),
                view.scanSession.Options.FilmType,
                rollName,
                DateTime.Now);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            view.ScanStatusText.Text = AppResources.Get("libraryImportFailed", "Text");
            return;
        }

        view.ScanStatusText.Text = AppResources.Get("scanSection", "Text");
        ScanRunOutcome outcome = await view.scanSession.RunAsync(
            view.libraryHost,
            _ => ScanStorageLayout.NextAvailablePath(directory, stem),
            preview);
        view.ScanStatusText.Text = Describe(outcome);
        if (preview)
        {
            // 프리뷰는 카탈로그에 올리지 않습니다. 그림만 읽어 두었다가 프레임 찾기에 넘깁니다.
            view.flatbedPreview = view.scanSession.LastPreviewPath is { } previewPath
                ? await PreviewLuminanceReader.ReadAsync(previewPath)
                : PreviewLuminance.None;
            if (!view.flatbedPreview.IsEmpty &&
                view.scanSession.Options.FrameDetectionMode == FlatbedFrameDetectionMode.Automatic)
            {
                _ = view.scanSession.RefreshRegions(
                    view.flatbedPreview.Values,
                    view.flatbedPreview.Width,
                    view.flatbedPreview.Height);
            }
            view.renderer.Render();
            return;
        }
        view.RequestLibraryReload();
    }

    private string Describe(ScanRunOutcome outcome)
    {
        if (outcome.IsSuccess)
        {
            return AppResources.FormatIntegers(
                "libraryFolderImportResult",
                "Text",
                outcome.Published,
                1);
        }
        // 실패는 어느 단계에서 멈췄는지를 남깁니다. "스캔 실패" 만으로는 다시 시도하는 것 말고
        // 사용자가 할 수 있는 일이 없습니다.
        string reason = view.scanSession?.LastFailureName ??
            outcome.LastScanStatus?.ToString() ??
            "unavailable";
        return AppResources.Get("libraryImportFailed", "Text") + " — " + reason;
    }
}
