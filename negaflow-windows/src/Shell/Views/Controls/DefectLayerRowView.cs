using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Controls;

public sealed record DefectLayerCommandTarget(string FrameId, Guid ItemId);

/// <summary>
/// 레이어 한 줄이 화면에 내는 값 전부입니다. 템플릿이 값을 짓지 않도록 글리프·도구설명·흐림까지
/// 여기서 정합니다.
/// </summary>
/// <remarks>
/// 글리프는 macOS SF Symbol 에 가장 가까운 Segoe Fluent 문자입니다. Segoe 에는
/// <c>bandage</c> 와 <c>scope</c> 가 없어 같은 이름을 쓸 수 없고, 뜻이 같은 것을 고릅니다.
/// </remarks>
public sealed class DefectLayerRowView
{
    /// <summary>macOS <c>eye</c> — Segoe Fluent RedEye.</summary>
    private const string EyeGlyph = "";

    /// <summary>macOS <c>eye.slash</c> — Segoe Fluent Hide.</summary>
    private const string EyeSlashGlyph = "";

    /// <summary>macOS <c>paintbrush.pointed.fill</c> — 직접 그린 붓.</summary>
    private const VectorIconKind BrushIcon = VectorIconKind.Paintbrush;

    /// <summary>macOS <c>rectangle.on.rectangle</c> — 직접 그린 겹친 사각형.</summary>
    private const VectorIconKind CloneIcon = VectorIconKind.CloneStamp;

    /// <summary>
    /// macOS <c>scope</c> — 자동·가이드·IR 이 모두 이것입니다. Segoe 에는 조준 모양이
    /// 없어 자르기 표식을 대신 쓰고 있었습니다. 직접 그린 조준으로 바꿨습니다.
    /// </summary>
    private const VectorIconKind RegionIcon = VectorIconKind.Scope;

    /// <summary>macOS <c>rectangle.dashed</c> — Segoe Fluent SelectAll.</summary>
    private const string MaskGlyph = "";

    /// <summary>macOS <c>trash</c> — Segoe Fluent Delete.</summary>
    private const string DeleteGlyph = "";

    public DefectLayerRowView(
        string frameId,
        DefectLayerRow row,
        DefectLayerText text,
        bool isBusy)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(frameId);
        ArgumentNullException.ThrowIfNull(row);
        ArgumentNullException.ThrowIfNull(text);
        Id = row.Id;
        Target = new DefectLayerCommandTarget(frameId, row.Id);
        IndexText = $"{row.DisplayIndex}.";
        Enabled = row.Enabled;
        Strength = row.Strength;
        Title = row.Title;
        Summary = row.Summary;
        StrengthLabel = text.Strength;
        MaskShown = row.MaskShown;
        EnabledGlyph = row.Enabled ? EyeGlyph : EyeSlashGlyph;
        EnabledTooltip = row.Enabled ? text.DisableLayer : text.EnableLayer;
        MaskTooltip = row.MaskShown ? text.HideMask : text.ShowMask;
        DeleteTooltip = text.DeleteLayer;
        KindIcon = row.Icon switch
        {
            DefectLayerIcon.Brush => BrushIcon,
            DefectLayerIcon.Clone => CloneIcon,
            _ => RegionIcon,
        };
        // macOS: .opacity(item.enabled ? 1 : 0.55)
        RowOpacity = row.Enabled ? 1.0 : 0.55;
        // 수리를 다시 만드는 동안에는 켜기와 삭제를 막습니다. 마스크 표시는 막지 않습니다 —
        // macOS 도 그 단추에는 disabled 를 걸지 않습니다.
        CanEdit = !isBusy;
        // macOS: .disabled(!item.enabled)
        CanSetStrength = row.Enabled;
    }

    public Guid Id { get; }

    public DefectLayerCommandTarget Target { get; }

    public string IndexText { get; }

    public bool Enabled { get; }

    public double Strength { get; }

    public string Title { get; }

    public string Summary { get; }

    public string StrengthLabel { get; }

    public bool MaskShown { get; }

    public string EnabledGlyph { get; }

    public VectorIconKind KindIcon { get; }

    public string MaskGlyphValue => MaskGlyph;

    public string DeleteGlyphValue => DeleteGlyph;

    public string EnabledTooltip { get; }

    public string MaskTooltip { get; }

    public string DeleteTooltip { get; }

    public double RowOpacity { get; }

    public bool CanEdit { get; }

    public bool CanSetStrength { get; }
}
