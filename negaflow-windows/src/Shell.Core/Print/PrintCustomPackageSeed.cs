namespace Negaflow.Shell.Print;

/// <summary>
/// 사용자 패키지를 처음 고른 순간의 배치입니다. macOS
/// <c>PrintWorkspaceSettingsStore.prepareDefaultCustomPackage(sourceCount:)</c> 를 그대로
/// 옮긴 것입니다.
/// </summary>
/// <remarks>
/// 고른 사진이 여러 장이면 <b>사진마다 칸을 하나씩</b> 놓습니다. Shift · Ctrl 로 여러 장을
/// 고른 뒤 사용자 패키지를 켜면 그 사진들이 한 판에 함께 올라가는 길이 이것입니다.
///
/// 손댄 배치는 건드리지 않습니다 — 기본값 그대로일 때만 바꿉니다. macOS 도 기본 칸 하나가
/// 판 전체를 덮고 있을 때만 격자로 바꿉니다.
/// </remarks>
public static class PrintCustomPackageSeed
{
    /// <summary>기본 배치입니다. 판 전체를 덮는 칸 하나입니다.</summary>
    public static IReadOnlyList<PrintCustomPackageItem> Default { get; } =
        [new PrintCustomPackageItem(0, new PrintRect(0, 0, 1, 1))];

    /// <summary>
    /// 지금 배치를 사진 수에 맞춰 다시 놓아야 하면 새 배치를, 그대로 두어야 하면
    /// <see langword="null"/> 을 냅니다.
    /// </summary>
    public static IReadOnlyList<PrintCustomPackageItem>? Prepare(
        IReadOnlyList<PrintCustomPackageItem> current,
        int sourceCount)
    {
        ArgumentNullException.ThrowIfNull(current);
        // 배치가 비어 있으면 기본 한 칸부터 놓습니다. macOS 는 설정 자체의 기본값이라 빈
        // 목록이 될 수 없지만, Windows 는 예전 저장본에 빈 목록이 남아 있을 수 있습니다.
        if (current.Count == 0)
        {
            return sourceCount > 1 ? Grid(sourceCount) : Default;
        }
        if (!IsUntouchedDefault(current) ||
            sourceCount <= 1 ||
            sourceCount > PrintPackageSettings.MaximumCustomItemCount)
        {
            return null;
        }
        return Grid(sourceCount);
    }

    /// <summary>
    /// 칸이 가리키는 사진 번호를 지금 고른 사진 안으로 당깁니다. 바뀐 것이 없으면
    /// <see langword="null"/> 을 냅니다.
    /// </summary>
    /// <remarks>
    /// 배치는 <b>칸 하나라도 없는 사진을 가리키면 통째로 거절</b>됩니다
    /// (<c>PrintPackageLayout.CustomPackagePages</c>, macOS <c>allSatisfy</c> 와 같은 규칙).
    /// 여러 장을 골라 칸을 만든 뒤 한 장만 남기면 판이 통째로 사라지던 자리입니다 — macOS 가
    /// 팝업에서 <c>min(sourceIndex, count - 1)</c> 로 당겨 보여 주는 값을 저장값에도 씁니다.
    /// </remarks>
    public static IReadOnlyList<PrintCustomPackageItem>? Clamp(
        IReadOnlyList<PrintCustomPackageItem> current,
        int sourceCount)
    {
        ArgumentNullException.ThrowIfNull(current);
        if (sourceCount <= 0 || current.Count == 0)
        {
            return null;
        }
        int highest = sourceCount - 1;
        if (current.All(item => item.SourceIndex >= 0 && item.SourceIndex <= highest))
        {
            return null;
        }
        return
        [
            .. current.Select(item => item.SourceIndex >= 0 && item.SourceIndex <= highest
                ? item
                : item with { SourceIndex = Math.Clamp(item.SourceIndex, 0, highest) }),
        ];
    }

    /// <summary>
    /// 사진 수만큼 칸을 격자로 놓습니다. macOS 와 같은 열·행 셈입니다 —
    /// <c>columns = ceil(sqrt(n))</c>, <c>rows = ceil(n / columns)</c>.
    /// </summary>
    public static IReadOnlyList<PrintCustomPackageItem> Grid(int sourceCount)
    {
        int count = Math.Max(1, sourceCount);
        int columns = (int)Math.Ceiling(Math.Sqrt(count));
        int rows = (count + columns - 1) / columns;
        double cellWidth = 1.0 / columns;
        double cellHeight = 1.0 / rows;
        List<PrintCustomPackageItem> items = new(count);
        for (int sourceIndex = 0; sourceIndex < count; ++sourceIndex)
        {
            int row = sourceIndex / columns;
            int column = sourceIndex % columns;
            items.Add(new PrintCustomPackageItem(
                sourceIndex,
                // macOS 는 아래가 0 이라 `1 - (row + 1) * cellHeight` 로 셉니다. 여기 배치는
                // 위가 0 이므로 같은 자리가 `row * cellHeight` 입니다.
                new PrintRect(column * cellWidth, row * cellHeight, cellWidth, cellHeight))
            {
                ZIndex = sourceIndex,
            });
        }
        return items;
    }

    /// <summary>
    /// 아직 손대지 않은 기본 배치인지. macOS 와 같이 <b>모든 항목</b>이 기본값일 때만
    /// 참입니다 — 하나라도 옮겼으면 사용자의 배치이므로 덮어쓰지 않습니다.
    /// </summary>
    private static bool IsUntouchedDefault(IReadOnlyList<PrintCustomPackageItem> items) =>
        items.Count == 1 &&
        items[0] is
        {
            SourceIndex: 0,
            PageIndex: 0,
            ContentMode: PrintPackageContentMode.Fit,
            RotateToFit: false,
            ZIndex: 0,
        } item &&
        item.NormalizedRect == new PrintRect(0, 0, 1, 1);
}
