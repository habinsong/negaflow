using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// macOS <c>Sidecar.developHistory</c> — 기록은 스냅샷과 같은 기계를 쓰되 목록만 다릅니다.
/// 두 목록이 서로를 건드리지 않는다는 것이 이 시험의 요지입니다.
/// </summary>
internal static class LibraryDevelopHistoryTests
{
    public static void Run()
    {
        JsonObject record = new()
        {
            ["id"] = "frame-1",
            ["params"] = new JsonObject { ["exposure"] = 0.25 },
            ["presetID"] = "neutral",
        };

        LibraryFrameWriteResult recorded = LibraryVersions.Capture(
            record,
            "history-1",
            "기록 1",
            DateTimeOffset.UnixEpoch,
            LibraryVersions.HistoryListName);
        Check(recorded.Error == LibraryFrameError.None, "history_capture_succeeds");
        JsonObject afterRecord = recorded.FrameRecord!;
        Check(afterRecord[LibraryVersions.HistoryListName] is JsonArray { Count: 1 }, "history_list_has_one");
        Check(
            afterRecord[LibraryVersions.SnapshotListName] is null,
            "history_capture_leaves_snapshots_untouched");

        // 기록을 담은 뒤 노출을 바꿉니다. 되돌리면 담을 때의 값으로 돌아와야 합니다.
        afterRecord["params"] = new JsonObject { ["exposure"] = 1.5 };
        LibraryFrameWriteResult applied = LibraryVersions.Restore(
            afterRecord,
            "history-1",
            LibraryVersions.HistoryListName);
        Check(applied.Error == LibraryFrameError.None, "history_restore_succeeds");
        Check(
            applied.FrameRecord!["params"]!["exposure"]!.GetValue<double>() == 0.25,
            "history_restore_brings_back_recipe");
        Check(
            applied.FrameRecord![LibraryVersions.HistoryListName] is JsonArray { Count: 1 },
            "history_restore_keeps_the_list");

        // 같은 프레임에 스냅샷도 담아 두 목록이 따로 사는지 봅니다.
        LibraryFrameWriteResult snapshot = LibraryVersions.Capture(
            applied.FrameRecord!,
            "snapshot-1",
            "스냅샷 1",
            DateTimeOffset.UnixEpoch);
        Check(snapshot.Error == LibraryFrameError.None, "snapshot_capture_succeeds");
        Check(
            snapshot.FrameRecord![LibraryVersions.SnapshotListName] is JsonArray { Count: 1 } &&
            snapshot.FrameRecord![LibraryVersions.HistoryListName] is JsonArray { Count: 1 },
            "two_lists_live_side_by_side");

        LibraryFrameWriteResult deleted = LibraryVersions.Delete(
            snapshot.FrameRecord!,
            "history-1",
            LibraryVersions.HistoryListName);
        Check(deleted.Error == LibraryFrameError.None, "history_delete_succeeds");
        Check(
            deleted.FrameRecord![LibraryVersions.HistoryListName] is JsonArray { Count: 0 } &&
            deleted.FrameRecord![LibraryVersions.SnapshotListName] is JsonArray { Count: 1 },
            "history_delete_leaves_snapshots");
    }
}
