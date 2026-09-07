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

        VerifyInputInterpretationRoundTrips();
    }

    /// <summary>
    /// 버전을 되돌리면 <b>입력 감마와 베이스 배율도</b> 담을 때의 값으로 와야 합니다(W66).
    /// </summary>
    /// <remarks>
    /// 이 둘은 <c>params</c> 안에 있지만 다른 조정값과 성격이 다릅니다 — <b>원본을 어떻게
    /// 읽을지</b>를 정하므로, 되돌아오지 않으면 그림 전체가 그때와 다른 밝기로 섭니다.
    /// 노출 하나만 확인하면 그 자리가 비어도 시험이 통과합니다.
    ///
    /// 소수 자리도 그대로여야 합니다. 표시용 반올림이 이 길에 새면 버전을 오갈 때마다 값이
    /// 조금씩 밀립니다.
    /// </remarks>
    private static void VerifyInputInterpretationRoundTrips()
    {
        const double gamma = 1.234_5;
        const double scale = 0.815;
        JsonObject record = new()
        {
            ["id"] = "frame-2",
            ["params"] = new JsonObject
            {
                ["exposure"] = 0.25,
                ["inputGamma"] = gamma,
                ["baseScale"] = scale,
                ["baseEstimationMode"] = "auto",
            },
        };

        LibraryFrameWriteResult captured = LibraryVersions.Capture(
            record,
            "input-1",
            "입력 기록",
            DateTimeOffset.UnixEpoch,
            LibraryVersions.HistoryListName);
        Check(captured.Error == LibraryFrameError.None, "history_input_capture_succeeds");

        // 담은 뒤 셋 다 바꿉니다.
        JsonObject changed = captured.FrameRecord!;
        changed["params"] = new JsonObject
        {
            ["exposure"] = 1.5,
            ["inputGamma"] = 3.3,
            ["baseScale"] = 1.4,
            ["baseEstimationMode"] = "auto",
        };

        LibraryFrameWriteResult restored = LibraryVersions.Restore(
            changed,
            "input-1",
            LibraryVersions.HistoryListName);
        Check(restored.Error == LibraryFrameError.None, "history_input_restore_succeeds");

        JsonObject? parameters = restored.FrameRecord!["params"] as JsonObject;
        Check(parameters?["inputGamma"]?.GetValue<double>() == gamma,
            "history_restore_brings_back_the_input_gamma",
            () => parameters?["inputGamma"]?.ToJsonString() ?? "null");
        Check(parameters?["baseScale"]?.GetValue<double>() == scale,
            "history_restore_brings_back_the_base_scale",
            () => parameters?["baseScale"]?.ToJsonString() ?? "null");
        Check(parameters?["exposure"]?.GetValue<double>() == 0.25,
            "history_restore_brings_back_the_exposure_too");
    }
}
