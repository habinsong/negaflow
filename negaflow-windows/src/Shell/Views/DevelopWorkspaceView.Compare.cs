using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
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

        if (panel.Compare.IsComparingSplit)
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
        if (panel is null || !panel.Compare.IsComparingSplit)
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
    /// 이웃 장의 TIFF 를 디코드 캐시에 올려 둡니다. 같은 세션 로그에서 첫 방문
    /// PreviewOnce 가 400ms(캐시 있음) 또는 3000ms(캐시 없음)로 갈렸습니다.
    /// </summary>
    private void WarmNeighborDecodes(LibraryFrameSnapshot current)
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
        LibraryFrameSnapshot? left = index > 0 ? all[index - 1] : null;
        LibraryFrameSnapshot? right = index + 1 < all.Count ? all[index + 1] : null;
        _ = System.Threading.Tasks.Task.Run(() =>
        {
            WarmDecode(left);
            WarmDecode(right);
        });
    }

    private static void WarmDecode(LibraryFrameSnapshot? frame)
    {
        if (frame is null || frame.SourcePath is not { Length: > 0 } path)
        {
            return;
        }
        try
        {
            string unused = Path.ChangeExtension(path, ".warm-decode.png");
            if (DevelopRequestFactory.Create(frame, unused).Request is not { } request)
            {
                return;
            }
            const uint edge = 360;
            byte[] pixels = new byte[edge * edge * 4];
            PreviewTrace.Write("warm decode start " + path);
            DevelopExportResult result = new NativeDevelopExporterAdapter().Preview(
                request, edge, edge, pixels);
            PreviewTrace.Write(
                "warm decode end ok=" + result.Succeeded +
                " fail=" + (result.FailureName ?? ""));
        }
        catch (Exception error)
        {
            PreviewTrace.Write("warm decode fault " + error.GetType().Name);
        }
    }
}
