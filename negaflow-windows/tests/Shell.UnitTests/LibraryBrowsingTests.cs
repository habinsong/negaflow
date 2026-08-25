using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class LibraryBrowsingTests
{
    public static void Run()
    {
        VerifyThumbnailScaler();
        VerifyLibrarySorter();
        VerifyLibraryQuickFilters();
    }

    private static void VerifyThumbnailScaler()
    {
        // 두 배 축소에서 첫 화소는 (0, 10, 20, 30) 의 평균이라 15 가 되어야 합니다.
        byte[] source = new byte[4 * 2 * 4];
        for (int index = 0; index < 4; ++index)
        {
            source[index] = 0;
            source[4 + index] = 10;
            source[(4 * 4) + index] = 20;
            source[(5 * 4) + index] = 30;
        }
        byte[] reduced = ThumbnailScaler.Reduce(source, 4, 2, 2, out int width, out int height);
        Check(width == 2 && height == 1 && reduced.Length == 8, "thumbnail_scaler_reduces_to_bound");
        Check(reduced[0] == 15 && reduced[3] == 15, "thumbnail_scaler_box_averages");

        byte[] untouched = ThumbnailScaler.Reduce(source, 4, 2, 360, out int keptWidth, out int keptHeight);
        Check(keptWidth == 4 && keptHeight == 2 && untouched[4] == 10, "thumbnail_scaler_keeps_small_images");

        byte[] wide = new byte[1000 * 10 * 4];
        _ = ThumbnailScaler.Reduce(wide, 1000, 10, 360, out int boundWidth, out int boundHeight);
        Check(Math.Max(boundWidth, boundHeight) <= 360, "thumbnail_scaler_never_exceeds_maximum");
    }

    /// <summary>
    /// 정렬은 macOS 비교자를 그대로 옮긴 것입니다. 사람이 읽는 숫자 순서와, 값이 같을 때
    /// 입력 순서가 지켜지는지가 실제로 눈에 띄는 두 가지입니다.
    /// </summary>
    private static void VerifyLibrarySorter()
    {
        LibraryFrameListItem Item(string id, string name, int rating) =>
            new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2), displayName: name) with
            {
                Id = id,
                Rating = rating,
            });

        LibraryFrameListItem[] source =
        [
            Item("a", "사진 10", 1),
            Item("b", "사진 2", 5),
            Item("c", "사진 1", 1),
        ];

        IReadOnlyList<LibraryFrameListItem> byName = LibrarySorter.Sort(
            source, LibrarySortKey.Name, ascending: true);
        Check(
            byName[0].DisplayName == "사진 1" &&
            byName[1].DisplayName == "사진 2" &&
            byName[2].DisplayName == "사진 10",
            "library_sort_name_reads_numbers_as_numbers");

        IReadOnlyList<LibraryFrameListItem> byRating = LibrarySorter.Sort(
            source, LibrarySortKey.Rating, ascending: false);
        Check(
            byRating[0].Id == "b" && byRating[1].Id == "a" && byRating[2].Id == "c",
            "library_sort_rating_keeps_input_order_within_ties");

        // **입력 순서도 방향은 따릅니다.** macOS 두 자리가 같은 말을 합니다:
        //   LibraryPresentation.sortedFrames:  if key == .inputOrder {
        //       return ascending ? frames : frames.reversed() }
        //   LibraryBrowserProjection.sortFrameIDs: guard descriptor.key != .inputOrder else {
        //       return descriptor.ascending ? frameIDs : frameIDs.reversed() }
        // 앞 판의 시험은 "차례를 비교하지 않는다"를 "방향을 무시한다"로 잘못 못 박아,
        // 기본 정렬에서 목록이 한 칸도 뒤집히지 않게 만들었습니다.
        Check(
            ReferenceEquals(LibrarySorter.Sort(source, LibrarySortKey.InputOrder, ascending: true), source),
            "library_sort_input_order_ascending_keeps_input");
        IReadOnlyList<LibraryFrameListItem> reversed =
            LibrarySorter.Sort(source, LibrarySortKey.InputOrder, ascending: false);
        Check(
            reversed[0].Id == "c" && reversed[1].Id == "b" && reversed[2].Id == "a",
            "library_sort_input_order_descending_reverses");
    }

    /// <summary>
    /// 빠른 필터는 전부 AND 이지만 채택/제외 두 깃발만 예외로 서로 OR 입니다. 그 규칙이
    /// macOS 와 같은지가 여기서 확인할 유일한 것입니다.
    /// </summary>
    private static void VerifyLibraryQuickFilters()
    {
        LibraryFrameListItem Item(string id, int rating, FramePickState pick) =>
            new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
            {
                Id = id,
                Rating = rating,
                PickState = pick,
            });

        LibraryFrameListItem[] source =
        [
            Item("picked", 4, FramePickState.Picked),
            Item("rejected", 2, FramePickState.Rejected),
            Item("plain", 5, FramePickState.Unflagged),
        ];

        Check(
            ReferenceEquals(LibraryQuickFilterState.None.Apply(source), source),
            "library_quick_filters_inactive_passes_everything");

        IReadOnlyList<LibraryFrameListItem> flags = new LibraryQuickFilterState
        {
            Picked = true,
            Rejected = true,
        }.Apply(source);
        Check(
            flags.Count == 2 && flags[0].Id == "picked" && flags[1].Id == "rejected",
            "library_quick_filters_flags_are_or");

        IReadOnlyList<LibraryFrameListItem> combined = new LibraryQuickFilterState
        {
            Picked = true,
            MinimumRating = 5,
        }.Apply(source);
        Check(combined.Count == 0, "library_quick_filters_axes_are_and");

        // 원본 크기·화소 수를 기록하지 못한 frame 만 남깁니다. 이 값이 없으면 relink 가 다른
        // 사진을 같은 자리에 연결하는 것을 막지 못하므로, 사용자가 찾아낼 수 있어야 합니다.
        LibraryFrameListItem[] metadata =
        [
            new(Frame(null) with
            {
                Id = "known",
                SourceMetadata = new LibrarySourceMetadata(1234, 4000, 3000, 3, 16, 1, 1),
            }),
            new(Frame(null) with { Id = "unknown", SourceMetadata = null }),
        ];
        IReadOnlyList<LibraryFrameListItem> unknown =
            new LibraryQuickFilterState { MetadataUnknown = true }.Apply(metadata);
        Check(unknown.Count == 1 && unknown[0].Id == "unknown",
            "library_quick_filters_metadata_unknown");

        // macOS 는 프로파일이 **없는** 사진을 이 축에 넣지 않습니다 — 검증할 프로파일이
        // 없기 때문입니다. 함께 나가는 15개는 전부 realOnly 라 걸린 것은 모두 걸립니다.
        LibraryFrameListItem[] profiles =
        [
            new(Frame(null) with
            {
                Id = "profiled",
                Base = new BaseRecipe(
                    BaseEstimationMode.Preset,
                    "kodak-portra-400",
                    null,
                    "noritsu__color-nega__kodak-portra-400"),
            }),
            new(Frame(null) with
            {
                Id = "no-profile",
                Base = new BaseRecipe(BaseEstimationMode.Preset, "kodak-portra-400", null, null),
            }),
        ];
        IReadOnlyList<LibraryFrameListItem> unvalidated =
            new LibraryQuickFilterState { UnvalidatedProfile = true }.Apply(profiles);
        Check(unvalidated.Count == 1 && unvalidated[0].Id == "profiled",
            "library_quick_filters_unvalidated_profile");

        // 저장된 찾기가 이 축을 잃으면, 다시 연 스마트 컬렉션이 다른 사진을 보여 줍니다.
        Check(
            LibraryStoredQuery
                .From(new LibraryQuickFilterState { UnvalidatedProfile = true }, null)
                .ToQuickFilters([]).UnvalidatedProfile,
            "stored_query_round_trips_unvalidated_profile");
    }

    /// <summary>
    /// 목적지 규칙은 사용자가 고른 것이 어디에 어떤 이름으로 쓰이는지를 정합니다. 빈 패턴으로
    /// 이름 없는 파일을 만들지 않는 것이 여기서 가장 중요합니다.
    /// </summary>
}
