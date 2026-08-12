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
/// 같은 값끼리는 입력 순서를 지키고, <c>inputOrder</c> 와 <c>fileSize</c> 는 비교하지 않습니다.
/// </summary>
public static class LibrarySorter
{
    public static IReadOnlyList<LibraryFrameListItem> Sort(
        IReadOnlyList<LibraryFrameListItem> items,
        LibrarySortKey key,
        bool ascending)
    {
        ArgumentNullException.ThrowIfNull(items);
        if (key is LibrarySortKey.InputOrder or LibrarySortKey.FileSize)
        {
            // macOS 는 이 두 기준을 비교하지 않습니다. 오름/내림도 입력 순서를 바꾸지 않습니다.
            return items;
        }

        return StableFor(items, [.. items], key, ascending);
    }

    private static int Compare(LibraryFrameListItem left, LibraryFrameListItem right, LibrarySortKey key) =>
        key switch
        {
            LibrarySortKey.Time => Nullable.Compare(left.Frame.ScannedAt, right.Frame.ScannedAt),
            // macOS 는 en_US_POSIX 에 numeric 옵션으로 비교합니다. 사진 2 가 사진 10 앞에 옵니다.
            LibrarySortKey.Name => NumericAwareCompare(left.DisplayName, right.DisplayName),
            LibrarySortKey.Flag => FlagRank(left.Frame.PickState).CompareTo(FlagRank(right.Frame.PickState)),
            LibrarySortKey.Rating => left.Frame.Rating.CompareTo(right.Frame.Rating),
            _ => 0,
        };

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
    private static IReadOnlyList<LibraryFrameListItem> StableFor(
        IReadOnlyList<LibraryFrameListItem> original,
        List<LibraryFrameListItem> sorted,
        LibrarySortKey key,
        bool ascending)
    {
        Dictionary<string, int> positions = new(original.Count, StringComparer.Ordinal);
        for (int index = 0; index < original.Count; ++index)
        {
            positions[original[index].Id] = index;
        }
        sorted.Sort((left, right) =>
        {
            int comparison = Compare(left, right, key);
            if (comparison != 0)
            {
                return ascending ? comparison : -comparison;
            }
            return positions[left.Id].CompareTo(positions[right.Id]);
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
