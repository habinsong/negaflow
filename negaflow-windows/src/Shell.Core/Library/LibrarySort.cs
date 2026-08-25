using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>macOS <c>LibrarySortKey</c> 와 같은 정렬 기준입니다.</summary>
public enum LibrarySortKey
{
    InputOrder,
    Time,
    Name,
    Flag,
    Rating,
    FileSize,
}

/// <summary>
/// 라이브러리 정렬입니다. macOS <c>LibraryBrowserProjection</c> 의 비교자를 그대로 씁니다 —
/// 같은 값끼리는 입력 순서를 지킵니다.
/// </summary>
public static class LibrarySorter
{
    public static IReadOnlyList<LibraryFrameListItem> Sort(
        IReadOnlyList<LibraryFrameListItem> items,
        LibrarySortKey key,
        bool ascending)
    {
        ArgumentNullException.ThrowIfNull(items);
        if (key is LibrarySortKey.InputOrder)
        {
            // **입력 순서도 방향은 따릅니다.**
            //
            // 앞 판은 이 기준에서 오름/내림을 통째로 무시했습니다. 기본값이 이것이라,
            // 사용자가 정렬을 뒤집어도 목록이 한 칸도 안 움직였습니다 - 특히 평판 프리뷰가
            // 언제나 맨 오른쪽(가장 최근에 붙은 자리)에 박혀 있는 것으로 보였습니다.
            // "차례를 비교하지 않는다" 와 "방향을 무시한다" 는 다른 말입니다.
            return ascending ? items : [.. items.Reverse()];
        }

        // 파일 크기는 **값이 없는 쪽을 방향과 무관하게 뒤로** 보냅니다. macOS
        // `LibraryBrowserProjection.sortFrameIDs` 가 그렇게 합니다:
        //   case (nil, .some): return false      // 값 없는 쪽이 뒤
        //   case (.some, nil): return true
        // 오름차순일 때 0 으로 취급해 앞에 모으면, 못 읽은 사진이 목록 머리를 차지합니다.
        Comparison<LibraryFrameListItem> directed = key is LibrarySortKey.FileSize
            ? (left, right) => CompareFileSize(left, right, ascending)
            : (left, right) =>
            {
                int comparison = Compare(left, right, key);
                return ascending ? comparison : -comparison;
            };
        return Stable(items, directed);
    }

    private static int CompareFileSize(
        LibraryFrameListItem left,
        LibraryFrameListItem right,
        bool ascending)
    {
        ulong? leftBytes = FileBytes(left);
        ulong? rightBytes = FileBytes(right);
        if (leftBytes is { } leftValue && rightBytes is { } rightValue && leftValue != rightValue)
        {
            return ascending ? leftValue.CompareTo(rightValue) : rightValue.CompareTo(leftValue);
        }
        if (leftBytes is null && rightBytes is not null)
        {
            return 1;
        }
        if (leftBytes is not null && rightBytes is null)
        {
            return -1;
        }
        return 0;
    }

    private static int Compare(LibraryFrameListItem left, LibraryFrameListItem right, LibrarySortKey key) =>
        key switch
        {
            LibrarySortKey.Time => Nullable.Compare(left.Frame.ScannedAt, right.Frame.ScannedAt),
            // macOS 는 en_US_POSIX 에 numeric 옵션으로 비교합니다. 사진 2 가 사진 10 앞에 옵니다.
            LibrarySortKey.Name => NumericAwareCompare(left.DisplayName, right.DisplayName),
            LibrarySortKey.Flag => FlagRank(left.Frame.PickState).CompareTo(FlagRank(right.Frame.PickState)),
            LibrarySortKey.Rating => left.Frame.Rating.CompareTo(right.Frame.Rating),
            // 원본 파일 크기입니다. 못 읽은 사진은 0 으로 두어 한쪽에 모입니다 - 값이 없는
            // 것을 있는 것 사이에 흩어 놓으면 차례가 뒤죽박죽으로 보입니다.
            _ => 0,
        };

    /// <summary>원본 파일 크기입니다. 못 읽은 사진은 값이 없습니다(macOS <c>fileSizeBytes?</c>).</summary>
    private static ulong? FileBytes(LibraryFrameListItem item) =>
        item.Frame.SourceMetadata is { IsValid: true } metadata ? metadata.FileBytes : null;

    private static int FlagRank(FramePickState state) => state switch
    {
        FramePickState.Picked => 0,
        FramePickState.Unflagged => 1,
        _ => 2,
    };

    /// <summary>
    /// <c>List.Sort</c> 는 안정 정렬이 아니므로, 같은 값끼리 입력 순서를 잃지 않도록 원래
    /// 위치를 보조 기준으로 다시 세웁니다.
    /// </summary>
    private static IReadOnlyList<LibraryFrameListItem> Stable(
        IReadOnlyList<LibraryFrameListItem> original,
        Comparison<LibraryFrameListItem> directed)
    {
        Dictionary<string, int> positions = new(original.Count, StringComparer.Ordinal);
        for (int index = 0; index < original.Count; ++index)
        {
            positions[original[index].Id] = index;
        }
        List<LibraryFrameListItem> sorted = [.. original];
        sorted.Sort((left, right) =>
        {
            int comparison = directed(left, right);
            return comparison != 0
                ? comparison
                : positions[left.Id].CompareTo(positions[right.Id]);
        });
        return sorted;
    }

    /// <summary>숫자가 섞인 이름을 사람이 읽는 순서로 견줍니다 — 사진 2 &lt; 사진 10.</summary>
    private static int NumericAwareCompare(string left, string right)
    {
        int leftIndex = 0;
        int rightIndex = 0;
        while (leftIndex < left.Length && rightIndex < right.Length)
        {
            char leftChar = left[leftIndex];
            char rightChar = right[rightIndex];
            if (char.IsAsciiDigit(leftChar) && char.IsAsciiDigit(rightChar))
            {
                int leftRun = RunLength(left, leftIndex);
                int rightRun = RunLength(right, rightIndex);
                ReadOnlySpan<char> leftDigits = TrimLeadingZeros(left.AsSpan(leftIndex, leftRun));
                ReadOnlySpan<char> rightDigits = TrimLeadingZeros(right.AsSpan(rightIndex, rightRun));
                if (leftDigits.Length != rightDigits.Length)
                {
                    return leftDigits.Length < rightDigits.Length ? -1 : 1;
                }
                int digitComparison = leftDigits.SequenceCompareTo(rightDigits);
                if (digitComparison != 0)
                {
                    return digitComparison < 0 ? -1 : 1;
                }
                leftIndex += leftRun;
                rightIndex += rightRun;
                continue;
            }
            if (leftChar != rightChar)
            {
                return leftChar < rightChar ? -1 : 1;
            }
            ++leftIndex;
            ++rightIndex;
        }
        return (left.Length - leftIndex).CompareTo(right.Length - rightIndex);
    }

    private static int RunLength(string value, int start)
    {
        int end = start;
        while (end < value.Length && char.IsAsciiDigit(value[end]))
        {
            ++end;
        }
        return end - start;
    }

    private static ReadOnlySpan<char> TrimLeadingZeros(ReadOnlySpan<char> digits)
    {
        int start = 0;
        while (start < digits.Length - 1 && digits[start] == '0')
        {
            ++start;
        }
        return digits[start..];
    }
}
