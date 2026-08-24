using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// GrainMend 레이어 목록의 조작 표면입니다 — 항목별 켜기·끄기, 강도, 삭제, 마스크 표시.
/// 획을 새로 긋는 것과는 다른 이유로 바뀌므로 <see cref="DevelopPanelState"/> 가 전부
/// 떠안지 않고 여기로 나눕니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 와 같은 제스처 규칙을 지킵니다. 강도 슬라이더를 <b>끄는 동안</b>에는 디스크에 쓰지
/// 않고 미리보기만 다시 그리며, <b>놓을 때</b> 한 번만 확정해 저장합니다.
/// </para>
/// <para>
/// 저장을 건너뛰는 것은 취향이 아니라 필요입니다. 결함 recipe 를 쓰려면 원본 파일 전체를
/// 읽어 SHA-256 을 다시 내야 하고(<c>LibraryDefectEditor.AppendStroke</c>), 100MB TIFF 에서는
/// 한 번에 수백 밀리초가 듭니다. 드래그 한 번에 수십 번 부르면 슬라이더가 멈춥니다.
/// </para>
/// </remarks>
public sealed class DevelopDefectLayerPanel
{
    /// <summary>macOS 슬라이더의 사각지대입니다. 이보다 작게 움직이면 아무것도 하지 않습니다.</summary>
    private const double StrengthEpsilon = 1.0e-3;

    /// <summary>왼쪽 끝은 해당 결함 제거 전 원본입니다.</summary>
    public const double MinimumStrength = 0.0;

    public const double MaximumStrength = 1.0;

    private readonly DevelopPanelState panel;
    private readonly DevelopDefectEditor editor;
    private readonly DefectLayerFrameInteractionState interactions;
    private LibraryFrameSnapshot? cachedPreviewSource;
    private LibraryDefectLiveStrength? cachedPreviewStrength;
    private LibraryFrameSnapshot? cachedPreviewFrame;

    internal DevelopDefectLayerPanel(
        DevelopPanelState panel,
        DevelopDefectEditor editor,
        LibraryDefectLiveStrengthStore liveStrengths)
    {
        this.panel = panel;
        this.editor = editor;
        interactions = new DefectLayerFrameInteractionState(liveStrengths);
    }

    /// <summary>마스크를 보여 주는 항목입니다. macOS <c>frame.defectMaskPreviewID</c> 와 같습니다.</summary>
    public Guid? MaskPreviewId => interactions.MaskPreview(panel.SelectedFrame?.Id);

    public IReadOnlyList<DefectEditItem> Items =>
        panel.SelectedFrame?.DefectRecipe?.Items ?? [];

    /// <summary>현재 frame에 아직 저장하지 않은 strength가 있으면 참입니다.</summary>
    public bool HasLiveStrength =>
        interactions.LiveStrength(panel.SelectedFrame?.Id) is not null;

    /// <summary>
    /// 미리보기가 그려야 하는 frame 입니다. 슬라이더를 끄는 동안에는 아직 저장하지 않은 강도를
    /// 얹은 사본이고, 그 밖에는 고른 frame 그대로입니다.
    /// </summary>
    public LibraryFrameSnapshot? PreviewFrame
    {
        get
        {
            if (panel.SelectedFrame is not { } frame)
            {
                return null;
            }
            if (interactions.LiveStrength(frame.Id) is not { } live ||
                frame.DefectRecipe is not { } recipe)
            {
                ClearPreviewCache();
                return frame;
            }
            if (ReferenceEquals(cachedPreviewSource, frame) &&
                cachedPreviewStrength == live &&
                cachedPreviewFrame is { } cached)
            {
                return cached;
            }
            LibraryFrameSnapshot preview = WithStrength(recipe, live.ItemId, live.Strength) is
                { } previewRecipe
                ? frame with { DefectRecipe = previewRecipe }
                : frame;
            cachedPreviewSource = frame;
            cachedPreviewStrength = live;
            cachedPreviewFrame = preview;
            return preview;
        }
    }

    /// <summary>항목 하나만의 before/after 입니다. 다른 항목은 그대로 둡니다.</summary>
    public LibraryFrameError SetEnabled(Guid id, bool enabled)
    {
        EndGesture();
        return Write(recipe => Map(
            recipe,
            id,
            item => item.Enabled == enabled ? null : item with { Enabled = enabled }));
    }

