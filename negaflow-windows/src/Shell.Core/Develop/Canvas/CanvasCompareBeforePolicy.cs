using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>CanvasCompareBeforeOption</c>.</summary>
public readonly record struct CanvasCompareBeforeOption(string Id, string Label, bool IsVirtualCopy);

/// <summary>macOS <c>selectedBeforeID</c> · <c>compareLabels</c> 위치 · Before 요청.</summary>
public static class CanvasCompareBeforePolicy
{
    public const string MainId = "main";
    public const string UneditedId = "unedited";
    public const string RawId = "raw";

    /// <summary>macOS <c>CanvasView.beforeFramePrefix</c>.</summary>
    public const string BeforeFramePrefix = "frame:";

    public const double BeforeCenterOffsetX = 60;
    public const double BeforeCenterOffsetY = 48;
    public const double AfterVerticalInsetX = 38;
    public const double AfterVerticalOffsetY = 48;
    public const double AfterHorizontalOffsetX = 36;
    public const double AfterHorizontalInsetY = 18;
    public const double MaxWidth = 112;
    public const double LabelPaddingX = 7;
    public const double LabelPaddingY = 3;
    public const double LabelCornerRadius = 6;
    public const double LabelSpacing = 4;

    public static string CanonicalId(string? raw, Func<string, bool>? frameExists = null)
    {
        if (raw is MainId or UneditedId or RawId)
        {
            return raw;
        }

        if (raw is not null &&
            raw.StartsWith(BeforeFramePrefix, StringComparison.Ordinal) &&
            frameExists?.Invoke(raw[BeforeFramePrefix.Length..]) == true)
        {
            return raw;
        }

        return UneditedId;
    }

    public static string FrameId(string frameId) => BeforeFramePrefix + frameId;

    public static bool TryFrameId(string selectedId, out string frameId)
    {
        if (selectedId.StartsWith(BeforeFramePrefix, StringComparison.Ordinal) &&
            selectedId.Length > BeforeFramePrefix.Length)
        {
            frameId = selectedId[BeforeFramePrefix.Length..];
            return true;
        }

        frameId = "";
        return false;
    }

    public static (double X, double Y) BeforeCenter(double frameLeft, double frameTop) =>
        (frameLeft + BeforeCenterOffsetX, frameTop + BeforeCenterOffsetY);

    public static (double X, double Y) AfterCenter(
        double frameLeft,
        double frameTop,
        double frameWidth,
        double frameHeight,
        CanvasCompareOrientation orientation) =>
        orientation == CanvasCompareOrientation.Vertical
            ? (frameLeft + frameWidth - AfterVerticalInsetX, frameTop + AfterVerticalOffsetY)
            : (frameLeft + AfterHorizontalOffsetX, frameTop + frameHeight - AfterHorizontalInsetY);

    public static IReadOnlyList<CanvasCompareBeforeOption> PrimaryOptions(
        string mainLabel,
        string uneditedLabel,
        string rawLabel) =>
    [
        new(MainId, mainLabel, false),
        new(UneditedId, uneditedLabel, false),
        new(RawId, rawLabel, false),
    ];

    public static IReadOnlyList<CanvasCompareBeforeOption> FrameOptions(
        string currentFrameId,
        IEnumerable<(string Id, string Label, bool IsVirtualCopy)> frames)
    {
        var options = new List<CanvasCompareBeforeOption>();
        foreach ((string id, string label, bool copy) in frames)
        {
            if (string.Equals(id, currentFrameId, StringComparison.Ordinal))
            {
                continue;
            }

            options.Add(new CanvasCompareBeforeOption(FrameId(id), label, copy));
        }

        return options;
    }

    public static string BeforeLabel(
        string selectedId,
        IReadOnlyList<CanvasCompareBeforeOption> primary,
        IReadOnlyList<CanvasCompareBeforeOption> frames,
        string uneditedFallback)
    {
        foreach (CanvasCompareBeforeOption option in primary)
        {
            if (option.Id == selectedId)
            {
                return option.Label;
            }
        }

        foreach (CanvasCompareBeforeOption option in frames)
        {
            if (option.Id == selectedId)
            {
                return option.Label;
            }
        }

        return uneditedFallback;
    }

    /// <summary>macOS <c>beforeImage</c> 에 쓸 프레임. raw 는 호출측이 반전 전으로 요청.</summary>
    public static LibraryFrameSnapshot BeforeSnapshot(
        LibraryFrameSnapshot current,
        string selectedId,
        IReadOnlyDictionary<string, LibraryFrameSnapshot>? others = null)
    {
        ArgumentNullException.ThrowIfNull(current);
        string id = CanonicalId(
            selectedId,
            others is null ? null : others.ContainsKey);
        if (TryFrameId(id, out string frameId) &&
            others is not null &&
            others.TryGetValue(frameId, out LibraryFrameSnapshot? other))
        {
            return other;
        }

        return id switch
        {
            MainId when current.DevelopTarget != DevelopTarget.Main =>
                current with { DevelopTarget = DevelopTarget.Main },
            RawId => current,
            UneditedId => ExportFlatMaster.Neutralize(current),
            MainId => current,
            _ => ExportFlatMaster.Neutralize(current),
        };
    }

    public static bool BeforeUsesUninvertedSource(string selectedId) =>
        CanonicalId(selectedId) == RawId;
}
