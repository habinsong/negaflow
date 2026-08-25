using Negaflow.Catalog;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 라이브러리·현상·인화 썸네일이 함께 쓰는 정렬의 시험입니다.
/// </summary>
/// <remarks>
/// 사용자 보고: 평판 프리뷰가 <b>언제나 맨 오른쪽</b>에 박혀 있고 정렬을 바꿔도 안 움직인다.
/// 기본 기준이 <c>InputOrder</c> 인데 그 기준이 <b>오름/내림을 통째로 무시</b>했습니다 —
/// 프리뷰는 카탈로그에 마지막으로 붙으므로 항상 끝자리였습니다. "차례를 비교하지 않는다" 와
/// "방향을 무시한다" 는 다른 말입니다.
///
/// <c>FileSize</c> 도 비교자가 없어 고르면 아무 일도 일어나지 않았습니다.
/// </remarks>
internal static class LibrarySortTests
{
    internal static void Run()
    {
        LibraryFrameListItem First = Item("a", "사진 1", 100UL);
        LibraryFrameListItem Second = Item("b", "사진 2", 300UL);
        LibraryFrameListItem Preview = Item("p", "프리뷰 1", 200UL, preview: true);
        IReadOnlyList<LibraryFrameListItem> input = [First, Second, Preview];

        // ① 입력 순서 + 오름 = 들어온 그대로.
        Check(
            Ids(LibrarySorter.Sort(input, LibrarySortKey.InputOrder, ascending: true))
                is ["a", "b", "p"],
            "library_sort_input_order_ascending_keeps_order");

        // ② 입력 순서 + 내림 = 뒤집힙니다. 프리뷰가 맨 앞으로 옵니다.
        Check(
            Ids(LibrarySorter.Sort(input, LibrarySortKey.InputOrder, ascending: false))
                is ["p", "b", "a"],
            "library_sort_input_order_descending_reverses");

        // ③ 이름순은 프리뷰도 이름으로 자리를 잡습니다 - 끝에 박히지 않습니다.
        IReadOnlyList<string> byName = Ids(
            LibrarySorter.Sort(input, LibrarySortKey.Name, ascending: true));
        Check(byName.Count == 3 && byName.Contains("p"), "library_sort_name_includes_preview");
        Check(
            !string.Equals(
                Ids(LibrarySorter.Sort(input, LibrarySortKey.Name, ascending: false))[^1],
                byName[^1],
                StringComparison.Ordinal),
            "library_sort_name_direction_moves_the_last_item");

        // ④ 파일 크기순이 실제로 크기를 봅니다. 앞 판은 아무 일도 안 했습니다.
        Check(
            Ids(LibrarySorter.Sort(input, LibrarySortKey.FileSize, ascending: true))
                is ["a", "p", "b"],
            "library_sort_file_size_ascending");
        Check(
            Ids(LibrarySorter.Sort(input, LibrarySortKey.FileSize, ascending: false))
                is ["b", "p", "a"],
            "library_sort_file_size_descending");
    }

    private static IReadOnlyList<string> Ids(IReadOnlyList<LibraryFrameListItem> items) =>
        [.. items.Select(item => item.Id)];

    private static LibraryFrameListItem Item(
        string id,
        string displayName,
        ulong fileBytes,
        bool preview = false) =>
        new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Id = id,
            DisplayName = displayName,
            IsPreviewScan = preview,
            SourceMetadata = new LibrarySourceMetadata(fileBytes, 100, 100, 3, 16, 1, 1),
        });
}
