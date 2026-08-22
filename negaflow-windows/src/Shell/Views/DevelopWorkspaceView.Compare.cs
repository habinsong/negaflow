using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 비교 보기(원본·중립·MAIN·다른 사진)와 이웃 사진 미리 디코드입니다.
/// </summary>
/// <remarks>
/// macOS <c>beforeAfterCompareActive</c> 갈래에 해당합니다. 비교 대상은 프레임마다 따로
/// 기억하므로 사진을 옮기면 그 프레임의 비교 설정이 따라옵니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    private DevelopRun? neighborWarmRun;
    private bool compareBeforeNeeded;
    private bool compareBeforeInFlight;

    private void OnCompareModeChosen(CanvasCompareMode mode)
    {
        if (panel is null)
        {
            return;
        }

        panel.SelectCompareMode(mode);
        if (previewCoordinator is not null)
        {
            previewCoordinator.UninvertedSource =
                BaseCard.IsBasePickerActive ||
                panel.Compare.ActiveMode == CanvasCompareMode.Raw;
        }

        if (panel.Compare.IsSplitRequested)
        {
            compareBeforeNeeded = true;
            RequestCompareBefore();
        }
        else
        {
            compareBeforeNeeded = false;
            RequestPreview();
        }

        PreviewCanvas.RefreshCompare();
    }

    private void OnCompareBeforeChosen(string id)
    {
        if (panel is null)
        {
            return;
        }

        panel.SelectCompareBefore(id, FrameExists);
        compareBeforeNeeded = true;
        RequestCompareBefore();
        PreviewCanvas.RefreshCompare();
    }

    /// <summary>macOS <c>updateCompareGating</c> 의 Before 1회 현상.</summary>
    private void RequestCompareBefore()
    {
        if (compareBeforeInFlight ||
            previewCoordinator is null ||
            panel?.DefectLayers.PreviewFrame is not { } frame)
        {
            return;
        }

        Dictionary<string, LibraryFrameSnapshot> others = CompareFrameMap(frame.Id);
        string selected = panel.Compare.SelectedBeforeId;
        LibraryFrameSnapshot source = CanvasCompareBeforePolicy.BeforeSnapshot(frame, selected, others);
        if (CanvasCompareBeforePolicy.CanonicalId(selected) == CanvasCompareBeforePolicy.MainId &&
            frame.DevelopTarget == DevelopTarget.Main &&
            PreviewCanvas.PreviewBitmap is { } after &&
            PreviewCanvas.PreviewPixels is { } pixels)
        {
            PreviewCanvas.PresentCompareBefore(pixels, after.PixelWidth, after.PixelHeight);
            compareBeforeNeeded = false;
            return;
        }

        bool restoreUninverted = BaseCard.IsBasePickerActive ||
            panel.Compare.ActiveMode == CanvasCompareMode.Raw;
        previewCoordinator.UninvertedSource =
            restoreUninverted || CanvasCompareBeforePolicy.BeforeUsesUninvertedSource(selected);
        compareBeforeInFlight = true;
        _ = previewCoordinator.RequestAsync(source, outcome =>
        {
            if (previewCoordinator is not null)
            {
                previewCoordinator.UninvertedSource = restoreUninverted;
            }

            ShowCompareBefore(outcome);
        });
    }

    private bool FrameExists(string id)
    {
        if (libraryHost is null)
        {
            return false;
        }

        foreach (LibraryFrameSnapshot frame in libraryHost.Frames)
        {
            if (string.Equals(frame.Id, id, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private Dictionary<string, LibraryFrameSnapshot> CompareFrameMap(string currentId)
    {
        var map = new Dictionary<string, LibraryFrameSnapshot>(StringComparer.Ordinal);
        if (libraryHost is null)
        {
            return map;
        }

        foreach (LibraryFrameSnapshot frame in libraryHost.Frames)
        {
            if (!string.Equals(frame.Id, currentId, StringComparison.Ordinal))
            {
                map[frame.Id] = frame;
            }
        }

        return map;
    }

    private IReadOnlyList<CanvasCompareBeforeOption> CompareFrameOptions()
    {
        if (panel?.SelectedFrame is not { } current || libraryHost is null)
        {
            return [];
        }

        return CanvasCompareBeforePolicy.FrameOptions(
            current.Id,
            libraryHost.Frames.Select(frame => (
                frame.Id,
                LibraryFrameNaming.DisplayName(frame),
                frame.VirtualCopyNumber is not null)));
    }

    private void ShowCompareBefore(PreviewOutcome outcome)
    {
        compareBeforeInFlight = false;
        // 여기서도 **고른 모드**로 봅니다. 이 시점에는 Before 그림이 아직 없어
        // `IsComparingSplit` 이 거짓이므로, 그것으로 막으면 결과를 버리게 됩니다.
        if (panel is null || !panel.Compare.IsSplitRequested)
        {
            return;
        }

        if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
            outcome.Pixels is not { } pixels ||
            outcome.Width == 0U ||
            outcome.Height == 0U)
        {
            return;
        }

        PreviewCanvas.PresentCompareBefore(pixels, (int)outcome.Width, (int)outcome.Height);
        compareBeforeNeeded = false;
    }

    /// <summary>
    /// 현재 장의 정착 뒤 이웃 장의 3600px raw 프록시를 채웁니다. 새 선택이 오면 취소하며,
    /// 선택된 장은 이 정착 슬롯에서 표시 크기 프록시를 파생하고 뒤따르는 정착에도 재사용합니다.
    /// </summary>
    private void WarmNeighborSettledPreviews(LibraryFrameSnapshot current)
    {
        if (libraryHost is null)
        {
            return;
        }
        IReadOnlyList<LibraryFrameSnapshot> all = libraryHost.Frames;
        int index = -1;
        for (int i = 0; i < all.Count; ++i)
        {
            if (string.Equals(all[i].Id, current.Id, StringComparison.Ordinal))
            {
                index = i;
                break;
            }
        }
        if (index < 0)
        {
            return;
        }
        List<LibraryFrameSnapshot> warmOrder = [];
        for (int distance = 1; warmOrder.Count + 1 < all.Count; ++distance)
        {
            if (index - distance >= 0)
            {
                warmOrder.Add(all[index - distance]);
            }
            if (index + distance < all.Count)
            {
                warmOrder.Add(all[index + distance]);
            }
        }
        uint edge = DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension);
        DevelopRun run = new();
        System.Threading.Interlocked.Exchange(ref neighborWarmRun, run)?.Cancel();
        _ = System.Threading.Tasks.Task.Run(() =>
        {
            ThreadPriority previousPriority = Thread.CurrentThread.Priority;
            bool priorityChanged = false;
            try
            {
                try
                {
                    Thread.CurrentThread.Priority = ThreadPriority.BelowNormal;
                    priorityChanged = true;
                }
                catch (Exception error) when (error is ThreadStateException or
                    System.Security.SecurityException)
                {
                }
                int pixelBytes = checked((int)((ulong)edge * edge * 4UL));
                byte[] pixels = new byte[pixelBytes];
                for (int warmIndex = 0;
                    warmIndex < warmOrder.Count && !run.IsCancelRequested;
                    ++warmIndex)
                {
                    bool keepResident = warmIndex < 2;
                    WarmSettledPreview(
                        warmOrder[warmIndex], edge, pixels, run, keepResident);
                    // 바로 이웃 두 장 뒤부터는 foreground 선택·조정을 위한 IO/GPU 유휴 구간을 둡니다.
                    if (warmIndex >= 1 && !WaitForBackground(run, milliseconds: 1000))
                    {
                        break;
                    }
                }
            }
            finally
            {
                if (priorityChanged)
                {
                    try
                    {
                        Thread.CurrentThread.Priority = previousPriority;
                    }
                    catch (Exception error) when (error is ThreadStateException or
                        System.Security.SecurityException)
                    {
                    }
                }
                _ = System.Threading.Interlocked.CompareExchange(
                    ref neighborWarmRun, null, run);
                run.Dispose();
            }
        });
    }

    private void WarmSettledPreview(
        LibraryFrameSnapshot? frame,
        uint edge,
        byte[] pixels,
        DevelopRun run,
        bool keepResident)
    {
        if (frame is null || frame.SourcePath is not { Length: > 0 } path)
        {
            return;
        }
        try
        {
            if (keepResident &&
                thumbnails?.TryGetDeveloped(frame, out var cached) == true && cached.Settled)
            {
                PreviewTrace.Write(
                    "warm preview cache HIT " + cached.Width + "x" + cached.Height + " " + path);
                return;
            }
            if (!keepResident && thumbnails?.HasSettledDeveloped(frame) == true)
            {
                PreviewTrace.Write("warm preview disk HIT " + path);
                return;
            }
            string unused = Path.ChangeExtension(path, ".warm-decode.png");
            if (DevelopRequestFactory.Create(frame, unused).Request is not { } request)
            {
                return;
            }
            DevelopedPreviewCacheIdentity? identity =
                ThumbnailService.CaptureDevelopedCacheIdentity(frame);
            PreviewTrace.Write(
                "warm preview start edge=" + edge +
                " resident=" + keepResident + " " + path);
            NativeDevelopExporterAdapter exporter = new();
            DevelopExportResult result = keepResident
                ? exporter.Preview(request, edge, edge, pixels, run)
                : exporter.PreviewBackground(request, edge, edge, pixels, run);
            PreviewTrace.Write(
                "warm preview end ok=" + result.Succeeded +
                " cancel=" + result.Cancelled +
                " fail=" + (result.FailureName ?? ""));
            if (result.Succeeded && result.ImageWidth > 0U && result.ImageHeight > 0U)
            {
                if (keepResident)
                {
                    thumbnails?.RememberDeveloped(
                        frame,
                        pixels,
                        (int)result.ImageWidth,
                        (int)result.ImageHeight,
                        settled: true,
                        identity);
                }
                else
                {
                    thumbnails?.StoreDevelopedOnDisk(
                        frame,
                        pixels,
                        (int)result.ImageWidth,
                        (int)result.ImageHeight,
                        identity);
                }
            }
        }
        catch (Exception error)
        {
            PreviewTrace.Write("warm preview fault " + error.GetType().Name);
        }
    }

    private static bool WaitForBackground(DevelopRun run, int milliseconds)
    {
        int remaining = milliseconds;
        while (remaining > 0 && !run.IsCancelRequested)
        {
            int slice = Math.Min(50, remaining);
            Thread.Sleep(slice);
            remaining -= slice;
        }
        return !run.IsCancelRequested;
    }
}
