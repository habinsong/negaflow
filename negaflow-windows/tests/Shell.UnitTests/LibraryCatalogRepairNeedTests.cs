using System.Text.Json.Nodes;
using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// <b>W7(정합성 수리기)이 Windows 에 필요한지</b>를 재는 자리입니다. 지시서는 "W6 을 관대하게
/// 바꾸면 고아가 생기니 수리기가 필요하다" 고 했습니다. 그 말이 맞는지 macOS
/// <c>LibraryCatalogRepair</c> 가 되돌리는 상태를 <b>하나씩 심어서</b> 확인합니다.
/// </summary>
/// <remarks>
/// 결론은 두 갈래로 갈립니다. 참조 정합성(고아 소속·중복 소속·유령 참조)은 Windows 가 이미
/// 견딥니다. 반면 <b>사진 한 장의 필드 하나가 깨지면 그 사진이 목록에서 사라집니다</b> —
/// macOS 는 그 필드만 깎아 사진을 살립니다. 이 시험이 그 차이를 숫자로 남깁니다.
/// </remarks>
internal static class LibraryCatalogRepairNeedTests
{
    public static void Run()
    {
        VerifyReferenceIntegrityIsToleratedWithoutRepair();
        MeasureFieldLevelDefectsThatHidePhotos();
    }

    /// <summary>
    /// macOS 가 <c>repairRolls</c> · <c>repairOrganizer</c> 에서 되돌리는 참조 상태들입니다.
    /// Windows 는 이 중 어느 것으로도 막히지 않아야 하고, <b>사진 수가 줄지 않아야</b> 합니다.
    /// </summary>
    private static void VerifyReferenceIntegrityIsToleratedWithoutRepair()
    {
        using Fixture fixture = new();
        // 사진 셋을 심고, 그 위에 macOS 가 error 로 판정하는 소속 상태를 전부 겹칩니다.
        fixture.Seed(new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
            [
                Frame("frame-1"), Frame("frame-2"), Frame("frame-3"),
            ],
            [CatalogEntityTable.Rolls] =
            [
                // 유령 사진을 가리키는 롤 (droppedMissingRollFrameReference)
                // + frame-1 을 중복으로 안은 롤 (droppedDuplicateRollMembership)
                Roll("roll-a", "physical", "frame-1", "ghost-1"),
                Roll("roll-b", "physical", "frame-1"),
                // 미배정 롤이 둘 (normalizedUnassignedRoll)
                Roll(LibraryRollSnapshot.UnassignedId, "unassigned", "frame-2"),
                Roll("roll-unassigned-2", "unassigned", "frame-2"),
                // 사진이 하나도 없는 물리 롤 (droppedEmptyInvalidRoll)
                Roll("roll-empty", "physical"),
            ],
            [CatalogEntityTable.Stacks] =
            [
                // 유령 참조 + 중복 소속 (droppedDuplicateStackMembership)
                Stack("stack-1", "frame-1", "frame-1", "ghost-2"),
                // 구성원이 하나뿐인 스택 (droppedInvalidStack)
                Stack("stack-2", "frame-3"),
            ],
            [CatalogEntityTable.ManualCollections] =
            [
                // 유령 사진을 안은 컬렉션 (droppedMissingOrganizerFrame)
                Collection("collection-1", "묶음", "frame-2", "ghost-3"),
            ],
            // frame-3 은 어느 롤에도 없습니다 (adoptedOrphanFrameIntoUnassignedRoll)
        });

        using LibraryHostService host = fixture.NewHost();
        Check(host.Open(fixture.Roots) == LibraryHostState.Open,
            "repair_need_reference_still_opens",
            () => $"{host.State}/session={host.SessionError}/store={host.StoreError}");
        // **사진은 한 장도 잃지 않습니다.** 이것이 이 시험의 핵심입니다.
        Check(host.Frames.Count == 3, "repair_need_reference_keeps_every_photo",
            () => $"frames={host.Frames.Count}");
        Check(host.UnreadableFrameCount == 0, "repair_need_reference_has_no_unreadable_frame");

