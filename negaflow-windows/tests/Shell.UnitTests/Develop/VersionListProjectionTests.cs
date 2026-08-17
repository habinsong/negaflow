using System.Globalization;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>버전 목록 줄의 표기입니다.</summary>
internal static class VersionListProjectionTests
{
    public static void Run()
    {
        Check(VersionListProjection.Rows([], "복원", "삭제").Count == 0,
            "version_list_is_empty_without_versions");

        DateTimeOffset created = new(2026, 8, 17, 3, 4, 5, TimeSpan.Zero);
        IReadOnlyList<VersionRow> rows = VersionListProjection.Rows(
            [
                new LibraryVersionSnapshot("v1", "밝게", created, null),
                new LibraryVersionSnapshot("v2", "어둡게", null, null),
            ],
            "복원",
            "삭제");
        Check(rows.Count == 2 && rows[0].Id == "v1" && rows[1].Id == "v2",
            "version_list_keeps_the_catalog_order");
        Check(rows[0].Name == "밝게" && rows[0].RestoreText == "복원" && rows[0].DeleteText == "삭제",
            "version_list_carries_the_name_and_the_button_words");
        Check(rows[0].CreatedText ==
                created.ToLocalTime().ToString("g", CultureInfo.CurrentCulture),
            "version_list_writes_the_created_time_in_local_time");
        // 기록되지 않은 시각을 지어내지 않습니다.
        Check(rows[1].CreatedText.Length == 0,
            "version_list_leaves_an_unrecorded_time_blank");
    }
}
