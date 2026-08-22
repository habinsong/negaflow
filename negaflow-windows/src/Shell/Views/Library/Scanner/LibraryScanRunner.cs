using System.IO;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Library.Scanner;

/// <summary>스캔해서 카탈로그에 게시합니다. 컨트롤 되비춤과 다른 이유입니다.</summary>
internal sealed class LibraryScanRunner
{
    private readonly LibraryScanPanel view;

    private CancellationTokenSource? running;

    internal LibraryScanRunner(LibraryScanPanel view) => this.view = view;

    /// <summary>macOS <c>cancelScan()</c> — 스캔 중에만 뜨는 취소 단추가 부릅니다.</summary>
    internal void Cancel() => running?.Cancel();

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
            // macOS `diskStorage.scansPath` — 스캔 패널에서 고른 자리가 우선이고, 없으면
            // 설정 · 디스크 탭의 "스캔 원본" 폴더입니다. 둘 다 없을 때만 카탈로그 옆으로
            // 갑니다 — 원본을 사용자가 모르는 곳에 두지 않기 위해서입니다.
            // 프리뷰는 원본이 아니라 프레임 찾기용 임시 그림입니다. macOS 도 스캔 원본과
            // 다른 자리(스캔 프리뷰 캐시)에 둡니다 - 원본 폴더에 섞이면 사용자가 지운 뒤에도
            // 남아 장수가 어긋납니다.
            string scanRoot = preview && view.diskScanPreviewRoot is { Length: > 0 } previewRoot
                ? previewRoot
                : view.scanSession.ScanStorageRoot is { Length: > 0 } chosen
                    ? chosen
                    : view.diskScanRoot is { Length: > 0 } configured
                        ? configured
                        : Path.Combine(roots.LibraryRoot, "Scans");
            directory = ScanStorageLayout.EnsureRollDirectory(
                scanRoot,
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
        using CancellationTokenSource cancellation = new();
        running?.Cancel();
        running = cancellation;
        ScanRunOutcome outcome;
        try
        {
            outcome = await view.scanSession.RunAsync(
                view.libraryHost,
                _ => ScanStorageLayout.NextAvailablePath(directory, stem),
                preview,
                cancellation.Token);
        }
        catch (OperationCanceledException)
        {
            // macOS 도 취소를 실패로 적지 않습니다 — 사용자가 멈춘 것입니다.
            view.ScanStatusText.Text = string.Empty;
            return;
        }
        finally
        {
            if (ReferenceEquals(running, cancellation))
            {
                running = null;
            }
        }
        view.ScanStatusText.Text = Describe(outcome);
        if (preview)
        {
            RemoveStalePreviewFrames();
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
                    view.flatbedPreview.Height,
                    view.flatbedPreview.PhysicalWidthMm,
                    view.flatbedPreview.PhysicalHeightMm);
            }
            view.renderer.Render();
            return;
        }
        view.RequestLibraryReload();
    }

    /// <summary>
    /// 지난 프리뷰 프레임을 걷어냅니다. macOS <c>removeEphemeralPreviewFrames(keeping:)</c>
    /// 자리이며, 남겨 두면 프리뷰를 누를 때마다 임시 그림이 쌓입니다.
    /// </summary>
    private void RemoveStalePreviewFrames()
    {
        if (view.libraryHost is not { } host)
        {
            return;
        }
        string? keep = host.ActiveFrameId;
        List<string> stale = [.. host.Frames
            .Where(frame => frame.IsPreviewScan && frame.Id != keep)
            .Select(frame => frame.Id)];
        if (stale.Count != 0)
        {
            _ = host.RemoveFrames(stale);
        }
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