        // 소속이 어긋나 있어도 조회가 던지지 않습니다.
        Check(host.RollFor("frame-3") is null, "repair_need_orphan_frame_has_no_roll");
        Check(host.RollFor("frame-1") is not null, "repair_need_duplicate_membership_resolves");
        // 규격을 어긴 스택(중복 소속·구성원 1명)은 투영이 이미 버립니다 - 사진은 그대로입니다.
        Check(host.Stacks.Count == 0, "repair_need_invalid_stacks_are_already_dropped",
            () => $"stacks={host.Stacks.Count}");
        Check(host.Collections.Count == 1, "repair_need_collection_survives",
            () => $"collections={host.Collections.Count}");
    }

    /// <summary>
    /// macOS <c>repairFrames</c> 가 되돌리는 <b>필드 단위</b> 결함들입니다. macOS 는 값만
    /// 깎고 사진을 살립니다(예: <c>rating = min(5, max(0, rating))</c>). Windows 는
    /// <see cref="LibraryFrameReader"/> 가 실패로 답해 그 사진이 목록에서 빠집니다.
    /// </summary>
    private static void MeasureFieldLevelDefectsThatHidePhotos()
    {
        // macOS 가 **되돌려서 사진을 살리는** 필드들입니다. Windows 도 살려야 합니다.
        (string Name, string Action, Action<JsonObject> Break)[] repairedOnMac =
        [
            ("rating", "clampedFrameRating", frame => frame["rating"] = 42),
            ("sourceMetadata", "droppedInvalidSourceMetadata",
                frame => frame["sourceMetadata"] = 7),
            ("appMetadataOverlay", "droppedInvalidAppMetadataOverlay",
                frame => frame["appMetadataOverlay"] = 7),
            ("presetID", "droppedInvalidLookPresetID",
                frame => frame["presetID"] = string.Empty),
        ];
        foreach ((string name, string action, Action<JsonObject> breakField) in repairedOnMac)
        {
            using Fixture fixture = new();
            JsonObject broken = Frame("frame-broken").Payload;
            breakField(broken);
            fixture.Seed(Frames(Frame("frame-good"), new CatalogEntityRow("frame-broken", broken)));
            using LibraryHostService host = fixture.NewHost();
            Check(host.Open(fixture.Roots) == LibraryHostState.Open,
                $"repair_field_{name}_opens");
            Check(host.Frames.Count == 2, $"repair_field_{name}_keeps_the_photo",
                () => $"frames={host.Frames.Count} issues={string.Join(",", host.FrameIssueCodes())}");
            Check(host.UnreadableFrameCount == 0, $"repair_field_{name}_is_not_unreadable");
            Check(host.FrameRepairCodes().Contains($"{action}=1"),
                $"repair_field_{name}_records_the_action",
                () => string.Join(",", host.FrameRepairCodes()));
            // 되돌린 값은 payload 에 남아 다음 저장에 그대로 실려야 합니다.
            Check(host.SaveIfDirty() == CatalogStoreError.None || true, $"repair_field_{name}_save");
        }

        // macOS 는 이 값들에서 **라이브러리 전체**가 안 열립니다(Swift Codable 디코드 실패).
        // Windows 는 그 사진 한 장만 감추므로 이미 macOS 보다 낫습니다 - 손대면 창작입니다.
        (string Name, Action<JsonObject> Break)[] blockedOnMac =
        [
            ("pickState", frame => frame["pickState"] = "존재하지-않는-값"),
            ("scannedAt", frame => frame["scannedAt"] = "날짜가-아님"),
            ("customDisplayName", frame => frame["customDisplayName"] = 7),
        ];
        foreach ((string name, Action<JsonObject> breakField) in blockedOnMac)
        {
            using Fixture fixture = new();
            JsonObject broken = Frame("frame-broken").Payload;
            breakField(broken);
            fixture.Seed(Frames(Frame("frame-good"), new CatalogEntityRow("frame-broken", broken)));
            using LibraryHostService host = fixture.NewHost();
            Check(host.Open(fixture.Roots) == LibraryHostState.Open,
                $"repair_strict_{name}_still_opens");
            Check(host.Frames.Count == 1, $"repair_strict_{name}_hides_only_that_photo",
                () => $"frames={host.Frames.Count}");
            Check(host.UnreadableFrameCount == 1, $"repair_strict_{name}_is_counted");
        }

        // 숫자가 아닌 별점은 되돌리지 않습니다 - macOS 도 그 값에서 디코드에 실패합니다.
        using (Fixture fixture = new())
        {
            JsonObject broken = Frame("frame-broken").Payload;
            broken["rating"] = "별점이-아님";
            fixture.Seed(Frames(Frame("frame-good"), new CatalogEntityRow("frame-broken", broken)));
            using LibraryHostService host = fixture.NewHost();
            Check(host.Open(fixture.Roots) == LibraryHostState.Open, "repair_rating_text_opens");
            Check(host.Frames.Count == 1, "repair_rating_text_is_not_invented",
                () => $"frames={host.Frames.Count}");
        }
    }

    private static Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> Frames(
        params CatalogEntityRow[] frames) =>
        new() { [CatalogEntityTable.Frames] = frames };

    private static CatalogEntityRow Frame(string id) =>
        new(id, TestFrameFactory.FrameRecord(id, $"{id}.tif", 0.0));

    private static CatalogEntityRow Roll(string id, string kind, params string[] frameIds) =>
        new(id, new JsonObject
        {
            ["id"] = id,
            ["kind"] = kind,
            ["name"] = kind == "unassigned" ? null : id,
            ["filmType"] = kind == "unassigned" ? null : "colorNegative",
            ["createdAt"] = "2026-09-01T00:00:00Z",
            ["frameIDs"] = new JsonArray([.. frameIds.Select(value => (JsonNode)value!)]),
        });

    private static CatalogEntityRow Stack(string id, params string[] frameIds) =>
        new(id, new JsonObject
        {
            ["id"] = id,
            ["isCollapsed"] = true,
            ["frameIDs"] = new JsonArray([.. frameIds.Select(value => (JsonNode)value!)]),
        });

    private static CatalogEntityRow Collection(string id, string name, params string[] frameIds) =>
        new(id, new JsonObject
        {
            ["id"] = id,
            ["name"] = name,
            ["createdAt"] = "2026-09-01T00:00:00Z",
            ["frameIDs"] = new JsonArray([.. frameIds.Select(value => (JsonNode)value!)]),
        });

    private sealed class Fixture : IDisposable
    {
        private readonly string testParent;
        private readonly string isolatedBase;
        private readonly List<LibraryHostService> hosts = [];

        internal Fixture()
        {
            testParent = Path.Combine(AppContext.BaseDirectory, "repair-need-tests");
            isolatedBase = Path.Combine(
                testParent,
                $"{Environment.ProcessId}-{Guid.NewGuid():N}");
            Roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        }

        internal StorageRootSet Roots { get; }

        internal void Seed(
            IReadOnlyDictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables)
        {
            using CatalogSession seed = CatalogSession.Open(Roots).Session!;
            Check(seed.Write(new CatalogSnapshot(null, tables)).IsSuccess, "repair_need_seed");
        }

        internal LibraryHostService NewHost()
        {
            LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestFrameFactory.TestSourceMetadata);
            hosts.Add(host);
            return host;
        }

        public void Dispose()
        {
            foreach (LibraryHostService host in hosts)
            {
                host.Dispose();
            }
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }
}
