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
            // 사유는 기록에만 남깁니다 - 스캔 단추 아래 빨간 줄은 사용자가 할 수 있는 일을
            // 알려 주지 않습니다.
            ScannerDiagnosticsLog.Write("scan run refused - no storage roots");
            view.SetScanStatus(string.Empty);
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
            if (preview)
            {
                // **프리뷰는 스캔 폴더에 넣지 않습니다.**
                //
                // macOS `AppModel+PreviewScanning`:
                //   opts.temporaryOutputURL = ScanTempFile.makeURL(
                //       prefix: "negaflow_preview", suffix: ".tiff", in: diskStorage.scanPreviewsURL)
                // 본 스캔만 <스캔 폴더>/<날짜>/<필름 종류>/… 로 갑니다.
                //
                // 앞 판은 프리뷰 캐시 자리가 비어 있으면 조용히 스캔 폴더로 되돌아갔고,
                // 그 자리는 실제로 늘 비어 있었습니다 - 그래서 프리뷰 한 장마다 롤 폴더에
                // `GT-X900-0001.tif` 같은 원본 이름을 하나씩 차지하고 사진 번호를 먹었습니다.
                // 되돌아갈 자리도 프리뷰 캐시여야 합니다.
                directory = view.diskScanPreviewRoot is { Length: > 0 } previewRoot
                    ? previewRoot
                    : Path.Combine(roots.LibraryRoot, ScanStorageLayout.PreviewCacheFolderName);
                _ = Directory.CreateDirectory(directory);
            }
            else
            {
                // macOS `diskStorage.scansPath` — 스캔 패널에서 고른 자리가 우선이고, 없으면
                // 설정 · 디스크 탭의 "스캔 원본" 폴더입니다. 둘 다 없을 때만 카탈로그 옆으로
                // 갑니다 — 원본을 사용자가 모르는 곳에 두지 않기 위해서입니다.
                string scanRoot = view.scanSession.ScanStorageRoot is { Length: > 0 } chosen
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
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ScannerDiagnosticsLog.Write(
                $"scan run refused - roll directory: {error.GetType().Name} {error.Message}");
            view.SetScanStatus(string.Empty);
            return;
        }

        // **돌고 있는 스캔은 끊지 않습니다.**
        //
        // 앞 판은 새 실행이 들어오면 무조건 `running?.Cancel()` 로 앞의 것을 끊었고, 취소를
        // 화면에도 기록에도 남기지 않았습니다. 배치 한 장이 IR 쌍까지 2분씩 걸리는데 그
        // 사이에 어떤 경로로든 이 함수가 한 번 더 불리면 **돌고 있던 롤이 조용히 사라집니다** -
        // 프레임 셋 중 마지막 한 장이 빠지고 실패 기록이 한 줄도 없던 모양입니다.
        //
        // 멈추는 것은 사용자의 취소 단추(`Cancel()`)가 할 일입니다. 여기서는 거절하고
        // 그 사실을 화면에 적습니다 - 조용히 덮어쓰지 않습니다.
        if (running is { IsCancellationRequested: false })
        {
            ScannerDiagnosticsLog.Write(
                $"scan run refused - another run is in flight (preview={preview})");
            view.SetScanStatus(AppResources.Get("scanBusy", "Text"));
            return;
        }
        view.SetScanStatus(string.Empty);
        using CancellationTokenSource cancellation = new();
        running = cancellation;
        ScanRunOutcome outcome;
        try
        {
            outcome = await view.scanSession.RunAsync(
                view.libraryHost,
                _ => preview
                    ? ScanStorageLayout.NewPreviewPath(directory)
                    : ScanStorageLayout.NextAvailablePath(directory, stem),
                preview,
                cancellation.Token,
                // 한 쌍이 끝날 때마다 화면을 갱신합니다. 앞 판은 배치가 **다 끝난 뒤에만**
                // 새로 고쳐서, 프레임 세 장짜리 롤이면 마지막 장이 끝날 때까지 아무 것도
                // 안 보였습니다 - IR 쌍은 한 장에 2분씩 걸립니다.
                framePublished: _ => RequestReloadOnUiThread());
        }
        catch (OperationCanceledException)
        {
            // macOS 도 취소를 실패로 적지 않습니다 — 사용자가 멈춘 것입니다. 화면에는
            // 남기지 않되 **기록에는 남깁니다** - 취소가 조용하면 "마지막 한 장이 왜
            // 빠졌는가" 를 추측으로만 다투게 됩니다.
            ScannerDiagnosticsLog.Write($"scan run cancelled (preview={preview})");
            view.SetScanStatus(string.Empty);
            return;
        }
        finally
        {
            if (ReferenceEquals(running, cancellation))
            {
                running = null;
            }
        }
        view.SetScanStatus(Describe(outcome));
        if (preview)
        {
            RemoveStalePreviewFrames(view.libraryHost?.ActiveFrameId);
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
            view.RequestLibraryReload();
            return;
        }
        // 본 스캔이 사진을 한 장이라도 냈으면 프리뷰는 제 할 일을 마쳤습니다. macOS 는
        // 프레임을 게시할 때마다 `removeEphemeralPreviewFrames(keeping: nil)` 을 부릅니다.
        //
        // **한 장도 못 냈으면 그대로 둡니다.** 스캔이 실패하거나 사용자가 멈춘 뒤에도 프리뷰를
        // 지우면, 찾아 둔 프레임 사각형을 보고 다시 뜨려던 사용자가 프리뷰부터 새로 찍어야
        // 합니다 - 사용자가 아무 것도 얻지 못한 채 가진 것만 잃습니다.
        if (outcome.Published > 0)
        {
            RemoveStalePreviewFrames(keep: null);
            view.flatbedPreview = PreviewLuminance.None;
        }
        view.RequestLibraryReload();
    }

    /// <summary>
    /// <b>UI 스레드로 넘겨서</b> 새로 고칩니다.
    /// </summary>
    /// <remarks>
    /// 본 스캔 경로는 `ConfigureAwait(false)` 로 워커에서 이어집니다. 거기서 곧바로
    /// <c>LibraryChanged</c> 를 올리면 그 처리기가 XAML 속성을 건드리고, WinUI 가
    /// <c>COMException</c>(RPC_E_WRONG_THREAD)을 던져 배치가 통째로 끊깁니다 - 평판
    /// 오버레이에서 실제로 겪은 고장입니다(§22.1).
    /// </remarks>
    private void RequestReloadOnUiThread()
    {
        if (view.DispatcherQueue is not { } queue || queue.HasThreadAccess)
        {
            view.RequestLibraryReload();
            return;
        }
        _ = queue.TryEnqueue(view.RequestLibraryReload);
    }

    /// <summary>
    /// 지난 프리뷰 프레임을 걷어냅니다. macOS <c>removeEphemeralPreviewFrames(keeping:)</c>
    /// 자리이며, 남겨 두면 프리뷰를 누를 때마다 임시 그림이 쌓입니다.
    /// </summary>
    private void RemoveStalePreviewFrames(string? keep)
    {
        if (view.libraryHost is not { } host)
        {
            return;
        }
        List<LibraryFrameSnapshot> stale = [.. host.Frames
            .Where(frame => frame.IsPreviewScan && !string.Equals(frame.Id, keep, StringComparison.Ordinal))];
        if (stale.Count == 0)
        {
            return;
        }
        // 카탈로그에서 빼고, 우리가 지은 이름의 캐시 파일도 지웁니다 - macOS 는 두 가지를
        // 함께 합니다(`removeFramesFromLibrary` + `removeOwnedPreviewFile`).
        _ = host.RemoveFrames([.. stale.Select(frame => frame.Id)]);
        foreach (LibraryFrameSnapshot frame in stale)
        {
            ScanStorageLayout.RemoveOwnedPreviewFile(frame.SourcePath);
        }
    }

    /// <summary>
    /// 실패 사유는 <b>기록에만</b> 남기고 화면에는 내지 않습니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 프리뷰·스캔 단추 바로 아래에 "선택한 사진을 가져올 수 없습니다 —
    /// ProcessFailed" 같은 줄을 띄웠습니다. 스캔을 <b>사용자가 중간에 멈춰도</b> 플러그인
    /// 프로세스가 0 이 아닌 코드로 끝나 `ProcessFailed` 가 되므로, 정상적인 취소에도 빨간
    /// 문구가 남았습니다. 게다가 `ProcessFailed` 는 실행 실패·신뢰 거부·시간 초과·출력 상한·
    /// 플러그인 오류를 한 이름으로 접은 것이라 사용자가 그 글자로 할 수 있는 일이 없습니다.
    ///
    /// 사유는 `scanner-failure.txt` 에 그대로 남습니다 — 진단은 거기서 봅니다.
    /// </remarks>
    private string Describe(ScanRunOutcome outcome)
    {
        if (!outcome.IsSuccess)
        {
            ScannerDiagnosticsLog.Write(
                "scan run failed: " +
                (view.scanSession?.LastFailureName ??
                    outcome.LastScanStatus?.ToString() ??
                    "unavailable"));
        }
        return string.Empty;
    }
}
