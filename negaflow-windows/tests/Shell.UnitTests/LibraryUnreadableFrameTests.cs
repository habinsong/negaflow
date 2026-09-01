using System.Text.Json.Nodes;
using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 이 버전이 읽지 못한 사진이 <b>조용히 사라지지 않는지</b> 재는 자리입니다.
/// macOS 의 <c>regionDefectDisplayROI</c> 사고가 Windows 에서 나타나는 모습이 바로
/// 이것입니다 — macOS 는 전체가 잠기고, Windows 는 그 사진만 목록에서 빠집니다.
/// </summary>
internal static class LibraryUnreadableFrameTests
{
    public static void Run()
    {
        VerifyUnreadableFramesAreCountedAndPreserved();
        VerifyDanglingReferencesDoNotBlockTheLibrary();
    }

    /// <summary>
    /// 부수 기록을 관대하게 읽으면 고아 참조가 생길 수 있습니다 — 그때 라이브러리가
    /// 막히는지 재는 자리입니다.
    /// </summary>
    /// <remarks>
    /// <b>이 시험이 W7(정합성 수리기)의 필요 여부를 판정합니다.</b> 사진·롤·폴더는 엄격하게
    /// 읽으므로 관대 처리가 뼈대에서 줄을 빼지 못하고, 투영 계층은 없는 id 를 이미 건너뜁니다
    /// (<c>LibraryStackProjection.Apply</c> 의 <c>order.ContainsKey</c>). 이 시험이 깨지는
    /// 날이 수리기가 필요해지는 날입니다.
    /// </remarks>
    private static void VerifyDanglingReferencesDoNotBlockTheLibrary()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "dangling-reference-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", TestFrameFactory.FrameRecord(
                                "frame-1",
                                "IMG_0001.tif",
                                0.0)),
                        ],
                        // 없는 사진 둘을 가리키는 묶음입니다 - 고아 참조 그 자체입니다.
                        [CatalogEntityTable.Stacks] =
                        [
                            new("stack-1", new JsonObject
                            {
                                ["id"] = "stack-1",
                                ["frameIDs"] = new JsonArray("frame-1", "ghost-1", "ghost-2"),
                                ["isCollapsed"] = true,
                            }),
                        ],
                    })).IsSuccess,
                    "dangling_seed_write");
            }

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestFrameFactory.TestSourceMetadata);
            Check(host.Open(roots) == LibraryHostState.Open, "dangling_still_opens",
                () => $"{host.State}/{host.StoreError}");
            Check(host.Frames.Count == 1, "dangling_keeps_frame_count",
                () => $"frames={host.Frames.Count}");
            Check(host.Stacks.Count == 1, "dangling_keeps_the_stack");
            Check(host.UnreadableFrameCount == 0, "dangling_is_not_an_unreadable_frame");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifyUnreadableFramesAreCountedAndPreserved()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "unreadable-frame-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        // 두 번째 사진은 이 빌드가 모르는 pickState 를 답니다 - macOS 도 그 값에서
        // 디코드에 실패하므로 되돌리지 않습니다(LibraryFrameRepair 참조).
        JsonObject unreadable = TestFrameFactory.FrameRecord("frame-2", "IMG_0002.tif", 0.0);
        unreadable["pickState"] = "이-빌드가-모르는-값";
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", TestFrameFactory.FrameRecord(
                                "frame-1",
                                "IMG_0001.tif",
                                0.0)),
                            new("frame-2", unreadable),
                        ],
                    })).IsSuccess,
                    "unreadable_seed_write");
            }

            using (LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestFrameFactory.TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "unreadable_open");
                // 못 읽은 사진은 목록에서 빠지되, 나머지는 그대로 열립니다.
                Check(host.Frames.Count == 1, "unreadable_drops_only_the_bad_frame",
                    () => $"frames={host.Frames.Count}");
                Check(host.UnreadableFrameCount == 1, "unreadable_counts_the_bad_frame",
                    () => $"issues={host.UnreadableFrameCount}");
                Check(host.FrameIssueCodes().Count == 1 &&
                    host.FrameIssueCodes()[0].StartsWith("InvalidPickState=", StringComparison.Ordinal),
                    "unreadable_reports_issue_code",
                    () => string.Join(",", host.FrameIssueCodes()));

                // 편집하고 저장해도 못 읽은 사진의 payload 는 그대로 다시 쓰여야 합니다.
                Check(host.Edit(
                        host.Frames[0].Id,
                        new LibraryFrameEdit(
                            new ToneAdjustment(0.5, 0, 0, 0, 0, 0),
                            null)) == LibraryFrameError.None,
                    "unreadable_edit_readable_frame");
                Check(host.SaveIfDirty() == CatalogStoreError.None, "unreadable_save",
                    () => host.SaveIfDirty().ToString());
            }

            using (CatalogSession reopened = CatalogSession.Open(roots).Session!)
            {
                CatalogReadResult read = reopened.Read();
                IReadOnlyList<CatalogEntityRow> rows =
                    read.Snapshot?.Rows(CatalogEntityTable.Frames) ?? [];
                // **읽기 실패가 사진을 지우지는 않습니다.** 이 설계는 macOS 보다 견고하며
                // 그대로 유지해야 합니다.
                Check(rows.Count == 2, "unreadable_survives_save", () => $"rows={rows.Count}");
                CatalogEntityRow? preserved = rows.FirstOrDefault(row =>
                    string.Equals(row.Id, "frame-2", StringComparison.Ordinal));
                Check(preserved is not null, "unreadable_row_still_present");
                Check(preserved?.Payload["pickState"]?.GetValue<string>() == "이-빌드가-모르는-값",
                    "unreadable_payload_unchanged",
                    () => preserved?.Payload.ToJsonString() ?? "<none>");
                Check(preserved?.Payload["futureFrameValue"]?.GetValue<string>() == "preserve-me",
                    "unreadable_payload_keeps_unknown_fields");
            }
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }
}
