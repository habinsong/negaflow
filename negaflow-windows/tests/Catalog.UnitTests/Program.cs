using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog.UnitTests;

internal static class Program
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    /// <summary>
    /// 이 인자로 실행되면 테스트가 아니라 lock 경쟁자로 동작합니다. 자기 자신을 다시 띄워
    /// **다른 프로세스**에서 세션을 열어 보게 하는 용도이며, 그래야 단일 작성자 계약이 프로세스
    /// 경계에서도 성립한다는 것이 추론이 아니라 관측이 됩니다.
    /// </summary>
    private const string LockContenderArgument = "--lock-contender";

    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == LockContenderArgument)
        {
            return RunLockContender(args[1]);
        }

        string fixturePath = Path.Combine(AppContext.BaseDirectory, "develop-route-v1.json");
        using JsonDocument fixture = JsonDocument.Parse(File.ReadAllBytes(fixturePath));

        VerifyValidFixtureCases(fixture.RootElement);
        VerifyInvalidFixtureCases(fixture.RootElement);
        VerifyReaderShapeErrors();
        VerifyRouteWriting(fixture.RootElement);
        VerifyAllFilmEmulationNames(fixture.RootElement);
        VerifyInvalidSelections(fixture.RootElement);
        VerifyCanonicalJson();
        VerifyStorageRootResolution();
        VerifyCatalogProcessLock();
        VerifySqliteCatalogStore();
        VerifyLibraryFrameProjection();

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "catalog_unit_tests",
            assertions = assertionCount,
            failures = Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

    private static void VerifyValidFixtureCases(JsonElement root)
    {
        Check(root.GetProperty("schemaVersion").GetInt32() == 1, "fixture_schema_version");

        foreach (JsonElement testCase in root.GetProperty("validCases").EnumerateArray())
        {
            string id = testCase.GetProperty("id").GetString() ?? "missing-id";
            DevelopRouteReadResult result = DevelopRouteReader.Read(
                testCase.GetProperty("frame"));
            Check(result.IsSuccess, $"{id}_read_success");
            if (result.Route is not { } route)
            {
                continue;
            }

            JsonElement expected = testCase.GetProperty("expected");
            Check(SourceTransportName(route.SourceTransport) ==
                expected.GetProperty("sourceTransport").GetString(), $"{id}_transport");
            Check(SourceSignalName(route.SourceSignalKind) ==
                expected.GetProperty("sourceSignalKind").GetString(), $"{id}_signal");
            Check(ProcessName(route.DevelopmentProcess) ==
                expected.GetProperty("developmentProcess").GetString(), $"{id}_process");
            Check(FilmLookSourceName(route.FilmLookSource) ==
                expected.GetProperty("filmLookSource").GetString(), $"{id}_look_source");
            Check(FilmEmulationName(route.FilmEmulation) ==
                expected.GetProperty("filmEmulation").GetString(), $"{id}_emulation");
            Check(Math.Abs(route.FilmEmulationIntensity -
                expected.GetProperty("filmEmulationIntensity").GetDouble()) < 1e-12,
                $"{id}_intensity");
            Check(route.UsedLegacySourceSignal ==
                expected.GetProperty("usedLegacySourceSignal").GetBoolean(),
                $"{id}_legacy_signal");
            Check(route.UsedLegacyIntensityDefault ==
                expected.GetProperty("usedLegacyIntensityDefault").GetBoolean(),
                $"{id}_legacy_intensity");
            Check(route.IsDigitalSource ==
                (route.SourceSignalKind == SourceSignalKind.RenderedDigital),
                $"{id}_digital_derived");
        }
    }

    private static void VerifyInvalidFixtureCases(JsonElement root)
    {
        foreach (JsonElement testCase in root.GetProperty("invalidCases").EnumerateArray())
        {
            string id = testCase.GetProperty("id").GetString() ?? "missing-id";
            DevelopRouteReadResult result = DevelopRouteReader.Read(
                testCase.GetProperty("frame"));
            Check(!result.IsSuccess, $"{id}_read_rejected");
            Check(ErrorName(result.Error) == testCase.GetProperty("expectedError").GetString(),
                $"{id}_error");
            Check(result.Route is null, $"{id}_no_partial_route");
        }
    }

    private static void VerifyRouteWriting(JsonElement root)
    {
        JsonElement legacyFrame = root.GetProperty("validCases")[0].GetProperty("frame");
        JsonObject original = JsonNode.Parse(legacyFrame.GetRawText())!.AsObject();
        DevelopRouteSelection digitalSelection = DevelopRouteSelection.FromProcess(
            DevelopmentProcess.DigitalColor,
            FilmEmulation.Portra400);

        Check(digitalSelection.FilmEmulationIntensity == 0.5, "new_recipe_intensity_half");
        DevelopRouteWriteResult write = DevelopRouteWriter.Apply(original, digitalSelection);
        Check(write.IsSuccess, "write_digital_success");
        if (write.FrameRecord is not { } digitalFrame)
        {
            return;
        }

        Check(original["sourceSignalKind"] is null, "write_original_unchanged");
        Check(digitalFrame["sourceKind"]!.GetValue<string>() == "imported",
            "write_preserves_transport");
        Check(digitalFrame["futureFrameValue"]!.GetValue<string>() == "preserve-me",
            "write_preserves_unknown_frame_field");
        JsonObject digitalParameters = digitalFrame["params"]!.AsObject();
        Check(digitalParameters["unknownAdjustment"]!["value"]!.GetValue<int>() == 7,
            "write_preserves_unknown_parameter_field");
        Check(digitalParameters["isDigitalSource"]!.GetValue<bool>(),
            "write_sets_legacy_digital_marker");

        DevelopRouteReadResult digitalRead = ReadNode(digitalFrame);
        Check(digitalRead.IsSuccess, "write_digital_round_trip");
        Check(digitalRead.Route?.DevelopmentProcess == DevelopmentProcess.DigitalColor,
            "write_digital_process");
        Check(digitalRead.Route?.SourceTransport == FrameSourceTransport.Imported,
            "import_transport_does_not_override_signal");

        DevelopRouteWriteResult filmWrite = DevelopRouteWriter.Apply(
            digitalFrame,
            DevelopRouteSelection.FromProcess(
                DevelopmentProcess.E6,
                FilmEmulation.Velvia50,
                0.35));
        Check(filmWrite.IsSuccess, "write_film_success");
        if (filmWrite.FrameRecord is not { } filmFrame)
        {
            return;
        }
        Check(!filmFrame["params"]!.AsObject().ContainsKey("isDigitalSource"),
            "write_film_omits_false_marker");
        DevelopRouteReadResult filmRead = ReadNode(filmFrame);
        Check(filmRead.IsSuccess, "write_film_round_trip");
        Check(filmRead.Route?.SourceSignalKind == SourceSignalKind.FilmPositiveScan,
            "write_film_explicit_signal");
        Check(filmRead.Route?.UsedLegacySourceSignal == false,
            "write_film_not_legacy_signal");
    }

    private static void VerifyReaderShapeErrors()
    {
        using JsonDocument array = JsonDocument.Parse("[]");
        DevelopRouteReadResult result = DevelopRouteReader.Read(array.RootElement);
        Check(result.Error == DevelopRouteError.FrameRecordNotObject,
            "reader_rejects_non_object");
        Check(result.Route is null, "reader_non_object_no_partial_route");
    }

    private static void VerifyAllFilmEmulationNames(JsonElement root)
    {
        JsonObject frame = JsonNode.Parse(
            root.GetProperty("validCases")[1].GetProperty("frame").GetRawText())!.AsObject();
        foreach (FilmEmulation emulation in Enum.GetValues<FilmEmulation>())
        {
            DevelopRouteWriteResult write = DevelopRouteWriter.Apply(
                frame,
                DevelopRouteSelection.FromProcess(DevelopmentProcess.D76, emulation));
            Check(write.IsSuccess, $"emulation_{emulation}_write");
            if (write.FrameRecord is not { } written)
            {
                continue;
            }
            DevelopRouteReadResult read = ReadNode(written);
            Check(read.Route?.FilmEmulation == emulation, $"emulation_{emulation}_round_trip");
            Check(read.Route?.SourceTransport == FrameSourceTransport.Imported,
                $"emulation_{emulation}_transport_independent");
        }
    }

    private static void VerifyInvalidSelections(JsonElement root)
    {
        JsonObject frame = JsonNode.Parse(
            root.GetProperty("validCases")[0].GetProperty("frame").GetRawText())!.AsObject();
        DevelopRouteWriteResult mismatched = DevelopRouteWriter.Apply(
            frame,
            new DevelopRouteSelection(
                SourceSignalKind.RenderedDigital,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5));
        Check(mismatched.Error == DevelopRouteError.SourceSignalFilmTypeMismatch,
            "invalid_selection_signal_type");
        Check(mismatched.FrameRecord is null, "invalid_selection_no_partial_record");
        Check(frame["sourceSignalKind"] is null, "invalid_selection_input_unchanged");

        DevelopRouteWriteResult nonfinite = DevelopRouteWriter.Apply(
            frame,
            new DevelopRouteSelection(
                SourceSignalKind.FilmPositiveScan,
                FilmType.ColorPositive,
                FilmEmulation.None,
                double.NaN));
        Check(nonfinite.Error == DevelopRouteError.InvalidFilmEmulationIntensity,
            "invalid_selection_nonfinite");

        JsonObject missingTransport = new()
        {
            ["params"] = new JsonObject(),
        };
        DevelopRouteWriteResult missingTransportWrite = DevelopRouteWriter.Apply(
            missingTransport,
            DevelopRouteSelection.FromProcess(DevelopmentProcess.C41));
        Check(missingTransportWrite.Error == DevelopRouteError.MissingSourceTransport,
            "writer_requires_transport");

        JsonObject invalidParameters = new()
        {
            ["sourceKind"] = "scanner",
            ["params"] = new JsonArray(),
        };
        DevelopRouteWriteResult invalidParametersWrite = DevelopRouteWriter.Apply(
            invalidParameters,
            DevelopRouteSelection.FromProcess(DevelopmentProcess.C41));
        Check(invalidParametersWrite.Error == DevelopRouteError.ParametersNotObject,
            "writer_rejects_non_object_parameters");
    }

    private static void VerifyCanonicalJson()
    {
        JsonNode first = JsonNode.Parse(
            """{"z":0,"a":{"b":2,"a":1},"list":[{"z":3,"a":2}]}""")!;
        JsonNode second = JsonNode.Parse(
            """{"list":[{"a":2,"z":3}],"a":{"a":1,"b":2},"z":0}""")!;
        byte[] firstBytes = CatalogJson.SerializeCanonical(first);
        byte[] secondBytes = CatalogJson.SerializeCanonical(second);
        const string expected = "{\"a\":{\"a\":1,\"b\":2},\"list\":[{\"a\":2,\"z\":3}],\"z\":0}";

        Check(firstBytes.SequenceEqual(secondBytes), "canonical_order_independent");
        Check(Encoding.UTF8.GetString(firstBytes) == expected, "canonical_expected_bytes");
    }

    private static void VerifyStorageRootResolution()
    {
        StorageRootResolutionResult missing = StorageRootResolver.ResolveForTests(string.Empty);
        Check(missing.Error == StorageRootResolutionError.MissingBaseRoot,
            "storage_root_rejects_empty");
        Check(missing.Roots is null, "storage_root_empty_no_partial_result");

        StorageRootResolutionResult relative = StorageRootResolver.ResolveForTests("relative");
        Check(relative.Error == StorageRootResolutionError.BaseRootNotFullyQualified,
            "storage_root_rejects_relative");

        string isolatedBase = Path.Combine(
            AppContext.BaseDirectory,
            "storage-root-tests",
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootResolutionResult resolution = StorageRootResolver.ResolveForTests(isolatedBase);
        Check(resolution.IsSuccess, "storage_root_test_resolution_success");
        if (resolution.Roots is not { } roots)
        {
            return;
        }

        string expectedProductRoot = Path.Combine(
            Path.GetFullPath(isolatedBase),
            "Negaflow");
        Check(roots.IsTestIsolated, "storage_root_marks_test_isolation");
        Check(roots.ProductDataRoot == expectedProductRoot, "storage_root_product_path");
        Check(roots.LibraryRoot == Path.Combine(expectedProductRoot, "Library"),
            "storage_root_library_path");
        Check(roots.CatalogPath == Path.Combine(roots.LibraryRoot, "library.sqlite"),
            "storage_root_catalog_path");
        Check(roots.CatalogBackupPath ==
            Path.Combine(roots.LibraryRoot, "library.backup.sqlite"),
            "storage_root_catalog_backup_path");
        Check(roots.CatalogLockPath ==
            Path.Combine(roots.LibraryRoot, "library.sqlite.lock"),
            "storage_root_catalog_lock_path");
        Check(roots.DefectRecipeRoot == Path.Combine(roots.LibraryRoot, "defects"),
            "storage_root_defects_path");
        Check(roots.BackupRoot == Path.Combine(roots.LibraryRoot, "Backups"),
            "storage_root_backups_path");
        Check(roots.PendingRestoreRoot == Path.Combine(roots.LibraryRoot, "PendingRestore"),
            "storage_root_pending_restore_path");
        Check(roots.MigrationRoot == Path.Combine(roots.LibraryRoot, "Migration"),
            "storage_root_migration_path");
        Check(roots.CacheRoot == Path.Combine(expectedProductRoot, "Cache"),
            "storage_root_cache_path");
        Check(roots.JournalRoot == Path.Combine(expectedProductRoot, "Journals"),
            "storage_root_journal_path");
        Check(roots.PluginRoot == Path.Combine(expectedProductRoot, "Plugins"),
            "storage_root_plugin_path");
        Check(roots.LogRoot == Path.Combine(expectedProductRoot, "Logs"),
            "storage_root_log_path");
        Check(roots.SettingsRoot == Path.Combine(expectedProductRoot, "Settings"),
            "storage_root_settings_path");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.CatalogPath), "storage_path_catalog_contained");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.ProductDataRoot), "storage_path_root_contains_itself");
        Check(!StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            $"{roots.ProductDataRoot}-outside"), "storage_path_rejects_prefix_sibling");

        Check(StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", "library.sqlite"),
            out string resolvedCatalog), "storage_path_resolves_relative");
        Check(resolvedCatalog == roots.CatalogPath, "storage_path_relative_value");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("..", "outside"),
            out _), "storage_path_rejects_parent_escape");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            roots.CatalogPath,
            out _), "storage_path_rejects_rooted_input");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", ".", "library.sqlite"),
            out _), "storage_path_rejects_dot_component");
    }

    private static void VerifyCatalogProcessLock()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "storage-lock-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        CatalogProcessLock? firstLock = null;
        CatalogProcessLock? reacquiredLock = null;

        try
        {
            Check(!Directory.Exists(roots.ProductDataRoot), "catalog_lock_root_initially_absent");
            CatalogProcessLockAcquireResult first = CatalogProcessLock.TryAcquire(roots);
            firstLock = first.Lock;
            Check(first.IsSuccess, "catalog_lock_first_acquire");
            Check(firstLock?.IsHeld == true, "catalog_lock_first_held");
            Check(Directory.Exists(roots.LibraryRoot), "catalog_lock_creates_library_root");
            Check(File.Exists(roots.CatalogLockPath), "catalog_lock_file_exists");
            Check(!File.Exists(roots.CatalogPath), "catalog_lock_does_not_create_catalog");
            Check(!Directory.Exists(roots.CacheRoot), "catalog_lock_does_not_create_cache");

            CatalogProcessLockAcquireResult second = CatalogProcessLock.TryAcquire(roots);
            Check(!second.IsSuccess, "catalog_lock_second_rejected");
            Check(second.Error == CatalogProcessLockError.Busy, "catalog_lock_second_busy");
            Check(second.Lock is null, "catalog_lock_busy_no_partial_handle");

            firstLock?.Dispose();
            Check(firstLock?.IsHeld == false, "catalog_lock_dispose_releases_handle");
            Check(File.Exists(roots.CatalogLockPath), "catalog_lock_stale_file_is_not_owner");

            CatalogProcessLockAcquireResult reacquired = CatalogProcessLock.TryAcquire(roots);
            reacquiredLock = reacquired.Lock;
            Check(reacquired.IsSuccess, "catalog_lock_reacquire_after_dispose");
            Check(reacquiredLock?.IsHeld == true, "catalog_lock_reacquired_held");
            reacquiredLock?.Dispose();
            reacquiredLock?.Dispose();
            Check(reacquiredLock?.IsHeld == false, "catalog_lock_dispose_idempotent");
        }
        finally
        {
            reacquiredLock?.Dispose();
            firstLock?.Dispose();
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifySqliteCatalogStore()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "catalog-store-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            VerifyStoreLifecycle(roots);
            VerifyStoreRefusals(roots);
            VerifyVerifiedCommit(roots);
            VerifyCatalogSession(roots);
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

    private static void VerifyStoreLifecycle(StorageRootSet roots)
    {
        string catalogPath = roots.CatalogPath;

        // 없는 파일을 빈 라이브러리로 읽지 않습니다.
        CatalogReadResult absent = SqliteCatalogStore.Read(catalogPath);
        Check(!absent.IsSuccess, "store_absent_not_success");
        Check(absent.Error == CatalogStoreError.NotFound, "store_absent_not_found");
        Check(absent.Snapshot is null, "store_absent_no_partial_snapshot");

        CatalogSnapshot first = Snapshot(
            "roll-a",
            Row("frame-1", "one"),
            Row("frame-2", "two"),
            Row("frame-3", "three"));
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_first_write");
        Check(File.Exists(catalogPath), "store_first_write_creates_file");

        CatalogReadResult reopened = SqliteCatalogStore.Read(catalogPath);
        Check(reopened.IsSuccess, "store_reopen_success");
        Check(FrameOrder(reopened) == "frame-1,frame-2,frame-3", "store_reopen_preserves_order");
        Check(FrameLabels(reopened) == "one,two,three", "store_reopen_preserves_payload");
        Check(reopened.Snapshot?.ActiveRollId == "roll-a", "store_reopen_preserves_active_roll");
        Check(reopened.Snapshot?.Rows(CatalogEntityTable.Rolls).Count == 0,
            "store_reopen_untouched_table_empty");

        // 자리 바꾸기입니다. position 이 UNIQUE 이므로 재배치 중 제약을 어기면 여기서 걸립니다.
        CatalogSnapshot reordered = Snapshot(
            "roll-a",
            Row("frame-3", "three"),
            Row("frame-1", "one-edited"),
            Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(reordered, catalogPath).IsSuccess, "store_reorder_write");
        CatalogReadResult afterReorder = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterReorder) == "frame-3,frame-1,frame-2", "store_reorder_order");
        Check(FrameLabels(afterReorder) == "three,one-edited,two", "store_reorder_payload");

        // 되돌리기도 같은 경로를 반대 방향으로 지납니다.
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_reorder_back_write");
        Check(FrameOrder(SqliteCatalogStore.Read(catalogPath)) == "frame-1,frame-2,frame-3",
            "store_reorder_back_order");

        CatalogSnapshot removed = Snapshot("roll-a", Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(removed, catalogPath).IsSuccess, "store_remove_write");
        CatalogReadResult afterRemove = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterRemove) == "frame-2", "store_remove_drops_rows");

        CatalogSnapshot cleared = Snapshot(activeRollId: null);
        Check(SqliteCatalogStore.Write(cleared, catalogPath).IsSuccess, "store_clear_write");
        CatalogReadResult afterClear = SqliteCatalogStore.Read(catalogPath);
        Check(afterClear.IsSuccess, "store_clear_reopen_success");
        Check(afterClear.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
            "store_clear_empties_table");
        Check(afterClear.Snapshot?.ActiveRollId is null, "store_clear_active_roll_null");

        Check(CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_valid_recovery_source");

        // Pooling 을 켜 두면 여기서 파일이 잠겨 backup 교체가 막힙니다.
        File.Delete(catalogPath);
        Check(!File.Exists(catalogPath), "store_no_lingering_file_handle");
    }

    private static void VerifyStoreRefusals(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "refusals.sqlite");

        CatalogSnapshot duplicated = Snapshot(
            null,
            Row("frame-1", "one"),
            Row("frame-1", "again"));
        CatalogWriteResult duplicateWrite = SqliteCatalogStore.Write(duplicated, catalogPath);
        Check(duplicateWrite.Error == CatalogStoreError.InvalidSnapshot,
            "store_rejects_duplicate_ids");
        Check(!File.Exists(catalogPath), "store_rejects_duplicate_ids_without_creating_file");

        CatalogSnapshot emptyId = Snapshot(null, Row(string.Empty, "one"));
        Check(SqliteCatalogStore.Write(emptyId, catalogPath).Error ==
            CatalogStoreError.InvalidSnapshot, "store_rejects_empty_id");

        Check(SqliteCatalogStore.Write(Snapshot(null, Row("frame-1", "one")), catalogPath)
            .IsSuccess, "store_refusal_fixture_write");

        // 물리 schema 가 미래 버전이면 읽지 않습니다.
        SetStorageVersion(catalogPath, 99);
        CatalogReadResult futureStorage = SqliteCatalogStore.Read(catalogPath);
        Check(futureStorage.Error == CatalogStoreError.UnsupportedStorageVersion,
            "store_rejects_future_storage_version");
        Check(futureStorage.ObservedVersion == 99, "store_reports_observed_storage_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_future_storage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), catalogPath).Error ==
            CatalogStoreError.UnsupportedStorageVersion,
            "store_refuses_write_over_future_storage_version");
        SetStorageVersion(catalogPath, 1);

        // macOS 파일은 논리 version 6 입니다. 조용히 읽지 않고 그 값을 보고합니다.
        SetCatalogVersion(catalogPath, 6);
        CatalogReadResult foreign = SqliteCatalogStore.Read(catalogPath);
        Check(foreign.Error == CatalogStoreError.UnsupportedCatalogVersion,
            "store_rejects_foreign_catalog_version");
        Check(foreign.ObservedVersion == 6, "store_reports_observed_catalog_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_foreign_catalog_is_not_recovery_source");
        SetCatalogVersion(catalogPath, CatalogSnapshot.CurrentCatalogVersion);
        Check(SqliteCatalogStore.Read(catalogPath).IsSuccess, "store_restored_fixture_reads");

        string garbagePath = Path.Combine(roots.LibraryRoot, "garbage.sqlite");
        File.WriteAllBytes(garbagePath, "this is not a database"u8.ToArray());
        CatalogReadResult garbage = SqliteCatalogStore.Read(garbagePath);
        Check(garbage.Error == CatalogStoreError.CorruptDatabase, "store_rejects_garbage_file");
        Check(garbage.Snapshot is null, "store_garbage_no_partial_snapshot");
        Check(!CatalogRecovery.IsValidCatalogSource(garbagePath),
            "store_garbage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), garbagePath).Error !=
            CatalogStoreError.None, "store_refuses_write_over_garbage_file");

        Check(SqliteCatalogStore.Read("library.sqlite").Error == CatalogStoreError.InvalidPath,
            "store_rejects_relative_path");
        Check(SqliteCatalogStore.Write(Snapshot(null), "library.sqlite").Error ==
            CatalogStoreError.InvalidPath, "store_write_rejects_relative_path");
    }

    private static void VerifyVerifiedCommit(StorageRootSet parentRoots)
    {
        string commitBase = Path.Combine(parentRoots.LocalApplicationDataRoot, "verified-commit");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(commitBase).Roots!;
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        using CatalogSession? session = opened.Session;
        Check(opened.IsSuccess, "commit_session_open");
        if (session is null)
        {
            return;
        }

        Check(session.ReadOrCreate().IsSuccess, "commit_initial_create");
        Check(!File.Exists(roots.CatalogBackupPath), "commit_initial_create_has_no_backup");

        CatalogSnapshot baseline = Snapshot("roll-a", Row("frame-1", "baseline"));
        CatalogSnapshot changed = Snapshot("roll-b", Row("frame-2", "changed"));
        CatalogSnapshot next = Snapshot("roll-c", Row("frame-3", "next"));
        Check(session.Write(baseline).IsSuccess, "commit_baseline_write");
        byte[] baselinePrimary = File.ReadAllBytes(roots.CatalogPath);
        Check(session.Write(changed).IsSuccess, "commit_changed_write");
        Check(File.Exists(roots.CatalogBackupPath), "commit_previous_primary_backup_exists");
        if (!File.Exists(roots.CatalogBackupPath))
        {
            return;
        }
        Check(File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(baselinePrimary),
            "commit_previous_primary_backup_exact_bytes");
        Check(FrameLabels(SqliteCatalogStore.Read(roots.CatalogBackupPath)) == "baseline",
            "commit_previous_primary_backup_payload");

        byte[] backupBeforeNoOp = File.ReadAllBytes(roots.CatalogBackupPath);
        Check(session.Write(changed).IsSuccess, "commit_noop_success");
        Check(File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(backupBeforeNoOp),
            "commit_noop_preserves_older_backup");

        byte[] changedPrimary = File.ReadAllBytes(roots.CatalogPath);
        CatalogWriteResult mismatch = CatalogCommitVerifier.CommitForTesting(
            next,
            roots,
            readback: _ => CatalogReadResult.Success(
                Snapshot("roll-wrong", Row("frame-wrong", "wrong"))));
        Check(mismatch.Error == CatalogStoreError.ReadbackFailed,
            "commit_readback_mismatch_error");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(changedPrimary),
            "commit_readback_mismatch_restores_exact_primary");
        Check(FrameLabels(session.Read()) == "changed",
            "commit_readback_mismatch_restores_payload");

        CatalogWriteResult writerFailure = CatalogCommitVerifier.CommitForTesting(
            next,
            roots,
            writer: (_, path) =>
            {
                CatalogWriteResult substituted = SqliteCatalogStore.Write(
                    Snapshot("roll-external", Row("frame-external", "external")),
                    roots.CatalogBackupPath);
                if (!substituted.IsSuccess)
                {
                    return substituted;
                }
                File.WriteAllBytes(path, "partial write"u8.ToArray());
                throw new IOException("injected writer failure");
            });
        Check(writerFailure.Error == CatalogStoreError.IoFailure,
            "commit_writer_failure_error");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(changedPrimary),
            "commit_writer_failure_restores_exact_primary");
        Check(FrameLabels(session.Read()) == "changed",
            "commit_writer_failure_restores_payload");

        CatalogWriteResult rollbackFailure = session.WriteForTesting(
            next,
            readback: _ => CatalogReadResult.Failure(CatalogStoreError.CorruptDatabase),
            restore: (_, _) => false);
        Check(rollbackFailure.Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_is_distinct");
        Check(FrameLabels(session.Read()) == "next",
            "commit_rollback_failure_does_not_claim_old_primary");
        byte[] unverifiedPrimary = File.ReadAllBytes(roots.CatalogPath);
        byte[] knownGoodBackup = File.ReadAllBytes(roots.CatalogBackupPath);
        Check(session.Write(baseline).Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_blocks_followup_write");
        Check(session.ReadOrCreate().Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_blocks_normal_open");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(unverifiedPrimary) &&
              File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(knownGoodBackup),
            "commit_blocked_followup_preserves_primary_and_backup");

        string absenceBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "verified-commit-absence");
        StorageRootSet absenceRoots = StorageRootResolver.ResolveForTests(absenceBase).Roots!;
        string journalPath = $"{absenceRoots.CatalogPath}-journal";
        CatalogWriteResult absenceMismatch = CatalogCommitVerifier.CommitForTesting(
            baseline,
            absenceRoots,
            writer: (_, path) =>
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllBytes(path, "partial database"u8.ToArray());
                File.WriteAllBytes(journalPath, "hot journal"u8.ToArray());
                return CatalogWriteResult.Failure(CatalogStoreError.IoFailure);
            });
        Check(absenceMismatch.Error == CatalogStoreError.IoFailure,
            "commit_absence_writer_error");
        Check(!File.Exists(absenceRoots.CatalogPath),
            "commit_absence_writer_restores_absence");
        Check(!File.Exists(journalPath),
            "commit_absence_writer_removes_journal");
        Check(!File.Exists(absenceRoots.CatalogBackupPath),
            "commit_absence_readback_does_not_create_backup");

        string guardedBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "verified-commit-guarded");
        StorageRootSet guardedRoots = StorageRootResolver.ResolveForTests(guardedBase).Roots!;
        CatalogSessionOpenResult guardedOpen = CatalogSession.Open(guardedRoots);
        using CatalogSession? guarded = guardedOpen.Session;
        Check(guardedOpen.IsSuccess, "commit_guarded_session_open");
        if (guarded is null)
        {
            return;
        }
        Check(guarded.ReadOrCreate().IsSuccess, "commit_guarded_create");
        Check(guarded.Write(baseline).IsSuccess, "commit_guarded_baseline");
        Check(guarded.Write(changed).IsSuccess, "commit_guarded_changed");
        byte[] guardedBackup = File.ReadAllBytes(guardedRoots.CatalogBackupPath);

        File.Delete(guardedRoots.CatalogPath);
        Check(guarded.ReadOrCreate().Error == CatalogStoreError.MissingAuthoritativeData,
            "commit_missing_primary_with_backup_blocks_empty_create");
        Check(!File.Exists(guardedRoots.CatalogPath),
            "commit_missing_primary_with_backup_preserves_absence");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_missing_primary_preserves_backup");

        File.Copy(guardedRoots.CatalogBackupPath, guardedRoots.CatalogPath);
        byte[] corruptPrimary = "not a database"u8.ToArray();
        File.WriteAllBytes(guardedRoots.CatalogPath, corruptPrimary);
        CatalogWriteResult corruptWrite = guarded.Write(next);
        Check(corruptWrite.Error == CatalogStoreError.CorruptDatabase,
            "commit_corrupt_primary_refuses_write");
        Check(File.ReadAllBytes(guardedRoots.CatalogPath).SequenceEqual(corruptPrimary),
            "commit_corrupt_primary_preserved");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_corrupt_primary_does_not_overwrite_backup");

        File.Copy(guardedRoots.CatalogBackupPath, guardedRoots.CatalogPath, overwrite: true);
        SetStorageVersion(guardedRoots.CatalogPath, 99);
        byte[] futurePrimary = File.ReadAllBytes(guardedRoots.CatalogPath);
        CatalogWriteResult futureWrite = guarded.Write(next);
        Check(futureWrite.Error == CatalogStoreError.UnsupportedStorageVersion,
            "commit_future_primary_refuses_write");
        Check(File.ReadAllBytes(guardedRoots.CatalogPath).SequenceEqual(futurePrimary),
            "commit_future_primary_preserved");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_future_primary_does_not_overwrite_backup");
    }

    private static JsonObject FrameRecord()
    {
        return new JsonObject
        {
            ["id"] = "frame-1",
            ["rawScanPath"] = @"C:\scans\roll-01\IMG_0001.tif",
            ["customDisplayName"] = "Roll 01 / 1",
            ["sourceKind"] = "scanner",
            ["filmType"] = "colorNegative",
            ["futureFrameValue"] = "preserve-me",
            ["params"] = new JsonObject
            {
                ["filmType"] = "colorNegative",
                ["baseEstimationMode"] = "preset",
                ["manualBaseRGB"] = new JsonArray(0.21, 0.22, 0.23),
                ["filmStockDminID"] = "kodak-portra-400",
                ["lightSourceProfileID"] = "v850-led",
                ["scannerProfileID"] = "noritsu__color-nega__kodak-portra-400",
                ["exposure"] = 0.5,
                ["curveShadows"] = -0.25,
                ["pointCurves"] = new JsonObject
                {
                    ["rgb"] = new JsonArray
                    {
                        new JsonObject { ["x"] = 1.0, ["y"] = 1.0 },
                        new JsonObject { ["x"] = 0.0, ["y"] = 0.0 },
                        new JsonObject { ["x"] = 0.45, ["y"] = 0.52 },
                    },
                    ["red"] = new JsonArray
                    {
                        new JsonObject { ["x"] = 0.0, ["y"] = 0.03 },
                        new JsonObject { ["x"] = 1.0, ["y"] = 0.97 },
                    },
                    ["green"] = new JsonArray(),
                    ["blue"] = new JsonArray(),
                },
                ["colorMixer"] = new JsonObject
                {
                    ["hue"] = new JsonArray(0.1, -0.2),
                    ["saturation"] = new JsonArray(0.3),
                    ["luminance"] = new JsonArray(-0.4),
                },
                ["unknownAdjustment"] = new JsonObject { ["value"] = 7 },
            },
        };
    }

    private static LibraryFrameReadResult ReadFrame(JsonObject frameRecord)
    {
        using JsonDocument document = JsonDocument.Parse(
            CatalogJson.SerializeCanonical(frameRecord));
        return LibraryFrameReader.Read(document.RootElement);
    }

    private static void VerifyLibraryFrameProjection()
    {
        LibraryFrameReadResult read = ReadFrame(FrameRecord());
        Check(read.IsSuccess, "library_frame_read_success");
        if (read.Frame is not { } frame)
        {
            return;
        }

        Check(frame.Id == "frame-1", "library_frame_id");
        Check(frame.SourcePath == @"C:\scans\roll-01\IMG_0001.tif", "library_frame_source_path");
        Check(frame.EffectiveDisplayName == "Roll 01 / 1", "library_frame_display_name");
        Check(frame.Route.FilmType == FilmType.ColorNegative, "library_frame_route_film_type");
        Check(frame.CanDevelop, "library_frame_preset_with_stock_can_develop");
        Check(frame.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23), "library_frame_manual_base");
        Check(frame.Base.Mode == BaseEstimationMode.Preset, "library_frame_base_mode");
        Check(frame.Base.FilmStockDminId == "kodak-portra-400", "library_frame_film_stock_id");
        Check(frame.Base.LightSourceProfileId == "v850-led", "library_frame_light_source_id");
        Check(frame.Base.ScannerProfileId == "noritsu__color-nega__kodak-portra-400", "library_frame_scanner_profile_id");
        Check(frame.Tone.Exposure == 0.5, "library_frame_exposure");
        Check(frame.Tone.CurveShadows == -0.25, "library_frame_curve_shadows");
        Check(frame.PointCurves.Rgb.Count == 3, "library_frame_point_curve_rgb_count");
        Check(frame.PointCurves.Rgb[0] == new PointCurvePoint(0.0, 0.0),
            "library_frame_point_curve_sorts_rgb");
        Check(frame.PointCurves.Rgb[1] == new PointCurvePoint(0.45, 0.52),
            "library_frame_point_curve_rgb_middle");
        Check(frame.PointCurves.Red.Count == 2 && frame.PointCurves.Green.Count == 0 &&
                frame.PointCurves.Blue.Count == 0,
            "library_frame_point_curve_channel_shapes");
        Check(frame.ColorMixer.Hue[0] == 0.1 && frame.ColorMixer.Hue[1] == -0.2 &&
                frame.ColorMixer.Hue[2] == 0.0 && frame.ColorMixer.Saturation[0] == 0.3 &&
                frame.ColorMixer.Luminance[0] == -0.4,
            "library_frame_color_mixer_normalizes_mac_shape");
        Check(frame.ColorGrading == ColorGradingRecipe.Identity,
            "library_frame_missing_color_grading_defaults_to_identity");
        ColorGradingRecipe colorGrading = new(
            new ColorGradeRegionRecipe(45.0, 0.2, -0.1),
            new ColorGradeRegionRecipe(180.0, 0.4, 0.1),
            new ColorGradeRegionRecipe(300.0, 0.6, 0.2),
            0.35,
            -0.25);
        LibraryFrameWriteResult writtenColorGrading = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorGrading: colorGrading));
        Check(
            writtenColorGrading.IsSuccess &&
                ReadFrame(writtenColorGrading.FrameRecord!).Frame?.ColorGrading == colorGrading,
            "library_frame_color_grading_write_round_trip");
        // 없는 톤 키는 macOS 와 같이 0 입니다.
        Check(frame.Tone.Contrast == 0.0, "library_frame_missing_tone_is_zero");

        // Preset resolver가 아직 없으면 manual base가 있어도 Auto로 바꾸어 추정하지 않습니다.
        JsonObject withoutBase = FrameRecord();
        withoutBase["params"]!.AsObject().Remove("manualBaseRGB");
        LibraryFrameReadResult noBase = ReadFrame(withoutBase);
        Check(noBase.IsSuccess, "library_frame_missing_base_still_reads");
        Check(noBase.Frame?.ManualBase is null, "library_frame_missing_base_is_absent");
        Check(noBase.Frame?.CanDevelop == true, "library_frame_preset_does_not_require_manual_base");

        JsonObject defaultBase = FrameRecord();
        JsonObject defaultBaseParams = defaultBase["params"]!.AsObject();
        defaultBaseParams.Remove("baseEstimationMode");
        defaultBaseParams.Remove("filmStockDminID");
        defaultBaseParams.Remove("lightSourceProfileID");
        defaultBaseParams.Remove("scannerProfileID");
        Check(ReadFrame(defaultBase).Frame?.Base == BaseRecipe.Auto,
            "library_frame_missing_base_recipe_defaults_to_auto");
        Check(ReadFrame(defaultBase).Frame?.CanDevelop == true,
            "library_frame_default_auto_can_develop");

        JsonObject withoutPointCurves = FrameRecord();
        withoutPointCurves["params"]!.AsObject().Remove("pointCurves");
        PointCurveRecipe? defaultPointCurves = ReadFrame(withoutPointCurves).Frame?.PointCurves;
        Check(defaultPointCurves is not null &&
                defaultPointCurves.Rgb.Count == 0 && defaultPointCurves.Red.Count == 0 &&
                defaultPointCurves.Green.Count == 0 && defaultPointCurves.Blue.Count == 0,
            "library_frame_missing_point_curves_defaults_to_identity");

        JsonObject withoutName = FrameRecord();
        withoutName.Remove("customDisplayName");
        Check(
            ReadFrame(withoutName).Frame?.EffectiveDisplayName == "IMG_0001.tif",
            "library_frame_falls_back_to_file_name");

        VerifyLibraryFrameRefusals();
        VerifyLibraryFrameWriting();
    }

    private static void VerifyLibraryFrameRefusals()
    {
        JsonObject missingId = FrameRecord();
        missingId.Remove("id");
        Check(
            ReadFrame(missingId).Error == LibraryFrameError.MissingId,
            "library_frame_rejects_missing_id");

        JsonObject blankId = FrameRecord();
        blankId["id"] = "   ";
        Check(
            ReadFrame(blankId).Error == LibraryFrameError.InvalidId,
            "library_frame_rejects_blank_id");

        JsonObject missingPath = FrameRecord();
        missingPath.Remove("rawScanPath");
        Check(
            ReadFrame(missingPath).Error == LibraryFrameError.MissingSourcePath,
            "library_frame_rejects_missing_source_path");

        // 상대 경로는 무엇을 기준으로 푸는지가 catalog 에 없습니다.
        JsonObject relativePath = FrameRecord();
        relativePath["rawScanPath"] = @"scans\IMG_0001.tif";
        Check(
            ReadFrame(relativePath).Error == LibraryFrameError.InvalidSourcePath,
            "library_frame_rejects_relative_source_path");

        JsonObject shortBase = FrameRecord();
        shortBase["params"]!["manualBaseRGB"] = new JsonArray(0.2, 0.2);
        Check(
            ReadFrame(shortBase).Error == LibraryFrameError.InvalidManualBase,
            "library_frame_rejects_two_channel_base");

        JsonObject textBase = FrameRecord();
        textBase["params"]!["manualBaseRGB"] = new JsonArray(0.2, "0.2", 0.2);
        Check(
            ReadFrame(textBase).Error == LibraryFrameError.InvalidManualBase,
            "library_frame_rejects_non_numeric_base");

        JsonObject invalidBaseMode = FrameRecord();
        invalidBaseMode["params"]!["baseEstimationMode"] = "guessed";
        Check(
            ReadFrame(invalidBaseMode).Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_rejects_unknown_base_mode");

        JsonObject invalidBaseIdentifier = FrameRecord();
        invalidBaseIdentifier["params"]!["filmStockDminID"] = " ";
        Check(
            ReadFrame(invalidBaseIdentifier).Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_rejects_blank_base_identifier");

        JsonObject invalidPointCurveShape = FrameRecord();
        invalidPointCurveShape["params"]!["pointCurves"]!["rgb"] = new JsonObject();
        Check(
            ReadFrame(invalidPointCurveShape).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_non_array");

        JsonObject invalidPointCurveCoordinate = FrameRecord();
        invalidPointCurveCoordinate["params"]!["pointCurves"]!["red"] = new JsonArray
        {
            new JsonObject { ["x"] = 0.25, ["y"] = "0.25" },
        };
        Check(
            ReadFrame(invalidPointCurveCoordinate).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_non_numeric_coordinate");

        JsonObject duplicatePointCurveCoordinate = FrameRecord();
        duplicatePointCurveCoordinate["params"]!["pointCurves"]!["blue"] = new JsonArray
        {
            new JsonObject { ["x"] = 0.5, ["y"] = 0.4 },
            new JsonObject { ["x"] = 0.5, ["y"] = 0.6 },
        };
        Check(
            ReadFrame(duplicatePointCurveCoordinate).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_duplicate_x");

        // 있는데 수가 아니면 조용히 0 으로 만들지 않습니다.
        JsonObject textTone = FrameRecord();
        textTone["params"]!["exposure"] = "0.5";
        Check(
            ReadFrame(textTone).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_rejects_non_numeric_tone");

        JsonObject missingParameters = FrameRecord();
        missingParameters.Remove("params");
        Check(
            ReadFrame(missingParameters).Error == LibraryFrameError.MissingParameters,
            "library_frame_rejects_missing_parameters");

        // route 거부는 그대로 전달되고 어느 쪽이 문제인지 구별됩니다.
        JsonObject brokenRoute = FrameRecord();
        brokenRoute["params"]!["filmType"] = "colorPositive";
        LibraryFrameReadResult routeFailure = ReadFrame(brokenRoute);
        Check(
            routeFailure.Error == LibraryFrameError.InvalidDevelopRoute,
            "library_frame_reports_route_failure");
        Check(
            routeFailure.RouteError == DevelopRouteError.MismatchedFilmType,
            "library_frame_preserves_route_error");
        Check(routeFailure.Frame is null, "library_frame_no_partial_snapshot");
    }

    private static void VerifyLibraryFrameWriting()
    {
        JsonObject original = FrameRecord();
        LibraryFrameEdit edit = new(
            new ToneAdjustment(
                1.25,
                -0.5,
                0.1,
                0.2,
                0.3,
                0.4,
                0.5,
                -0.6,
                0.7,
                -0.8,
                0.9),
            new ManualBaseRgb(0.31, 0.32, 0.33));

        LibraryFrameWriteResult write = LibraryFrameWriter.Apply(original, edit);
        Check(write.IsSuccess, "library_frame_write_success");
        if (write.FrameRecord is not { } updated)
        {
            return;
        }

        Check(
            original["params"]!["exposure"]!.GetValue<double>() == 0.5,
            "library_frame_write_leaves_input_alone");
        Check(
            updated["futureFrameValue"]!.GetValue<string>() == "preserve-me",
            "library_frame_write_preserves_unknown_frame_field");
        Check(
            updated["params"]!["unknownAdjustment"]!["value"]!.GetValue<int>() == 7,
            "library_frame_write_preserves_unknown_parameter_field");

        LibraryFrameReadResult reread = ReadFrame(updated);
        Check(reread.IsSuccess, "library_frame_write_round_trip");
        Check(reread.Frame?.Tone == edit.Tone, "library_frame_write_tone_round_trip");
        Check(
            updated["params"]!["density"]!.GetValue<double>() == 0.5 &&
                updated["params"]!["highlight"]!.GetValue<double>() == -0.6 &&
                updated["params"]!["shadow"]!.GetValue<double>() == 0.7 &&
                updated["params"]!["whites"]!.GetValue<double>() == -0.8 &&
                updated["params"]!["blacks"]!.GetValue<double>() == 0.9,
            "library_frame_write_basic_tone_names");
        Check(reread.Frame?.ManualBase == edit.ManualBase, "library_frame_write_base_round_trip");
        Check(reread.Frame?.Base == new BaseRecipe(
                BaseEstimationMode.Preset,
                "kodak-portra-400",
                "v850-led",
                "noritsu__color-nega__kodak-portra-400"),
            "library_frame_write_preserves_base_recipe_when_not_edited");
        Check(reread.Frame?.PointCurves.Rgb.Count == 3,
            "library_frame_write_preserves_point_curves_when_not_edited");
        Check(reread.Frame?.ColorMixer.Hue[0] == 0.1 && reread.Frame.ColorMixer.Hue[2] == 0.0,
            "library_frame_write_preserves_color_mixer_when_not_edited");

        BaseRecipe manualRecipe = new(
            BaseEstimationMode.Manual,
            "kodak-portra-400",
            null,
            null);
        LibraryFrameWriteResult baseWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, manualRecipe));
        Check(baseWrite.IsSuccess, "library_frame_base_recipe_write_success");
        Check(ReadFrame(baseWrite.FrameRecord!).Frame?.Base == manualRecipe,
            "library_frame_base_recipe_write_round_trip");

        PointCurveRecipe pointCurveEdit = new(
            [
                new PointCurvePoint(1.0, 0.95),
                new PointCurvePoint(0.0, 0.05),
                new PointCurvePoint(0.5, 0.60),
            ],
            [],
            [new PointCurvePoint(0.25, 0.20)],
            []);
        LibraryFrameWriteResult pointCurveWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, PointCurves: pointCurveEdit));
        Check(pointCurveWrite.IsSuccess, "library_frame_point_curve_write_success");
        Check(
            pointCurveWrite.FrameRecord?["params"]!["pointCurves"]!["rgb"]![0]!["x"]!
                .GetValue<double>() == 0.0,
            "library_frame_point_curve_write_canonicalizes_order");
        LibraryFrameReadResult pointCurveReread = ReadFrame(pointCurveWrite.FrameRecord!);
        Check(pointCurveReread.IsSuccess &&
                pointCurveReread.Frame?.PointCurves.Rgb[1] == new PointCurvePoint(0.5, 0.60) &&
                pointCurveReread.Frame?.PointCurves.Green[0] == new PointCurvePoint(0.25, 0.20),
            "library_frame_point_curve_write_round_trip");

        ColorMixerRecipe colorMixerEdit = new(
            [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
            [-0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7, -0.8],
            new double[ColorMixerRecipe.BandCount]);
        LibraryFrameWriteResult colorMixerWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, ColorMixer: colorMixerEdit));
        Check(colorMixerWrite.IsSuccess &&
                colorMixerWrite.FrameRecord?["params"]!["colorMixer"]!["hue"]!.AsArray().Count ==
                    ColorMixerRecipe.BandCount,
            "library_frame_color_mixer_write_canonicalizes_eight_bands");
        LibraryFrameReadResult colorMixerReread = ReadFrame(colorMixerWrite.FrameRecord!);
        Check(colorMixerReread.IsSuccess &&
                colorMixerReread.Frame?.ColorMixer.Hue[7] == 0.8 &&
                colorMixerReread.Frame.ColorMixer.Saturation[7] == -0.8,
            "library_frame_color_mixer_write_round_trip");

        // base 를 지우는 것은 auto 추정으로 되돌린다는 뜻이므로 키를 없앱니다.
        LibraryFrameWriteResult cleared = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(ToneAdjustment.Neutral, null));
        Check(cleared.IsSuccess, "library_frame_clear_base_write");
        Check(
            cleared.FrameRecord?["params"]!.AsObject().ContainsKey("manualBaseRGB") == false,
            "library_frame_clear_base_removes_key");

        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    new ToneAdjustment(double.NaN, 0, 0, 0, 0, 0),
                    null)).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_write_rejects_nan_tone");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral with { Density = double.PositiveInfinity },
                    null)).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_write_rejects_non_finite_basic_tone");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    new ManualBaseRgb(0.2, double.PositiveInfinity, 0.2)))
                .Error == LibraryFrameError.InvalidManualBase,
            "library_frame_write_rejects_infinite_base");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    new BaseRecipe((BaseEstimationMode)99, null, null, null)))
                .Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_write_rejects_unknown_base_mode");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PointCurves: new PointCurveRecipe(
                        [new PointCurvePoint(0.5, 0.5), new PointCurvePoint(0.5, 0.6)],
                        [], [], [])))
                .Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_write_rejects_point_curve_duplicate_x");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PointCurves: new PointCurveRecipe(
                        [new PointCurvePoint(double.NaN, 0.5)],
                        [], [], [])))
                .Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_write_rejects_point_curve_nonfinite_coordinate");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    ColorMixer: new ColorMixerRecipe(
                        [0.0, 0.0],
                        new double[ColorMixerRecipe.BandCount],
                        new double[ColorMixerRecipe.BandCount])))
                .Error == LibraryFrameError.InvalidColorMixer,
            "library_frame_write_rejects_short_color_mixer");
    }

    private static int RunLockContender(string isolatedBase)
    {
        StorageRootResolutionResult resolution =
            StorageRootResolver.ResolveForTests(isolatedBase);
        if (resolution.Roots is not { } contenderRoots)
        {
            Console.WriteLine("resolve-failed");
            return 2;
        }

        CatalogSessionOpenResult opened = CatalogSession.Open(contenderRoots);
        if (opened.Session is { } session)
        {
            session.Dispose();
            Console.WriteLine("acquired");
            return 0;
        }
        Console.WriteLine(opened.Error.ToString());
        return 1;
    }

    /// <summary>
    /// 같은 실행 파일을 별도 프로세스로 띄워 lock 을 잡아 보게 합니다. 결과 문자열을 돌려줍니다.
    /// </summary>
    private static string RunContenderProcess(string isolatedBase)
    {
        string executablePath = Environment.ProcessPath ?? string.Empty;
        ProcessStartInfo startInfo = new()
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        // apphost 로 빌드되면 exe 를 바로 띄우고, dotnet 호스트로 실행 중이면 dll 을 넘깁니다.
        string assemblyPath = Path.Combine(
            AppContext.BaseDirectory,
            "Negaflow.Catalog.UnitTests.dll");
        if (Path.GetFileNameWithoutExtension(executablePath) == "dotnet")
        {
            startInfo.FileName = executablePath;
            startInfo.ArgumentList.Add(assemblyPath);
        }
        else
        {
            startInfo.FileName = executablePath;
        }
        startInfo.ArgumentList.Add(LockContenderArgument);
        startInfo.ArgumentList.Add(isolatedBase);

        using Process? contender = Process.Start(startInfo);
        if (contender is null)
        {
            return "start-failed";
        }
        string output = contender.StandardOutput.ReadToEnd().Trim();
        contender.WaitForExit(30_000);
        return output;
    }

    private static void VerifyCatalogSession(StorageRootSet roots)
    {
        string sessionBase = Path.Combine(
            Path.GetDirectoryName(roots.LocalApplicationDataRoot)!,
            $"session-{Guid.NewGuid():N}");
        StorageRootSet sessionRoots = StorageRootResolver.ResolveForTests(sessionBase).Roots!;
        CatalogSession? session = null;

        try
        {
            CatalogSessionOpenResult opened = CatalogSession.Open(sessionRoots);
            session = opened.Session;
            Check(opened.IsSuccess, "session_open");
            Check(session?.IsOpen == true, "session_open_is_open");
            Check(File.Exists(sessionRoots.CatalogLockPath), "session_holds_lock");
            Check(!File.Exists(sessionRoots.CatalogPath), "session_open_does_not_create_catalog");

            // 두 번째 작성자는 lock 에서 막힙니다. 세션 없이는 store 에 닿을 방법이 없습니다.
            CatalogSessionOpenResult second = CatalogSession.Open(sessionRoots);
            Check(!second.IsSuccess, "session_second_rejected");
            Check(second.Error == CatalogSessionError.Busy, "session_second_busy");
            Check(second.Session is null, "session_busy_no_partial_session");

            // 프로세스 경계에서도 같아야 합니다. 같은 프로세스 안의 거부만 보면 FileShare.None 이
            // 실제로 무엇을 막는지는 추론으로 남습니다.
            Check(RunContenderProcess(sessionBase) == "Busy", "session_other_process_busy");

            Check(session!.Read().Error == CatalogStoreError.NotFound,
                "session_read_absent_is_not_found");

            CatalogReadResult created = session.ReadOrCreate();
            Check(created.IsSuccess, "session_read_or_create_success");
            Check(created.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
                "session_read_or_create_is_empty");
            Check(File.Exists(sessionRoots.CatalogPath), "session_read_or_create_creates_file");

            Check(session.Write(Snapshot("roll-s", Row("frame-1", "one"))).IsSuccess,
                "session_write");
            Check(FrameOrder(session.Read()) == "frame-1", "session_write_round_trip");

            // 이미 있는 카탈로그에서는 ReadOrCreate 가 덮지 않습니다.
            CatalogReadResult reopened = session.ReadOrCreate();
            Check(FrameOrder(reopened) == "frame-1", "session_read_or_create_preserves_existing");

            // 손상은 ReadOrCreate 에서도 빈 라이브러리가 되지 않습니다.
            session.Dispose();
            File.WriteAllBytes(sessionRoots.CatalogPath, "not a database"u8.ToArray());
            CatalogSessionOpenResult reopenedSession = CatalogSession.Open(sessionRoots);
            session = reopenedSession.Session;
            Check(reopenedSession.IsSuccess, "session_reopen_after_dispose");
            Check(session!.ReadOrCreate().Error == CatalogStoreError.CorruptDatabase,
                "session_read_or_create_refuses_corrupt");

            session.Dispose();
            Check(session.IsOpen == false, "session_dispose_releases_lock");
            bool threw = false;
            try
            {
                session.Read();
            }
            catch (ObjectDisposedException)
            {
                threw = true;
            }
            Check(threw, "session_read_after_dispose_throws");

            CatalogSessionOpenResult third = CatalogSession.Open(sessionRoots);
            Check(third.IsSuccess, "session_reacquire_after_dispose");
            third.Session?.Dispose();

            // lock 이 풀린 뒤에는 다른 프로세스가 잡을 수 있어야 합니다. 위의 Busy 가 경로 오류나
            // 프로세스 기동 실패를 잘못 읽은 것이 아님을 이것이 확인합니다.
            Check(RunContenderProcess(sessionBase) == "acquired",
                "session_other_process_acquires_when_free");
        }
        finally
        {
            session?.Dispose();
            if (Directory.Exists(sessionBase))
            {
                Directory.Delete(sessionBase, recursive: true);
            }
        }
    }

    private static void SetStorageVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(catalogPath, $"PRAGMA user_version={version}");

    private static void SetCatalogVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(
            catalogPath,
            $"UPDATE catalog_metadata SET catalog_version={version} WHERE singleton=1");

    private static void ExecuteFixtureSql(string catalogPath, string sql)
    {
        SqliteConnectionStringBuilder builder = new()
        {
            DataSource = catalogPath,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false,
        };
        using SqliteConnection connection = new(builder.ConnectionString);
        connection.Open();
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static CatalogEntityRow Row(string id, string label) =>
        new(id, new JsonObject { ["label"] = label });

    private static CatalogSnapshot Snapshot(
        string? activeRollId,
        params CatalogEntityRow[] frames) =>
        new(activeRollId, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = frames,
        });

    private static string FrameOrder(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Id));

    private static string FrameLabels(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Payload["label"]!.GetValue<string>()));

    private static DevelopRouteReadResult ReadNode(JsonObject frameRecord)
    {
        byte[] bytes = CatalogJson.SerializeCanonical(frameRecord);
        using JsonDocument document = JsonDocument.Parse(bytes);
        return DevelopRouteReader.Read(document.RootElement);
    }

    private static string SourceTransportName(FrameSourceTransport value) => value switch
    {
        FrameSourceTransport.Scanner => "scanner",
        FrameSourceTransport.Imported => "imported",
        _ => "invalid",
    };

    private static string SourceSignalName(SourceSignalKind value) => value switch
    {
        SourceSignalKind.FilmNegativeScan => "filmNegativeScan",
        SourceSignalKind.FilmPositiveScan => "filmPositiveScan",
        SourceSignalKind.RenderedDigital => "renderedDigital",
        SourceSignalKind.SceneLinearDigital => "sceneLinearDigital",
        SourceSignalKind.Unknown => "unknown",
        _ => "invalid",
    };

    private static string ProcessName(DevelopmentProcess value) => value switch
    {
        DevelopmentProcess.C41 => "c41",
        DevelopmentProcess.E6 => "e6",
        DevelopmentProcess.D76 => "d76",
        DevelopmentProcess.BlackAndWhiteReversal => "bwReversal",
        DevelopmentProcess.DigitalColor => "digitalColor",
        DevelopmentProcess.DigitalBlackAndWhite => "digitalBW",
        _ => "invalid",
    };

    private static string FilmLookSourceName(FilmLookSource value) => value switch
    {
        FilmLookSource.FilmScan => "filmScan",
        FilmLookSource.RenderedDigital => "renderedDigital",
        _ => "invalid",
    };

    private static string FilmEmulationName(FilmEmulation value) => value switch
    {
        FilmEmulation.None => "none",
        FilmEmulation.EktachromeE100 => "ektachromeE100",
        FilmEmulation.Provia100F => "provia100F",
        FilmEmulation.Velvia50 => "velvia50",
        FilmEmulation.Portra160 => "portra160",
        FilmEmulation.Portra400 => "portra400",
        FilmEmulation.Portra800 => "portra800",
        FilmEmulation.Ektar100 => "ektar100",
        FilmEmulation.Ultramax400 => "ultramax400",
        FilmEmulation.ColorPlus200 => "colorPlus200",
        FilmEmulation.FujicolorC200 => "fujicolorC200",
        FilmEmulation.Pro400H => "pro400H",
        _ => "invalid",
    };

    private static string ErrorName(DevelopRouteError value) => value switch
    {
        DevelopRouteError.MissingSourceTransport => "missingSourceTransport",
        DevelopRouteError.InvalidSourceTransport => "invalidSourceTransport",
        DevelopRouteError.MissingFilmType => "missingFilmType",
        DevelopRouteError.MissingParameters => "missingParameters",
        DevelopRouteError.ParametersNotObject => "parametersNotObject",
        DevelopRouteError.MismatchedFilmType => "mismatchedFilmType",
        DevelopRouteError.InvalidDigitalSourceMarker => "invalidDigitalSourceMarker",
        DevelopRouteError.InvalidSourceSignal => "invalidSourceSignal",
        DevelopRouteError.UnsupportedSourceSignal => "unsupportedSourceSignal",
        DevelopRouteError.SourceSignalMarkerMismatch => "sourceSignalMarkerMismatch",
        DevelopRouteError.SourceSignalFilmTypeMismatch => "sourceSignalFilmTypeMismatch",
        DevelopRouteError.InvalidFilmEmulation => "invalidFilmEmulation",
        DevelopRouteError.InvalidFilmEmulationIntensity => "invalidFilmEmulationIntensity",
        _ => value.ToString(),
    };

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
