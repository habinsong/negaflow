using System.ComponentModel;
using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 별·깃발·제외가 라이브러리 격자·현상 스트립·인화 스트립·도구줄에서 <b>같이</b> 움직이는지 봅니다.
/// </summary>
/// <remarks>
/// 네 곳은 모두 <see cref="LibraryFrameListItem"/> <b>같은 객체</b>를 봅니다. 목록을 다시 지어
/// 새 객체를 넣는 길로는 필름스트립이 따라오지 않습니다 — <c>FilmstripView.ShowFrames</c> 는
/// 아이디가 같으면 예전 객체를 그대로 붙들기 때문입니다(칸을 헐면 선택이 튀고 앱이 죽습니다).
/// 그래서 값은 <b>제자리에서</b> 갈아 끼워야 하고, 그때 알림이 나가야 화면이 따라옵니다.
/// </remarks>
internal static class FrameMarkSyncTests
{
    public static void Run()
    {
        VerifyMarksRefreshInPlace();
        VerifyUnchangedFramesStaySilent();
    }

    private static LibraryFrameSnapshot Numbered(string id, int rating, FramePickState pick) =>
        Frame(null) with { Id = id, Rating = rating, PickState = pick };

    private static void VerifyMarksRefreshInPlace()
    {
        LibraryFrameSnapshot[] before =
        [
            Numbered("a", 0, FramePickState.Unflagged),
            Numbered("b", 0, FramePickState.Unflagged),
        ];
        IReadOnlyList<LibraryFrameListItem> items = LibraryFrameListItems.From(before);
        LibraryFrameListItem watched = items[1];
        List<string> announced = [];
        watched.PropertyChanged += (_, args) => announced.Add(args.PropertyName ?? string.Empty);

        LibraryFrameSnapshot[] after =
        [
            before[0],
            Numbered("b", 4, FramePickState.Rejected),
        ];
        int changed = LibraryFrameListItems.Refresh(items, after);

        Check(changed == 1, "marks refresh touches only the edited frame");
        // 스트립이 붙들고 있는 바로 그 객체여야 합니다. 새 객체를 만들면 스트립은 못 봅니다.
        Check(ReferenceEquals(items[1], watched), "marks refresh keeps the item object");
        Check(watched.Rating == 4, "marks refresh carries the rating");
        Check(watched.PickState == FramePickState.Rejected, "marks refresh carries the pick state");
        Check(watched.IsFlagged, "rejected frames show a mark");
        Check(announced.Contains(nameof(LibraryFrameListItem.Rating)), "rating change is announced");
        Check(
            announced.Contains(nameof(LibraryFrameListItem.PickState)) &&
            announced.Contains(nameof(LibraryFrameListItem.PickGlyph)) &&
            announced.Contains(nameof(LibraryFrameListItem.IsFlagged)),
            "pick state change is announced");
    }

    private static void VerifyUnchangedFramesStaySilent()
    {
        LibraryFrameSnapshot[] frames = [Numbered("a", 2, FramePickState.Picked)];
        IReadOnlyList<LibraryFrameListItem> items = LibraryFrameListItems.From(frames);
        int announced = 0;
        items[0].PropertyChanged += (_, _) => ++announced;

        Check(
            LibraryFrameListItems.Refresh(items, frames) == 0,
            "the same snapshot refreshes nothing");
        Check(announced == 0, "the same snapshot announces nothing");

        // 값이 같아도 스냅샷 객체가 다르면 갈아 끼우되, 바뀌지 않은 값은 알리지 않습니다.
        int ratingAnnounced = 0;
        items[0].PropertyChanged += (_, args) =>
        {
            if (string.Equals(args.PropertyName, nameof(LibraryFrameListItem.Rating), StringComparison.Ordinal))
            {
                ++ratingAnnounced;
            }
        };
        Check(
            LibraryFrameListItems.Refresh(items, [Numbered("a", 2, FramePickState.Picked)]) == 1,
            "a fresh snapshot is taken");
        Check(ratingAnnounced == 0, "an unchanged rating is not announced");
    }
}
