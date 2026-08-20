using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>AppModel+LocalAdjustments</c> 와 <c>LocalAdjustmentMaskSupport</c> 를 옮긴
/// 순수 함수들입니다. 카탈로그 쓰기는 부르는 쪽이 합니다.
/// </summary>
public static class LocalAdjustmentEditing
{
    /// <summary>macOS 브러시 페더는 0...0.25 라, 슬라이더의 0...1 과 이 값으로 환산합니다.</summary>
    public const double BrushFeatherScale = 0.25;

    /// <summary>
    /// macOS <c>normalizedFeather</c> — 슬라이더가 보여 줄 0...1 값입니다. 브러시는 획의
    /// 페더를 0.25 로 나눈 값이고, 나머지 셋은 마스크의 페더를 그대로 씁니다.
    /// </summary>
    public static double NormalizedFeather(LocalDodgeBurnAdjustment adjustment)
    {
        ArgumentNullException.ThrowIfNull(adjustment);
        if (adjustment.Mask.Kind != LocalDodgeBurnMaskKind.Brush)
        {
            return Math.Clamp(adjustment.Mask.Feather, 0.0, 1.0);
        }
        double stroke = adjustment.Mask.Strokes.Count == 0
            ? 0.0
            : adjustment.Mask.Strokes[0].Feather;
        return Math.Clamp(stroke / BrushFeatherScale, 0.0, 1.0);
    }

    /// <summary>
    /// macOS <c>setNormalizedFeather(_:)</c> — 브러시는 <b>모든 획</b>의 페더를 같이 바꿉니다.
    /// </summary>
    public static LocalDodgeBurnAdjustment WithNormalizedFeather(
        LocalDodgeBurnAdjustment adjustment,
        double value)
    {
        ArgumentNullException.ThrowIfNull(adjustment);
        double clamped = Math.Clamp(value, 0.0, 1.0);
        if (adjustment.Mask.Kind != LocalDodgeBurnMaskKind.Brush)
        {
            return adjustment with { Mask = adjustment.Mask with { Feather = clamped } };
        }
        LocalDodgeBurnStroke[] strokes = [.. adjustment.Mask.Strokes.Select(stroke =>
            stroke with { Feather = clamped * BrushFeatherScale })];
        return adjustment with { Mask = adjustment.Mask with { Strokes = strokes } };
    }

    /// <summary>macOS <c>addLocalAdjustment(_:to:)</c> — 목록 끝에 붙입니다.</summary>
    public static IReadOnlyList<LocalDodgeBurnAdjustment> Add(
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments,
        LocalDodgeBurnAdjustment adjustment)
    {
        ArgumentNullException.ThrowIfNull(adjustments);
        ArgumentNullException.ThrowIfNull(adjustment);
        return [.. adjustments, adjustment];
    }

    /// <summary>
    /// macOS <c>updateLocalAdjustment(id:on:_:)</c> — 없는 id 면 목록을 그대로 돌려줍니다.
    /// </summary>
    public static IReadOnlyList<LocalDodgeBurnAdjustment> Update(
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments,
        Guid id,
        Func<LocalDodgeBurnAdjustment, LocalDodgeBurnAdjustment> update)
    {
        ArgumentNullException.ThrowIfNull(adjustments);
        ArgumentNullException.ThrowIfNull(update);
        int index = IndexOf(adjustments, id);
        if (index < 0)
        {
            return adjustments;
        }
        LocalDodgeBurnAdjustment[] next = [.. adjustments];
        next[index] = update(next[index]);
        return next;
    }

    /// <summary>macOS <c>removeLocalAdjustment(id:from:)</c>.</summary>
    public static IReadOnlyList<LocalDodgeBurnAdjustment> Remove(
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments,
        Guid id)
    {
        ArgumentNullException.ThrowIfNull(adjustments);
        return IndexOf(adjustments, id) < 0
            ? adjustments
            : [.. adjustments.Where(adjustment => adjustment.Id != id)];
    }

    /// <summary>macOS 목록 줄의 이름 — <c>"1 · 브러시"</c> 처럼 번호와 종류를 붙입니다.</summary>
    public static string RowTitle(int index, string kindName) =>
        string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{index + 1} · {kindName}");

    private static int IndexOf(IReadOnlyList<LocalDodgeBurnAdjustment> adjustments, Guid id)
    {
        for (int index = 0; index < adjustments.Count; ++index)
        {
            if (adjustments[index].Id == id)
            {
                return index;
            }
        }
        return -1;
    }
}
