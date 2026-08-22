using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasCompareMode</c>.</summary>
public enum CanvasCompareMode
{
    Raw,
    Developed,
    SplitVertical,
    SplitHorizontal,
}

/// <summary>macOS <c>CompareBeforeContent</c> — 분할 비교의 Before 대상.</summary>
public enum CompareBeforeContent
{
    Main,
    Unedited,
    Raw,
}

/// <summary>
/// macOS <c>CanvasView.selectCompareMode</c> · <c>toggleDevelopedShortcut</c> ·
/// <c>updateCompareGating</c>. 화면 없이 모드와 게이트만 바꿉니다.
/// </summary>
public sealed class CanvasCompareState
{
    /// <summary>
    /// macOS <c>ScanFrame.showDeveloped</c> 는 프레임마다 따로 삽니다. 여기 한 벌만 두면
    /// 한 프레임에서 `원본` 을 켠 뒤 다른 프레임으로 가도 그대로 원본이 남고,
    /// <c>UninvertedSource</c> 가 켜진 채 현상 요청이 나가 **모든 사진이 반전 전
    /// 네거티브(주황 베이스 + 반전 전 그레인)로 그려집니다.** 프레임별로 기억합니다.
    /// </summary>
    private readonly Dictionary<string, bool> showDevelopedByFrame = new(StringComparer.Ordinal);

    private string? boundFrameId;

    public CanvasCompareMode Mode { get; private set; } = CanvasCompareMode.Developed;

    public CanvasCompareMode PreviousMode { get; private set; } = CanvasCompareMode.Raw;

    public bool ShowDeveloped { get; private set; } = true;

    /// <summary>Before 이미지와 현상본이 둘 다 있을 때만 분할 모드가 유지됩니다.</summary>
    public bool CanCompare { get; set; }

    public CompareBeforeContent BeforeContent { get; private set; } = CompareBeforeContent.Unedited;

    /// <summary>macOS <c>beforeContentRaw</c> 가 <c>frame:</c> 일 때.</summary>
    public string? BeforeFrameId { get; private set; }

    public DevelopTarget DevelopTarget { get; set; } = DevelopTarget.Main;

    public bool BeforeAfterCompareActive { get; private set; }

    public bool BeforeAfterMainCompareActive { get; private set; }

    /// <summary>macOS <c>splitVerticalFraction</c> / <c>splitHorizontalFraction</c>.</summary>
    public CanvasCompareDividerState Divider { get; } = new();

    public CanvasCompareMode ActiveMode
    {
        get
        {
            if (!CanCompare)
            {
                return ShowDeveloped ? CanvasCompareMode.Developed : CanvasCompareMode.Raw;
            }

            return Mode;
        }
    }

    public bool IsComparingSplit =>
        ActiveMode is CanvasCompareMode.SplitVertical or CanvasCompareMode.SplitHorizontal;

    /// <summary>macOS <c>selectedBeforeID</c>.</summary>
    public string SelectedBeforeId =>
        BeforeFrameId is { Length: > 0 } frameId
            ? CanvasCompareBeforePolicy.FrameId(frameId)
            : BeforeContent switch
            {
                CompareBeforeContent.Main => CanvasCompareBeforePolicy.MainId,
                CompareBeforeContent.Raw => CanvasCompareBeforePolicy.RawId,
                _ => CanvasCompareBeforePolicy.UneditedId,
            };

    /// <summary>macOS <c>onSelectBefore</c>.</summary>
    public void SelectBefore(string id, Func<string, bool>? frameExists = null)
    {
        string canonical = CanvasCompareBeforePolicy.CanonicalId(id, frameExists);
        if (CanvasCompareBeforePolicy.TryFrameId(canonical, out string frameId))
        {
            BeforeFrameId = frameId;
            UpdateCompareGating();
            return;
        }

        BeforeFrameId = null;
        BeforeContent = canonical switch
        {
            CanvasCompareBeforePolicy.MainId => CompareBeforeContent.Main,
            CanvasCompareBeforePolicy.RawId => CompareBeforeContent.Raw,
            _ => CompareBeforeContent.Unedited,
        };
        UpdateCompareGating();
    }

    /// <summary>
    /// macOS 는 <c>frame.showDeveloped</c> 를 프레임 객체가 들고 있어 프레임을 옮기면 그
    /// 프레임의 값이 따라옵니다. 여기서 같은 것을 합니다 — 지금 프레임의 값을 넣어 두고,
    /// 새 프레임의 값을 꺼냅니다. 한 번도 본 적 없는 프레임은 macOS 기본값과 같이 현상본입니다.
    /// </summary>
    public void BindFrame(string? frameId)
    {
        if (string.Equals(boundFrameId, frameId, StringComparison.Ordinal))
        {
            return;
        }

        if (boundFrameId is { Length: > 0 } previous)
        {
            showDevelopedByFrame[previous] = ShowDeveloped;
        }
        boundFrameId = frameId;
        bool showDeveloped = frameId is not { Length: > 0 } ||
            !showDevelopedByFrame.TryGetValue(frameId, out bool stored) ||
            stored;
        if (showDeveloped == ShowDeveloped)
        {
            return;
        }
        Select(showDeveloped ? CanvasCompareMode.Developed : CanvasCompareMode.Raw);
    }

    /// <summary>macOS <c>selectCompareMode</c>.</summary>
    public void Select(CanvasCompareMode mode)
    {
        Mode = mode;
        ShowDeveloped = mode != CanvasCompareMode.Raw;
        if (boundFrameId is { Length: > 0 } frameId)
        {
            showDevelopedByFrame[frameId] = ShowDeveloped;
        }
        if (mode != CanvasCompareMode.Developed)
        {
            PreviousMode = mode;
        }

        UpdateCompareGating();
    }

    /// <summary>macOS <c>toggleDevelopedShortcut</c>.</summary>
    public void ToggleDeveloped()
    {
        CanvasCompareMode target = ActiveMode == CanvasCompareMode.Developed
            ? PreviousMode
            : CanvasCompareMode.Developed;
        Select(target);
    }

    /// <summary>macOS <c>updateCompareGating</c> 의 플래그만.</summary>
    public void UpdateCompareGating()
    {
        bool active = IsComparingSplit;
        BeforeAfterCompareActive = active;
        BeforeAfterMainCompareActive = active
            && BeforeContent == CompareBeforeContent.Main
            && DevelopTarget != DevelopTarget.Main;
    }
}