    /// <summary>
    /// 항목 하나의 강도입니다.
    /// </summary>
    /// <param name="live">
    /// 끄는 중이면 참입니다. 저장하지 않고 <see cref="PreviewFrame"/> 만 바꿉니다.
    /// </param>
    public LibraryFrameError SetStrength(Guid id, double strength, bool live)
    {
        if (!double.IsFinite(strength))
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        double clamped = Math.Clamp(strength, MinimumStrength, MaximumStrength);
        if (Current(id) is not { } item)
        {
            return LibraryFrameError.MissingId;
        }
        // macOS 는 변화량이 1e-3 이하이면 아무 것도 하지 않습니다.
        if (panel.SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }
        if (live && frame.DefectRecipe?.RecipeRevision == ulong.MaxValue)
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        LibraryDefectLiveStrength? currentLive = interactions.LiveStrength(frame.Id);
        double reference = currentLive is { } liveState && liveState.ItemId == id
            ? liveState.Strength
            : item.Strength;
        if (live && Math.Abs(clamped - reference) <= StrengthEpsilon)
        {
            return LibraryFrameError.None;
        }
        if (live)
        {
            ClearPreviewCache();
            interactions.SetLiveStrength(frame.Id, id, clamped);
            return LibraryFrameError.None;
        }

        if (currentLive is null && interactions.HasLiveStrengthForOtherFrame(frame.Id, id))
        {
            return LibraryFrameError.None;
        }

        bool commitsLiveGesture = currentLive is { } pending && pending.ItemId == id;
        EndGesture();
        return !commitsLiveGesture && Math.Abs(clamped - item.Strength) <= StrengthEpsilon
            ? LibraryFrameError.None
            : Write(recipe => Map(recipe, id, existing => existing with { Strength = clamped }));
    }

    /// <summary>
    /// 항목 하나를 지웁니다. 그 항목의 마스크를 보고 있었다면 표시도 끕니다 — 없는 항목의
    /// 마스크는 그릴 수 없습니다.
    /// </summary>
    public LibraryFrameError Remove(Guid id)
    {
        EndGesture();
        LibraryFrameError error = Write(
            recipe =>
            {
                DefectEditItem[] remaining = [.. recipe.Items.Where(item => item.Id != id)];
                return remaining.Length == recipe.Items.Count ? null : remaining;
            },
            LibraryDefectHistoryMode.Exact);
        if (error == LibraryFrameError.None &&
            panel.SelectedFrame is { } frame &&
            MaskPreviewId == id)
        {
            interactions.SetMaskPreview(frame.Id, itemId: null);
        }
        return error;
    }

    /// <summary>마스크 표시를 켜고 끕니다. 한 번에 한 항목만 보입니다.</summary>
    public void ToggleMaskPreview(Guid id)
    {
        if (panel.SelectedFrame is { } frame)
        {
            interactions.ToggleMaskPreview(frame.Id, id);
        }
    }

    /// <summary>
    /// 목록이 바뀐 뒤 사라진 항목의 마스크 표시를 거둡니다. 고른 사진이 바뀔 때도 부릅니다.
    /// </summary>
    public void ForgetMissingMaskPreview()
    {
        if (panel.SelectedFrame is not { } frame)
        {
            return;
        }
        interactions.SetMaskPreview(
            frame.Id,
            DefectLayerProjection.SurvivingMaskPreview(frame, MaskPreviewId));
    }

    /// <summary>끄는 중이던 값을 버립니다. 사진을 바꾸거나 다른 편집이 끼어들 때 부릅니다.</summary>
    public void EndGesture()
    {
        ClearPreviewCache();
        interactions.EndGesture(panel.SelectedFrame?.Id);
    }

    internal void RetainFrames(IEnumerable<string> frameIds)
    {
        ClearPreviewCache();
        interactions.RetainFrames(frameIds);
    }

    private void ClearPreviewCache()
    {
        cachedPreviewSource = null;
        cachedPreviewStrength = null;
        cachedPreviewFrame = null;
    }

    private DefectEditItem? Current(Guid id) =>
        panel.SelectedFrame?.DefectRecipe?.Items.FirstOrDefault(item => item.Id == id);

    private LibraryFrameError Write(
        Func<DefectRecipeSnapshot, IReadOnlyList<DefectEditItem>?> map,
        LibraryDefectHistoryMode historyMode = LibraryDefectHistoryMode.PreservingInfrared)
    {
        DevelopDefectEditResult result = editor.ReplaceItems(
            panel.SelectedFrame,
            map,
            historyMode);
        return panel.RefreshAfterDefectEdit(result);
    }

    /// <summary>한 항목만 바꾼 목록입니다. 바뀌지 않으면 null 이라 쓰기 자체를 건너뜁니다.</summary>
    private static IReadOnlyList<DefectEditItem>? Map(
        DefectRecipeSnapshot recipe,
        Guid id,
        Func<DefectEditItem, DefectEditItem?> change)
    {
        DefectEditItem[] items = [.. recipe.Items];
        for (int index = 0; index < items.Length; ++index)
        {
            if (items[index].Id != id)
            {
                continue;
            }
            if (change(items[index]) is not { } replacement)
            {
                return null;
            }
            items[index] = replacement;
            return items;
        }
        return null;
    }

    private static DefectRecipeSnapshot? WithStrength(
        DefectRecipeSnapshot recipe,
        Guid id,
        double strength)
    {
        if (Map(recipe, id, item => item with { Strength = strength }) is not { } items)
        {
            return null;
        }
        try
        {
            return DefectRecipeSnapshot.Create(
                recipe.FrameId,
                checked(recipe.RecipeRevision + 1UL),
                recipe.SourceIdentity,
                items);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            return null;
        }
    }
}
