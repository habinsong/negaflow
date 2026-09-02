using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 비교 보기입니다 — 원본·중립·MAIN·다른 사진.
/// </summary>
/// <remarks>
/// <para>
/// macOS <c>beforeAfterCompareActive</c> 갈래에 해당합니다. 비교 대상은 프레임마다 따로
/// 기억하므로 사진을 옮기면 그 프레임의 비교 설정이 따라옵니다.
/// </para>
/// <para>
/// 여기 있던 <b>이웃 사진 미리 디코드</b>는 걷어냈습니다. macOS 는 선택이 바뀌어도
/// 고른 한 장만 현상하고(<c>AppModel+FrameSelection.handleSelectedFrameChange</c>),
/// 이웃을 미리 그리는 자리가 없습니다. Windows 판은 "이웃"이라는 이름으로 실제로는
/// <b>라이브러리 전체</b>를 돌았습니다 — 실측(2026-09-02, 114장): 정착 한 번마다 6~7분
/// 동안 쉬지 않고 디코딩했고 private 이 천장 8,959MB 를 넘겨 9,890MB 까지 올라갔으며,
/// 그 때문에 앞단 raw 예산이 2,910MB → 1,324MB 로 깎여 <b>정작 사용자가 고른 사진이
/// 매번 캐시 미스</b>였습니다.
/// </para>
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

}
